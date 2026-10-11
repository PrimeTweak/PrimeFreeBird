// The muted-words list lives in NSUserDefaults as plain strings: an "@" prefix
// means an account, a space a phrase, anything else a word. Timeline.x reads the
// same keys and reloads through pfbRefreshMutedWords().

#import "Features/Timelines/PFBMutedWordsViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsStyle.h"
#import "Features/Timelines/PFBMutedAddCell.h"
#import "Features/Timelines/PFBMutedTermCell.h"
#import "Features/Timelines/PFBMutedToggleCell.h"

// The hidden-conversation registry lives with the code that fills it.
extern NSArray<NSDictionary*>* PFBHiddenThreads(void);
extern void PFBUnhideThread(NSString* threadID);

// A language row's own height, so the switch is spaced like one more entry.
static const CGFloat kPFBTranslateBarHeight = 51.0;
// The popover's rounded corners cut into its bottom row, so its list sits a
// little further in than the full screen's; the segment keeps the card's own
// margin above it.
static const CGFloat kPFBCompactRowMargin = 14.0;
static const NSInteger kPFBTickTag = 7701;

static NSString* const kPFBMutedWordsKey = @"pfb_muted_words";
static NSString* const kPFBMutedWholeWordsKey = @"pfb_muted_whole_words";
static NSString* const kPFBMutedInConversationsKey = @"pfb_muted_in_conversations";
static NSString* const kPFBMutedExpiryKey = @"pfb_muted_expiry";
static NSString* const kPFBMutedSkipFollowingKey = @"pfb_muted_skip_following";
static NSString* const kPFBMutedIncludeRepostsKey = @"pfb_muted_include_reposts";

// MARK: - controller

@interface PFBMutedWordsViewController () <UITextFieldDelegate,
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
@property (nonatomic, strong) UIVisualEffectView* headerMaterial;
@property (nonatomic, strong) UIVisualEffectView* barMaterial;
@property (nonatomic, assign) CGFloat pinnedHeaderHeight;
@end

