// The Advanced Search form, styled after x.com/search-advanced: bordered fields
// with floating labels, example lines, filter toggles, language menu, date pickers.

#import "Features/Search/PFBAdvancedSearchViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

// x.com focus blue (#1D9BF0) — the web form's focus ring.
static UIColor* PFBAdvBlue(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0x9B / 255.0
                            blue:0xF0 / 255.0
                           alpha:1.0];
}

// MARK: - field model

typedef NS_ENUM(NSInteger, PFBAdvFieldKind) {
    PFBAdvFieldText = 0,     // free words / phrases / account lists
    PFBAdvFieldNumber,       // minimum engagement counts
    PFBAdvFieldDate,         // calendar picker, optional
    PFBAdvFieldMenu,         // language pull-down
    PFBAdvFieldToggle,       // filters switches
};

@interface PFBAdvField : NSObject
@property (nonatomic, copy) NSString* storeKey;     // NSUserDefaults draft key
@property (nonatomic, copy) NSString* labelKey;     // field title key
@property (nonatomic, copy) NSString* exampleKey;   // example line key (nilable)
@property (nonatomic, assign) PFBAdvFieldKind kind;
@end


UIImage* PFBTwitterGlyphFor(NSString* name, UIImage* systemImage);

@implementation PFBAdvField
+ (instancetype)key:(NSString*)k
              label:(NSString*)l
            example:(NSString*)e
               kind:(PFBAdvFieldKind)kind {
    PFBAdvField* f = [PFBAdvField new];
    f.storeKey = k;
    f.labelKey = l;
    f.exampleKey = e;
    f.kind = kind;
    return f;
}
@end

// MARK: - shared box scaffolding (border + floating label + example line)

// Builds the web form's bordered box with a floating label, hosting an
// arbitrary content view, plus the gray example line underneath. Returns the
// box view through outBox so cells can restyle the border on focus.
static UILabel* PFBAdvInstallBox(UITableViewCell* cell,
                                 UIView* content,
                                 UIView** outBox,
                                 UILabel** outExample) {
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];

    UIView* box = [[UIView alloc] init];
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [UIColor systemGray3Color].CGColor;
    box.layer.cornerRadius = 6.0;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:box];

    UILabel* floatLabel = [[UILabel alloc] init];
    floatLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    floatLabel.textColor = [UIColor secondaryLabelColor];
    floatLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:floatLabel];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:content];

    UILabel* example = [[UILabel alloc] init];
    example.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
    example.textColor = [UIColor secondaryLabelColor];
    example.numberOfLines = 0;
    example.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:example];

    UILayoutGuide* margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                      constant:7.0],
        [box.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        [floatLabel.topAnchor constraintEqualToAnchor:box.topAnchor constant:7.0],
        [floatLabel.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                                 constant:12.0],
        [floatLabel.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                  constant:-12.0],

        [content.topAnchor constraintEqualToAnchor:floatLabel.bottomAnchor
                                          constant:1.0],
        [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                              constant:12.0],
        [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                               constant:-12.0],
        [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor
                                             constant:-9.0],
        [content.heightAnchor constraintGreaterThanOrEqualToConstant:22.0],

        [example.topAnchor constraintEqualToAnchor:box.bottomAnchor constant:6.0],
        [example.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor
                                               constant:2.0],
        [example.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [example.bottomAnchor
            constraintEqualToAnchor:cell.contentView.bottomAnchor
                           constant:-7.0],
    ]];
    if (outBox) { *outBox = box; }
    if (outExample) { *outExample = example; }
    return floatLabel;
}

// MARK: - text / number cell

// The web form's floating-label box: fixed box height, the label centered as a
// placeholder while empty and unfocused, floating small and gray on focus or once
// there is a value. Two labels cross-faded, so no row height changes.

@interface PFBAdvBoxCell : UITableViewCell <UITextFieldDelegate>
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* placeholderLabel;
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) PFBAdvField* model;
@end

