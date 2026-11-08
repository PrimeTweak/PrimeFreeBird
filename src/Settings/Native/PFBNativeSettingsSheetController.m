// One group of a settings page in a sheet, as Twitter's new settings show theirs: its title and
// a close button, the group's rows, then Done. A row's choices open as a step of the sheet, and a
// value to type gets a sheet of its own laid out the same way.

#import "Settings/Native/PFBNativeSettingsSheetController.h"
#import "Common/PFBBundle.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/PFBManager.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"

static void* kPFBSheetRowsContext = &kPFBSheetRowsContext;

// The room under the content: the gap above the button, the button itself, and the margin below it.
static const CGFloat kPFBSheetDoneGap = 12;
static const CGFloat kPFBSheetDoneHeight = 48;
static const CGFloat kPFBSheetBottomMargin = 16;
// A step's row and the ring that marks the chosen one; a value's field, as the new look's Filters.
static const CGFloat kPFBChoiceRowHeight = 52;
static const CGFloat kPFBChoiceRing = 22;
static const CGFloat kPFBFieldHeight = 50;

static UIFont* PFBSheetBoldFont(void) {
    return PFBFontGroupFont(@selector(headline2BoldFont), [UIFont systemFontOfSize:17 weight:UIFontWeightBold]);
}

static UIColor* PFBSheetGround(void) {
    return PFBShowcaseUsesGlass() ? [UIColor clearColor] : [PFBPalette currentBackgroundColor];
}

// A sheet's button in the text color with the background's color on it, as Twitter's own.
static UIButton* PFBSheetButton(NSString* title) {
    UIButton* button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    button.layer.cornerRadius = kPFBSheetDoneHeight / 2;
    return button;
}

static void PFBSheetThemeButton(UIButton* button) {
    UIColor* ground = [PFBPalette currentBackgroundColor];
    button.backgroundColor = PFBSettingsTextColor();
    button.titleLabel.font = PFBSheetBoldFont();
    [button setTitleColor:ground forState:UIControlStateNormal];
    [button setTitleColor:[ground colorWithAlphaComponent:0.6] forState:UIControlStateHighlighted];
}

// The button sits under the content, held above the bottom edge.
static NSArray<NSLayoutConstraint*>* PFBSheetButtonConstraints(UIButton* button, UIView* view) {
    return @[
        [button.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
        [button.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20],
        [button.heightAnchor constraintEqualToConstant:kPFBSheetDoneHeight],
        [button.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor
                                            constant:-kPFBSheetBottomMargin],
    ];
}

// The sheet's height from the room its content takes, within what the screen allows.
static void PFBSheetFitDetent(UIViewController* sheet, CGFloat (^height)(void)) {
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController* presentation = sheet.sheetPresentationController;
    if (@available(iOS 16.0, *)) {
        presentation.detents = @[ [UISheetPresentationControllerDetent
            customDetentWithIdentifier:@"pfb.group"
                              resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                  CGFloat fitted = height();
                                  return fitted > 0 ? MIN(fitted, context.maximumDetentValue)
                                                    : context.maximumDetentValue;
                              }] ];
    } else {
        presentation.detents = @[ [UISheetPresentationControllerDetent mediumDetent],
                                  [UISheetPresentationControllerDetent largeDetent] ];
    }
}

// Lets the sheet take the height its content now needs; while it comes up, the new height joins
// its opening rather than following it.
static void PFBSheetRefit(UIViewController* sheet) {
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController* presentation = sheet.sheetPresentationController;
        if (sheet.isBeingPresented) {
            [presentation invalidateDetents];
            return;
        }
        [presentation animateChanges:^{
            [presentation invalidateDetents];
        }];
    }
}

#pragma mark - Head

@implementation PFBNativeSheetHead {
    BOOL _step;
    UIView* _line;
}