// The confirm glyph is baked opaque white by the theme hooks, but only while the
// theme-screen count is up. Without joining that count the glyph stays a template
// that the glass material blends with the capsule underneath.
@implementation PFBMutedWordsViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Not in compact mode. Raising this count arms a whitener that bakes every
    // small image view in the right-hand 40 % of any navigation bar, and the popover
    // has no bar and no confirm check, so it would arm one it has no use for.
    if (!self.compact) {
        PFBThemeScreenEnter(self);
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

static NSString* const kPFBLanguagesKey = @"pfb_filter_languages";

// The popover shows the first four, the full screen the first six, and the
// picker holds everything after that.
static NSArray<NSString*>* PFBLanguageCatalog(void) {
    return @[
        @"en", @"fr", @"es", @"zh", @"pt", @"ja", @"hi", @"ar", @"de", @"ru",
        @"it", @"ko", @"nl", @"pl", @"sv", @"uk", @"fa", @"he", @"th", @"vi",
        @"id", @"tr"
    ];
}

static const NSUInteger kPFBLanguagesQuick = 4;
static const NSUInteger kPFBLanguagesFull = 6;

// The language's own name, so it is recognized without knowing the code.
static NSString* PFBLanguageName(NSString* code) {
    NSLocale* locale = [NSLocale localeWithLocaleIdentifier:code];
    NSString* name = [locale localizedStringForLanguageCode:code];
    if (!name.length) {
        name = [[NSLocale currentLocale] localizedStringForLanguageCode:code];
    }
    return name.length ? [name capitalizedStringWithLocale:locale]
                       : code.uppercaseString;
}

static NSMutableArray<NSString*>* PFBKeptLanguageList(void) {
    NSArray* stored =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kPFBLanguagesKey];
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
    CGFloat cap = (self.mode == 0) ? 330.0 : 420.0;
    self.preferredContentSize = CGSizeMake(320.0, MIN(measured, cap));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Reloading adds cells above the pinned views, so their order is restored
    // on every layout pass.
    [self.tableView bringSubviewToFront:self.pinnedHeader];
    [self.tableView bringSubviewToFront:self.pinnedBar];
    [self updateBarMaterials];
    [self updatePreferredSize];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.title = [bundle
        localizedStringForKey:self.othersOnly ? @"LANGUAGES_OTHERS_TITLE"
                                              : @"FILTERS_TITLE"];
    self.terms = [([[NSUserDefaults standardUserDefaults] arrayForKey:kPFBMutedWordsKey]
                       ?: @[]) mutableCopy];
    [self pruneExpiredTerms];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (self.compact) {
        // A popover draws its own translucent material; an opaque background
        // would flatten it into a plain white card.
        self.tableView.backgroundColor = [UIColor clearColor];
        self.view.backgroundColor = [UIColor clearColor];
        // Plain tables reserve room above their first section on iOS 15 and
        // later; the pinned segment already provides that gap.
        self.tableView.sectionHeaderTopPadding = 0.0;
    } else {
        // Full screen follows the advanced-search recipe.
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    // A self-sizing footer needs an estimate, or the table collapses it.
    self.tableView.estimatedSectionFooterHeight = 44.0;
    self.languageCodes = PFBLanguageCatalog();
    if (!self.othersOnly) {
        [self installModeControl];
    }
    [self updatePreferredSize];
    [self.tableView registerClass:[PFBMutedAddCell class] forCellReuseIdentifier:@"add"];
    [self.tableView registerClass:[PFBMutedToggleCell class] forCellReuseIdentifier:@"opt"];
    [self.tableView registerClass:[PFBMutedTermCell class] forCellReuseIdentifier:@"term"];
}

// MARK: mode

// A segmented control in the table header: it scrolls with the content in full
// screen and costs the popover a single row of height.
- (void)installModeControl {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UISegmentedControl* control = [[UISegmentedControl alloc] initWithItems:@[
        [bundle localizedStringForKey:@"FILTERS_SEGMENT_WORDS"],
        [bundle localizedStringForKey:@"FILTERS_SEGMENT_LANGUAGES"],
        [bundle localizedStringForKey:@"FILTERS_SEGMENT_THREADS"]
    ]];
    control.selectedSegmentIndex = self.mode;
    [control addTarget:self
                  action:@selector(modeChanged:)
        forControlEvents:UIControlEventValueChanged];
    // The segment keeps its system appearance: it names a place in the screen,
    // not a setting, so it stays out of the accent's vocabulary.
    CGFloat inset = kPFBMutedSideMargin;
    CGFloat controlHeight = 32.0;
    CGFloat top = kPFBMutedSideMargin;
    // The popover's material fills this header, so it carries the same margin
    // below the segment as above it; the full screen centers in a fixed band.
    CGFloat height = self.compact ? top + controlHeight + top : 48.0;
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
        // The controller's view is the table, so a subview travels with the rows
        // unless tied to the frame layout guide. The view carries no surface of its
        // own, so the popover's glass shows through.
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
        self.headerMaterial = PFBMaterialBehind(header);
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
        [[PFBBundle sharedBundle] localizedStringForKey:@"LANGUAGES_TRANSLATE_TITLE"];
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
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
                                            constant:[self rowMargin]],
        [label.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor
                                              constant:-[self rowMargin]],
        [toggle.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [hairline.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],
        [bar.leadingAnchor constraintEqualToAnchor:tableFrame.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:tableFrame.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:kPFBTranslateBarHeight],
        [bar.bottomAnchor constraintEqualToAnchor:tableFrame.bottomAnchor],
    ]];
    self.barMaterial = PFBMaterialBehind(bar);
    self.pinnedBar = bar;
    self.pinnedSwitch = toggle;
}

// The rows start below the segment and end where the switch's bar begins, at the
// bubble's bottom edge; the bar shows only with the languages.
- (void)updatePinnedInsets {
    if (!self.compact) {
        return;
    }
    BOOL languages = self.mode == 1;
    self.pinnedBar.hidden = !languages;
    CGFloat bottom = languages ? kPFBTranslateBarHeight : 0.0;
    UIEdgeInsets insets =
        UIEdgeInsetsMake(self.pinnedHeaderHeight, 0, bottom, 0);
    self.tableView.contentInset = insets;
    self.tableView.verticalScrollIndicatorInsets = insets;
    [self.tableView bringSubviewToFront:self.pinnedHeader];
    [self.tableView bringSubviewToFront:self.pinnedBar];
    [self updateBarMaterials];
}

