// The Compatibility report screen and its option lists, drawn like the settings pages.
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Settings/PFBModernSettingsCells.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Debug/PFBTourChoicePopover.h"

// An orange dark enough to read on a light page; the system orange on a dark one.
static UIColor* PFBCompatWarningTextColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                   ? [UIColor systemOrangeColor]
                   : [UIColor colorWithRed:0.60 green:0.30 blue:0.0 alpha:1.0];
    }];
}

typedef NS_ENUM(NSInteger, PFBReportRowKind) {
    PFBReportRowHeader,
    PFBReportRowList,
    PFBReportRowOption,
    PFBReportRowClearAll,
    PFBReportRowHistory,
};

// One row of the report or of one of its lists.
@interface PFBReportRow : NSObject
@property (nonatomic) PFBReportRowKind kind;
@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy) NSString* value;
@property (nonatomic, copy) NSString* detail;
// Whether a tap does something: a list with options in it, or Clear all.
@property (nonatomic) BOOL enabled;
// The verdict a list row opens.
@property (nonatomic) PFBCompatVerdict verdict;
@end

@implementation PFBReportRow
@end

static PFBReportRow* PFBReportRowMake(PFBReportRowKind kind, NSString* title, NSString* value, NSString* detail) {
    PFBReportRow* row = [PFBReportRow new];
    row.kind = kind;
    row.title = title;
    row.value = value;
    row.detail = detail;
    return row;
}

// An option with a problem carries its reason under its name, and Off when it is off; a
// working option shows its state on the right. A not tested one adds what was seen before,
// as the copied report does.
static PFBReportRow* PFBReportOptionRow(PFBCompatResult* result) {
    BOOL working = result.verdict == PFBCompatVerdictOK;
    NSString* state = result.enabled ? (result.alwaysOn ? @"Always on" : @"On") : @"Off";
    NSString* value = result.internal ? nil : (working ? state : (result.enabled ? nil : @"Off"));
    NSString* detail = (!working || result.internal) ? result.detail : nil;
    if (result.verdict == PFBCompatVerdictNotTested && result.evidence.length) {
        detail = detail.length ? [NSString stringWithFormat:@"%@ \u00b7 %@", detail, result.evidence] : result.evidence;
    }
    return PFBReportRowMake(PFBReportRowOption, result.title, value, detail);
}

// "today", or the day as "Oct 23", with its year when it is not this one.
static NSString* PFBReportDay(NSDate* date) {
    NSCalendar* calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) {
        return @"today";
    }
    BOOL thisYear = [calendar component:NSCalendarUnitYear fromDate:date] ==
                    [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSDateFormatter* formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    formatter.dateFormat = thisYear ? @"MMM d" : @"MMM d, yyyy";
    return [formatter stringFromDate:date];
}

// "Counting since Oct 23 · this build since Oct 25.", one date when both are the same day.
static NSString* PFBReportHistoryText(void) {
    NSDate* build = PFBCompatCountingSince(NO);
    if (!build) {
        return nil;
    }
    NSDate* earlier = PFBCompatCountingSince(YES);
    NSString* buildDay = PFBReportDay(build);
    NSString* earlierDay = earlier ? PFBReportDay(earlier) : nil;
    if (!earlierDay || [earlierDay isEqualToString:buildDay]) {
        return [NSString stringWithFormat:@"Counting since %@.", buildDay];
    }
    return [NSString stringWithFormat:@"Counting since %@ · this build since %@.", earlierDay, buildDay];
}

// The settings pages' table: their cells, no separators, the palette's background.
static void PFBReportSetUpTable(UITableView* table) {
    table.backgroundColor = [PFBPalette currentBackgroundColor];
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.sectionHeaderTopPadding = 0.0;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 80.0;
    [table registerClass:[PFBModernSettingsHeaderCell class] forCellReuseIdentifier:@"HeaderCell"];
    [table registerClass:[PFBModernSettingsCompactButtonCell class] forCellReuseIdentifier:@"CompactButtonCell"];
    [table registerClass:[PFBModernSettingsTableViewCell class] forCellReuseIdentifier:@"ButtonCell"];
}