@implementation PFBAdvBoxCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _box = [[UIView alloc] init];
        _box.layer.borderWidth = 1.0;
        _box.layer.borderColor = [UIColor systemGray3Color].CGColor;
        _box.layer.cornerRadius = 6.0;

        _placeholderLabel = [[UILabel alloc] init];
        _placeholderLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        _placeholderLabel.textColor = [UIColor secondaryLabelColor];
        _placeholderLabel.userInteractionEnabled = NO;

        _floatLabel = [[UILabel alloc] init];
        _floatLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
        _floatLabel.textColor = [UIColor secondaryLabelColor];
        _floatLabel.alpha = 0.0;

        _field = [[UITextField alloc] init];
        _field.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.returnKeyType = UIReturnKeyDone;
        _field.delegate = self;
        [_field addTarget:self
                      action:@selector(pfbFieldEdited:)
            forControlEvents:UIControlEventEditingChanged];

        _exampleLabel = [[UILabel alloc] init];
        _exampleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
        _exampleLabel.textColor = [UIColor secondaryLabelColor];
        _exampleLabel.numberOfLines = 0;

        for (UIView* v in @[ _box, _exampleLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        for (UIView* v in @[ _floatLabel, _field, _placeholderLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [_box addSubview:v];
        }

        UILayoutGuide* m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                           constant:7.0],
            [_box.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_box.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [_box.heightAnchor constraintEqualToConstant:56.0],

            [_placeholderLabel.leadingAnchor
                constraintEqualToAnchor:_box.leadingAnchor
                               constant:12.0],
            [_placeholderLabel.trailingAnchor
                constraintEqualToAnchor:_box.trailingAnchor
                               constant:-12.0],
            [_placeholderLabel.centerYAnchor
                constraintEqualToAnchor:_box.centerYAnchor],

            [_floatLabel.topAnchor constraintEqualToAnchor:_box.topAnchor
                                                  constant:7.0],
            [_floatLabel.leadingAnchor
                constraintEqualToAnchor:_box.leadingAnchor
                               constant:12.0],
            [_floatLabel.trailingAnchor
                constraintEqualToAnchor:_box.trailingAnchor
                               constant:-12.0],

            [_field.leadingAnchor constraintEqualToAnchor:_box.leadingAnchor
                                                 constant:12.0],
            [_field.trailingAnchor constraintEqualToAnchor:_box.trailingAnchor
                                                  constant:-12.0],
            [_field.bottomAnchor constraintEqualToAnchor:_box.bottomAnchor
                                                constant:-7.0],
            [_field.heightAnchor constraintEqualToConstant:24.0],

            [_exampleLabel.topAnchor constraintEqualToAnchor:_box.bottomAnchor
                                                    constant:6.0],
            [_exampleLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor
                                                        constant:2.0],
            [_exampleLabel.trailingAnchor
                constraintEqualToAnchor:m.trailingAnchor],
            [_exampleLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-7.0],
        ]];
    }
    return self;
}

- (void)configureWith:(PFBAdvField*)model {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:model.labelKey];
    self.placeholderLabel.text = title;
    self.floatLabel.text = title;
    self.field.keyboardType = (model.kind == PFBAdvFieldNumber)
                                  ? UIKeyboardTypeNumberPad
                                  : UIKeyboardTypeDefault;
    self.field.text =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey] ?: @"";
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    [self pfbApplyFloatAnimated:NO];
}

// Label floats up on focus or once there's text — the web behavior.
- (void)pfbApplyFloatAnimated:(BOOL)animated {
    BOOL up = self.field.isFirstResponder || self.field.text.length > 0;
    void (^apply)(void) = ^{
        self.placeholderLabel.alpha = up ? 0.0 : 1.0;
        self.floatLabel.alpha = up ? 1.0 : 0.0;
    };
    if (animated) {
        [UIView animateWithDuration:0.15 animations:apply];
    } else {
        apply();
    }
}

- (void)pfbFieldEdited:(UITextField*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setObject:(sender.text ?: @"")
                                              forKey:self.model.storeKey];
    [self pfbApplyFloatAnimated:YES];
}

- (void)textFieldDidBeginEditing:(UITextField*)textField {
    self.box.layer.borderColor = PFBAdvBlue().CGColor;
    self.box.layer.borderWidth = 2.0;
    [self pfbApplyFloatAnimated:YES];
}

