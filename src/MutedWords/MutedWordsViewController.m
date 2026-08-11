//
//  MutedWordsViewController.m
//  PrimeFreeBird
//
//  The list lives in NSUserDefaults as plain strings. Anything starting with
//  "@" is treated as an account handle, anything containing a space as a
//  phrase, everything else as a single word. Timeline.x reads the same keys
//  and is told to reload through nfbRefreshMutedWords() whenever this screen
//  changes something, so filtering updates without a restart.
//

#import "MutedWords/MutedWordsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/TwitterChirpFont.h"
#import "Hooks/HookHelpers.h"

// The table's layout margins resolve to about 20 points inside a cell and
// about 8 on the bare view a section header is built from, putting headers
// and their rows on two different verticals — and neither matches the 10
// points the rest of the settings uses (ModernSettingsCells). One number,
// applied everywhere.
static const CGFloat kNFBMutedSideMargin = 10.0;
// A language row's own height, so the switch is spaced like one more entry.
static const CGFloat kNFBTranslateBarHeight = 44.0;

NSString* const kNFBMutedWordsKey = @"nfb_muted_words";
NSString* const kNFBMutedWholeWordsKey = @"nfb_muted_whole_words";
NSString* const kNFBMutedInConversationsKey = @"nfb_muted_in_conversations";
NSString* const kNFBMutedCountKey = @"nfb_muted_words_count";
NSString* const kNFBMutedExpiryKey = @"nfb_muted_expiry";
NSString* const kNFBMutedSkipFollowingKey = @"nfb_muted_skip_following";
NSString* const kNFBMutedIncludeRepostsKey = @"nfb_muted_include_reposts";

// MARK: - add row

@interface NFBMutedAddCell : UITableViewCell
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) UIButton* addButton;
@property (nonatomic, strong) UILabel* hintLabel;
// The popover closes this gap so the box sits under the segment exactly as
// the first language row does.
@property (nonatomic, strong) NSLayoutConstraint* boxTop;
@end

@implementation NFBMutedAddCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        // Bordered box, 1px systemGray3, radius 6 — the exact box the advanced
        // search screen uses, so the two screens read as one design.
        UIView* box = [[UIView alloc] init];
        box.layer.borderWidth = 1.0;
        box.layer.borderColor = [UIColor systemGray3Color].CGColor;
        box.layer.cornerRadius = 6.0;

        _field = [[UITextField alloc] init];
        _field.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16];
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.returnKeyType = UIReturnKeyDone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;

        // The explanation lives inside this cell, under the box: that keeps
        // the order fixed (box, then hint, then the list) in both the full
        // screen and the popover, without a separate footer.
        _hintLabel = [[UILabel alloc] init];
        _hintLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5];
        _hintLabel.textColor = [UIColor secondaryLabelColor];
        _hintLabel.numberOfLines = 0;

        _addButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _addButton.titleLabel.font =
            [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15];
        [_addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _addButton.backgroundColor = self.tintColor ?: [UIColor systemBlueColor];
        _addButton.layer.cornerRadius = 6.0;
        [_addButton setContentHuggingPriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisHorizontal];

        for (UIView* v in @[ box, _addButton, _hintLabel ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        [box addSubview:_field];

        _boxTop = [box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                               constant:8.0];
        [NSLayoutConstraint activateConstraints:@[
            [box.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                              constant:kNFBMutedSideMargin],
            _boxTop,
            [box.heightAnchor constraintEqualToConstant:42.0],
            [_hintLabel.topAnchor constraintEqualToAnchor:box.bottomAnchor
                                                 constant:8.0],
            [_hintLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:kNFBMutedSideMargin + 2.0],
            [_hintLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                      constant:-kNFBMutedSideMargin],
            [_hintLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                    constant:-10.0],
            [_field.leadingAnchor constraintEqualToAnchor:box.leadingAnchor
                                                 constant:12.0],
            [_field.trailingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                  constant:-10.0],
            [_field.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [_addButton.leadingAnchor constraintEqualToAnchor:box.trailingAnchor
                                                     constant:10.0],
            [_addButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                      constant:-kNFBMutedSideMargin],
            [_addButton.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [_addButton.heightAnchor constraintEqualToConstant:42.0],
            [_addButton.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],
        ]];
    }
    return self;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    self.addButton.backgroundColor = self.tintColor ?: [UIColor systemBlueColor];
}

@end

// MARK: - term row (badge on the left, remove button on the right)

@interface NFBMutedTermCell : UITableViewCell
@property (nonatomic, strong) UILabel* kindLabel;
@property (nonatomic, strong) UILabel* termLabel;
@property (nonatomic, strong) UIButton* durationButton;
@property (nonatomic, strong) UIButton* removeButton;
@end

@implementation NFBMutedTermCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _kindLabel = [[UILabel alloc] init];
        _kindLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:12];
        // Derived from the label colour rather than a semantic fill: Twitter
        // re-themes the system fills, which turned this badge into a dark
        // block with unreadable text.
        _kindLabel.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
        _kindLabel.textAlignment = NSTextAlignmentCenter;
        _kindLabel.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
        _kindLabel.layer.cornerRadius = 5.0;
        _kindLabel.layer.masksToBounds = YES;
        [_kindLabel setContentHuggingPriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisHorizontal];

        _termLabel = [[UILabel alloc] init];
        _termLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];

        // Expiry pill: tapping it opens a native duration menu.
        _durationButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _durationButton.titleLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        _durationButton.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.05];
        _durationButton.layer.cornerRadius = 11.0;
        _durationButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
        _durationButton.showsMenuAsPrimaryAction = YES;
        [_durationButton setContentHuggingPriority:UILayoutPriorityRequired
                                           forAxis:UILayoutConstraintAxisHorizontal];

        _removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_removeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                       forState:UIControlStateNormal];
        _removeButton.tintColor = [[UIColor labelColor] colorWithAlphaComponent:0.25];

        for (UIView* v in @[ _kindLabel, _termLabel, _durationButton, _removeButton ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_kindLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                     constant:kNFBMutedSideMargin],
            [_kindLabel.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_kindLabel.heightAnchor constraintEqualToConstant:22.0],
            [_kindLabel.widthAnchor constraintGreaterThanOrEqualToConstant:58.0],
            [_termLabel.leadingAnchor constraintEqualToAnchor:_kindLabel.trailingAnchor
                                                     constant:12.0],
            [_termLabel.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_termLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:_durationButton.leadingAnchor
                                         constant:-8.0],
            [_durationButton.trailingAnchor
                constraintEqualToAnchor:_removeButton.leadingAnchor
                               constant:-8.0],
            [_durationButton.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_durationButton.heightAnchor constraintEqualToConstant:22.0],
            [_termLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                 constant:11.0],
            [_termLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                    constant:-11.0],
            [_removeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                         constant:-kNFBMutedSideMargin],
            [_removeButton.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_removeButton.widthAnchor constraintEqualToConstant:26.0],
        ]];
    }
    return self;
}