// The settings cell that draws a row; every state is set again, as cells are recycled.
static UITableViewCell* PFBReportCell(UITableView* table, NSIndexPath* indexPath, PFBReportRow* row) {
    if (row.kind == PFBReportRowHeader) {
        PFBModernSettingsHeaderCell* cell = [table dequeueReusableCellWithIdentifier:@"HeaderCell"
                                                                         forIndexPath:indexPath];
        [cell configureWithTitle:row.title];
        return cell;
    }
    UITableViewCellSelectionStyle selection =
        row.enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if (row.kind == PFBReportRowList || row.kind == PFBReportRowOption) {
        PFBModernSettingsCompactButtonCell* cell =
            [table dequeueReusableCellWithIdentifier:@"CompactButtonCell" forIndexPath:indexPath];
        [cell configureWithTitle:row.title subtitle:row.value detail:row.detail];
        [cell setShowsChevron:row.kind == PFBReportRowList && row.enabled];
        cell.selectionStyle = selection;
        return cell;
    }
    PFBModernSettingsTableViewCell* cell = [table dequeueReusableCellWithIdentifier:@"ButtonCell"
                                                                        forIndexPath:indexPath];
    [cell configureWithTitle:row.title subtitle:row.detail iconName:nil];
    [cell setShowsChevron:NO];
    cell.titleLabel.textColor = row.kind == PFBReportRowClearAll ? [UIColor systemRedColor] : [UIColor labelColor];
    cell.selectionStyle = selection;
    return cell;
}

// The height a page needs in the stethoscope's sheet: its bar and its table's content.
static CGFloat PFBReportPageHeight(UIViewController* page) {
    if (![page isKindOfClass:[UITableViewController class]] || !page.isViewLoaded) {
        return 0.0;
    }
    UITableView* table = ((UITableViewController*)page).tableView;
    return ceil(table.adjustedContentInset.top + table.contentSize.height);
}

// On the stethoscope's navigation: the height its sheet takes, and the most it can take.
static const void* kPFBReportFittedKey = &kPFBReportFittedKey;
static const void* kPFBReportMostKey = &kPFBReportMostKey;

// The stethoscope's sheet takes the height of the page in front again when it changed, up
// to the most it can take. Pushed in the settings, the report has no sheet of its own.
static void PFBReportFitSheet(UIViewController* page) {
    UINavigationController* navigation = page.navigationController;
    if (navigation.topViewController != page || !navigation.presentingViewController ||
        ![navigation.viewControllers.firstObject isKindOfClass:[PFBCompatibilityReportViewController class]]) {
        return;
    }
    if (@available(iOS 16.0, *)) {
        NSNumber* most = objc_getAssociatedObject(navigation, kPFBReportMostKey);
        CGFloat height = MIN(PFBReportPageHeight(page), most ? most.doubleValue : navigation.view.window.bounds.size.height);
        NSNumber* fitted = objc_getAssociatedObject(navigation, kPFBReportFittedKey);
        if (height <= 0.0 || (fitted && fabs(fitted.doubleValue - height) < 1.0)) {
            return;
        }
        objc_setAssociatedObject(navigation, kPFBReportFittedKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UISheetPresentationController* sheet = navigation.sheetPresentationController;
        // While the sheet comes up, the height joins its opening rather than following it.
        if (navigation.isBeingPresented) {
            [sheet invalidateDetents];
            return;
        }
        [sheet animateChanges:^{
          [sheet invalidateDetents];
        }];
    }
}

// One verdict's options on a page of their own: those not tested, or those working under
// their settings pages. The internal checks stay in the copied report.
@interface PFBCompatibilityListViewController : UITableViewController
- (instancetype)initWithVerdict:(PFBCompatVerdict)verdict title:(NSString*)title note:(NSString*)note;
@end

@implementation PFBCompatibilityListViewController {
    PFBCompatVerdict _verdict;
    NSString* _note;
    NSArray<PFBReportRow*>* _rows;
}

- (instancetype)initWithVerdict:(PFBCompatVerdict)verdict title:(NSString*)title note:(NSString*)note {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _verdict = verdict;
        _note = [note copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    PFBReportSetUpTable(self.tableView);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(compatDidChange:)
                                                 name:PFBCompatDidChangeNotification
                                               object:nil];
}

- (void)compatDidChange:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self rebuild];
        [self.tableView reloadData];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBDebuggerSetTriggerHidden(YES);
    [self rebuild];
    [self.tableView reloadData];
}