- (instancetype)initWithTitle:(NSString*)title step:(BOOL)step {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _step = step;
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.numberOfLines = 0;
        _titleLabel.textAlignment = step ? NSTextAlignmentCenter : NSTextAlignmentNatural;
        _titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
        _button = [UIButton buttonWithType:UIButtonTypeCustom];
        _button.accessibilityLabel = [[PFBBundle sharedBundle]
            localizedTwitterStringForKey:step ? @"BACK_ACTION_ACCESSIBILITY_LABEL" : @"CLOSE_ACTION_LABEL"];
        _line = [[UIView alloc] init];
        for (UIView* part in @[ _titleLabel, _button, _line ]) {
            part.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:part];
        }
        // The step's title stays centered, with the back button's room kept on both sides.
        NSArray<NSLayoutConstraint*>* placed =
            step ? @[
                [_titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
                [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:58],
                [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-58],
                [_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            ]
                 : @[
                       [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
                       [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_button.leadingAnchor
                                                                            constant:-12],
                       [_button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
                   ];
        [NSLayoutConstraint activateConstraints:placed];
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:24],
            [_button.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_button.widthAnchor constraintEqualToConstant:36],
            [_button.heightAnchor constraintEqualToConstant:36],
            [_line.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:18],
            [_line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
            [_line.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        [self applyTheme];
    }
    return self;
}

// The title bold at 20 pt and the button's Twitter glyph, both in the text color; the system
// symbol stands in where the app has no glyph.
- (void)applyTheme {
    UIColor* ink = PFBSettingsTextColor();
    self.titleLabel.font = PFBScaledFont([PFBSheetBoldFont() fontWithSize:20]);
    self.titleLabel.textColor = ink;
    _line.backgroundColor = PFBSettingsDividerColor();
    NSString* name = _step ? @"chevron_left" : @"close_nomargin";
    UIImage* glyph = [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]
                         ? [UIImage tfn_vectorImageNamed:name fitsSize:CGSizeMake(16, 16) fillColor:ink]
                         : nil;
    glyph = glyph ?: [UIImage systemImageNamed:_step ? @"chevron.left" : @"xmark"];
    [self.button setImage:_step ? [glyph imageFlippedForRightToLeftLayoutDirection] : glyph
                 forState:UIControlStateNormal];
    self.button.tintColor = ink;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end

#pragma mark - Choice row

@implementation PFBSheetChoiceRow {
    UIView* _ring;
}

- (instancetype)initWithTitle:(NSString*)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _title = [[UILabel alloc] init];
        _title.text = title;
        _title.numberOfLines = 0;
        _ring = [[UIView alloc] init];
        _ring.layer.cornerRadius = kPFBChoiceRing / 2;
        for (UIView* part in @[ _title, _ring ]) {
            part.translatesAutoresizingMaskIntoConstraints = NO;
            part.userInteractionEnabled = NO;
            [self addSubview:part];
        }
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:kPFBChoiceRowHeight],
            [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
            [_title.trailingAnchor constraintLessThanOrEqualToAnchor:_ring.leadingAnchor constant:-12],
            [_title.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:14],
            [_title.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14],
            [_title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_ring.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
            [_ring.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_ring.widthAnchor constraintEqualToConstant:kPFBChoiceRing],
            [_ring.heightAnchor constraintEqualToConstant:kPFBChoiceRing],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = title;
        [self applyTheme];
    }
    return self;
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self applyTheme];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.4;
    [self applyTheme];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? PFBSettingsFaintColor() : [UIColor clearColor];
}

// The chosen ring takes the text color and a thick stroke. A CGColor does not follow the
// appearance, so the stroke is set again on every change.
- (void)applyTheme {
    self.title.font = [PFBNativeSettingsRowStyle shared].titleFont
                          ?: PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
    self.title.textColor = PFBSettingsTextColor();
    UIColor* stroke = self.chosen ? PFBSettingsTextColor() : PFBSettingsSubtitleColor();
    _ring.layer.borderColor = [stroke resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    _ring.layer.borderWidth = self.chosen ? 6.5 : 1.5;
    self.accessibilityTraits = UIAccessibilityTraitButton | (self.chosen ? UIAccessibilityTraitSelected : 0) |
                               (self.enabled ? 0 : UIAccessibilityTraitNotEnabled);
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end

#pragma mark - Field sheet

// A value to type in a sheet of its own: the head, the note, the field, then Save.
@interface PFBNativeFieldSheetController : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) NSString* sheetTitle;
@property (nonatomic, copy) NSString* note;
@property (nonatomic, copy) NSString* value;
@property (nonatomic, copy) NSString* placeholder;
@property (nonatomic, copy) void (^save)(NSString* text);
@property (nonatomic) CGFloat fittedHeight;
@end

@implementation PFBNativeFieldSheetController {
    UILabel* _noteLabel;
    PFBShowcaseSurface* _surface;
    UITextField* _field;
    UIButton* _saveButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBNativeSheetHead* head = [[PFBNativeSheetHead alloc] initWithTitle:self.sheetTitle step:NO];
    [head.button addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    _noteLabel = [[UILabel alloc] init];
    _noteLabel.text = self.note;
    _noteLabel.numberOfLines = 0;
    _surface = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
    _field = [[UITextField alloc] init];
    _field.text = self.value;
    _field.placeholder = self.placeholder;
    _field.keyboardType = UIKeyboardTypeURL;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.returnKeyType = UIReturnKeyDone;
    _field.delegate = self;
    _saveButton = PFBSheetButton([[PFBBundle sharedBundle] localizedTwitterStringForKey:@"SAVE_ACTION_LABEL"]);
    [_saveButton addTarget:self action:@selector(saveAndClose) forControlEvents:UIControlEventTouchUpInside];
    for (UIView* part in @[ head, _noteLabel, _surface, _saveButton ]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:part];
    }
    _field.translatesAutoresizingMaskIntoConstraints = NO;
    [_surface.contentView addSubview:_field];
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [head.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [head.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_noteLabel.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:16],
        [_noteLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [_noteLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [_surface.topAnchor constraintEqualToAnchor:_noteLabel.bottomAnchor constant:16],
        [_surface.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_surface.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_surface.heightAnchor constraintEqualToConstant:kPFBFieldHeight],
        [_field.leadingAnchor constraintEqualToAnchor:_surface.contentView.leadingAnchor constant:18],
        [_field.trailingAnchor constraintEqualToAnchor:_surface.contentView.trailingAnchor constant:-12],
        [_field.topAnchor constraintEqualToAnchor:_surface.contentView.topAnchor],
        [_field.bottomAnchor constraintEqualToAnchor:_surface.contentView.bottomAnchor],
    ]];
    [NSLayoutConstraint activateConstraints:PFBSheetButtonConstraints(_saveButton, self.view)];
    [self applyTheme];
}

- (void)applyTheme {
    self.view.backgroundColor = PFBSheetGround();
    _noteLabel.font = PFBSettingsDetailFont();
    _noteLabel.textColor = PFBSettingsSubtitleColor();
    _field.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
    _field.textColor = PFBSettingsTextColor();
    if (self.placeholder.length) {
        _field.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:self.placeholder
                attributes:@{NSForegroundColorAttributeName: PFBSettingsSubtitleColor()}];
    }
    PFBSheetThemeButton(_saveButton);
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

// The keyboard comes up with the sheet, as with the alert it replaces.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_field becomeFirstResponder];
}

// The head, the note and the field, then Save.
- (CGFloat)contentHeight {
    return CGRectGetMaxY(_surface.frame) + kPFBSheetDoneGap + kPFBSheetDoneHeight + kPFBSheetBottomMargin;
}

// A larger text size makes the note taller, and the sheet with it.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat height = [self contentHeight];
    if (self.fittedHeight > 0 && fabs(height - self.fittedHeight) >= 1) {
        self.fittedHeight = height;
        PFBSheetRefit(self);
    }
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [self saveAndClose];
    return NO;
}

- (void)saveAndClose {
    void (^save)(NSString*) = self.save;
    self.save = nil;
    if (save) {
        save(_field.text ?: @"");
    }
    [self close];
}

- (void)close {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Group sheet

@interface PFBNativeSettingsSheetController ()
@property (nonatomic, strong) UIViewController<PFBNativeSheetRows>* page;
@property (nonatomic, copy) NSString* groupTitle;
@property (nonatomic, copy) void (^closed)(void);
@property (nonatomic, strong) PFBNativeSheetHead* head;
@property (nonatomic, strong) UIButton* doneButton;
@property (nonatomic) CGFloat fittedHeight;
@property (nonatomic) BOOL watchingRows;
// The step a row's choices opened, with their actions and rows; nil while the rows show.
@property (nonatomic, strong) UIView* stepView;
@property (nonatomic, copy) NSArray<UIAction*>* stepActions;
@property (nonatomic, copy) NSArray<PFBSheetChoiceRow*>* stepRows;
@end

@implementation PFBNativeSettingsSheetController

+ (void)presentRows:(UIViewController<PFBNativeSheetRows>*)rows
             titled:(NSString*)title
               from:(UIViewController*)presenter
             closed:(void (^)(void))closed {
    PFBNativeSettingsSheetController* sheet = [[self alloc] init];
    sheet.page = rows;
    sheet.groupTitle = title;
    sheet.closed = closed;
    // Sized once at the window's width before it opens, so the sheet comes up at its rows' height.
    [sheet loadViewIfNeeded];
    sheet.view.frame = presenter.view.window ? presenter.view.window.bounds : UIScreen.mainScreen.bounds;
    [sheet.view layoutIfNeeded];
    [rows.tableView layoutIfNeeded];
    sheet.fittedHeight = [sheet contentHeight];
    __weak PFBNativeSettingsSheetController* weakSheet = sheet;
    PFBSheetFitDetent(sheet, ^CGFloat {
        return weakSheet.fittedHeight;
    });
    [presenter presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentFieldTitled:(NSString*)title
                      note:(NSString*)note
                     value:(NSString*)value
               placeholder:(NSString*)placeholder
                      from:(UIViewController*)presenter
                      save:(void (^)(NSString* text))save {
    PFBNativeFieldSheetController* sheet = [[PFBNativeFieldSheetController alloc] init];
    sheet.sheetTitle = title;
    sheet.note = note;
    sheet.value = value;
    sheet.placeholder = placeholder;
    sheet.save = save;
    // Sized once at the window's width before it opens, as a group's sheet.
    [sheet loadViewIfNeeded];
    sheet.view.frame = presenter.view.window ? presenter.view.window.bounds : UIScreen.mainScreen.bounds;
    [sheet.view layoutIfNeeded];
    sheet.fittedHeight = [sheet contentHeight];
    __weak PFBNativeFieldSheetController* weakSheet = sheet;
    PFBSheetFitDetent(sheet, ^CGFloat {
        return weakSheet.fittedHeight;
    });
    [presenter presentViewController:sheet animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.head = [[PFBNativeSheetHead alloc] initWithTitle:self.groupTitle step:NO];
    [self.head.button addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    self.doneButton = PFBSheetButton([[PFBBundle sharedBundle] localizedTwitterStringForKey:@"DONE_ACTION_LABEL"]);
    [self.doneButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];

    [self addChildViewController:self.page];
    UIView* rows = self.page.view;
    for (UIView* part in @[ self.head, rows, self.doneButton ]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:part];
    }
    [self.page didMoveToParentViewController:self];

    // With the rows' own 10 pt margin, these 14 pt put their text under the title.
    [NSLayoutConstraint activateConstraints:@[
        [self.head.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.head.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.head.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [rows.topAnchor constraintEqualToAnchor:self.head.bottomAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [rows.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [rows.bottomAnchor constraintEqualToAnchor:self.doneButton.topAnchor constant:-kPFBSheetDoneGap],
    ]];
    [NSLayoutConstraint activateConstraints:PFBSheetButtonConstraints(self.doneButton, self.view)];
    [self.page.tableView addObserver:self forKeyPath:@"contentSize" options:0 context:kPFBSheetRowsContext];
    self.watchingRows = YES;
    [self applyTheme];
}

- (void)dealloc {
    if (_watchingRows) {
        [_page.tableView removeObserver:self forKeyPath:@"contentSize" context:kPFBSheetRowsContext];
    }
}

- (void)applyTheme {
    self.view.backgroundColor = PFBSheetGround();
    PFBSheetThemeButton(self.doneButton);
}

// The rows and the heads keep up on their own; the ground and Done follow here.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Done, the X and a swipe down all end here.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    void (^closed)(void) = self.closed;
    if (self.isBeingDismissed && closed) {
        self.closed = nil;
        closed();
    }
}

// The head and the rows, or the step, then Done.
- (CGFloat)contentHeight {
    CGFloat top = self.stepView ? CGRectGetMaxY(self.stepView.frame)
                                : CGRectGetMinY(self.page.view.frame) + self.page.tableView.contentSize.height;
    return top + kPFBSheetDoneGap + kPFBSheetDoneHeight + kPFBSheetBottomMargin;
}

// Rows that appear, go or change size resize the sheet, as a step does, once the layout is over.
- (void)refit {
    if (self.fittedHeight <= 0) {
        return;
    }
    CGFloat height = [self contentHeight];
    if (fabs(height - self.fittedHeight) < 1) {
        return;
    }
    self.fittedHeight = height;
    PFBSheetRefit(self);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self refit];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
    if (context == kPFBSheetRowsContext) {
        [self.view setNeedsLayout];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Step

// The step takes the place of the head and the rows at its own height; Done stays.
- (void)showChoices:(UIMenu*)menu note:(NSString*)note {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    for (UIMenuElement* element in menu.children) {
        if ([element isKindOfClass:[UIAction class]]) {
            [actions addObject:(UIAction*)element];
        }
    }
    if (actions.count == 0 || self.stepView) {
        return;
    }
    PFBNativeSheetHead* head = [[PFBNativeSheetHead alloc] initWithTitle:menu.title step:YES];
    [head.button addTarget:self action:@selector(leaveStep) forControlEvents:UIControlEventTouchUpInside];
    UILabel* noteLabel = [[UILabel alloc] init];
    noteLabel.text = note;
    noteLabel.numberOfLines = 0;
    noteLabel.font = PFBSettingsDetailFont();
    noteLabel.textColor = PFBSettingsSubtitleColor();
    NSMutableArray<PFBSheetChoiceRow*>* rows = [NSMutableArray array];
    for (UIAction* action in actions) {
        PFBSheetChoiceRow* row = [[PFBSheetChoiceRow alloc] initWithTitle:action.title];
        row.chosen = action.state == UIMenuElementStateOn;
        row.enabled = !(action.attributes & UIMenuElementAttributesDisabled);
        [row addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
        [rows addObject:row];
    }
    UIStackView* list = [[UIStackView alloc] initWithArrangedSubviews:rows];
    list.axis = UILayoutConstraintAxisVertical;
    BOOL hasNote = note.length > 0;
    noteLabel.hidden = !hasNote;
    UIView* step = [[UIView alloc] init];
    for (UIView* part in @[ head, noteLabel, list ]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
        [step addSubview:part];
    }
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:step.topAnchor],
        [head.leadingAnchor constraintEqualToAnchor:step.leadingAnchor],
        [head.trailingAnchor constraintEqualToAnchor:step.trailingAnchor],
        [noteLabel.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:16],
        [noteLabel.leadingAnchor constraintEqualToAnchor:step.leadingAnchor constant:24],
        [noteLabel.trailingAnchor constraintEqualToAnchor:step.trailingAnchor constant:-24],
        [list.topAnchor constraintEqualToAnchor:hasNote ? noteLabel.bottomAnchor : head.bottomAnchor constant:8],
        [list.leadingAnchor constraintEqualToAnchor:step.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:step.trailingAnchor],
        [list.bottomAnchor constraintEqualToAnchor:step.bottomAnchor],
    ]];
    self.stepView = step;
    self.stepActions = actions;
    self.stepRows = rows;
    step.translatesAutoresizingMaskIntoConstraints = NO;
    step.alpha = 0;
    [self.view addSubview:step];
    [NSLayoutConstraint activateConstraints:@[
        [step.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [step.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [step.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    [self.view layoutIfNeeded];
    // Only the content fades: Done stays drawn and follows the sheet's bottom as it resizes.
    [UIView animateWithDuration:0.25
        animations:^{
          step.alpha = 1;
          [self fadeGroup:0];
        }
        completion:^(__unused BOOL finished) {
          if (self.stepView == step) {
              [self showGroup:NO];
              [self fadeGroup:1];
          }
        }];
    [self.view setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, head.titleLabel);
}

// The group's head and rows, hidden while a step shows.
- (void)showGroup:(BOOL)shown {
    self.head.hidden = !shown;
    self.page.view.hidden = !shown;
}

- (void)fadeGroup:(CGFloat)alpha {
    self.head.alpha = alpha;
    self.page.view.alpha = alpha;
}

- (void)leaveStep {
    UIView* step = self.stepView;
    self.stepView = nil;
    self.stepActions = nil;
    self.stepRows = nil;
    [self fadeGroup:0];
    [self showGroup:YES];
    [UIView animateWithDuration:0.25
        animations:^{
          step.alpha = 0;
          [self fadeGroup:1];
        }
        completion:^(__unused BOOL finished) {
          [step removeFromSuperview];
        }];
    [self.view setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.head.titleLabel);
}

// The ring moves at once; the action is the menu's own, so the page stores the choice as before.
- (void)choose:(PFBSheetChoiceRow*)row {
    NSUInteger index = [self.stepRows indexOfObjectIdenticalTo:row];
    if (index == NSNotFound) {
        return;
    }
    for (PFBSheetChoiceRow* other in self.stepRows) {
        other.chosen = other == row;
    }
    [row sendAction:self.stepActions[index]];
}

@end