@end

// MARK: - option row

@interface NFBMutedToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel2;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UISwitch* toggle;
@end

@implementation NFBMutedToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];

        _titleLabel2 = [[UILabel alloc] init];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.numberOfLines = 0;

        _toggle = [[UISwitch alloc] init];

        for (UIView* v in @[ _titleLabel2, _subtitleLabel, _toggle ]) {
            v.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:v];
        }
        [self applyTheme];
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel2.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                   constant:18.0],
            [_titleLabel2.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                       constant:kNFBMutedSideMargin],
            [_titleLabel2.trailingAnchor
                constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor
                                         constant:-16.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel2.bottomAnchor
                                                     constant:2.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel2.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor
                                                          constant:-16.0],
            [_subtitleLabel.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-18.0],
            [_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                   constant:-kNFBMutedSideMargin],
        ]];
    }
    return self;
}

// The same fonts and palette colours the rest of the settings uses, rather than
// hard sizes and system greys: a bold title over a subtitle in the theme's own
// secondary colour. Re-applied on trait changes because a palette colour, unlike
// secondaryLabelColor, does not follow light and dark on its own.
- (void)applyTheme {
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel2.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    self.titleLabel2.textColor = [colorPalette performSelector:@selector(textColor)];
    self.subtitleLabel.textColor = [colorPalette performSelector:@selector(tabBarItemColor)];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end

// MARK: - controller

@interface MutedWordsViewController () <UITextFieldDelegate,
                                       UIPopoverPresentationControllerDelegate>
@property (nonatomic, strong) NSMutableArray<NSString*>* terms;
@property (nonatomic, assign) BOOL compact;
// 0 shows the muted terms, 1 shows the language list. The segmented control
// above the table drives it, in both presentations.
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, strong) NSArray<NSString*>* languageCodes;
// The pushed screen that holds every language the two shortlists leave out.
@property (nonatomic, assign) BOOL othersOnly;
// In the popover the segment and the switch are held against the table's
// frame, so only the rows between them move.
@property (nonatomic, strong) UIView* pinnedHeader;
@property (nonatomic, strong) UIView* pinnedBar;
@property (nonatomic, strong) UISwitch* pinnedSwitch;
@property (nonatomic, assign) CGFloat pinnedHeaderHeight;
@end

// The confirm glyph in the navigation bar is baked opaque white by the theme
// hooks, but only while NFBColorThemeScreenVisible is up — Twitter's settings
// roots and the tweak's own settings pages raise it, and this screen never did. Left
// out, the glyph stays a template the glass material blends with the capsule
// underneath, which is the wash that shows on a light accent and nowhere else.
// Joining the count is the whole fix: the recipe already exists, this screen
// simply was not counted.
extern NSInteger NFBColorThemeScreenVisible;

@implementation MutedWordsViewController

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

