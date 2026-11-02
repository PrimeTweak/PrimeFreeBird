// The Filters screen: muted words and accounts, kept languages, hidden conversations.

#import "Features/Timelines/PFBMutedWordsViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/Timelines/PFBMutedWordsStyle.h"
#import "Features/Timelines/PFBMutedAddCell.h"
#import "Features/Timelines/PFBMutedTermCell.h"
#import "Settings/PFBModernSettingsToggleCell.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Settings/Native/PFBNativeSettingsSheetController.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Features/Timelines/PFBMutedShowcaseCells.h"

// The popover's rounded corners cut into its bottom row, so its list sits a
// little further in than the full screen's; the segment keeps the card's own
// margin above it.
static const CGFloat kPFBCompactRowMargin = 14.0;
static const NSInteger kPFBTickTag = 7701;
// The new look's button over a term's row, which opens its menu.
static const NSInteger kPFBRowMenuTag = 7702;

// Plain strings: an "@" prefix marks an account, a space a phrase, anything else a
// word. Timeline.x reads the same keys and reloads through pfbRefreshMutedWords().
static NSString* const kPFBMutedWordsKey = @"pfb_muted_words";
static NSString* const kPFBMutedWholeWordsKey = @"pfb_muted_whole_words";
static NSString* const kPFBMutedInConversationsKey = @"pfb_muted_in_conversations";
static NSString* const kPFBMutedExpiryKey = @"pfb_muted_expiry";
// The span picked for each timed term, so its menu checks that span whatever time is left.
static NSString* const kPFBMutedSpanKey = @"pfb_muted_span";
static NSString* const kPFBMutedSkipFollowingKey = @"pfb_muted_skip_following";
static NSString* const kPFBMutedIncludeRepostsKey = @"pfb_muted_include_reposts";

// When the filters last changed; back to 0 once the screen closes on that change.
static CFAbsoluteTime gPFBFiltersChangedAt = 0;

static void PFBNoteFiltersChange(void) {
    gPFBFiltersChangedAt = CFAbsoluteTimeGetCurrent();
}

// The filters act when Twitter hands a list its sections. Three seconds after the screen
// closes on a change, the report notes whether a list on screen was handed sections since.
static void PFBFollowFiltersChange(void) {
    CFAbsoluteTime changedAt = gPFBFiltersChangedAt;
    gPFBFiltersChangedAt = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PFBCompatMeasure(@"filters",
                         pfbLastTimelineDelivery() > changedAt
                             ? @"Twitter delivered Tweets within 3 s of a Filters change"
                             : @"no new Tweets within 3 s of a Filters change: words already on screen stay",
                         2);
    });
}

// MARK: - options

enum { kPFBMutedOptionCount = 4 };

// One option's row: what it says, and its switch as stored, or as its default until set.
static void PFBMutedConfigureOption(PFBModernSettingsToggleCell* cell, NSUInteger index) {
    struct {
        __unsafe_unretained NSString* titleKey;
        __unsafe_unretained NSString* detailKey;
        __unsafe_unretained NSString* prefKey;
        BOOL defaultOn;
    } options[kPFBMutedOptionCount] = {
        { @"MUTED_WORDS_WHOLE_TITLE", @"MUTED_WORDS_WHOLE_DETAIL",
          kPFBMutedWholeWordsKey, YES },
        { @"MUTED_WORDS_CONVERSATIONS_TITLE", @"MUTED_WORDS_CONVERSATIONS_DETAIL",
          kPFBMutedInConversationsKey, YES },
        { @"MUTED_WORDS_FOLLOWING_TITLE", @"MUTED_WORDS_FOLLOWING_DETAIL",
          kPFBMutedSkipFollowingKey, YES },
        { @"MUTED_WORDS_REPOSTS_TITLE", @"MUTED_WORDS_REPOSTS_DETAIL",
          kPFBMutedIncludeRepostsKey, NO },
    };
    if (index >= kPFBMutedOptionCount) {
        index = 0;
    }
    PFBBundle* bundle = [PFBBundle sharedBundle];
    [cell configureWithTitle:[bundle localizedStringForKey:options[index].titleKey]
                    subtitle:[bundle localizedStringForKey:options[index].detailKey]];
    cell.toggleSwitch.tag = (NSInteger)index;
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    cell.toggleSwitch.on = ([d objectForKey:options[index].prefKey] == nil)
                               ? options[index].defaultOn
                               : [d boolForKey:options[index].prefKey];
}

// An option's switch moved: its key is written and the filters run again.
static void PFBMutedOptionToggled(UISwitch* sender) {
    NSArray* keys = @[ kPFBMutedWholeWordsKey, kPFBMutedInConversationsKey,
                       kPFBMutedSkipFollowingKey, kPFBMutedIncludeRepostsKey ];
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= keys.count) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:keys[index]];
    pfbRefreshMutedWords();
    PFBNoteFiltersChange();
}