- (void)textFieldDidEndEditing:(UITextField*)textField {
    self.box.layer.borderColor = [UIColor systemGray3Color].CGColor;
    self.box.layer.borderWidth = 1.0;
    [self pfbApplyFloatAnimated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

// MARK: - language menu cell

@interface PFBAdvMenuCell : UITableViewCell
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIButton* valueButton;
@property (nonatomic, strong) PFBAdvField* model;
@end

@implementation PFBAdvMenuCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _valueButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _valueButton.titleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        [_valueButton setTitleColor:[UIColor labelColor]
                           forState:UIControlStateNormal];
        _valueButton.contentHorizontalAlignment =
            UIControlContentHorizontalAlignmentLeft;
        [_valueButton setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"]
                      forState:UIControlStateNormal];
        _valueButton.tintColor = [UIColor secondaryLabelColor];
        _valueButton.semanticContentAttribute =
            UISemanticContentAttributeForceRightToLeft;
        _valueButton.showsMenuAsPrimaryAction = YES;
        UIView* box = nil;
        UILabel* example = nil;
        _floatLabel = PFBAdvInstallBox(self, _valueButton, &box, &example);
        _exampleLabel = example;
    }
    return self;
}

- (void)configureWith:(PFBAdvField*)model
                 menu:(UIMenu*)menu
         currentTitle:(NSString*)currentTitle
             hasValue:(BOOL)hasValue {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.floatLabel.text = [bundle localizedStringForKey:model.labelKey];
    (void)hasValue;
    self.floatLabel.alpha = 1.0;   // the menu always shows a value, so its label stays
    [self.valueButton setTitle:currentTitle forState:UIControlStateNormal];
    self.valueButton.menu = menu;
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
}

@end

// MARK: - filters toggle cell

@interface PFBAdvToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel2;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UISwitch* toggle;
@property (nonatomic, strong) PFBAdvField* model;
@end

@implementation PFBAdvToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _titleLabel2 = [[UILabel alloc] init];
        _titleLabel2.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        _titleLabel2.textColor = [UIColor labelColor];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.numberOfLines = 0;

        _toggle = [[UISwitch alloc] init];
        _toggle.onTintColor = PFBAdvBlue();
        [_toggle addTarget:self
                      action:@selector(pfbToggled:)
            forControlEvents:UIControlEventValueChanged];

        for (UIView* v in @[ _titleLabel2, _subtitleLabel, _toggle ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        UILayoutGuide* m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel2.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor
                               constant:10.0],
            [_titleLabel2.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_subtitleLabel.topAnchor
                constraintEqualToAnchor:_titleLabel2.bottomAnchor
                               constant:2.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [_subtitleLabel.trailingAnchor
                constraintEqualToAnchor:_toggle.leadingAnchor
                               constant:-12.0],
            [_subtitleLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-10.0],
            [_titleLabel2.trailingAnchor
                constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor
                                         constant:-12.0],
            [_toggle.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggle.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        ]];
    }
    return self;
}

- (void)configureWith:(PFBAdvField*)model on:(BOOL)on {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.titleLabel2.text = [bundle localizedStringForKey:model.labelKey];
    self.subtitleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    self.toggle.on = on;
}

- (void)pfbToggled:(UISwitch*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:self.model.storeKey];
}

@end

// MARK: - calendar date cell

@interface PFBAdvDateCell : UITableViewCell
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIDatePicker* picker;
@property (nonatomic, strong) UIButton* clearButton;
@property (nonatomic, strong) PFBAdvField* model;
@end

