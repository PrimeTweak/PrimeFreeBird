//
//  AdvancedSearchViewController.m
//  PrimeFreeBird
//
//  Twitter's Advanced Search only exists on the web. This is the same form,
//  native — styled to match x.com/search-advanced verbatim: individually
//  bordered fields with floating labels, the official example line under each
//  field, the Filters toggles, the Language menu, calendar date pickers, and
//  the black pill Search button. Drafts persist between opens; Search
//  assembles the standard operator query and hands it to the app's OWN search
//  screen through Twitter's internal URL router — native results, no web view
//  anywhere.
//

#import "Search/AdvancedSearchViewController.h"
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import <math.h>
#import <objc/message.h>

// x.com focus blue (#1D9BF0) — the web form's focus ring.
static UIColor* NFBAdvBlue(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0x9B / 255.0
                            blue:0xF0 / 255.0
                           alpha:1.0];
}

// MARK: - field model

typedef NS_ENUM(NSInteger, NFBAdvFieldKind) {
    NFBAdvFieldText = 0,     // free words / phrases / account lists
    NFBAdvFieldNumber,       // minimum engagement counts
    NFBAdvFieldDate,         // calendar picker, optional
    NFBAdvFieldMenu,         // language pull-down
    NFBAdvFieldToggle,       // filters switches
};

@interface NFBAdvField : NSObject
@property (nonatomic, copy) NSString* storeKey;     // NSUserDefaults draft key
@property (nonatomic, copy) NSString* labelKey;     // field title key
@property (nonatomic, copy) NSString* exampleKey;   // example line key (nilable)
@property (nonatomic, assign) NFBAdvFieldKind kind;
@end

@implementation NFBAdvField
+ (instancetype)key:(NSString*)k
              label:(NSString*)l
            example:(NSString*)e
               kind:(NFBAdvFieldKind)kind {
    NFBAdvField* f = [NFBAdvField new];
    f.storeKey = k;
    f.labelKey = l;
    f.exampleKey = e;
    f.kind = kind;
    return f;
}
@end

// MARK: - shared box scaffolding (border + floating label + example line)

// Builds the web form's bordered box with a floating label, hosting an
// arbitrary content view, plus the grey example line underneath. Returns the
// box view through outBox so cells can restyle the border on focus.
static UILabel* NFBAdvInstallBox(UITableViewCell* cell,
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
    floatLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    floatLabel.textColor = [UIColor secondaryLabelColor];
    floatLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:floatLabel];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:content];

    UILabel* example = [[UILabel alloc] init];
    example.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5];
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
//
// The web form's floating-label box, faithfully: FIXED box height, the label
// sits centred as a placeholder while the field is empty and unfocused, and
// floats to the top (small, grey) on focus or once there's a value. Two
// labels cross-faded — no constraint juggling, no row-height changes.

@interface NFBAdvBoxCell : UITableViewCell <UITextFieldDelegate>
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* placeholderLabel;
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) NFBAdvField* model;
@end

@implementation NFBAdvBoxCell

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
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
        _placeholderLabel.textColor = [UIColor secondaryLabelColor];
        _placeholderLabel.userInteractionEnabled = NO;

        _floatLabel = [[UILabel alloc] init];
        _floatLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        _floatLabel.textColor = [UIColor secondaryLabelColor];
        _floatLabel.alpha = 0.0;

        _field = [[UITextField alloc] init];
        _field.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.returnKeyType = UIReturnKeyDone;
        _field.delegate = self;
        [_field addTarget:self
                      action:@selector(nfbFieldEdited:)
            forControlEvents:UIControlEventEditingChanged];

        _exampleLabel = [[UILabel alloc] init];
        _exampleLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5];
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

- (void)configureWith:(NFBAdvField*)model {
    self.model = model;
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:model.labelKey];
    self.placeholderLabel.text = title;
    self.floatLabel.text = title;
    self.field.keyboardType = (model.kind == NFBAdvFieldNumber)
                                  ? UIKeyboardTypeNumberPad
                                  : UIKeyboardTypeDefault;
    self.field.text =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey] ?: @"";
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    [self nfbApplyFloatAnimated:NO];
}