// The languages offered, in the order the advanced-search menu already uses.
static NSString* const kNFBLanguagesKey = @"nfb_filter_languages";

// The popover shows the first four, the full screen the first six, and the
// picker holds everything after that.
static NSArray<NSString*>* NFBLanguageCatalog(void) {
    return @[
        @"en", @"fr", @"es", @"zh", @"pt", @"ja", @"hi", @"ar", @"de", @"ru",
        @"it", @"ko", @"nl", @"pl", @"sv", @"uk", @"fa", @"he", @"th", @"vi",
        @"id", @"tr"
    ];
}

static const NSUInteger kNFBLanguagesQuick = 4;
static const NSUInteger kNFBLanguagesFull = 6;

// The language's own name, so it is recognised without knowing the code.
static NSString* NFBLanguageName(NSString* code) {
    NSLocale* locale = [NSLocale localeWithLocaleIdentifier:code];
    NSString* name = [locale localizedStringForLanguageCode:code];
    if (!name.length) {
        name = [[NSLocale currentLocale] localizedStringForLanguageCode:code];
    }
    return name.length ? [name capitalizedStringWithLocale:locale]
                       : code.uppercaseString;
}

static NSMutableArray<NSString*>* NFBKeptLanguageList(void) {
    NSArray* stored =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kNFBLanguagesKey];
    return [([stored isKindOfClass:[NSArray class]] ? stored : @[]) mutableCopy];
}

- (instancetype)initCompact {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _compact = YES;
    }
    return self;
}

// A popover on iPhone becomes a full-screen sheet unless the delegate says
// otherwise; this keeps it an anchored popover on every size class.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:
                                (UIPresentationController*)controller
                                                          traitCollection:
                                (UITraitCollection*)traitCollection {
    return UIModalPresentationNone;
}

// Height measured from the laid-out table rather than estimated, so the last
// entry is never clipped.
- (void)updatePreferredSize {
    if (!self.compact) {
        return;
    }
    [self.tableView layoutIfNeeded];
    CGFloat measured = self.tableView.contentSize.height +
                       self.tableView.contentInset.top +
                       self.tableView.contentInset.bottom;
    if (measured < 100.0) {
        measured = 100.0;
    }
    // The language list is short and fixed: the popover asks for its whole
    // height, so nothing scrolls and the switch below stays in view.
    CGFloat cap = (self.mode == 1) ? 420.0 : 330.0;
    self.preferredContentSize = CGSizeMake(320.0, MIN(measured, cap));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Reloading adds cells above the pinned views, so their order is restored
    // on every layout pass.
    [self.tableView bringSubviewToFront:self.pinnedHeader];
    [self.tableView bringSubviewToFront:self.pinnedBar];
    [self updatePreferredSize];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BHTBundle* bundle = [BHTBundle sharedBundle];
    self.title = [bundle
        localizedStringForKey:self.othersOnly ? @"LANGUAGES_OTHERS_TITLE"
                                              : @"FILTERS_TITLE"];
    self.terms = [([[NSUserDefaults standardUserDefaults] arrayForKey:kNFBMutedWordsKey]
                       ?: @[]) mutableCopy];
    [self pruneExpiredTerms];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (self.compact) {
        // A popover draws its own translucent material: forcing an opaque
        // background is what flattened it into a plain white card.
        self.tableView.backgroundColor = [UIColor clearColor];
        self.view.backgroundColor = [UIColor clearColor];
        // Plain tables reserve room above their first section on iOS 15 and
        // later; the pinned segment already provides that gap.
        if (@available(iOS 15.0, *)) {
            self.tableView.sectionHeaderTopPadding = 0.0;
        }
    } else {
        // Full screen follows the advanced-search recipe.
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    // A self-sizing footer needs an estimate, or the table collapses it.
    self.tableView.estimatedSectionFooterHeight = 44.0;
    self.languageCodes = NFBLanguageCatalog();
    if (!self.othersOnly) {
        [self installModeControl];
    }
    [self updatePreferredSize];
    [self.tableView registerClass:[NFBMutedAddCell class] forCellReuseIdentifier:@"add"];
    [self.tableView registerClass:[NFBMutedToggleCell class] forCellReuseIdentifier:@"opt"];
    [self.tableView registerClass:[NFBMutedTermCell class] forCellReuseIdentifier:@"term"];
}

// MARK: mode

// A segmented control in the table header: it scrolls with the content in full
// screen and costs the popover a single row of height.
- (void)installModeControl {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UISegmentedControl* control = [[UISegmentedControl alloc] initWithItems:@[
        [bundle localizedStringForKey:@"FILTERS_SEGMENT_WORDS"],
        [bundle localizedStringForKey:@"FILTERS_SEGMENT_LANGUAGES"]
    ]];
    control.selectedSegmentIndex = self.mode;
    [control addTarget:self
                  action:@selector(modeChanged:)
        forControlEvents:UIControlEventValueChanged];
    // The segment keeps its system appearance: it names a place in the screen,
    // not a setting, so it stays out of the accent's vocabulary.
    CGFloat inset = kNFBMutedSideMargin;
    // The popover pins the control to the top so the row below supplies the
    // only gap under it; the full screen centres it in a taller header, where
    // the extra air belongs.
    CGFloat controlHeight = 32.0;
    CGFloat top = kNFBMutedSideMargin;
    CGFloat height = self.compact ? top + controlHeight : 48.0;
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, height)];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:control];
    NSLayoutConstraint* vertical =
        self.compact
            ? [control.topAnchor constraintEqualToAnchor:header.topAnchor
                                                constant:top]
            : [control.centerYAnchor constraintEqualToAnchor:header.centerYAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [control.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                              constant:inset],
        [control.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                               constant:-inset],
        vertical,
        [control.heightAnchor constraintEqualToConstant:controlHeight],
    ]];
    if (self.compact) {
        // The controller's view IS the table, so a subview of it travels with
        // the rows unless it is tied to the frame layout guide, which follows
        // the table's frame instead of its content. The view carries no
        // surface of its own: the popover's own glass shows through it.
        header.translatesAutoresizingMaskIntoConstraints = NO;
        header.backgroundColor = [UIColor clearColor];
        [self.tableView addSubview:header];
        UILayoutGuide* tableFrame = self.tableView.frameLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [header.leadingAnchor constraintEqualToAnchor:tableFrame.leadingAnchor],
            [header.trailingAnchor constraintEqualToAnchor:tableFrame.trailingAnchor],
            [header.topAnchor constraintEqualToAnchor:tableFrame.topAnchor],
            [header.heightAnchor constraintEqualToConstant:height],
        ]];
        self.pinnedHeader = header;
        self.pinnedHeaderHeight = height;
        [self installTranslateBar];
        [self updatePinnedInsets];
        return;
    }
    // The header's size is read when it is assigned, so its frame is set
    // first; the flexible width keeps it correct if the table is laid out
    // later than this.
    CGFloat width = self.tableView.bounds.size.width > 0.0
                        ? self.tableView.bounds.size.width
                        : self.view.bounds.size.width;
    header.frame = CGRectMake(0, 0, width, height);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header layoutIfNeeded];
    self.tableView.tableHeaderView = header;
}