@implementation PFBAdvDateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _picker = [[UIDatePicker alloc] init];
        _picker.datePickerMode = UIDatePickerModeDate;
        _picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
        [_picker addTarget:self
                      action:@selector(pfbDateChanged:)
            forControlEvents:UIControlEventValueChanged];

        _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_clearButton setImage:PFBTwitterGlyphFor(@"close_circle_fill", [UIImage systemImageNamed:@"xmark.circle.fill"])
                      forState:UIControlStateNormal];
        _clearButton.tintColor = [UIColor systemGray3Color];
        [_clearButton addTarget:self
                          action:@selector(pfbClearDate)
                forControlEvents:UIControlEventTouchUpInside];

        // Compact row: the native calendar capsule anchored to the RIGHT
        // (the iOS Settings pattern), the clear × just left of it, nothing
        // stretched — the box stays as tight as every other field.
        UIView* row = [[UIView alloc] init];
        _picker.translatesAutoresizingMaskIntoConstraints = NO;
        _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_picker setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisHorizontal];
        [_picker setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisVertical];
        [row addSubview:_picker];
        [row addSubview:_clearButton];
        [NSLayoutConstraint activateConstraints:@[
            [_picker.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [_picker.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [_picker.topAnchor
                constraintGreaterThanOrEqualToAnchor:row.topAnchor],
            [_picker.bottomAnchor
                constraintLessThanOrEqualToAnchor:row.bottomAnchor],
            [row.heightAnchor constraintEqualToConstant:36.0],
            [_clearButton.centerYAnchor
                constraintEqualToAnchor:_picker.centerYAnchor],
            [_clearButton.trailingAnchor
                constraintEqualToAnchor:_picker.leadingAnchor
                               constant:-8.0],
            [_clearButton.widthAnchor constraintEqualToConstant:26.0],
        ]];

        UIView* box = nil;
        UILabel* example = nil;
        _floatLabel = PFBAdvInstallBox(self, row, &box, &example);
        _box = box;
        _exampleLabel = example;
        _floatLabel.alpha = 1.0;   // date rows keep their label visible
    }
    return self;
}

+ (NSDateFormatter*)pfbFormatter {
    static NSDateFormatter* f = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"yyyy-MM-dd";
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return f;
}

- (void)configureWith:(PFBAdvField*)model {
    self.model = model;
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.floatLabel.text = [bundle localizedStringForKey:model.labelKey];
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    NSString* stored =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey];
    NSDate* date = stored ? [[PFBAdvDateCell pfbFormatter] dateFromString:stored]
                          : nil;
    if (date) { self.picker.date = date; }
    BOOL active = (date != nil);
    self.picker.alpha = active ? 1.0 : 0.45;
    self.clearButton.hidden = !active;
}

- (void)pfbDateChanged:(UIDatePicker*)sender {
    if (!self.model) { return; }
    NSString* s = [[PFBAdvDateCell pfbFormatter] stringFromDate:sender.date];
    [[NSUserDefaults standardUserDefaults] setObject:s
                                              forKey:self.model.storeKey];
    self.picker.alpha = 1.0;
    self.clearButton.hidden = NO;
}

- (void)pfbClearDate {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:self.model.storeKey];
    self.picker.alpha = 0.45;
    self.clearButton.hidden = YES;
}

@end

// MARK: - controller

@interface PFBAdvancedSearchViewController ()
@property (nonatomic, strong) NSArray<NSString*>* sectionKeys;
@property (nonatomic, strong) NSArray<NSArray<PFBAdvField*>*>* sections;
@property (nonatomic, strong) NSArray<NSString*>* languageCodes;
@end

// A glyph escapes the glass material's wash by being baked: opaque pixels handed
// over as AlwaysOriginal. A title has no such escape, since the label is drawn by
// the button, so the word is baked into a bitmap and passed as an image.
static UIImage* pfbBakedTitleImage(NSString* title, UIFont* font) {
    if (title.length == 0 || !font) {
        return nil;
    }
    NSDictionary* attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [UIColor whiteColor]
    };
    // A capsule built around an image comes out narrower than one built around a
    // title, so the difference is padded back into the bitmap transparently and the
    // button keeps its proportions.
    const CGFloat kSidePadding = 10.0;
    CGSize measured = [title sizeWithAttributes:attributes];
    CGSize size = CGSizeMake(ceilf((float)measured.width) + kSidePadding * 2.0,
                             ceilf((float)measured.height));
    if (size.width < 1.0 || size.height < 1.0) {
        return nil;
    }
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [title drawAtPoint:CGPointMake(kSidePadding, 0.0) withAttributes:attributes];
        }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

extern NSInteger PFBColorThemeScreenVisible;