// The codes this screen lists: the picker takes the tail, the popover the
// first four, the full screen the first six.
- (NSArray<NSString*>*)visibleLanguages {
    NSArray* all = self.languageCodes;
    if (self.othersOnly) {
        return [all subarrayWithRange:NSMakeRange(kPFBLanguagesFull,
                                                  all.count - kPFBLanguagesFull)];
    }
    NSUInteger head = self.compact ? kPFBLanguagesQuick : kPFBLanguagesFull;
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

// Rows of the popover clear the corner curve; the full screen keeps its own.
- (CGFloat)rowMargin {
    return self.compact ? kPFBCompactRowMargin : kPFBMutedSideMargin;
}

// A bar shows its material only while content passes underneath, the way the
// system's own bars do; at rest it is the card's glass that shows.
- (void)updateBarMaterials {
    if (!self.compact) {
        return;
    }
    UIScrollView* list = self.tableView;
    CGFloat under = list.contentOffset.y + list.adjustedContentInset.top;
    CGFloat below = list.contentSize.height -
                    (list.contentOffset.y + CGRectGetHeight(list.bounds) -
                     list.adjustedContentInset.bottom);
    self.headerMaterial.alpha = MIN(MAX(under / 8.0, 0.0), 1.0);
    self.barMaterial.alpha = MIN(MAX(below / 8.0, 0.0), 1.0);
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    [self updateBarMaterials];
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
    return [([[NSUserDefaults standardUserDefaults] dictionaryForKey:kPFBMutedExpiryKey]
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
    [[NSUserDefaults standardUserDefaults] setObject:map forKey:kPFBMutedExpiryKey];
    pfbRefreshMutedWords();
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
    [d setObject:self.terms forKey:kPFBMutedWordsKey];
    [d setObject:map forKey:kPFBMutedExpiryKey];
    pfbRefreshMutedWords();
}

// "forever", or how many days are left.
- (NSString*)durationLabelForTerm:(NSString*)term {
    PFBBundle* bundle = [PFBBundle sharedBundle];
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
    PFBBundle* bundle = [PFBBundle sharedBundle];
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
    [d setObject:self.terms forKey:kPFBMutedWordsKey];
    pfbRefreshMutedWords();
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
    NSArray* keys = @[ kPFBMutedWholeWordsKey, kPFBMutedInConversationsKey,
                       kPFBMutedSkipFollowingKey, kPFBMutedIncludeRepostsKey ];
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= keys.count) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:keys[index]];
    pfbRefreshMutedWords();
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [self addTermFromField:textField];
    [textField resignFirstResponder];
    return YES;
}

// MARK: table

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    if (self.mode != 0) {
        return 1;
    }
    return self.compact ? 1 : 2;
}

// Section 0 is "Filters": the add row first, then the list (or one empty row).
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.mode == 2) {
        // One row stands in for the empty list, as the word list does.
        return (NSInteger)MAX(PFBHiddenThreads().count, (NSUInteger)1);
    }
    if (self.mode == 1) {
        return (NSInteger)[self visibleLanguages].count + [self languageExtraRows];
    }
    if (section == 0) {
        return 1 + (NSInteger)MAX(self.terms.count, (NSUInteger)1);
    }
    return 4;
}

// Custom headers, Chirp heavy — the advanced-search recipe, instead of the
// small gray system captions.
- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.compact) {
        return nil;
    }
    if (self.mode != 0 || section == 0) {
        // The segment above the table already names this list.
        return nil;
    }
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIView* container = [[UIView alloc] init];
    UILabel* label = [[UILabel alloc] init];
    label.text = [bundle localizedStringForKey:@"MUTED_WORDS_OPTIONS_HEADER"];
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20]);
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                            constant:kPFBMutedSideMargin],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                             constant:-kPFBMutedSideMargin],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                           constant:-6.0],
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (self.compact || self.mode != 0 || section == 0) {
        return 0.01;
    }
    return 46.0;
}