// The options in a sheet of the new look, the same switches the classic screen lists.
@interface PFBMutedOptionsViewController : UIViewController <PFBNativeSheetRows, UITableViewDataSource,
                                                            UITableViewDelegate>
@property (nonatomic, strong) UITableView* tableView;
@end

@implementation PFBMutedOptionsViewController

// A sheet's rows sit on its ground and scroll only past its height, as a settings group's do.
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    UITableView* table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    table.backgroundColor = [UIColor clearColor];
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 80;
    table.alwaysBounceVertical = NO;
    table.showsVerticalScrollIndicator = NO;
    table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    table.sectionHeaderTopPadding = 0;
    table.estimatedSectionHeaderHeight = 0;
    table.estimatedSectionFooterHeight = 0;
    table.dataSource = self;
    table.delegate = self;
    [table registerClass:[PFBModernSettingsToggleCell class] forCellReuseIdentifier:@"opt"];
    [self.view addSubview:table];
    self.tableView = table;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return kPFBMutedOptionCount;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"opt"
                                                                       forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    PFBMutedConfigureOption(cell, (NSUInteger)indexPath.row);
    [cell.toggleSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.toggleSwitch addTarget:self
                          action:@selector(optionChanged:)
                forControlEvents:UIControlEventValueChanged];
    return cell;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (void)optionChanged:(UISwitch*)sender {
    PFBMutedOptionToggled(sender);
}

@end

// The new look's symbol for a term's kind: "@handle" an account, "two words" a phrase, else a word.
static NSString* PFBMutedKindSymbol(NSString* term) {
    if ([term hasPrefix:@"@"]) {
        return @"at";
    }
    if ([term rangeOfString:@" "].location != NSNotFound) {
        return @"quote.opening";
    }
    return @"textformat";
}

// The durations a term can be filtered for, the last being forever.
static NSArray<NSArray*>* PFBMutedDurations(void) {
    return @[ @[ @"MUTED_WORDS_DURATION_24H", @(86400.0) ], @[ @"MUTED_WORDS_DURATION_7D", @(604800.0) ],
              @[ @"MUTED_WORDS_DURATION_30D", @(2592000.0) ], @[ @"MUTED_WORDS_DURATION_FOREVER", @(0.0) ] ];
}

// MARK: - controller

@interface PFBMutedWordsViewController () <UITextFieldDelegate,
                                       UIPopoverPresentationControllerDelegate>
@property (nonatomic, strong) NSMutableArray<NSString*>* terms;
@property (nonatomic, assign) BOOL compact;
// 0 shows the muted terms, 1 the languages, 2 the hidden conversations. The
// segmented control above the table drives it, in both presentations.
@property (nonatomic, assign) NSInteger mode;
@property (nonatomic, strong) NSArray<NSString*>* languageCodes;
// The pushed screen that holds every language the two shortlists leave out.
@property (nonatomic, assign) BOOL othersOnly;
// In the popover the segment is held against the table's frame, so only the
// rows under it move.
@property (nonatomic, strong) UIView* pinnedHeader;
@property (nonatomic, strong) UIVisualEffectView* headerMaterial;
// The new look: the duration the next term added gets, forever when 0, and the kind its head shows.
@property (nonatomic, assign) NSTimeInterval pendingSpan;
@property (nonatomic, copy) NSString* shownKindSymbol;
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
    // Back from the language picker: the Other languages row lists what was picked there.
    if (!self.compact && !self.othersOnly && self.mode == 1) {
        [self.tableView reloadData];
    }
}