@implementation PFBAdvancedSearchViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBColorThemeScreenVisible++;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (PFBColorThemeScreenVisible > 0) {
        PFBColorThemeScreenVisible--;
    }
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.title = [bundle localizedStringForKey:@"ADVANCED_SEARCH_TITLE"];

    self.languageCodes = @[
        @"en", @"fr", @"es", @"de", @"it", @"pt", @"ja", @"ko", @"ar", @"ru",
        @"zh", @"hi", @"id", @"tr", @"nl", @"pl", @"sv", @"uk", @"fa", @"he",
        @"th", @"vi",
    ];

    self.sectionKeys = @[
        @"ADVSEARCH_SECTION_WORDS",
        @"ADVSEARCH_SECTION_ACCOUNTS",
        @"ADVSEARCH_SECTION_FILTERS",
        @"ADVSEARCH_SECTION_ENGAGEMENT",
        @"ADVSEARCH_SECTION_DATES",
    ];
    self.sections = @[
        @[
            [PFBAdvField key:@"pfb_advs_all" label:@"ADVSEARCH_ALL_WORDS"
                      example:@"ADVSEARCH_EX_ALL" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_exact" label:@"ADVSEARCH_EXACT_PHRASE"
                      example:@"ADVSEARCH_EX_EXACT" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_any" label:@"ADVSEARCH_ANY_WORDS"
                      example:@"ADVSEARCH_EX_ANY" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_none" label:@"ADVSEARCH_NONE_WORDS"
                      example:@"ADVSEARCH_EX_NONE" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_tags" label:@"ADVSEARCH_HASHTAGS"
                      example:@"ADVSEARCH_EX_TAGS" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_lang" label:@"ADVSEARCH_LANGUAGE"
                      example:nil kind:PFBAdvFieldMenu],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_from" label:@"ADVSEARCH_FROM_ACCOUNTS"
                      example:@"ADVSEARCH_EX_FROM" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_to" label:@"ADVSEARCH_TO_ACCOUNTS"
                      example:@"ADVSEARCH_EX_TO" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_mention" label:@"ADVSEARCH_MENTIONING"
                      example:@"ADVSEARCH_EX_MENTION" kind:PFBAdvFieldText],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_replies" label:@"ADVSEARCH_REPLIES"
                      example:@"ADVSEARCH_REPLIES_SUB" kind:PFBAdvFieldToggle],
            [PFBAdvField key:@"pfb_advs_links" label:@"ADVSEARCH_LINKS"
                      example:@"ADVSEARCH_LINKS_SUB" kind:PFBAdvFieldToggle],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_minreplies" label:@"ADVSEARCH_MIN_REPLIES"
                      example:@"ADVSEARCH_EX_MINREPLIES" kind:PFBAdvFieldNumber],
            [PFBAdvField key:@"pfb_advs_minfaves" label:@"ADVSEARCH_MIN_LIKES"
                      example:@"ADVSEARCH_EX_MINLIKES" kind:PFBAdvFieldNumber],
            [PFBAdvField key:@"pfb_advs_minrt" label:@"ADVSEARCH_MIN_REPOSTS"
                      example:@"ADVSEARCH_EX_MINREPOSTS" kind:PFBAdvFieldNumber],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_since" label:@"ADVSEARCH_SINCE_DATE"
                      example:@"ADVSEARCH_EX_SINCE" kind:PFBAdvFieldDate],
            [PFBAdvField key:@"pfb_advs_until" label:@"ADVSEARCH_UNTIL_DATE"
                      example:@"ADVSEARCH_EX_UNTIL" kind:PFBAdvFieldDate],
        ],
    ];

    // A system Done bar button gives one native Liquid Glass capsule, where a custom
    // view would be wrapped in a second one. With no explicit tint it inherits the
    // window tint and follows the color theme.
    NSString* searchTitle = [bundle localizedStringForKey:@"ADVSEARCH_SEARCH"];
    UIFont* searchFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15]);
    UIImage* bakedTitle = pfbBakedTitleImage(searchTitle, searchFont);
    if (bakedTitle) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithImage:bakedTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(pfbRunSearch)];
        // The word is a picture now, so VoiceOver is told what it says.
        self.navigationItem.rightBarButtonItem.accessibilityLabel = searchTitle;
    } else {
        // Only reachable if the bitmap could not be drawn at all; a bar button
        // with no image would simply be invisible, so the plain title stands in.
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:searchTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(pfbRunSearch)];
        NSDictionary* chirpButton = @{
            NSFontAttributeName : searchFont,
            NSForegroundColorAttributeName : [UIColor whiteColor]
        };
        [self.navigationItem.rightBarButtonItem setTitleTextAttributes:chirpButton
                                                              forState:UIControlStateNormal];
        [self.navigationItem.rightBarButtonItem setTitleTextAttributes:chirpButton
                                                              forState:UIControlStateHighlighted];
    }

    if (self.presentingViewController
        || self.navigationController.presentingViewController) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                 target:self
                                 action:@selector(pfbCancel)];
        // Marked for the bar-glass pass: this one keeps the capsule iOS gives it.
        objc_setAssociatedObject(self.navigationItem.leftBarButtonItem,
                                 @selector(pfbKeepsBarGlass), @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSDictionary* chirpTitle = @{
        NSFontAttributeName : PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17])
    };
    self.navigationController.navigationBar.titleTextAttributes = chirpTitle;

    // Outline pill, pale gray border and pale gray text — the fork's
    // "Reset to default" style, per request.
    UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 78.0)];
    UIButton* clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:[bundle localizedStringForKey:@"ADVSEARCH_CLEAR"]
           forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor secondaryLabelColor]
                forState:UIControlStateNormal];
    clear.titleLabel.font =
        PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15.5]);
    clear.layer.borderWidth = 1.0;
    clear.layer.borderColor = [UIColor systemGray4Color].CGColor;
    clear.layer.cornerRadius = 22.0;
    [clear addTarget:self
                  action:@selector(pfbClearAll)
        forControlEvents:UIControlEventTouchUpInside];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:clear];
    [NSLayoutConstraint activateConstraints:@[
        [clear.topAnchor constraintEqualToAnchor:footer.topAnchor constant:16.0],
        [clear.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor
                                            constant:16.0],
        [clear.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor
                                             constant:-16.0],
        [clear.heightAnchor constraintEqualToConstant:44.0],
    ]];
    self.tableView.tableFooterView = footer;

    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[PFBAdvBoxCell class]
           forCellReuseIdentifier:@"box"];
    [self.tableView registerClass:[PFBAdvMenuCell class]
           forCellReuseIdentifier:@"menu"];
    [self.tableView registerClass:[PFBAdvToggleCell class]
           forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:[PFBAdvDateCell class]
           forCellReuseIdentifier:@"date"];
    self.tableView.keyboardDismissMode =
        UIScrollViewKeyboardDismissModeInteractive;
}