// The switch is held against the bottom of the table's frame, below the rows
// it belongs to.
- (void)installTranslateBar {
    // Built to a language row's proportions rather than reusing the settings
    // cell, whose 18 pt margins would set it apart from the list above it.
    UIView* bar = [[UIView alloc] init];
    bar.backgroundColor = [UIColor clearColor];
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* label = [[UILabel alloc] init];
    label.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"LANGUAGES_TRANSLATE_TITLE"];
    label.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UISwitch* toggle = [[UISwitch alloc] init];
    toggle.on =
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"disable_auto_translate"];
    [toggle addTarget:self
                  action:@selector(translateChanged:)
        forControlEvents:UIControlEventValueChanged];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;

    // Edge to edge rather than inset like the row separators: it marks where
    // the scrolling list ends and the pinned switch begins.
    UIView* hairline = [[UIView alloc] init];
    hairline.backgroundColor = [UIColor separatorColor];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;

    for (UIView* v in @[ label, toggle, hairline ]) {
        [bar addSubview:v];
    }
    [self.tableView addSubview:bar];
    UILayoutGuide* tableFrame = self.tableView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor
                                            constant:kNFBMutedSideMargin],
        [label.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor
                                              constant:-kNFBMutedSideMargin],
        [toggle.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [hairline.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],
        [bar.leadingAnchor constraintEqualToAnchor:tableFrame.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:tableFrame.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:tableFrame.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:kNFBTranslateBarHeight],
    ]];
    self.pinnedBar = bar;
    self.pinnedSwitch = toggle;
}

// The rows start below the segment and end above the switch, and the switch
// only exists while the languages are showing.
- (void)updatePinnedInsets {
    if (!self.compact) {
        return;
    }
    BOOL languages = self.mode == 1;
    self.pinnedBar.hidden = !languages;
    CGFloat bottom = languages ? kNFBTranslateBarHeight : 0.0;
    UIEdgeInsets insets =
        UIEdgeInsetsMake(self.pinnedHeaderHeight, 0, bottom, 0);
    self.tableView.contentInset = insets;
    self.tableView.verticalScrollIndicatorInsets = insets;
    [self.tableView bringSubviewToFront:self.pinnedHeader];
    [self.tableView bringSubviewToFront:self.pinnedBar];
}


// The codes this screen lists: the picker takes the tail, the popover the
// first four, the full screen the first six.
- (NSArray<NSString*>*)visibleLanguages {
    NSArray* all = self.languageCodes;
    if (self.othersOnly) {
        return [all subarrayWithRange:NSMakeRange(kNFBLanguagesFull,
                                                  all.count - kNFBLanguagesFull)];
    }
    NSUInteger head = self.compact ? kNFBLanguagesQuick : kNFBLanguagesFull;
    return [all subarrayWithRange:NSMakeRange(0, MIN(head, all.count))];
}