// The new look's ground is a fixed palette color, read again when light and dark switch.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.nativeLook && !self.compact &&
        [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
    // Closed: dismissed, popped, or gone with its navigation; the language list popping back
    // to the screen leaves it open.
    BOOL closed = self.isBeingDismissed || self.navigationController.isBeingDismissed ||
                  (self.isMovingFromParentViewController && !self.othersOnly);
    if (closed && gPFBFiltersChangedAt > 0) {
        PFBFollowFiltersChange();
    }
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
    // height, so nothing scrolls.
    CGFloat cap = (self.mode == 0) ? 330.0 : 420.0;
    self.preferredContentSize = CGSizeMake(320.0, MIN(measured, cap));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Reloading adds cells above the pinned header, so its order is restored
    // on every layout pass.
    [self.tableView bringSubviewToFront:self.pinnedHeader];
    [self updateBarMaterials];
    [self updatePreferredSize];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:self.othersOnly ? @"LANGUAGES_OTHERS_TITLE" : @"FILTERS_TITLE"];
    if (self.nativeLook && !self.compact) {
        PFBShowcaseSetTitle(self, title);
    } else {
        self.title = title;
    }
    self.terms = [([[NSUserDefaults standardUserDefaults] arrayForKey:kPFBMutedWordsKey]
                       ?: @[]) mutableCopy];
    // A change counts from the screen it is made in, not from an earlier one left open.
    if (!self.othersOnly) {
        gPFBFiltersChangedAt = 0;
    }
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
    } else if (self.nativeLook) {
        // The new look stands on the settings pages' ground.
        self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    } else {
        // Full screen follows the advanced-search recipe.
        self.tableView.backgroundColor = [UIColor systemBackgroundColor];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    // A self-sizing footer needs an estimate, or the table collapses it.
    self.tableView.estimatedSectionFooterHeight = 44.0;
    [self.tableView registerClass:[PFBMutedAddCell class] forCellReuseIdentifier:@"add"];
    [self.tableView registerClass:[PFBModernSettingsToggleCell class] forCellReuseIdentifier:@"opt"];
    [self.tableView registerClass:[PFBMutedTermCell class] forCellReuseIdentifier:@"term"];
    // The new look's other languages with their check, then its heads and rows.
    [self.tableView registerClass:[PFBNativeSettingsRowCell class] forCellReuseIdentifier:@"NativeCheck"];
    [self.tableView registerClass:[PFBMutedWordsHeroCell class] forCellReuseIdentifier:@"WordsHero"];
    [self.tableView registerClass:[PFBMutedLanguagesHeroCell class] forCellReuseIdentifier:@"LanguagesHero"];
    [self.tableView registerClass:[PFBMutedThreadsHeroCell class] forCellReuseIdentifier:@"ThreadsHero"];
    [self.tableView registerClass:[PFBShowcaseRowCell class] forCellReuseIdentifier:@"ShowcaseRow"];
    self.languageCodes = PFBLanguageCatalog();
    if (!self.othersOnly) {
        [self installModeControl];
    }
    [self updatePreferredSize];
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
    CGFloat inset = self.nativeLook ? 20.0 : kPFBMutedSideMargin;
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
        // The rows start below the segment.
        UIEdgeInsets insets = UIEdgeInsetsMake(height, 0, 0, 0);
        self.tableView.contentInset = insets;
        self.tableView.verticalScrollIndicatorInsets = insets;
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

// After the languages comes the picker row, on the full screen only.
- (NSInteger)languageExtraRows {
    return self.othersOnly || self.compact ? 0 : 1;
}

- (BOOL)rowIsPicker:(NSInteger)row {
    return !self.othersOnly && !self.compact &&
           row == (NSInteger)[self visibleLanguages].count;
}

// Rows of the popover clear the corner curve; the full screen keeps its own.
- (CGFloat)rowMargin {
    return self.compact ? kPFBCompactRowMargin : kPFBMutedSideMargin;
}

// The segment's bar shows its material only while rows pass underneath, the way
// the system's own bars do; at rest it is the card's glass that shows.
- (void)updateBarMaterials {
    if (!self.compact) {
        return;
    }
    UIScrollView* list = self.tableView;
    CGFloat under = list.contentOffset.y + list.adjustedContentInset.top;
    self.headerMaterial.alpha = MIN(MAX(under / 8.0, 0.0), 1.0);
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    [self updateBarMaterials];
}

- (void)modeChanged:(UISegmentedControl*)control {
    // The new look's field leaves with the Words head, so its keyboard goes first.
    if ([self showcase]) {
        [self.view endEditing:YES];
    }
    self.mode = control.selectedSegmentIndex;
    [self.tableView reloadData];
    [self updatePreferredSize];
}

// MARK: expiry

// Expiry lives in a companion dictionary keyed by the term, beside the plain list of terms.
- (NSMutableDictionary*)expiryMap {
    return [([[NSUserDefaults standardUserDefaults] dictionaryForKey:kPFBMutedExpiryKey]
                 ?: @{}) mutableCopy];
}

- (NSTimeInterval)expiryForTerm:(NSString*)term {
    id value = [self expiryMap][term];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

- (NSMutableDictionary*)spanMap {
    return [([[NSUserDefaults standardUserDefaults] dictionaryForKey:kPFBMutedSpanKey]
                 ?: @{}) mutableCopy];
}

// A deadline of 0 means forever, which has no span.
- (void)setExpiry:(NSTimeInterval)deadline span:(NSTimeInterval)span forTerm:(NSString*)term {
    NSMutableDictionary* map = [self expiryMap];
    NSMutableDictionary* spans = [self spanMap];
    if (deadline <= 0) {
        [map removeObjectForKey:term];
        [spans removeObjectForKey:term];
    } else {
        map[term] = @(deadline);
        spans[term] = @(span);
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:map forKey:kPFBMutedExpiryKey];
    [defaults setObject:spans forKey:kPFBMutedSpanKey];
    pfbRefreshMutedWords();
    PFBNoteFiltersChange();
}

// Drops filters whose deadline has passed, and forgets their entry.
- (void)pruneExpiredTerms {
    NSMutableDictionary* map = [self expiryMap];
    if (map.count == 0) {
        return;
    }
    NSMutableDictionary* spans = [self spanMap];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray* alive = [NSMutableArray array];
    BOOL changed = NO;
    for (NSString* term in self.terms) {
        id value = map[term];
        double deadline =
            [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
        if (deadline > 0 && deadline <= now) {
            [map removeObjectForKey:term];
            [spans removeObjectForKey:term];
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
    [d setObject:spans forKey:kPFBMutedSpanKey];
    pfbRefreshMutedWords();
}

// "Forever", or how many days are left.
- (NSString*)durationLabelForTerm:(NSString*)term {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSTimeInterval deadline = [self expiryForTerm:term];
    if (deadline <= 0) {
        return [bundle localizedStringForKey:@"MUTED_WORDS_DURATION_FOREVER"];
    }
    NSTimeInterval remaining = deadline - [[NSDate date] timeIntervalSince1970];
    return [bundle daysLeftText:MAX((NSInteger)ceil(remaining / 86400.0), 1)];
}

- (UIMenu*)durationMenuForTerm:(NSString*)term {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSTimeInterval current = [self expiryForTerm:term];
    id picked = [self spanMap][term];
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
                        [weakSelf setExpiry:deadline span:span forTerm:term];
                        [weakSelf.tableView reloadData];
                    }];
        // A timed term with no saved span is matched by its time left.
        BOOL selected;
        if (span <= 0) {
            selected = current <= 0;
        } else if ([picked respondsToSelector:@selector(doubleValue)]) {
            selected = current > 0 && fabs([picked doubleValue] - span) < 1.0;
        } else {
            selected = current > 0 &&
                       fabs((current - [[NSDate date] timeIntervalSince1970]) - span) < 86400.0;
        }
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
    PFBNoteFiltersChange();
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
            [self refreshWordsHero];
            return;
        }
    }
    // A new term starts with no deadline, even one a removed term left under its name.
    NSMutableDictionary* map = [self expiryMap];
    if (map[raw]) {
        [self setExpiry:0 span:0 forTerm:raw];
    }
    [self.terms insertObject:raw atIndex:0];
    field.text = @"";
    [self persist];
    // On the Words list, the new look slides the term in under the head, which keeps the field
    // and the keyboard.
    if ([self showcase]) {
        if (self.pendingSpan > 0) {
            [self setExpiry:[[NSDate date] timeIntervalSince1970] + self.pendingSpan span:self.pendingSpan forTerm:raw];
        }
        self.pendingSpan = 0;
        if (self.mode == 0) {
            NSIndexPath* first = [NSIndexPath indexPathForRow:1 inSection:0];
            [self.tableView performBatchUpdates:^{
              if (self.terms.count == 1) {
                  [self.tableView reloadRowsAtIndexPaths:@[ first ] withRowAnimation:UITableViewRowAnimationFade];
              } else {
                  [self.tableView insertRowsAtIndexPaths:@[ first ] withRowAnimation:UITableViewRowAnimationTop];
              }
            }
                                     completion:nil];
            [self refreshWordsHero];
            return;
        }
    }
    [self updatePreferredSize];
    [self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch*)sender {
    PFBMutedOptionToggled(sender);
}

// The new look lists the options in a sheet, as Twitter's new settings hold theirs.
- (void)showOptions {
    [PFBNativeSettingsSheetController
        presentRows:[[PFBMutedOptionsViewController alloc] init]
             titled:[[PFBBundle sharedBundle] localizedStringForKey:@"MUTED_WORDS_OPTIONS_HEADER"]
               from:self
             closed:nil];
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
    // The new look opens each list on its head; Languages then holds one row.
    if ([self showcase] && self.mode != 0) {
        return 1 + (self.mode == 1 ? 1 : (NSInteger)PFBHiddenThreads().count);
    }
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
    // The new look opens the options from a single row.
    return self.nativeLook ? 1 : kPFBMutedOptionCount;
}

// Custom headers in Chirp Bold, as on the Advanced search screen, instead of the
// small gray system captions.
- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.compact || self.nativeLook) {
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
    if (self.compact || self.nativeLook || self.mode != 0 || section == 0) {
        return 0.01;
    }
    return 46.0;
}

// The note under each list: the hidden conversations, the language filter's state,
// or how many Tweets the words filtered today.
- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    // In the new look the heads say what the lists do; Languages adds the language-less Tweets.
    if ([self showcase]) {
        return self.mode == 1 ? [[PFBBundle sharedBundle] localizedStringForKey:@"LANGUAGES_NOTE_UNDETECTED"] : nil;
    }
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
    // In the new look the note starts where the rows' gray circles do.
    CGFloat margin = [self showcase] ? kPFBShowcaseRowLeading : kPFBMutedSideMargin;
    label.textAlignment = NSTextAlignmentNatural;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                            constant:margin],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                             constant:-margin],
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