// MARK: language helpers

static NSString* PFBAdvLangName(NSString* code) {
    NSString* name =
        [[NSLocale currentLocale] localizedStringForLanguageCode:code];
    if (name.length) {
        return [[[name substringToIndex:1] localizedUppercaseString]
            stringByAppendingString:[name substringFromIndex:1]];
    }
    return code;
}

- (NSString*)pfbCurrentLanguageTitle {
    NSString* code =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"];
    if (code.length == 0) {
        return [[PFBBundle sharedBundle]
            localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"];
    }
    return PFBAdvLangName(code);
}

- (UIMenu*)pfbLanguageMenu {
    NSString* current =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"]
            ?: @"";
    __weak typeof(self) weakSelf = self;
    NSMutableArray* actions = [NSMutableArray array];
    UIAction* any = [UIAction
        actionWithTitle:[[PFBBundle sharedBundle]
                            localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"]
                  image:nil
             identifier:nil
                handler:^(UIAction* a) {
                    [[NSUserDefaults standardUserDefaults]
                        removeObjectForKey:@"pfb_advs_lang"];
                    [weakSelf.tableView reloadData];
                }];
    any.state = (current.length == 0) ? UIMenuElementStateOn
                                      : UIMenuElementStateOff;
    [actions addObject:any];
    for (NSString* code in self.languageCodes) {
        UIAction* a = [UIAction
            actionWithTitle:PFBAdvLangName(code)
                      image:nil
                 identifier:nil
                    handler:^(UIAction* act) {
                        [[NSUserDefaults standardUserDefaults]
                            setObject:code forKey:@"pfb_advs_lang"];
                        [weakSelf.tableView reloadData];
                    }];
        a.state = [current isEqualToString:code] ? UIMenuElementStateOn
                                                 : UIMenuElementStateOff;
        [actions addObject:a];
    }
    return [UIMenu menuWithChildren:actions];
}

// Filters default ON (the web form's default): absent key means included.
static BOOL PFBAdvFilterOn(NSString* key) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    return ([d objectForKey:key] == nil) ? YES : [d boolForKey:key];
}

// MARK: table

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView*)tableView
    numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (UIView*)tableView:(UITableView*)tableView
    viewForHeaderInSection:(NSInteger)section {
    UIView* container = [[UIView alloc] init];
    UILabel* label = [[UILabel alloc] init];
    label.text = [[PFBBundle sharedBundle]
        localizedStringForKey:self.sectionKeys[(NSUInteger)section]];
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20]);
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor
            constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [label.trailingAnchor
            constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                           constant:-6.0],
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView*)tableView
    heightForHeaderInSection:(NSInteger)section {
    return 46.0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBAdvField* model =
        self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    switch (model.kind) {
        case PFBAdvFieldMenu: {
            PFBAdvMenuCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"menu"
                                                forIndexPath:indexPath];
            NSString* code = [[NSUserDefaults standardUserDefaults]
                stringForKey:@"pfb_advs_lang"];
            [cell configureWith:model
                           menu:[self pfbLanguageMenu]
                   currentTitle:[self pfbCurrentLanguageTitle]
                       hasValue:(code.length > 0)];
            return cell;
        }
        case PFBAdvFieldToggle: {
            PFBAdvToggleCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"toggle"
                                                forIndexPath:indexPath];
            [cell configureWith:model on:PFBAdvFilterOn(model.storeKey)];
            return cell;
        }
        case PFBAdvFieldDate: {
            PFBAdvDateCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"date"
                                                forIndexPath:indexPath];
            [cell configureWith:model];
            return cell;
        }
        default: {
            PFBAdvBoxCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"box"
                                                forIndexPath:indexPath];
            [cell configureWith:model];
            return cell;
        }
    }
}