// After the languages come the picker row (full screen only) and the
// auto-translate row; the picker screen has neither.
- (NSInteger)languageExtraRows {
    if (self.othersOnly) {
        return 0;
    }
    // The popover holds its switch outside the table, so the list carries no
    // extra row there.
    return self.compact ? 0 : 2;
}

- (BOOL)rowIsPicker:(NSInteger)row {
    return !self.othersOnly && !self.compact &&
           row == (NSInteger)[self visibleLanguages].count;
}

- (BOOL)rowIsTranslate:(NSInteger)row {
    return !self.othersOnly &&
           row == (NSInteger)[self visibleLanguages].count + (self.compact ? 0 : 1);
}

- (void)modeChanged:(UISegmentedControl*)control {
    self.mode = control.selectedSegmentIndex;
    [self.tableView reloadData];
    [self updatePinnedInsets];
    [self updatePreferredSize];
}

// MARK: expiry

// Expiry lives in a companion dictionary keyed by the term, so an existing
// list of plain strings keeps working untouched.
- (NSMutableDictionary*)expiryMap {
    return [([[NSUserDefaults standardUserDefaults] dictionaryForKey:kNFBMutedExpiryKey]
                 ?: @{}) mutableCopy];
}

- (NSTimeInterval)expiryForTerm:(NSString*)term {
    id value = [self expiryMap][term];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

- (void)setExpiry:(NSTimeInterval)deadline forTerm:(NSString*)term {
    NSMutableDictionary* map = [self expiryMap];
    if (deadline <= 0) {
        [map removeObjectForKey:term];
    } else {
        map[term] = @(deadline);
    }
    [[NSUserDefaults standardUserDefaults] setObject:map forKey:kNFBMutedExpiryKey];
    nfbRefreshMutedWords();
}

// Drops filters whose deadline has passed, and forgets their entry.
- (void)pruneExpiredTerms {
    NSMutableDictionary* map = [self expiryMap];
    if (map.count == 0) {
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray* alive = [NSMutableArray array];
    BOOL changed = NO;
    for (NSString* term in self.terms) {
        id value = map[term];
        double deadline =
            [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
        if (deadline > 0 && deadline <= now) {
            [map removeObjectForKey:term];
            changed = YES;
            continue;
        }
        [alive addObject:term];
    }
    if (!changed) {
        return;
    }
    self.terms = alive;
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.terms forKey:kNFBMutedWordsKey];
    [d setObject:map forKey:kNFBMutedExpiryKey];
    nfbRefreshMutedWords();
}

// "forever", or how many days are left.
- (NSString*)durationLabelForTerm:(NSString*)term {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSTimeInterval deadline = [self expiryForTerm:term];
    if (deadline <= 0) {
        return [bundle localizedStringForKey:@"MUTED_WORDS_DURATION_FOREVER"];
    }
    NSTimeInterval remaining = deadline - [[NSDate date] timeIntervalSince1970];
    NSInteger days = (NSInteger)ceil(remaining / 86400.0);
    if (days < 1) {
        days = 1;
    }
    return [NSString stringWithFormat:
                         [bundle localizedStringForKey:@"MUTED_WORDS_EXPIRES_FORMAT"],
                         (long)days];
}

- (UIMenu*)durationMenuForTerm:(NSString*)term {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSTimeInterval current = [self expiryForTerm:term];
    __weak typeof(self) weakSelf = self;
    NSArray* options = @[ @[ @"MUTED_WORDS_DURATION_24H", @(86400.0) ],
                          @[ @"MUTED_WORDS_DURATION_7D", @(604800.0) ],
                          @[ @"MUTED_WORDS_DURATION_30D", @(2592000.0) ],
                          @[ @"MUTED_WORDS_DURATION_FOREVER", @(0.0) ] ];
    NSMutableArray* actions = [NSMutableArray array];
    for (NSArray* option in options) {
        double span = [option[1] doubleValue];
        UIAction* action = [UIAction
            actionWithTitle:[bundle localizedStringForKey:option[0]]
                      image:nil
                 identifier:nil
                    handler:^(UIAction* a) {
                        double deadline =
                            (span <= 0)
                                ? 0.0
                                : [[NSDate date] timeIntervalSince1970] + span;
                        [weakSelf setExpiry:deadline forTerm:term];
                        [weakSelf.tableView reloadData];
                    }];
        BOOL selected = (span <= 0) ? (current <= 0)
                                    : (current > 0 &&
                                       fabs((current - [[NSDate date] timeIntervalSince1970]) -
                                            span) < 86400.0);
        action.state = selected ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithChildren:actions];
}

// MARK: persistence

- (void)persist {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.terms forKey:kNFBMutedWordsKey];
    // The settings row shows this string on its right-hand side.
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSString* summary =
        self.terms.count ? [NSString stringWithFormat:@"%lu", (unsigned long)self.terms.count]
                         : [bundle localizedStringForKey:@"MUTED_WORDS_NONE"];
    [d setObject:summary forKey:kNFBMutedCountKey];
    nfbRefreshMutedWords();
}

// MARK: actions

- (void)addTermFromField:(UITextField*)field {
    NSString* raw = [field.text stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) {
        return;
    }
    for (NSString* existing in self.terms) {
        if ([existing caseInsensitiveCompare:raw] == NSOrderedSame) {
            field.text = @"";
            return;
        }
    }
    [self.terms insertObject:raw atIndex:0];
    field.text = @"";
    [self persist];
    [self updatePreferredSize];
    [self.tableView reloadData];
}

// The stored flag is the negative one, so the switch reads and writes it
// inverted: on means Twitter may translate.
- (void)translateChanged:(UISwitch*)sender {
    [[NSUserDefaults standardUserDefaults] setBool:!sender.isOn
                                            forKey:@"disable_auto_translate"];
    self.pinnedSwitch.on = sender.isOn;
    [self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch*)sender {
    NSArray* keys = @[ kNFBMutedWholeWordsKey, kNFBMutedInConversationsKey,
                       kNFBMutedSkipFollowingKey, kNFBMutedIncludeRepostsKey ];
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= keys.count) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:keys[index]];
    nfbRefreshMutedWords();
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [self addTermFromField:textField];
    [textField resignFirstResponder];
    return YES;
}