// MARK: new look

// The full screen of the new look; its language picker keeps plain rows.
- (BOOL)showcase {
    return self.nativeLook && !self.compact && !self.othersOnly;
}

// Each list opens on its head; Words then lists its terms and Options, Languages the other
// languages, Conversations what is hidden.
- (UITableViewCell*)showcaseCellFor:(UITableView*)tableView at:(NSIndexPath*)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        if (self.mode == 0) {
            return [self wordsHeroFor:tableView at:indexPath];
        }
        return self.mode == 1 ? [self languagesHeroFor:tableView at:indexPath] : [self threadsHeroFor:tableView at:indexPath];
    }
    PFBShowcaseRowCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ShowcaseRow" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [[cell.contentView viewWithTag:kPFBRowMenuTag] removeFromSuperview];
    if (self.mode == 0 && indexPath.section == 1) {
        [cell configureWithSymbol:@"slider.horizontal.3"
                            title:[[PFBBundle sharedBundle] localizedStringForKey:@"MUTED_WORDS_OPTIONS_HEADER"]
                         subtitle:nil
                            value:nil
                        accessory:PFBShowcaseAccessoryMore];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (self.mode == 0) {
        return [self termCell:cell at:(NSUInteger)indexPath.row - 1];
    }
    if (self.mode == 1) {
        return [self otherLanguagesCell:cell];
    }
    return [self threadCell:cell at:(NSUInteger)indexPath.row - 1];
}