// MARK: actions

- (void)pfbCancel {
    [self.presentingViewController dismissViewControllerAnimated:YES
                                                      completion:nil];
}

- (void)pfbClearAll {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    for (NSArray<PFBAdvField*>* section in self.sections) {
        for (PFBAdvField* f in section) {
            [d removeObjectForKey:f.storeKey];
        }
    }
    [self.tableView reloadData];
}

// MARK: query building

static NSArray<NSString*>* PFBAdvTokens(NSString* raw) {
    NSMutableArray* out = [NSMutableArray array];
    NSCharacterSet* seps =
        [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    for (NSString* t in [raw componentsSeparatedByCharactersInSet:seps]) {
        NSString* trimmed = [t stringByTrimmingCharactersInSet:
                                   [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length) { [out addObject:trimmed]; }
    }
    return out;
}

static NSString* PFBAdvOrGroup(NSArray<NSString*>* tokens) {
    if (tokens.count == 1) { return tokens[0]; }
    return [NSString stringWithFormat:@"(%@)",
                                      [tokens componentsJoinedByString:@" OR "]];
}

static NSString* PFBAdvValue(NSString* key) {
    NSString* v = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return [v stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceCharacterSet]] ?: @"";
}

- (NSString*)pfbBuildQueryOrError:(NSString**)errorKey {
    NSMutableArray* parts = [NSMutableArray array];

    NSString* all = PFBAdvValue(@"pfb_advs_all");
    if (all.length) { [parts addObject:all]; }

    NSString* exact = PFBAdvValue(@"pfb_advs_exact");
    if (exact.length) {
        [parts addObject:[NSString stringWithFormat:@"\"%@\"", exact]];
    }

    NSArray* any = PFBAdvTokens(PFBAdvValue(@"pfb_advs_any"));
    if (any.count) { [parts addObject:PFBAdvOrGroup(any)]; }

    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_none"))) {
        [parts addObject:[NSString stringWithFormat:@"-%@", t]];
    }

    NSMutableArray* tags = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_tags"))) {
        [tags addObject:[t hasPrefix:@"#"]
                            ? t
                            : [NSString stringWithFormat:@"#%@", t]];
    }
    if (tags.count) { [parts addObject:PFBAdvOrGroup(tags)]; }

    NSString* lang =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"];
    if (lang.length) {
        [parts addObject:[NSString stringWithFormat:@"lang:%@", lang]];
    }

    NSMutableArray* from = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_from"))) {
        NSString* u = [t hasPrefix:@"@"] ? [t substringFromIndex:1] : t;
        [from addObject:[NSString stringWithFormat:@"from:%@", u]];
    }
    if (from.count) { [parts addObject:PFBAdvOrGroup(from)]; }

    NSMutableArray* to = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_to"))) {
        NSString* u = [t hasPrefix:@"@"] ? [t substringFromIndex:1] : t;
        [to addObject:[NSString stringWithFormat:@"to:%@", u]];
    }
    if (to.count) { [parts addObject:PFBAdvOrGroup(to)]; }

    NSMutableArray* mention = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_mention"))) {
        NSString* u = [t hasPrefix:@"@"] ? t
                                         : [NSString stringWithFormat:@"@%@", t];
        [mention addObject:u];
    }
    if (mention.count) { [parts addObject:PFBAdvOrGroup(mention)]; }

    if (!PFBAdvFilterOn(@"pfb_advs_replies")) {
        [parts addObject:@"-filter:replies"];
    }
    if (!PFBAdvFilterOn(@"pfb_advs_links")) {
        [parts addObject:@"-filter:links"];
    }

    struct {
        __unsafe_unretained NSString* key;
        __unsafe_unretained NSString* op;
    } mins[] = {
        { @"pfb_advs_minreplies", @"min_replies" },
        { @"pfb_advs_minfaves", @"min_faves" },
        { @"pfb_advs_minrt", @"min_retweets" },
    };
    for (size_t i = 0; i < sizeof(mins) / sizeof(mins[0]); i++) {
        NSString* v = PFBAdvValue(mins[i].key);
        if (v.length && v.integerValue > 0) {
            [parts addObject:[NSString stringWithFormat:@"%@:%ld", mins[i].op,
                                                        (long)v.integerValue]];
        }
    }

    NSString* since = PFBAdvValue(@"pfb_advs_since");
    if (since.length) {
        [parts addObject:[NSString stringWithFormat:@"since:%@", since]];
    }
    NSString* until = PFBAdvValue(@"pfb_advs_until");
    if (until.length) {
        [parts addObject:[NSString stringWithFormat:@"until:%@", until]];
    }

    if (!parts.count) {
        *errorKey = @"ADVSEARCH_EMPTY";
        return nil;
    }
    return [parts componentsJoinedByString:@" "];
}