// MARK: table

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    if (self.mode == 1) {
        return 1;
    }
    return self.compact ? 1 : 2;
}

// Section 0 is "Filters": the add row first, then the list (or one empty row).
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.mode == 1) {
        return (NSInteger)[self visibleLanguages].count + [self languageExtraRows];
    }
    if (section == 0) {
        return 1 + (NSInteger)MAX(self.terms.count, (NSUInteger)1);
    }
    return 4;
}

// Custom headers, Chirp heavy — the advanced-search recipe, instead of the
// small grey system captions.
- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.compact) {
        return nil;
    }
    if (self.mode == 1 || section == 0) {
        // The segment above the table already names this list.
        return nil;
    }
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIView* container = [[UIView alloc] init];
    UILabel* label = [[UILabel alloc] init];
    label.text = [bundle localizedStringForKey:@"MUTED_WORDS_OPTIONS_HEADER"];
    label.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                            constant:kNFBMutedSideMargin],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                             constant:-kNFBMutedSideMargin],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                           constant:-6.0],
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.compact || self.mode == 1 || section == 0) {
        return 0.01;
    }
    return 46.0;
}

// How much the filter actually did today, under the list.
- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    if (self.mode == 1) {
        if (self.compact || self.othersOnly) {
            return nil;
        }
        BHTBundle* bundle = [BHTBundle sharedBundle];
        return [bundle localizedStringForKey:NFBKeptLanguageList().count
                                                 ? @"LANGUAGES_FOOTER_ON"
                                                 : @"LANGUAGES_FOOTER_OFF"];
    }
    if (self.compact || section != 0) {
        return nil;
    }
    return [NSString stringWithFormat:
                         [[BHTBundle sharedBundle]
                             localizedStringForKey:@"MUTED_WORDS_COUNT_FORMAT"],
                         (long)nfbMutedHiddenCountToday()];
}

// "@handle" -> account, "two words" -> phrase, otherwise a single word.
- (NSString*)kindLabelForTerm:(NSString*)term {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    if ([term hasPrefix:@"@"]) {
        return [bundle localizedStringForKey:@"MUTED_WORDS_KIND_ACCOUNT"];
    }
    if ([term rangeOfString:@" "].location != NSNotFound) {
        return [bundle localizedStringForKey:@"MUTED_WORDS_KIND_PHRASE"];
    }
    return [bundle localizedStringForKey:@"MUTED_WORDS_KIND_WORD"];
}