- (UITableViewCell*)wordsHeroFor:(UITableView*)tableView at:(NSIndexPath*)indexPath {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    PFBMutedWordsHeroCell* hero = [tableView dequeueReusableCellWithIdentifier:@"WordsHero" forIndexPath:indexPath];
    hero.intro.text = [bundle localizedStringForKey:@"MUTED_WORDS_SUBTITLE"];
    hero.field.placeholder = [bundle localizedStringForKey:@"MUTED_WORDS_ADD_PLACEHOLDER"];
    hero.field.delegate = self;
    [hero.field removeTarget:self action:NULL forControlEvents:UIControlEventEditingChanged];
    [hero.field addTarget:self action:@selector(heroFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    hero.addButton.accessibilityLabel = [bundle localizedStringForKey:@"MUTED_WORDS_ADD_BUTTON"];
    [hero.addButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
    [hero.addButton addTarget:self action:@selector(heroAddTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self configureWordsHero:hero];
    return hero;
}

// The day's count, and under the field, while a term is typed, its kind and the duration it gets.
- (void)configureWordsHero:(PFBMutedWordsHeroCell*)hero {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    [hero setCount:pfbMutedHiddenCountToday() caption:[bundle localizedStringForKey:@"MUTED_WORDS_COUNT_TODAY"]];
    NSString* typed =
        [hero.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString* symbol = typed.length ? PFBMutedKindSymbol(typed) : nil;
    [hero setKindSymbol:symbol name:typed.length ? [[self kindLabelForTerm:typed] localizedCapitalizedString] : nil];
    self.shownKindSymbol = symbol;
    hero.durationButton.label = [self durationNameForSpan:self.pendingSpan];
    hero.durationButton.menu = [self pendingDurationMenu];
}

// The head is set again in place, so the field keeps its text and the keyboard; its height follows.
- (void)refreshWordsHero {
    UITableViewCell* head = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    if (![head isKindOfClass:[PFBMutedWordsHeroCell class]]) {
        return;
    }
    [self configureWordsHero:(PFBMutedWordsHeroCell*)head];
    [self.tableView performBatchUpdates:nil completion:nil];
}

// Only a change of kind redraws the head, not every letter.
- (void)heroFieldChanged:(UITextField*)field {
    NSString* typed = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString* symbol = typed.length ? PFBMutedKindSymbol(typed) : nil;
    if (symbol != self.shownKindSymbol && ![symbol isEqualToString:self.shownKindSymbol]) {
        [self refreshWordsHero];
    }
}

- (void)heroAddTapped:(UIButton*)sender {
    UITableViewCell* head = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    if ([head isKindOfClass:[PFBMutedWordsHeroCell class]]) {
        [self addTermFromField:((PFBMutedWordsHeroCell*)head).field];
    }
}

- (NSString*)durationNameForSpan:(NSTimeInterval)span {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    for (NSArray* option in PFBMutedDurations()) {
        if (fabs([option[1] doubleValue] - span) < 1.0) {
            return [bundle localizedStringForKey:option[0]];
        }
    }
    return [bundle localizedStringForKey:@"MUTED_WORDS_DURATION_FOREVER"];
}

// The duration the next term gets, chosen before it is added.
- (UIMenu*)pendingDurationMenu {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSArray* option in PFBMutedDurations()) {
        double span = [option[1] doubleValue];
        UIAction* action = [UIAction actionWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:option[0]]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction* chosen) {
                                               weakSelf.pendingSpan = span;
                                               [weakSelf refreshWordsHero];
                                             }];
        action.state = fabs(span - self.pendingSpan) < 1.0 ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithChildren:actions];
}

// A term: its kind's symbol, the term, then its kind and the time left. The row opens its menu:
// the durations, then Remove. With none yet, a line says the list is empty.
- (UITableViewCell*)termCell:(PFBShowcaseRowCell*)cell at:(NSUInteger)index {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    if (index >= self.terms.count) {
        [cell configureWithSymbol:nil
                            title:@""
                         subtitle:[bundle localizedStringForKey:@"MUTED_WORDS_EMPTY"]
                            value:nil
                        accessory:PFBShowcaseAccessoryNone];
        return cell;
    }
    NSString* term = self.terms[index];
    NSString* kind = [[self kindLabelForTerm:term] localizedCapitalizedString];
    [cell configureWithSymbol:PFBMutedKindSymbol(term)
                        title:term
                     subtitle:[NSString stringWithFormat:@"%@ · %@", kind, [self durationLabelForTerm:term]]
                        value:nil
                    accessory:PFBShowcaseAccessoryMenu];
    UIButton* menu = [UIButton buttonWithType:UIButtonTypeCustom];
    menu.tag = kPFBRowMenuTag;
    menu.showsMenuAsPrimaryAction = YES;
    menu.frame = cell.contentView.bounds;
    menu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    menu.menu = [self termMenuForTerm:term];
    menu.isAccessibilityElement = NO;
    [cell.contentView addSubview:menu];
    return cell;
}

- (UIMenu*)termMenuForTerm:(NSString*)term {
    __weak typeof(self) weakSelf = self;
    UIAction* remove = [UIAction actionWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"MUTED_WORDS_REMOVE_ACTION"]
                                           image:[UIImage systemImageNamed:@"trash"]
                                      identifier:nil
                                         handler:^(__unused UIAction* chosen) {
                                           [weakSelf removeTerm:term];
                                         }];
    remove.attributes = UIMenuElementAttributesDestructive;
    UIMenu* removal = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[ remove ]];
    return [UIMenu menuWithChildren:[[self durationMenuForTerm:term].children arrayByAddingObject:removal]];
}