// MARK: launch

- (void)pfbRunSearch {
    [self.view endEditing:YES];
    NSString* errorKey = nil;
    NSString* query = [self pfbBuildQueryOrError:&errorKey];
    if (!query) {
        PFBBundle* bundle = [PFBBundle sharedBundle];
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:[bundle localizedStringForKey:
                                                 @"ADVANCED_SEARCH_TITLE"]
                             message:[bundle localizedStringForKey:errorKey]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString* encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:
                                   [NSCharacterSet URLQueryAllowedCharacterSet]];
    encoded = [[encoded stringByReplacingOccurrencesOfString:@"&"
                                                  withString:@"%26"]
        stringByReplacingOccurrencesOfString:@"+"
                                  withString:@"%2B"];
    NSURL* deepLink = [NSURL
        URLWithString:[NSString
                          stringWithFormat:@"twitter://search?query=%@", encoded]];

    // The form closes first, then the deep link goes straight to the app delegate's
    // own URL router. Never through iOS: a sideloaded bundle may not have the
    // twitter:// scheme registered, and the web fallback lands on a login wall.
    void (^launch)(void) = ^{
        id delegate = [UIApplication sharedApplication].delegate;
        if (deepLink && [delegate respondsToSelector:@selector(openURL:options:)]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(delegate,
                                                      @selector(openURL:options:),
                                                      deepLink, @{});
        }
    };
    UIViewController* presenter = self.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), launch);
}

@end