// Label floats up on focus or once there's text — the web behaviour.
- (void)nfbApplyFloatAnimated:(BOOL)animated {
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

- (void)nfbFieldEdited:(UITextField*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setObject:(sender.text ?: @"")
                                              forKey:self.model.storeKey];
    [self nfbApplyFloatAnimated:YES];
}

- (void)textFieldDidBeginEditing:(UITextField*)textField {
    self.box.layer.borderColor = NFBAdvBlue().CGColor;
    self.box.layer.borderWidth = 2.0;
    [self nfbApplyFloatAnimated:YES];
}

- (void)textFieldDidEndEditing:(UITextField*)textField {
    self.box.layer.borderColor = [UIColor systemGray3Color].CGColor;
    self.box.layer.borderWidth = 1.0;
    [self nfbApplyFloatAnimated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

// MARK: - language menu cell

@interface NFBAdvMenuCell : UITableViewCell
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIButton* valueButton;
@property (nonatomic, strong) NFBAdvField* model;
@end

@implementation NFBAdvMenuCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _valueButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _valueButton.titleLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
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
        _floatLabel = NFBAdvInstallBox(self, _valueButton, &box, &example);
        _exampleLabel = example;
    }
    return self;
}

- (void)configureWith:(NFBAdvField*)model
                 menu:(UIMenu*)menu
         currentTitle:(NSString*)currentTitle
             hasValue:(BOOL)hasValue {
    self.model = model;
    BHTBundle* bundle = [BHTBundle sharedBundle];
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

@interface NFBAdvToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel2;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UISwitch* toggle;
@property (nonatomic, strong) NFBAdvField* model;
@end

@implementation NFBAdvToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _titleLabel2 = [[UILabel alloc] init];
        _titleLabel2.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
        _titleLabel2.textColor = [UIColor labelColor];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5];
        _subtitleLabel.textColor = [UIColor secondaryLabelColor];
        _subtitleLabel.numberOfLines = 0;

        _toggle = [[UISwitch alloc] init];
        _toggle.onTintColor = NFBAdvBlue();
        [_toggle addTarget:self
                      action:@selector(nfbToggled:)
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

- (void)configureWith:(NFBAdvField*)model on:(BOOL)on {
    self.model = model;
    BHTBundle* bundle = [BHTBundle sharedBundle];
    self.titleLabel2.text = [bundle localizedStringForKey:model.labelKey];
    self.subtitleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    self.toggle.on = on;
}

- (void)nfbToggled:(UISwitch*)sender {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:self.model.storeKey];
}

@end

// MARK: - calendar date cell

@interface NFBAdvDateCell : UITableViewCell
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIDatePicker* picker;
@property (nonatomic, strong) UIButton* clearButton;
@property (nonatomic, strong) NFBAdvField* model;
@end

@implementation NFBAdvDateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _picker = [[UIDatePicker alloc] init];
        _picker.datePickerMode = UIDatePickerModeDate;
        _picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
        [_picker addTarget:self
                      action:@selector(nfbDateChanged:)
            forControlEvents:UIControlEventValueChanged];

        _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_clearButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                      forState:UIControlStateNormal];
        _clearButton.tintColor = [UIColor systemGray3Color];
        [_clearButton addTarget:self
                          action:@selector(nfbClearDate)
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
        _floatLabel = NFBAdvInstallBox(self, row, &box, &example);
        _box = box;
        _exampleLabel = example;
        _floatLabel.alpha = 1.0;   // date rows keep their label visible
    }
    return self;
}

+ (NSDateFormatter*)nfbFormatter {
    static NSDateFormatter* f = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"yyyy-MM-dd";
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return f;
}

- (void)configureWith:(NFBAdvField*)model {
    self.model = model;
    BHTBundle* bundle = [BHTBundle sharedBundle];
    self.floatLabel.text = [bundle localizedStringForKey:model.labelKey];
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
    NSString* stored =
        [[NSUserDefaults standardUserDefaults] stringForKey:model.storeKey];
    NSDate* date = stored ? [[NFBAdvDateCell nfbFormatter] dateFromString:stored]
                          : nil;
    if (date) { self.picker.date = date; }
    BOOL active = (date != nil);
    self.picker.alpha = active ? 1.0 : 0.45;
    self.clearButton.hidden = !active;
}