// How much the filter actually did today, under the list.
- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    if (self.mode == 2) {
        if (self.compact) {
            return nil;
        }
        return [[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_FOOTER"];
    }
    if (self.mode == 1) {
        if (self.compact || self.othersOnly) {
            return nil;
        }
        PFBBundle* bundle = [PFBBundle sharedBundle];
        return [bundle localizedStringForKey:PFBKeptLanguageList().count
                                                 ? @"LANGUAGES_FOOTER_ON"
                                                 : @"LANGUAGES_FOOTER_OFF"];
    }
    if (self.compact || section != 0) {
        return nil;
    }
    return [NSString stringWithFormat:
                         [[PFBBundle sharedBundle]
                             localizedStringForKey:@"MUTED_WORDS_COUNT_FORMAT"],
                         (long)pfbMutedHiddenCountToday()];
}

// "@handle" -> account, "two words" -> phrase, otherwise a single word.
- (NSString*)kindLabelForTerm:(NSString*)term {
    PFBBundle* bundle = [PFBBundle sharedBundle];
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
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13.5]);
    label.textColor = [UIColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                            constant:kPFBMutedSideMargin],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                             constant:-kPFBMutedSideMargin],
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
    PFBBundle* bundle = [PFBBundle sharedBundle];

    if (self.mode == 2) {
        PFBMutedTermCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"term"
                                            forIndexPath:indexPath];
        NSArray<NSDictionary*>* threads = PFBHiddenThreads();
        if (!threads.count) {
            [cell applyThreadRowWithMargin:[self rowMargin] showBadge:NO];
            cell.termLabel.text = [bundle localizedStringForKey:@"THREADS_EMPTY"];
            cell.termLabel.textColor = [UIColor secondaryLabelColor];
            return cell;
        }
        NSDictionary* entry = threads[(NSUInteger)indexPath.row];
        NSString* preview = entry[@"preview"];
        NSString* who = entry[@"who"];
        // The badge is the Words list's kind pill, which only fits a thread when the
        // author was resolved. Empty it would leave a gray box, so the row shows the
        // preview alone.
        [cell applyThreadRowWithMargin:[self rowMargin] showBadge:who.length > 0];
        cell.kindLabel.text = who;
        cell.termLabel.text =
            preview.length ? preview
                           : [bundle localizedStringForKey:@"THREADS_NO_PREVIEW"];
        cell.termLabel.textColor = [UIColor labelColor];
        return cell;
    }

    if (self.mode == 1) {
        UIColor* accent = PFBCurrentAccentColor() ?: self.view.tintColor;

        if ([self rowIsTranslate:indexPath.row]) {
            PFBMutedToggleCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"opt"
                                                forIndexPath:indexPath];
            cell.titleLabel2.text =
                [bundle localizedStringForKey:@"LANGUAGES_TRANSLATE_TITLE"];
            cell.subtitleLabel.text =
                [bundle localizedStringForKey:@"LANGUAGES_TRANSLATE_DETAIL"];
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
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        // The table's own margins are wider than this screen's, which would
        // leave the languages indented past the rows around them.
        cell.preservesSuperviewLayoutMargins = NO;
        cell.contentView.preservesSuperviewLayoutMargins = NO;
        CGFloat margin = [self rowMargin];
        cell.layoutMargins = UIEdgeInsetsMake(0, margin, 0, margin);
        cell.contentView.layoutMargins = cell.layoutMargins;
        cell.separatorInset = UIEdgeInsetsMake(0, margin, 0, 0);

        if ([self rowIsPicker:indexPath.row]) {
            NSArray* tail = [self.languageCodes
                subarrayWithRange:NSMakeRange(kPFBLanguagesFull,
                                              self.languageCodes.count -
                                                  kPFBLanguagesFull)];
            NSMutableArray* picked = [NSMutableArray array];
            for (NSString* code in tail) {
                if ([PFBKeptLanguageList() containsObject:code]) {
                    [picked addObject:PFBLanguageName(code)];
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
        BOOL kept = [PFBKeptLanguageList() containsObject:code];
        cell.textLabel.text = PFBLanguageName(code);
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor =
            kept ? [UIColor labelColor]
                 : [[UIColor labelColor] colorWithAlphaComponent:0.45];
        // Placed by constraint rather than as an accessory: the system gives an
        // accessory its own inset, which leaves this column adrift from the switch
        // pinned below the list.
        UIImageView* tick = [cell.contentView viewWithTag:kPFBTickTag];
        if (!tick) {
            tick = [[UIImageView alloc] init];
            tick.tag = kPFBTickTag;
            tick.contentMode = UIViewContentModeScaleAspectFit;
            tick.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:tick];
            [NSLayoutConstraint activateConstraints:@[
                [tick.trailingAnchor
                    constraintEqualToAnchor:cell.contentView.trailingAnchor
                                   constant:-margin],
                [tick.centerYAnchor
                    constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
        }
        tick.image = PFBTwitterGlyphFor(@"checkmark", [UIImage systemImageNamed:@"checkmark"]);
        tick.tintColor = accent;
        tick.hidden = !kept;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 0) {
        PFBMutedAddCell* cell = [tableView dequeueReusableCellWithIdentifier:@"add"
                                                               forIndexPath:indexPath];
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
            PFBMutedTermCell* example =
                [tableView dequeueReusableCellWithIdentifier:@"term"
                                                forIndexPath:indexPath];
            [example applyTermRow];
            example.termLabel.text =
                [bundle localizedStringForKey:@"MUTED_WORDS_EXAMPLE_TERM"];
            example.termLabel.font =
                PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
            example.kindLabel.text =
                [NSString stringWithFormat:@"  %@  ",
                                           [bundle localizedStringForKey:
                                                       @"MUTED_WORDS_KIND_WORD"]];
            example.durationButton.hidden = YES;
            example.removeButton.hidden = YES;
            // Dimmed on purpose: it shows the shape of a filter, not a real one.
            example.contentView.alpha = 0.38;
            return example;
        }
        PFBMutedTermCell* cell = [tableView dequeueReusableCellWithIdentifier:@"term"
                                                                 forIndexPath:indexPath];
        NSString* term = self.terms[termIndex];
        // Undo whatever the example row or the Threads list changed — cells are
        // reused across all three modes.
        [cell applyTermRow];
        cell.termLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
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

    PFBMutedToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"opt"
                                                              forIndexPath:indexPath];
    struct {
        __unsafe_unretained NSString* titleKey;
        __unsafe_unretained NSString* detailKey;
        __unsafe_unretained NSString* prefKey;
        BOOL defaultOn;
    } options[] = {
        { @"MUTED_WORDS_WHOLE_TITLE", @"MUTED_WORDS_WHOLE_DETAIL",
          kPFBMutedWholeWordsKey, YES },
        { @"MUTED_WORDS_CONVERSATIONS_TITLE", @"MUTED_WORDS_CONVERSATIONS_DETAIL",
          kPFBMutedInConversationsKey, YES },
        { @"MUTED_WORDS_FOLLOWING_TITLE", @"MUTED_WORDS_FOLLOWING_DETAIL",
          kPFBMutedSkipFollowingKey, YES },
        { @"MUTED_WORDS_REPOSTS_TITLE", @"MUTED_WORDS_REPOSTS_DETAIL",
          kPFBMutedIncludeRepostsKey, NO },
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
    while (view && ![view isKindOfClass:[PFBMutedAddCell class]]) {
        view = view.superview;
    }
    if ([view isKindOfClass:[PFBMutedAddCell class]]) {
        [self addTermFromField:((PFBMutedAddCell*)view).field];
    }
}

- (BOOL)tableView:(UITableView*)tableView
    canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    if (self.mode == 2) {
        return PFBHiddenThreads().count > 0;
    }
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
        PFBMutedWordsViewController* others = [[PFBMutedWordsViewController alloc] init];
        others.othersOnly = YES;
        others.mode = 1;
        [self.navigationController pushViewController:others animated:YES];
        return;
    }
    NSString* code = [self visibleLanguages][(NSUInteger)indexPath.row];
    NSMutableArray* kept = PFBKeptLanguageList();
    if ([kept containsObject:code]) {
        [kept removeObject:code];
    } else {
        [kept addObject:code];
    }
    [[NSUserDefaults standardUserDefaults] setObject:kept forKey:kPFBLanguagesKey];
    [tableView reloadData];
}

- (void)tableView:(UITableView*)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath*)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    if (self.mode == 2) {
        NSArray<NSDictionary*>* threads = PFBHiddenThreads();
        if (indexPath.row < (NSInteger)threads.count) {
            PFBUnhideThread(threads[(NSUInteger)indexPath.row][@"id"]);
        }
        [self updatePreferredSize];
        [tableView reloadData];
        return;
    }
    [self.terms removeObjectAtIndex:(NSUInteger)indexPath.row - 1];
    [self persist];
    [self updatePreferredSize];
    [tableView reloadData];
}

@end