// Left together with the report, by closing the sheet or going back past it, the list
// refreshes the status and the settings page below, as the report would.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    PFBDebuggerSetTriggerHidden(NO);
    UINavigationController* navigation = self.navigationController;
    BOOL reportStays = NO;
    for (UIViewController* controller in navigation.viewControllers) {
        reportStays = reportStays || [controller isKindOfClass:[PFBCompatibilityReportViewController class]];
    }
    if (reportStays && !navigation.isBeingDismissed) {
        return;
    }
    PFBCompatRefreshStatus();
    UIViewController* below = navigation.viewControllers.lastObject;
    if ([below isKindOfClass:[PFBModernSettingsPageViewController class]]) {
        [((PFBModernSettingsPageViewController*)below).tableView reloadData];
    }
}

// The page is drawn again with the palette when light and dark switch.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
        [self.tableView reloadData];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    PFBReportFitSheet(self);
}

- (void)rebuild {
    NSMutableArray<PFBReportRow*>* rows = [NSMutableArray array];
    NSString* section = nil;
    for (PFBCompatResult* result in PFBCompatResults()) {
        if (result.verdict != _verdict || result.internal) {
            continue;
        }
        // Working options sit under their settings page, as in the copied report.
        if (_verdict == PFBCompatVerdictOK && ![result.section isEqualToString:section]) {
            section = result.section;
            [rows addObject:PFBReportRowMake(PFBReportRowHeader, section, nil, nil)];
        }
        [rows addObject:PFBReportOptionRow(result)];
    }
    _rows = rows;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_rows.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    return PFBReportCell(tableView, indexPath, _rows[(NSUInteger)indexPath.row]);
}

- (BOOL)tableView:(UITableView*)tableView shouldHighlightRowAtIndexPath:(NSIndexPath*)indexPath {
    return NO;
}

// The page's description, drawn as the settings pages draw theirs.
- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = _note;
    label.numberOfLines = 0;
    label.font = PFBSettingsDetailFont();
    label.textColor = PFBSettingsSubtitleColor();
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView*)tableView estimatedHeightForHeaderInSection:(NSInteger)section {
    return 44.0;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

@end

@implementation PFBCompatibilityReportViewController {
    NSArray<PFBReportRow*>* _rows;
}

+ (UINavigationController*)sheetFor:(UIWindow*)window {
    PFBCompatibilityReportViewController* report = [[self alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:report];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 16.0, *)) {
        __weak UINavigationController* weakNavigation = navigation;
        UISheetPresentationControllerDetent* fitted = [UISheetPresentationControllerDetent
            customDetentWithIdentifier:@"PFBReportFitted"
                              resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                UINavigationController* sheetNavigation = weakNavigation;
                                if (!sheetNavigation) {
                                    return context.maximumDetentValue;
                                }
                                objc_setAssociatedObject(sheetNavigation, kPFBReportMostKey,
                                                         @(context.maximumDetentValue),
                                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                CGFloat height =
                                    [objc_getAssociatedObject(sheetNavigation, kPFBReportFittedKey) doubleValue];
                                return height > 0.0 ? MIN(height, context.maximumDetentValue)
                                                    : context.maximumDetentValue;
                              }];
        navigation.sheetPresentationController.detents = @[ fitted ];
        // Sized once at the window's width before it opens, from a bar and the page's table,
        // so the sheet comes up at about the page's height.
        [report loadViewIfNeeded];
        report.view.frame = window.bounds;
        [report.tableView layoutIfNeeded];
        CGFloat bar = [navigation.navigationBar sizeThatFits:window.bounds.size].height;
        objc_setAssociatedObject(navigation, kPFBReportFittedKey,
                                 @(MIN(ceil(bar + report.tableView.contentSize.height), window.bounds.size.height)),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return navigation;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(compatDidChange:)
                                                 name:PFBCompatDidChangeNotification
                                               object:nil];
    self.title = [[PFBBundle sharedBundle] localizedStringForKey:@"COMPATIBILITY_REPORT_TITLE"];
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    PFBReportSetUpTable(self.tableView);
    UIBarButtonItem* copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(copyReport)];
    copy.tag = PFBNativeGlassTag;
    UIBarButtonItem* tours = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checklist"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(showTourChoice:)];
    tours.accessibilityLabel = @"Check options";
    tours.tag = PFBNativeGlassTag;
    self.navigationItem.rightBarButtonItems = @[ copy, tours ];
    [self rebuild];
}