- (void)nfbDateChanged:(UIDatePicker*)sender {
    if (!self.model) { return; }
    NSString* s = [[NFBAdvDateCell nfbFormatter] stringFromDate:sender.date];
    [[NSUserDefaults standardUserDefaults] setObject:s
                                              forKey:self.model.storeKey];
    self.picker.alpha = 1.0;
    self.clearButton.hidden = NO;
}

- (void)nfbClearDate {
    if (!self.model) { return; }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:self.model.storeKey];
    self.picker.alpha = 0.45;
    self.clearButton.hidden = YES;
}

@end

// MARK: - controller

@interface AdvancedSearchViewController ()
@property (nonatomic, strong) NSArray<NSString*>* sectionKeys;
@property (nonatomic, strong) NSArray<NSArray<NFBAdvField*>*>* sections;
@property (nonatomic, strong) NSArray<NSString*>* languageCodes;
@end

// The confirm glyph in the navigation bar is baked opaque white by the theme
// hooks, but only while NFBColorThemeScreenVisible is up — Twitter's settings
// roots and our own settings pages raise it, and this screen never did. Left
// out, the glyph stays a template the glass material blends with the capsule
// underneath, which is the wash that shows on a light accent and nowhere else.
// Joining the count is the whole fix: the recipe already exists, this screen
// simply was not counted.
// The confirm glyph comes out clean white on the yellow capsule because it is
// baked — opaque white pixels handed over as AlwaysOriginal, with nothing left
// for the glass material to blend. A title has no such escape: the label is
// drawn by the button itself, and the material washes it. That is the shine
// that survived giving the title an explicit colour, and it is why the
// checkmark on this same screen came out clean while the word did not.
//
// So the word is baked the same way the glyph is. Drawn once into a bitmap and
// passed as an image, it takes exactly the path that already works.
static UIImage* nfbBakedTitleImage(NSString* title, UIFont* font) {
    if (title.length == 0 || !font) {
        return nil;
    }
    NSDictionary* attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [UIColor whiteColor]
    };
    // A capsule built around an image comes out narrower than one built around a
    // title: measured side by side, 65.3 points against 84.7 for the same word.
    // The difference is padded back into the bitmap itself, transparently, so
    // the button keeps the proportions it had before the word became a picture.
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

extern NSInteger NFBColorThemeScreenVisible;