- (void)removeTerm:(NSString*)term {
    NSUInteger index = [self.terms indexOfObject:term];
    if (index == NSNotFound) {
        return;
    }
    [self.terms removeObjectAtIndex:index];
    [self persist];
    [self.tableView reloadData];
}

- (UITableViewCell*)languagesHeroFor:(UITableView*)tableView at:(NSIndexPath*)indexPath {
    PFBMutedLanguagesHeroCell* hero = [tableView dequeueReusableCellWithIdentifier:@"LanguagesHero"
                                                                      forIndexPath:indexPath];
    [self configureLanguagesHero:hero];
    return hero;
}

// What the filter does now, then a chip per language of the list, filled while it is kept.
- (void)configureLanguagesHero:(PFBMutedLanguagesHeroCell*)hero {
    NSArray<NSString*>* codes = [self visibleLanguages];
    NSArray* kept = PFBKeptLanguageList();
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    NSMutableIndexSet* on = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < codes.count; i++) {
        [names addObject:PFBLanguageName(codes[i])];
        if ([kept containsObject:codes[i]]) {
            [on addIndex:i];
        }
    }
    hero.intro.text =
        [[PFBBundle sharedBundle] localizedStringForKey:kept.count ? @"LANGUAGES_INTRO_ON" : @"LANGUAGES_FOOTER_OFF"];
    [hero setLanguages:names kept:on target:self action:@selector(languageChipTapped:)];
}