// Twitter's binaries may finish reading while the report is open: it redraws then.
- (void)compatDidChange:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self rebuild];
        [self.tableView reloadData];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The stethoscope leads here: it steps aside while the report is on screen.
    PFBDebuggerSetTriggerHidden(YES);
    // Opened as a sheet, the report gets a check button that closes it.
    if (self.navigationController.presentingViewController &&
        self.navigationController.viewControllers.firstObject == self &&
        !self.navigationItem.leftBarButtonItem) {
        UIImageSymbolConfiguration* size =
            [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
        UIBarButtonItem* done =
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:size]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(close)];
        done.tintColor = [UIColor labelColor];
        done.tag = PFBNativeGlassTag;
        self.navigationItem.leftBarButtonItem = done;
    }
    [self rebuild];
    [self.tableView reloadData];
}

// The page underneath shows the status on its Report row; it redraws on return. Covered by
// one of its own lists, the report has not left.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    PFBDebuggerSetTriggerHidden(NO);
    NSArray* stack = self.navigationController.viewControllers;
    if (self.navigationController.topViewController != self && [stack containsObject:self]) {
        return;
    }
    PFBCompatRefreshStatus();
    NSUInteger index = [stack indexOfObject:self];
    UIViewController* below = (index != NSNotFound && index > 0) ? stack[index - 1] : stack.lastObject;
    if ([below isKindOfClass:[PFBModernSettingsPageViewController class]]) {
        [((PFBModernSettingsPageViewController*)below).tableView reloadData];
    }
}

// The page and its header are drawn again with the palette when light and dark switch.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
        [self rebuild];
        [self.tableView reloadData];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    PFBReportFitSheet(self);
}

// The problems first, then the options by verdict, then the counts.
- (void)rebuild {
    NSArray<PFBCompatResult*>* results = PFBCompatResults();
    NSMutableArray<PFBReportRow*>* broken = [NSMutableArray array];
    NSUInteger notTested = 0;
    NSUInteger working = 0;
    for (PFBCompatResult* result in results) {
        if (result.verdict == PFBCompatVerdictBroken) {
            [broken addObject:PFBReportOptionRow(result)];
        } else if (result.verdict == PFBCompatVerdictNotTested) {
            notTested++;
        } else if (!result.internal) {
            working++;
        }
    }
    NSMutableArray<PFBReportRow*>* rows = [NSMutableArray array];
    if (broken.count > 0) {
        [rows addObject:PFBReportRowMake(PFBReportRowHeader, @"Broken", nil, nil)];
        [rows addObjectsFromArray:broken];
    }
    [rows addObject:PFBReportRowMake(PFBReportRowHeader, @"Options", nil, nil)];
    PFBReportRow* untestedRow = PFBReportRowMake(PFBReportRowList, @"Not tested", @(notTested).stringValue,
                                                 @"Not seen yet during the check.");
    untestedRow.verdict = PFBCompatVerdictNotTested;
    untestedRow.enabled = notTested > 0;
    [rows addObject:untestedRow];
    PFBReportRow* workingRow = PFBReportRowMake(PFBReportRowList, @"Working", @(working).stringValue,
                                                @"Seen working on this build.");
    workingRow.verdict = PFBCompatVerdictOK;
    workingRow.enabled = working > 0;
    [rows addObject:workingRow];

    [rows addObject:PFBReportRowMake(PFBReportRowHeader, @"Data", nil, nil)];
    PFBReportRow* clearAll = PFBReportRowMake(PFBReportRowClearAll, @"Clear all", nil,
                                              @"Clear the counts and close Twitter. Settings are kept.");
    clearAll.enabled = YES;
    [rows addObject:clearAll];
    NSString* history = PFBReportHistoryText();
    if (history) {
        [rows addObject:PFBReportRowMake(PFBReportRowHistory, @"History", nil, history)];
    }
    _rows = rows;
    self.tableView.tableHeaderView = [self summaryHeaderFor:results];
}