// The table's own footer sits on the system margin, which is wider than this
// screen's; the text is drawn instead so it starts under the rows.
- (UIView*)tableView:(UITableView*)tableView viewForFooterInSection:(NSInteger)section {
    NSString* text = [self tableView:tableView titleForFooterInSection:section];
    if (!text.length) {
        return nil;
    }
    UIView* container = [[UIView alloc] init];
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5];
    label.textColor = [UIColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                            constant:kNFBMutedSideMargin],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                             constant:-kNFBMutedSideMargin],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:14.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                           constant:-18.0],
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView*)tableView
    heightForFooterInSection:(NSInteger)section {
    return [self tableView:tableView titleForFooterInSection:section].length
               ? UITableViewAutomaticDimension
               : 0.01;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    BHTBundle* bundle = [BHTBundle sharedBundle];

    if (self.mode == 1) {
        extern UIColor* CurrentAccentColor(void);
        UIColor* accent = CurrentAccentColor() ?: self.view.tintColor;

        if ([self rowIsTranslate:indexPath.row]) {
            NFBMutedToggleCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"opt"
                                                forIndexPath:indexPath];
            cell.titleLabel2.text =
                [bundle localizedStringForKey:@"LANGUAGES_TRANSLATE_TITLE"];
            // The popover is meant to be read in a glance, so it carries the
            // switch alone.
            cell.subtitleLabel.text =
                self.compact
                    ? @""
                    : [bundle localizedStringForKey:@"LANGUAGES_TRANSLATE_DETAIL"];
            cell.toggle.tag = NSIntegerMax;
            cell.toggle.on =
                ![[NSUserDefaults standardUserDefaults] boolForKey:@"disable_auto_translate"];
            [cell.toggle removeTarget:nil
                               action:NULL
                     forControlEvents:UIControlEventValueChanged];
            [cell.toggle addTarget:self
                            action:@selector(translateChanged:)
                  forControlEvents:UIControlEventValueChanged];
            return cell;
        }

        UITableViewCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"lang"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                          reuseIdentifier:@"lang"];
            cell.backgroundColor = [UIColor clearColor];
        }
        cell.tintColor = accent;
        cell.textLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
        // The table's own margins are wider than this screen's, which would
        // leave the languages indented past the rows around them.
        cell.preservesSuperviewLayoutMargins = NO;
        cell.contentView.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, kNFBMutedSideMargin, 0,
                                              kNFBMutedSideMargin);
        cell.contentView.layoutMargins = cell.layoutMargins;
        cell.separatorInset = UIEdgeInsetsMake(0, kNFBMutedSideMargin, 0, 0);

        if ([self rowIsPicker:indexPath.row]) {
            NSArray* tail = [self.languageCodes
                subarrayWithRange:NSMakeRange(kNFBLanguagesFull,
                                              self.languageCodes.count -
                                                  kNFBLanguagesFull)];
            NSMutableArray* picked = [NSMutableArray array];
            for (NSString* code in tail) {
                if ([NFBKeptLanguageList() containsObject:code]) {
                    [picked addObject:NFBLanguageName(code)];
                }
            }
            cell.textLabel.text =
                [bundle localizedStringForKey:@"LANGUAGES_OTHERS_TITLE"];
            cell.textLabel.textColor = [UIColor labelColor];
            cell.detailTextLabel.text =
                picked.count ? [picked componentsJoinedByString:@", "]
                             : [bundle localizedStringForKey:@"LANGUAGES_OTHERS_NONE"];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        NSString* code = [self visibleLanguages][(NSUInteger)indexPath.row];
        BOOL kept = [NFBKeptLanguageList() containsObject:code];
        cell.textLabel.text = NFBLanguageName(code);
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor =
            kept ? [UIColor labelColor]
                 : [[UIColor labelColor] colorWithAlphaComponent:0.45];
        // The system checkmark sits on its own inset, which leaves the right
        // column ragged against the switch below. Supplying the glyph as an
        // accessory view puts it on the cell's own margin instead.
        if (kept) {
            UIImageView* tick = [[UIImageView alloc]
                initWithImage:[UIImage systemImageNamed:@"checkmark"]];
            tick.tintColor = accent;
            [tick sizeToFit];
            cell.accessoryView = tick;
        } else {
            cell.accessoryView = nil;
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 0) {
        NFBMutedAddCell* cell = [tableView dequeueReusableCellWithIdentifier:@"add"
                                                               forIndexPath:indexPath];
        // A language row centres its text 14 pt below its own top edge; the
        // box starts at the same offset so both panels read alike.
        cell.boxTop.constant = 14.0;
        cell.field.placeholder =
            [bundle localizedStringForKey:@"MUTED_WORDS_ADD_PLACEHOLDER"];
        cell.hintLabel.text = [bundle localizedStringForKey:@"MUTED_WORDS_SUBTITLE"];
        cell.field.delegate = self;
        [cell.addButton setTitle:[bundle localizedStringForKey:@"MUTED_WORDS_ADD_BUTTON"]
                        forState:UIControlStateNormal];
        [cell.addButton removeTarget:nil
                              action:NULL
                    forControlEvents:UIControlEventTouchUpInside];
        [cell.addButton addTarget:self
                           action:@selector(addTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
        return cell;
    }

    if (indexPath.section == 0) {
        NSUInteger termIndex = (NSUInteger)indexPath.row - 1;
        if (self.terms.count == 0) {
            // A dimmed example instead of "nothing here": it shows what a
            // filter looks like and what may be typed. No remove button, so it
            // can't be mistaken for a real entry.
            NFBMutedTermCell* example =
                [tableView dequeueReusableCellWithIdentifier:@"term"
                                                forIndexPath:indexPath];
            example.termLabel.text =
                [bundle localizedStringForKey:@"MUTED_WORDS_EXAMPLE_TERM"];
            example.termLabel.font =
                [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
            example.kindLabel.text =
                [NSString stringWithFormat:@"  %@  ",
                                           [bundle localizedStringForKey:
                                                       @"MUTED_WORDS_KIND_WORD"]];
            example.durationButton.hidden = YES;
            example.removeButton.hidden = YES;
            example.contentView.alpha = 0.38;
            return example;
        }
        NFBMutedTermCell* cell = [tableView dequeueReusableCellWithIdentifier:@"term"
                                                                 forIndexPath:indexPath];
        NSString* term = self.terms[termIndex];
        // Undo whatever the example row changed — cells are reused.
        cell.contentView.alpha = 1.0;
        cell.durationButton.hidden = NO;
        cell.removeButton.hidden = NO;
        cell.termLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
        cell.termLabel.text = term;
        cell.kindLabel.text = [NSString stringWithFormat:@"  %@  ",
                                                         [self kindLabelForTerm:term]];
        [cell.durationButton setTitle:[self durationLabelForTerm:term]
                             forState:UIControlStateNormal];
        cell.durationButton.menu = [self durationMenuForTerm:term];
        cell.removeButton.tag = (NSInteger)termIndex;
        [cell.removeButton removeTarget:nil
                                 action:NULL
                       forControlEvents:UIControlEventTouchUpInside];
        [cell.removeButton addTarget:self
                              action:@selector(removeTapped:)
                    forControlEvents:UIControlEventTouchUpInside];
        return cell;
    }

    NFBMutedToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"opt"
                                                              forIndexPath:indexPath];
    struct {
        __unsafe_unretained NSString* titleKey;
        __unsafe_unretained NSString* detailKey;
        __unsafe_unretained NSString* prefKey;
        BOOL defaultOn;
    } options[] = {
        { @"MUTED_WORDS_WHOLE_TITLE", @"MUTED_WORDS_WHOLE_DETAIL",
          kNFBMutedWholeWordsKey, YES },
        { @"MUTED_WORDS_CONVERSATIONS_TITLE", @"MUTED_WORDS_CONVERSATIONS_DETAIL",
          kNFBMutedInConversationsKey, YES },
        { @"MUTED_WORDS_FOLLOWING_TITLE", @"MUTED_WORDS_FOLLOWING_DETAIL",
          kNFBMutedSkipFollowingKey, YES },
        { @"MUTED_WORDS_REPOSTS_TITLE", @"MUTED_WORDS_REPOSTS_DETAIL",
          kNFBMutedIncludeRepostsKey, NO },
    };
    NSUInteger index = (NSUInteger)indexPath.row;
    if (index >= sizeof(options) / sizeof(options[0])) {
        index = 0;
    }
    cell.titleLabel2.text = [bundle localizedStringForKey:options[index].titleKey];
    cell.subtitleLabel.text = [bundle localizedStringForKey:options[index].detailKey];
    cell.toggle.tag = (NSInteger)index;
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    cell.toggle.on = ([d objectForKey:options[index].prefKey] == nil)
                         ? options[index].defaultOn
                         : [d boolForKey:options[index].prefKey];
    [cell.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.toggle addTarget:self
                    action:@selector(toggleChanged:)
          forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (void)removeTapped:(UIButton*)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= self.terms.count) {
        return;
    }
    [self.terms removeObjectAtIndex:index];
    [self persist];
    [self updatePreferredSize];
    [self.tableView reloadData];
}

- (void)addTapped:(UIButton*)sender {
    UIView* view = sender;
    while (view && ![view isKindOfClass:[NFBMutedAddCell class]]) {
        view = view.superview;
    }
    if ([view isKindOfClass:[NFBMutedAddCell class]]) {
        [self addTermFromField:((NFBMutedAddCell*)view).field];
    }
}

- (BOOL)tableView:(UITableView*)tableView
    canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    if (self.mode == 1) {
        return NO;
    }
    return indexPath.section == 0 && indexPath.row > 0 && self.terms.count > 0;
}

// Selecting a language keeps it; clearing the last one empties the set, which
// turns the filter off rather than hiding everything.
- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.mode != 1) {
        return;
    }
    if ([self rowIsTranslate:indexPath.row]) {
        return;
    }
    if ([self rowIsPicker:indexPath.row]) {
        MutedWordsViewController* others = [[MutedWordsViewController alloc] init];
        others.othersOnly = YES;
        others.mode = 1;
        [self.navigationController pushViewController:others animated:YES];
        return;
    }
    NSString* code = [self visibleLanguages][(NSUInteger)indexPath.row];
    NSMutableArray* kept = NFBKeptLanguageList();
    if ([kept containsObject:code]) {
        [kept removeObject:code];
    } else {
        [kept addObject:code];
    }
    [[NSUserDefaults standardUserDefaults] setObject:kept forKey:kNFBLanguagesKey];
    [tableView reloadData];
}

- (void)tableView:(UITableView*)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath*)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    [self.terms removeObjectAtIndex:(NSUInteger)indexPath.row - 1];
    [self persist];
    [self updatePreferredSize];
    [tableView reloadData];
}

@end