- (void)languageChipTapped:(UIButton*)chip {
    NSArray<NSString*>* codes = [self visibleLanguages];
    if (chip.tag < 0 || (NSUInteger)chip.tag >= codes.count) {
        return;
    }
    [self toggleLanguage:codes[(NSUInteger)chip.tag]];
    UITableViewCell* head = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    if ([head isKindOfClass:[PFBMutedLanguagesHeroCell class]]) {
        [self configureLanguagesHero:(PFBMutedLanguagesHeroCell*)head];
        [self.tableView performBatchUpdates:nil completion:nil];
    }
}

// The languages the list leaves out, named once picked, behind a chevron.
- (UITableViewCell*)otherLanguagesCell:(PFBShowcaseRowCell*)cell {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSArray* tail = [self.languageCodes
        subarrayWithRange:NSMakeRange(kPFBLanguagesFull, self.languageCodes.count - kPFBLanguagesFull)];
    NSMutableArray* picked = [NSMutableArray array];
    for (NSString* code in tail) {
        if ([PFBKeptLanguageList() containsObject:code]) {
            [picked addObject:PFBLanguageName(code)];
        }
    }
    [cell configureWithSymbol:@"globe"
                        title:[bundle localizedStringForKey:@"LANGUAGES_OTHERS_TITLE"]
                     subtitle:nil
                        value:picked.count ? [NSListFormatter localizedStringByJoiningStrings:picked]
                                           : [bundle localizedStringForKey:@"LANGUAGES_OTHERS_NONE"]
                    accessory:PFBShowcaseAccessoryChevron];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell*)threadsHeroFor:(UITableView*)tableView at:(NSIndexPath*)indexPath {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    PFBMutedThreadsHeroCell* hero = [tableView dequeueReusableCellWithIdentifier:@"ThreadsHero" forIndexPath:indexPath];
    hero.intro.text = [bundle localizedStringForKey:@"THREADS_INTRO"];
    NSUInteger count = PFBHiddenThreads().count;
    if (count == 0) {
        [hero setTitle:[bundle localizedStringForKey:@"THREADS_EMPTY"]
                  hint:[bundle localizedStringForKey:@"THREADS_EMPTY_HINT"]];
    } else {
        [hero setTitle:count == 1 ? [bundle localizedStringForKey:@"THREADS_COUNT_ONE"]
                                  : [NSString stringWithFormat:[bundle localizedStringForKey:@"THREADS_COUNT_FORMAT"],
                                                               (long)count]
                  hint:nil];
    }
    return hero;
}

// A hidden conversation: its text, its author under it, and Show, which brings it back.
- (UITableViewCell*)threadCell:(PFBShowcaseRowCell*)cell at:(NSUInteger)index {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSArray<NSDictionary*>* threads = PFBHiddenThreads();
    // The list can shrink after the row count was taken.
    if (index >= threads.count) {
        [cell configureWithSymbol:nil title:@"" subtitle:nil value:nil accessory:PFBShowcaseAccessoryNone];
        return cell;
    }
    NSDictionary* entry = threads[index];
    NSString* preview = entry[@"preview"];
    NSString* who = entry[@"who"];
    NSString* title = preview.length ? preview : [bundle localizedStringForKey:@"THREADS_NO_PREVIEW"];
    cell.titleLines = 2;
    [cell configureWithSymbol:@"bubble.left"
                        title:title
                     subtitle:who.length ? who : nil
                        value:nil
                    accessory:PFBShowcaseAccessoryNone];
    PFBShowcaseButton* show = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
    show.label = [bundle localizedStringForKey:@"THREADS_SHOW_ACTION"];
    show.accessibilityValue = title;
    show.labelFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:14]);
    show.tag = (NSInteger)index;
    [show addTarget:self action:@selector(showThreadTapped:) forControlEvents:UIControlEventTouchUpInside];
    show.frame = CGRectMake(0, 0, [show sizeThatFits:CGSizeMake(CGFLOAT_MAX, 32.0)].width, 32.0);
    cell.trailingView = show;
    return cell;
}

- (void)showThreadTapped:(UIButton*)sender {
    NSArray<NSDictionary*>* threads = PFBHiddenThreads();
    if (sender.tag < 0 || (NSUInteger)sender.tag >= threads.count) {
        return;
    }
    PFBUnhideThread(threads[(NSUInteger)sender.tag][@"id"]);
    pfbRefreshMutedWords();
    PFBNoteFiltersChange();
    [self.tableView reloadData];
}