@implementation AdvancedSearchViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NFBColorThemeScreenVisible++;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (NFBColorThemeScreenVisible > 0) {
        NFBColorThemeScreenVisible--;
    }
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BHTBundle* bundle = [BHTBundle sharedBundle];
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
            [NFBAdvField key:@"nfb_advs_all" label:@"ADVSEARCH_ALL_WORDS"
                      example:@"ADVSEARCH_EX_ALL" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_exact" label:@"ADVSEARCH_EXACT_PHRASE"
                      example:@"ADVSEARCH_EX_EXACT" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_any" label:@"ADVSEARCH_ANY_WORDS"
                      example:@"ADVSEARCH_EX_ANY" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_none" label:@"ADVSEARCH_NONE_WORDS"
                      example:@"ADVSEARCH_EX_NONE" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_tags" label:@"ADVSEARCH_HASHTAGS"
                      example:@"ADVSEARCH_EX_TAGS" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_lang" label:@"ADVSEARCH_LANGUAGE"
                      example:nil kind:NFBAdvFieldMenu],
        ],
        @[
            [NFBAdvField key:@"nfb_advs_from" label:@"ADVSEARCH_FROM_ACCOUNTS"
                      example:@"ADVSEARCH_EX_FROM" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_to" label:@"ADVSEARCH_TO_ACCOUNTS"
                      example:@"ADVSEARCH_EX_TO" kind:NFBAdvFieldText],
            [NFBAdvField key:@"nfb_advs_mention" label:@"ADVSEARCH_MENTIONING"
                      example:@"ADVSEARCH_EX_MENTION" kind:NFBAdvFieldText],
        ],
        @[
            [NFBAdvField key:@"nfb_advs_replies" label:@"ADVSEARCH_REPLIES"
                      example:@"ADVSEARCH_REPLIES_SUB" kind:NFBAdvFieldToggle],
            [NFBAdvField key:@"nfb_advs_links" label:@"ADVSEARCH_LINKS"
                      example:@"ADVSEARCH_LINKS_SUB" kind:NFBAdvFieldToggle],
        ],
        @[
            [NFBAdvField key:@"nfb_advs_minreplies" label:@"ADVSEARCH_MIN_REPLIES"
                      example:@"ADVSEARCH_EX_MINREPLIES" kind:NFBAdvFieldNumber],
            [NFBAdvField key:@"nfb_advs_minfaves" label:@"ADVSEARCH_MIN_LIKES"
                      example:@"ADVSEARCH_EX_MINLIKES" kind:NFBAdvFieldNumber],
            [NFBAdvField key:@"nfb_advs_minrt" label:@"ADVSEARCH_MIN_REPOSTS"
                      example:@"ADVSEARCH_EX_MINREPOSTS" kind:NFBAdvFieldNumber],
        ],
        @[
            [NFBAdvField key:@"nfb_advs_since" label:@"ADVSEARCH_SINCE_DATE"
                      example:@"ADVSEARCH_EX_SINCE" kind:NFBAdvFieldDate],
            [NFBAdvField key:@"nfb_advs_until" label:@"ADVSEARCH_UNTIL_DATE"
                      example:@"ADVSEARCH_EX_UNTIL" kind:NFBAdvFieldDate],
        ],
    ];

    // SYSTEM Done bar button: one single native Liquid Glass capsule (a
    // custom view gets WRAPPED in a second glass capsule — the double-pill
    // bug), and with no explicit tint it inherits the fork's window tint, so
    // it follows the user's colour theme automatically.
    NSString* searchTitle = [bundle localizedStringForKey:@"ADVSEARCH_SEARCH"];
    UIFont* searchFont = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15];
    UIImage* bakedTitle = nfbBakedTitleImage(searchTitle, searchFont);
    if (bakedTitle) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithImage:bakedTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(nfbRunSearch)];
        // The word is a picture now, so VoiceOver is told what it says.
        self.navigationItem.rightBarButtonItem.accessibilityLabel = searchTitle;
    } else {
        // Only reachable if the bitmap could not be drawn at all; a bar button
        // with no image would simply be invisible, so the plain title stands in.
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:searchTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(nfbRunSearch)];
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
                                 action:@selector(nfbCancel)];
    }
    NSDictionary* chirpTitle = @{
        NSFontAttributeName : [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17]
    };
    self.navigationController.navigationBar.titleTextAttributes = chirpTitle;

    // Outline pill, pale grey border and pale grey text — the fork's
    // "Reset to default" style, per request.
    UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 78.0)];
    UIButton* clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:[bundle localizedStringForKey:@"ADVSEARCH_CLEAR"]
           forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor secondaryLabelColor]
                forState:UIControlStateNormal];
    clear.titleLabel.font =
        [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15.5];
    clear.layer.borderWidth = 1.0;
    clear.layer.borderColor = [UIColor systemGray4Color].CGColor;
    clear.layer.cornerRadius = 22.0;
    [clear addTarget:self
                  action:@selector(nfbClearAll)
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
    [self.tableView registerClass:[NFBAdvBoxCell class]
           forCellReuseIdentifier:@"box"];
    [self.tableView registerClass:[NFBAdvMenuCell class]
           forCellReuseIdentifier:@"menu"];
    [self.tableView registerClass:[NFBAdvToggleCell class]
           forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:[NFBAdvDateCell class]
           forCellReuseIdentifier:@"date"];
    self.tableView.keyboardDismissMode =
        UIScrollViewKeyboardDismissModeInteractive;
}

// MARK: language helpers

static NSString* NFBAdvLangName(NSString* code) {
    NSString* name =
        [[NSLocale currentLocale] localizedStringForLanguageCode:code];
    if (name.length) {
        return [[[name substringToIndex:1] localizedUppercaseString]
            stringByAppendingString:[name substringFromIndex:1]];
    }
    return code;
}