- (UIView*)summaryHeaderFor:(NSArray<PFBCompatResult*>*)results {
    NSInteger broken = 0;
    NSUInteger optionCount = 0;
    for (PFBCompatResult* r in results) {
        broken += r.verdict == PFBCompatVerdictBroken ? 1 : 0;
        optionCount += r.internal ? 0 : 1;
    }
    PFBCompatReadState state = PFBCompatReadStatus();
    NSString* version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    // Never "Compatible" before Twitter's binaries are read; problems show as soon as known.
    UIColor* tone = [UIColor systemGreenColor];
    NSString* symbol = @"checkmark";
    NSString* title = [NSString stringWithFormat:@"Compatible with Twitter %@", version];
    if (broken > 0) {
        tone = [UIColor systemRedColor];
        symbol = @"xmark";
        title = [NSString stringWithFormat:@"%ld problem%@ with Twitter %@", (long)broken,
                                           broken == 1 ? @"" : @"s", version];
    } else if (state == PFBCompatReadPending) {
        tone = PFBSettingsSubtitleColor();
        symbol = nil;
        title = [NSString stringWithFormat:@"Checking Twitter %@", version];
    } else if (PFBCompatCheckIsDue()) {
        tone = [UIColor systemOrangeColor];
        symbol = @"exclamationmark";
        title = [NSString stringWithFormat:@"Twitter %@ not checked yet", version];
    } else if (state == PFBCompatReadFailed) {
        tone = [UIColor systemOrangeColor];
        symbol = @"exclamationmark";
        title = [NSString stringWithFormat:@"Twitter %@ not fully checked", version];
    }
    BOOL statusLine = state != PFBCompatReadDone;
    UIView* header = [[UIView alloc]
        initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, statusLine ? 172.0 : 140.0)];

    UIView* disc = [[UIView alloc] init];
    disc.backgroundColor = [tone colorWithAlphaComponent:0.15];
    disc.layer.cornerRadius = 26.0;
    disc.translatesAutoresizingMaskIntoConstraints = NO;
    UIView* mark;
    if (symbol) {
        UIImageSymbolConfiguration* markSize =
            [UIImageSymbolConfiguration configurationWithPointSize:26.0 weight:UIImageSymbolWeightBold];
        UIImageView* image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
                                                                         withConfiguration:markSize]];
        image.tintColor = tone;
        mark = image;
    } else {
        UIActivityIndicatorView* spinner =
            [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        mark = spinner;
    }
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    [disc addSubview:mark];

    UILabel* headline = [[UILabel alloc] init];
    headline.text = title;
    headline.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17]);
    headline.textColor = [UIColor labelColor];
    headline.textAlignment = NSTextAlignmentCenter;
    headline.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* subline = [[UILabel alloc] init];
    subline.text = [NSString stringWithFormat:@"iOS %@ · %lu options", UIDevice.currentDevice.systemVersion,
                                              (unsigned long)optionCount];
    subline.font = PFBSettingsDetailFont();
    subline.textColor = PFBSettingsSubtitleColor();
    subline.textAlignment = NSTextAlignmentCenter;
    subline.translatesAutoresizingMaskIntoConstraints = NO;

    [header addSubview:disc];
    [header addSubview:headline];
    [header addSubview:subline];
    NSMutableArray<NSLayoutConstraint*>* constraints = [NSMutableArray arrayWithArray:@[
        [disc.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.0],
        [disc.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [disc.widthAnchor constraintEqualToConstant:52.0],
        [disc.heightAnchor constraintEqualToConstant:52.0],
        [mark.centerXAnchor constraintEqualToAnchor:disc.centerXAnchor],
        [mark.centerYAnchor constraintEqualToAnchor:disc.centerYAnchor],
        [headline.topAnchor constraintEqualToAnchor:disc.bottomAnchor constant:10.0],
        [headline.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [headline.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [subline.topAnchor constraintEqualToAnchor:headline.bottomAnchor constant:3.0],
        [subline.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [subline.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    ]];
    if (statusLine) {
        UIView* icon;
        UILabel* status = [[UILabel alloc] init];
        status.font = PFBSettingsDetailFont();
        if (state == PFBCompatReadPending) {
            UIActivityIndicatorView* small =
                [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            small.transform = CGAffineTransformMakeScale(0.7, 0.7);
            [small startAnimating];
            icon = small;
            status.text = @"Checking Twitter’s settings…";
            status.textColor = PFBSettingsSubtitleColor();
        } else {
            UIImageView* warning =
                [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.circle.fill"]];
            warning.tintColor = [UIColor systemOrangeColor];
            warning.contentMode = UIViewContentModeScaleAspectFit;
            icon = warning;
            status.text = @"Twitter’s settings could not be read";
            status.textColor = PFBCompatWarningTextColor();
        }
        UIStackView* line = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, status ]];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = 6.0;
        line.alignment = UIStackViewAlignmentCenter;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:line];
        [constraints addObjectsFromArray:@[
            [icon.widthAnchor constraintEqualToConstant:16.0],
            [icon.heightAnchor constraintEqualToConstant:16.0],
            [line.topAnchor constraintEqualToAnchor:subline.bottomAnchor constant:12.0],
            [line.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_rows.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    return PFBReportCell(tableView, indexPath, _rows[(NSUInteger)indexPath.row]);
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (BOOL)tableView:(UITableView*)tableView shouldHighlightRowAtIndexPath:(NSIndexPath*)indexPath {
    return _rows[(NSUInteger)indexPath.row].enabled;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PFBReportRow* row = _rows[(NSUInteger)indexPath.row];
    if (!row.enabled) {
        return;
    }
    if (row.kind == PFBReportRowList) {
        NSString* version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"";
        NSString* note = row.verdict == PFBCompatVerdictOK
                             ? [NSString stringWithFormat:@"Options seen working on Twitter %@.", version]
                             : [NSString stringWithFormat:@"Options not seen yet on Twitter %@, or not since their code "
                                                          @"changed. The next tour or normal use proves them.",
                                                          version];
        PFBCompatibilityListViewController* list =
            [[PFBCompatibilityListViewController alloc] initWithVerdict:row.verdict title:row.title note:note];
        [self.navigationController pushViewController:list animated:YES];
    } else if (row.kind == PFBReportRowClearAll) {
        [self confirmClearAll];
    }
}

- (void)confirmClearAll {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:@"Clear all"
                         message:@"Clears everything counted and closes Twitter. Reopen it and every option is "
                                 @"checked on its own, then this report opens. Your settings are kept."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear all"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction* action) {
                                                // No app can relaunch itself: quitting cleanly makes the next
                                                // launch replay everything a new install does.
                                                PFBCompatReset();
                                                PFBCompatScheduleTourAtLaunch();
                                                [[NSUserDefaults standardUserDefaults] synchronize];
                                                exit(0);
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// The tours are offered from the checklist button, the popover's arrow on the icon:
// an image item's rendered view carries the rect the arrow needs.
- (void)showTourChoice:(UIBarButtonItem*)sender {
    if (PFBCompatTourIsRunning() || self.presentedViewController) {
        return;
    }
    PFBTourChoicePopover* choice = [[PFBTourChoicePopover alloc] init];
    __weak __typeof(self) weakSelf = self;
    choice.chosen = ^(BOOL full) {
      [weakSelf startTour:full];
    };
    choice.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController* popover = choice.popoverPresentationController;
    UIView* anchor = nil;
    @try {
        id rendered = [sender valueForKey:@"view"];
        anchor = [rendered isKindOfClass:[UIView class]] ? rendered : nil;
    } @catch (__unused id exception) {
        anchor = nil;
    }
    if (anchor) {
        popover.sourceView = anchor;
        popover.sourceRect = anchor.bounds;
    } else {
        popover.barButtonItem = sender;
    }
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    popover.delegate = choice;
    [self presentViewController:choice animated:YES completion:nil];
}

// The tour needs Twitter's screens in front, so the report steps aside first.
- (void)startTour:(BOOL)full {
    if (PFBCompatTourIsRunning()) {
        return;
    }
    void (^run)(void) = ^{
      if (full) {
          PFBCompatRunTour();
      } else {
          PFBCompatRunTourLeft();
      }
    };
    UIViewController* presenter = self.navigationController.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:YES completion:run];
    } else {
        run();
    }
}

- (void)copyReport {
    [UIPasteboard generalPasteboard].string = PFBCompatReportText();
    self.navigationItem.rightBarButtonItem.title = @"Copied";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     self.navigationItem.rightBarButtonItem.title = @"Copy";
                   });
}

@end