// A language: its name, with a check while its Tweets are kept.
- (UITableViewCell*)nativeLanguageCellFor:(UITableView*)tableView at:(NSIndexPath*)indexPath {
    PFBNativeSettingsRowCell* cell = [tableView dequeueReusableCellWithIdentifier:@"NativeCheck"
                                                                     forIndexPath:indexPath];
    UIImageView* tick = [cell.accessoryView isKindOfClass:[UIImageView class]] ? (UIImageView*)cell.accessoryView : nil;
    if (!tick) {
        tick = [[UIImageView alloc] initWithImage:PFBTwitterGlyphFor(@"checkmark", [UIImage systemImageNamed:@"checkmark"])];
        tick.tintColor = [UIColor labelColor];
        cell.accessoryView = tick;
    }
    NSString* code = [self visibleLanguages][(NSUInteger)indexPath.row];
    tick.hidden = ![PFBKeptLanguageList() containsObject:code];
    [cell configureWithTitle:PFBLanguageName(code)
                    iconName:nil
                       value:nil
                   accessory:PFBNativeSettingsRowAccessoryNone];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.contentView.alpha = 1.0;
    return cell;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    if ([self showcase]) {
        return [self showcaseCellFor:tableView at:indexPath];
    }
    if (self.nativeLook && self.othersOnly) {
        return [self nativeLanguageCellFor:tableView at:indexPath];
    }

    if (self.mode == 2) {
        PFBMutedTermCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"term"
                                            forIndexPath:indexPath];
        NSArray<NSDictionary*>* threads = PFBHiddenThreads();
        // The list can shrink after the row count was taken.
        if ((NSUInteger)indexPath.row >= threads.count) {
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
        cell.kindLabel.text = who.length ? [NSString stringWithFormat:@"  %@  ", who] : who;
        cell.termLabel.text =
            preview.length ? preview
                           : [bundle localizedStringForKey:@"THREADS_NO_PREVIEW"];
        cell.termLabel.textColor = [UIColor labelColor];
        return cell;
    }

    if (self.mode == 1) {
        UIColor* accent = PFBCurrentAccentColor() ?: self.view.tintColor;

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
                picked.count ? [NSListFormatter localizedStringByJoiningStrings:picked]
                             : [bundle localizedStringForKey:@"LANGUAGES_OTHERS_NONE"];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            // A reused language row can bring its tick along.
            [cell.contentView viewWithTag:kPFBTickTag].hidden = YES;
            return cell;
        }

        NSString* code = [self visibleLanguages][(NSUInteger)indexPath.row];
        BOOL kept = [PFBKeptLanguageList() containsObject:code];
        cell.textLabel.text = PFBLanguageName(code);
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor = [UIColor labelColor];
        // Placed by constraint rather than as an accessory: the system gives an
        // accessory its own inset, which would set this column apart from the
        // screen's row margin.
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

    PFBModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"opt"
                                                                       forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    PFBMutedConfigureOption(cell, (NSUInteger)indexPath.row);
    [cell.toggleSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    [cell.toggleSwitch addTarget:self
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
    // In the new look the heads stand at the top; the conversations follow theirs.
    if ([self showcase] && self.mode == 2) {
        return indexPath.row > 0;
    }
    if (self.mode == 2) {
        return PFBHiddenThreads().count > 0;
    }
    if (self.mode == 1) {
        return NO;
    }
    return indexPath.section == 0 && indexPath.row > 0 && self.terms.count > 0;
}

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self showcase]) {
        if (self.mode == 0 && indexPath.section == 1) {
            [self showOptions];
        } else if (self.mode == 1 && indexPath.row == 1) {
            [self showOtherLanguages];
        }
        return;
    }
    if (self.mode != 1) {
        return;
    }
    if ([self rowIsPicker:indexPath.row]) {
        [self showOtherLanguages];
        return;
    }
    [self toggleLanguage:[self visibleLanguages][(NSUInteger)indexPath.row]];
    [tableView reloadData];
}

- (void)showOtherLanguages {
    PFBMutedWordsViewController* others = [[PFBMutedWordsViewController alloc] init];
    others.othersOnly = YES;
    others.mode = 1;
    others.nativeLook = self.nativeLook;
    [self.navigationController pushViewController:others animated:YES];
}

// Keeping a language adds it; clearing the last one empties the set, which turns the filter off
// rather than hiding everything.
- (void)toggleLanguage:(NSString*)code {
    NSMutableArray* kept = PFBKeptLanguageList();
    if ([kept containsObject:code]) {
        [kept removeObject:code];
    } else {
        [kept addObject:code];
    }
    [[NSUserDefaults standardUserDefaults] setObject:kept forKey:kPFBLanguagesKey];
    PFBNoteFiltersChange();
}

- (void)tableView:(UITableView*)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath*)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    if (self.mode == 2) {
        NSArray<NSDictionary*>* threads = PFBHiddenThreads();
        NSInteger index = [self showcase] ? indexPath.row - 1 : indexPath.row;
        if (index >= 0 && index < (NSInteger)threads.count) {
            PFBUnhideThread(threads[(NSUInteger)index][@"id"]);
            pfbRefreshMutedWords();
            PFBNoteFiltersChange();
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