- (NSString*)nfbCurrentLanguageTitle {
    NSString* code =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"nfb_advs_lang"];
    if (code.length == 0) {
        return [[BHTBundle sharedBundle]
            localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"];
    }
    return NFBAdvLangName(code);
}

- (UIMenu*)nfbLanguageMenu {
    NSString* current =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"nfb_advs_lang"]
            ?: @"";
    __weak typeof(self) weakSelf = self;
    NSMutableArray* actions = [NSMutableArray array];
    UIAction* any = [UIAction
        actionWithTitle:[[BHTBundle sharedBundle]
                            localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"]
                  image:nil
             identifier:nil
                handler:^(UIAction* a) {
                    [[NSUserDefaults standardUserDefaults]
                        removeObjectForKey:@"nfb_advs_lang"];
                    [weakSelf.tableView reloadData];
                }];
    any.state = (current.length == 0) ? UIMenuElementStateOn
                                      : UIMenuElementStateOff;
    [actions addObject:any];
    for (NSString* code in self.languageCodes) {
        UIAction* a = [UIAction
            actionWithTitle:NFBAdvLangName(code)
                      image:nil
                 identifier:nil
                    handler:^(UIAction* act) {
                        [[NSUserDefaults standardUserDefaults]
                            setObject:code forKey:@"nfb_advs_lang"];
                        [weakSelf.tableView reloadData];
                    }];
        a.state = [current isEqualToString:code] ? UIMenuElementStateOn
                                                 : UIMenuElementStateOff;
        [actions addObject:a];
    }
    return [UIMenu menuWithChildren:actions];
}

// Filters default ON (the web form's default): absent key means included.
static BOOL NFBAdvFilterOn(NSString* key) {
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
    label.text = [[BHTBundle sharedBundle]
        localizedStringForKey:self.sectionKeys[(NSUInteger)section]];
    label.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20];
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
    NFBAdvField* model =
        self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    switch (model.kind) {
        case NFBAdvFieldMenu: {
            NFBAdvMenuCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"menu"
                                                forIndexPath:indexPath];
            NSString* code = [[NSUserDefaults standardUserDefaults]
                stringForKey:@"nfb_advs_lang"];
            [cell configureWith:model
                           menu:[self nfbLanguageMenu]
                   currentTitle:[self nfbCurrentLanguageTitle]
                       hasValue:(code.length > 0)];
            return cell;
        }
        case NFBAdvFieldToggle: {
            NFBAdvToggleCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"toggle"
                                                forIndexPath:indexPath];
            [cell configureWith:model on:NFBAdvFilterOn(model.storeKey)];
            return cell;
        }
        case NFBAdvFieldDate: {
            NFBAdvDateCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"date"
                                                forIndexPath:indexPath];
            [cell configureWith:model];
            return cell;
        }
        default: {
            NFBAdvBoxCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"box"
                                                forIndexPath:indexPath];
            [cell configureWith:model];
            return cell;
        }
    }
}

// MARK: actions

- (void)nfbCancel {
    [self.presentingViewController dismissViewControllerAnimated:YES
                                                      completion:nil];
}

- (void)nfbClearAll {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    for (NSArray<NFBAdvField*>* section in self.sections) {
        for (NFBAdvField* f in section) {
            [d removeObjectForKey:f.storeKey];
        }
    }
    [self.tableView reloadData];
}

// MARK: query building

static NSArray<NSString*>* NFBAdvTokens(NSString* raw) {
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

static NSString* NFBAdvOrGroup(NSArray<NSString*>* tokens) {
    if (tokens.count == 1) { return tokens[0]; }
    return [NSString stringWithFormat:@"(%@)",
                                      [tokens componentsJoinedByString:@" OR "]];
}

static NSString* NFBAdvValue(NSString* key) {
    NSString* v = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return [v stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceCharacterSet]] ?: @"";
}

- (NSString*)nfbBuildQueryOrError:(NSString**)errorKey {
    NSMutableArray* parts = [NSMutableArray array];

    NSString* all = NFBAdvValue(@"nfb_advs_all");
    if (all.length) { [parts addObject:all]; }

    NSString* exact = NFBAdvValue(@"nfb_advs_exact");
    if (exact.length) {
        [parts addObject:[NSString stringWithFormat:@"\"%@\"", exact]];
    }

    NSArray* any = NFBAdvTokens(NFBAdvValue(@"nfb_advs_any"));
    if (any.count) { [parts addObject:NFBAdvOrGroup(any)]; }

    for (NSString* t in NFBAdvTokens(NFBAdvValue(@"nfb_advs_none"))) {
        [parts addObject:[NSString stringWithFormat:@"-%@", t]];
    }

    NSMutableArray* tags = [NSMutableArray array];
    for (NSString* t in NFBAdvTokens(NFBAdvValue(@"nfb_advs_tags"))) {
        [tags addObject:[t hasPrefix:@"#"]
                            ? t
                            : [NSString stringWithFormat:@"#%@", t]];
    }
    if (tags.count) { [parts addObject:NFBAdvOrGroup(tags)]; }

    NSString* lang =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"nfb_advs_lang"];
    if (lang.length) {
        [parts addObject:[NSString stringWithFormat:@"lang:%@", lang]];
    }

    NSMutableArray* from = [NSMutableArray array];
    for (NSString* t in NFBAdvTokens(NFBAdvValue(@"nfb_advs_from"))) {
        NSString* u = [t hasPrefix:@"@"] ? [t substringFromIndex:1] : t;
        [from addObject:[NSString stringWithFormat:@"from:%@", u]];
    }
    if (from.count) { [parts addObject:NFBAdvOrGroup(from)]; }

    NSMutableArray* to = [NSMutableArray array];
    for (NSString* t in NFBAdvTokens(NFBAdvValue(@"nfb_advs_to"))) {
        NSString* u = [t hasPrefix:@"@"] ? [t substringFromIndex:1] : t;
        [to addObject:[NSString stringWithFormat:@"to:%@", u]];
    }
    if (to.count) { [parts addObject:NFBAdvOrGroup(to)]; }

    NSMutableArray* mention = [NSMutableArray array];
    for (NSString* t in NFBAdvTokens(NFBAdvValue(@"nfb_advs_mention"))) {
        NSString* u = [t hasPrefix:@"@"] ? t
                                         : [NSString stringWithFormat:@"@%@", t];
        [mention addObject:u];
    }
    if (mention.count) { [parts addObject:NFBAdvOrGroup(mention)]; }

    if (!NFBAdvFilterOn(@"nfb_advs_replies")) {
        [parts addObject:@"-filter:replies"];
    }
    if (!NFBAdvFilterOn(@"nfb_advs_links")) {
        [parts addObject:@"-filter:links"];
    }

    struct {
        __unsafe_unretained NSString* key;
        __unsafe_unretained NSString* op;
    } mins[] = {
        { @"nfb_advs_minreplies", @"min_replies" },
        { @"nfb_advs_minfaves", @"min_faves" },
        { @"nfb_advs_minrt", @"min_retweets" },
    };
    for (size_t i = 0; i < sizeof(mins) / sizeof(mins[0]); i++) {
        NSString* v = NFBAdvValue(mins[i].key);
        if (v.length && v.integerValue > 0) {
            [parts addObject:[NSString stringWithFormat:@"%@:%ld", mins[i].op,
                                                        (long)v.integerValue]];
        }
    }

    NSString* since = NFBAdvValue(@"nfb_advs_since");
    if (since.length) {
        [parts addObject:[NSString stringWithFormat:@"since:%@", since]];
    }
    NSString* until = NFBAdvValue(@"nfb_advs_until");
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

- (void)nfbRunSearch {
    [self.view endEditing:YES];
    NSString* errorKey = nil;
    NSString* query = [self nfbBuildQueryOrError:&errorKey];
    if (!query) {
        BHTBundle* bundle = [BHTBundle sharedBundle];
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

    // Close the form first, then hand the deep link STRAIGHT to Twitter's own
    // internal URL router (the app delegate's openURL:options: — the proven
    // in-app mechanism this fork already uses to open a status natively after
    // a web reply). Never through iOS: a sideloaded bundle may not have the
    // twitter:// scheme registered, and any web fallback lands in Safari on a
    // login wall. Everything stays in-app by construction.
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
