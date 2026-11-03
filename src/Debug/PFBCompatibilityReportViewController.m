// The Compatibility report screen and its option lists, drawn like the settings pages.
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Settings/PFBModernSettingsCells.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Common/PFBSettings.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Debug/PFBTourChoicePopover.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/Native/PFBNativeSettingsSheetController.h"
#import "Support/PFBTwitterPopups.h"

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
    PFBReportRowCopy,
};

// One row of the report or of one of its lists.
@interface PFBReportRow : NSObject
@property (nonatomic) PFBReportRowKind kind;
@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy) NSString* value;
@property (nonatomic, copy) NSString* detail;
// Whether a tap does something: a list with options in it, Clear all, or the copy.
@property (nonatomic) BOOL enabled;
// The verdict a list row opens.
@property (nonatomic) PFBCompatVerdict verdict;
// The new look's symbol before the title.
@property (nonatomic, copy) NSString* iconName;
@end

@implementation PFBReportRow
@end

// A group's name in a list of the new look, over the rows it holds.
@interface PFBReportGroupCell : UITableViewCell
@property (nonatomic, strong) UILabel* label;
@end

@implementation PFBReportGroupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.numberOfLines = 0;
        [self.contentView addSubview:_label];
        CGFloat margin = [PFBNativeSettingsRowStyle shared].iconFrame.origin.x;
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:margin],
            [_label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-margin],
            [_label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
            [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    self.label.font = PFBSettingsTitleFont();
    self.label.textColor = PFBSettingsSubtitleColor();
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

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
    [table registerClass:[PFBNativeSettingsRowCell class] forCellReuseIdentifier:@"NativeRow"];
    [table registerClass:[PFBReportGroupCell class] forCellReuseIdentifier:@"GroupCell"];
    [table registerClass:[PFBShowcaseRowCell class] forCellReuseIdentifier:@"ShowcaseRow"];
}

// A row of a list in the new look: a group's name, or an option with its reason under its name.
static UITableViewCell* PFBReportNativeCell(UITableView* table, NSIndexPath* indexPath, PFBReportRow* row) {
    if (row.kind == PFBReportRowHeader) {
        PFBReportGroupCell* cell = [table dequeueReusableCellWithIdentifier:@"GroupCell" forIndexPath:indexPath];
        cell.label.text = row.title;
        return cell;
    }
    PFBNativeSettingsRowCell* cell = [table dequeueReusableCellWithIdentifier:@"NativeRow" forIndexPath:indexPath];
    [cell configureWithTitle:row.title
                      detail:row.detail
                    iconName:nil
                       value:row.value
                   accessory:PFBNativeSettingsRowAccessoryNone];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// The settings cell that draws a row; every state is set again, as cells are recycled.
static UITableViewCell* PFBReportCell(UITableView* table, NSIndexPath* indexPath, PFBReportRow* row, BOOL native) {
    if (native) {
        return PFBReportNativeCell(table, indexPath, row);
    }
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

// The sheet's height in the report while it moves: when a page asks for it, right after, and
// once the page has settled, for the first moves of a launch.
static NSUInteger gPFBReportFitMeasured;
static void PFBReportMeasureFit(UIViewController* page, NSString* moment) {
    UINavigationController* navigation = page.navigationController;
    if (gPFBReportFitMeasured >= 12 || !navigation.presentingViewController) {
        return;
    }
    gPFBReportFitMeasured++;
    PFBCompatMeasure(@"sheet fit",
                     [NSString stringWithFormat:@"%@ %@: sheet %.0f, page needs %.0f, moving %@",
                                                NSStringFromClass([page class]), moment,
                                                CGRectGetHeight(navigation.view.frame), PFBReportPageHeight(page),
                                                page.transitionCoordinator ? @"yes" : @"no"],
                     12);
}

// The stethoscope's sheet takes the height of the page in front again when it changed, up
// to the most it can take. Pushed in the settings, the report has no sheet of its own.
// The sheet re-reads its height at its next layout, which waits for the end of a push or a
// pop: during one, that layout is run at once, inside the animation, so the sheet moves with it.
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
        BOOL moving = page.transitionCoordinator != nil;
        [sheet animateChanges:^{
          [sheet invalidateDetents];
          if (moving) {
              [sheet.containerView layoutIfNeeded];
          }
        }];
    }
}

// A page coming in by a push or a pop takes its height as it starts to slide in, not once it
// has settled, so the sheet never shows it cut at the height of the page it replaces.
static void PFBReportFitSheetAlongside(UIViewController* page) {
    if (!page.transitionCoordinator || page.navigationController.isBeingPresented) {
        return;
    }
    [page.view layoutIfNeeded];
    PFBReportMeasureFit(page, @"comes in");
    PFBReportFitSheet(page);
    PFBReportMeasureFit(page, @"asked");
}

// One verdict's options on a page of their own: those not tested, or those working under
// their settings pages. The internal checks stay in the copied report, but for a broken one,
// which the new look's Broken row counts.
@interface PFBCompatibilityListViewController : UITableViewController
- (instancetype)initWithVerdict:(PFBCompatVerdict)verdict
                          title:(NSString*)title
                           note:(NSString*)note
                         native:(BOOL)native;
@end

@implementation PFBCompatibilityListViewController {
    PFBCompatVerdict _verdict;
    NSString* _note;
    BOOL _native;
    NSArray<PFBReportRow*>* _rows;
}

- (instancetype)initWithVerdict:(PFBCompatVerdict)verdict
                          title:(NSString*)title
                           note:(NSString*)note
                         native:(BOOL)native {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _verdict = verdict;
        _note = [note copy];
        _native = native;
        if (native) {
            PFBShowcaseSetTitle(self, title);
        } else {
            self.title = title;
        }
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

// Over the report's Tray head, which hides the bar, the list shows it again: also when a swipe
// back to the report is called off.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBDebuggerSetTriggerHidden(YES);
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self rebuild];
    [self.tableView reloadData];
    PFBReportFitSheetAlongside(self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    PFBReportMeasureFit(self, @"settled");
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
        if (result.verdict != _verdict || (result.internal && _verdict != PFBCompatVerdictBroken)) {
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
    return PFBReportCell(tableView, indexPath, _rows[(NSUInteger)indexPath.row], _native);
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
    // The new look's rows start their text where its icons stand.
    CGFloat margin = _native ? [PFBNativeSettingsRowStyle shared].iconFrame.origin.x : 10;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:margin],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-margin],
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

// A row that opens one verdict's list, with how many options it holds.
static PFBReportRow* PFBReportListRow(NSString* title, NSUInteger count, PFBCompatVerdict verdict, NSString* iconName) {
    PFBReportRow* row = PFBReportRowMake(PFBReportRowList, title, @(count).stringValue, nil);
    row.verdict = verdict;
    row.enabled = count > 0;
    row.iconName = iconName;
    return row;
}

// The verdict the report opens on, its mark and the mark's tone. Never "Compatible" before
// Twitter's binaries are read; problems show as soon as known. A nil mark is a spinner.
static NSString* PFBReportVerdict(NSArray<PFBCompatResult*>* results, UIColor** tone, NSString** symbol) {
    NSInteger broken = 0;
    for (PFBCompatResult* r in results) {
        broken += r.verdict == PFBCompatVerdictBroken ? 1 : 0;
    }
    PFBCompatReadState state = PFBCompatReadStatus();
    NSString* version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    *tone = [UIColor systemGreenColor];
    *symbol = @"checkmark";
    if (broken > 0) {
        *tone = [UIColor systemRedColor];
        *symbol = @"xmark";
        return [NSString stringWithFormat:@"%ld problem%@ with Twitter %@", (long)broken, broken == 1 ? @"" : @"s",
                                          version];
    }
    if (state == PFBCompatReadPending) {
        *tone = PFBSettingsSubtitleColor();
        *symbol = nil;
        return [NSString stringWithFormat:@"Checking Twitter %@", version];
    }
    if (PFBCompatCheckIsDue()) {
        *tone = [UIColor systemOrangeColor];
        *symbol = @"exclamationmark";
        return [NSString stringWithFormat:@"Twitter %@ not checked yet", version];
    }
    if (state == PFBCompatReadFailed) {
        *tone = [UIColor systemOrangeColor];
        *symbol = @"exclamationmark";
        return [NSString stringWithFormat:@"Twitter %@ not fully checked", version];
    }
    return [NSString stringWithFormat:@"Compatible with Twitter %@", version];
}

// The line under the verdict while Twitter's settings are read, or when they could not be.
static NSString* PFBReportReadLine(void) {
    PFBCompatReadState state = PFBCompatReadStatus();
    if (state == PFBCompatReadPending) {
        return @"Checking Twitter’s settings…";
    }
    return state == PFBCompatReadFailed ? @"Twitter’s settings could not be read" : nil;
}

// The new look's head of the report: its line, then a card with the verdict on a glass disc,
// the share of options seen working on a glass meter, and the button that checks the rest.
@interface PFBReportShowcaseHeader : UIView
@property (nonatomic, strong) UILabel* intro;
@property (nonatomic, strong) UIView* card;
@property (nonatomic, strong) PFBShowcaseSurface* disc;
@property (nonatomic, strong) UIView* mark;
@property (nonatomic, strong) UILabel* verdict;
@property (nonatomic, strong) UILabel* subline;
@property (nonatomic, strong) UILabel* readLine;
@property (nonatomic, strong) PFBShowcaseSurface* meter;
@property (nonatomic, strong) NSArray<UIView*>* segments;
@property (nonatomic, strong) NSArray<NSNumber*>* shares;
@property (nonatomic, strong) UILabel* caption;
@property (nonatomic, strong) PFBShowcaseButton* check;
@end

@implementation PFBReportShowcaseHeader

- (instancetype)initWithResults:(NSArray<PFBCompatResult*>*)results {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        NSUInteger working = 0;
        NSUInteger notTested = 0;
        NSUInteger broken = 0;
        NSUInteger options = 0;
        for (PFBCompatResult* result in results) {
            options += result.internal ? 0 : 1;
            if (result.verdict == PFBCompatVerdictBroken) {
                broken++;
            } else if (result.verdict == PFBCompatVerdictNotTested) {
                notTested++;
            } else if (!result.internal) {
                working++;
            }
        }
        _intro = PFBShowcaseIntroLabel();
        _intro.text = @"Check every option still works after a Twitter update.";
        _card = PFBShowcaseCard();
        _disc = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        UIColor* tone = nil;
        NSString* symbol = nil;
        _verdict = [[UILabel alloc] init];
        _verdict.text = PFBReportVerdict(results, &tone, &symbol);
        _verdict.numberOfLines = 0;
        _verdict.textAlignment = NSTextAlignmentCenter;
        _verdict.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:17]);
        _verdict.textColor = PFBSettingsTextColor();
        if (symbol) {
            UIImageSymbolConfiguration* size = [UIImageSymbolConfiguration configurationWithPointSize:26
                                                                                              weight:UIImageSymbolWeightBold];
            UIImageView* image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:size]];
            image.contentMode = UIViewContentModeCenter;
            image.tintColor = tone;
            _mark = image;
        } else {
            UIActivityIndicatorView* spinner =
                [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            _mark = spinner;
        }
        [_disc.contentView addSubview:_mark];
        _subline = [[UILabel alloc] init];
        _subline.text = [NSString stringWithFormat:@"iOS %@ · %lu options", UIDevice.currentDevice.systemVersion,
                                                   (unsigned long)options];
        _subline.textAlignment = NSTextAlignmentCenter;
        _subline.font = PFBSettingsDetailFont();
        _subline.textColor = PFBSettingsSubtitleColor();
        NSString* read = PFBReportReadLine();
        if (read) {
            _readLine = [[UILabel alloc] init];
            _readLine.text = read;
            _readLine.numberOfLines = 0;
            _readLine.textAlignment = NSTextAlignmentCenter;
            _readLine.font = PFBSettingsDetailFont();
            _readLine.textColor = PFBCompatReadStatus() == PFBCompatReadFailed ? PFBCompatWarningTextColor()
                                                                               : PFBSettingsSubtitleColor();
        }
        // The meter holds what was seen working, what is not tested yet, and what broke.
        _meter = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        NSMutableArray<UIView*>* segments = [NSMutableArray array];
        for (UIColor* color in @[ [UIColor systemGreenColor], [UIColor systemGray3Color], [UIColor systemRedColor] ]) {
            UIView* segment = [[UIView alloc] init];
            segment.backgroundColor = color;
            [_meter.contentView addSubview:segment];
            [segments addObject:segment];
        }
        _segments = segments;
        _shares = @[ @(working), @(notTested), @(broken) ];
        NSMutableString* caption =
            [NSMutableString stringWithFormat:@"%lu of %lu seen working", (unsigned long)working, (unsigned long)options];
        if (broken > 0) {
            [caption appendFormat:@" · %lu broken", (unsigned long)broken];
        }
        if (notTested > 0) {
            [caption appendFormat:@" · %lu to check", (unsigned long)notTested];
        }
        _caption = [[UILabel alloc] init];
        _caption.text = caption;
        _caption.numberOfLines = 0;
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.font = PFBSettingsDetailFont();
        _caption.textColor = PFBSettingsSubtitleColor();
        _check = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
        _check.symbolName = @"checklist";
        _check.label = @"Check options";
        for (UIView* part in @[ _disc, _verdict, _subline, _meter, _caption, _check ]) {
            [_card addSubview:part];
        }
        if (_readLine) {
            [_card addSubview:_readLine];
        }
        [self addSubview:_intro];
        [self addSubview:_card];
    }
    return self;
}

// Lays the parts out at the width given and returns the height they take.
- (CGFloat)layoutForWidth:(CGFloat)width {
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    CGFloat introHeight = ceil([self.intro sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    self.intro.frame = CGRectMake(side, 12.0, inner, introHeight);
    CGFloat room = MAX(0, inner - 2 * side);
    CGFloat y = 24.0;
    self.disc.frame = CGRectMake(inner / 2.0 - 32.0, y, 64.0, 64.0);
    self.mark.frame = self.disc.bounds;
    y = CGRectGetMaxY(self.disc.frame) + 14.0;
    CGFloat verdictHeight = ceil([self.verdict sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
    self.verdict.frame = CGRectMake(side, y, room, verdictHeight);
    y += verdictHeight + 4.0;
    CGFloat sublineHeight = ceil(self.subline.font.lineHeight);
    self.subline.frame = CGRectMake(side, y, room, sublineHeight);
    y += sublineHeight;
    if (self.readLine) {
        CGFloat readHeight = ceil([self.readLine sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
        self.readLine.frame = CGRectMake(side, y + 8.0, room, readHeight);
        y += 8.0 + readHeight;
    }
    y += 18.0;
    self.meter.frame = CGRectMake(side, y, room, 12.0);
    [self layoutMeter];
    y += 12.0 + 8.0;
    CGFloat captionHeight = ceil([self.caption sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
    self.caption.frame = CGRectMake(side, y, room, captionHeight);
    y += captionHeight + 16.0;
    CGFloat checkHeight = [self.check sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height + 4.0;
    self.check.frame = CGRectMake(side, y, room, checkHeight);
    y += checkHeight + 20.0;
    self.card.frame = CGRectMake(side, CGRectGetMaxY(self.intro.frame) + 20.0, inner, y);
    return CGRectGetMaxY(self.card.frame) + 8.0;
}

// The shares side by side in the meter, 2 points apart and 2 points in from its edge.
- (void)layoutMeter {
    CGRect track = CGRectInset(self.meter.bounds, 2.0, 2.0);
    double total = 0;
    NSUInteger shown = 0;
    for (NSNumber* share in self.shares) {
        total += share.doubleValue;
        shown += share.doubleValue > 0 ? 1 : 0;
    }
    CGFloat room = MAX(0, CGRectGetWidth(track) - 2.0 * (CGFloat)MAX((NSInteger)shown - 1, 0));
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat x = CGRectGetMinX(track);
    for (NSUInteger i = 0; i < self.segments.count; i++) {
        double share = self.shares[i].doubleValue;
        CGFloat length = total > 0 ? floor(room * (CGFloat)(share / total)) : 0;
        CGRect frame = CGRectMake(x, CGRectGetMinY(track), length, CGRectGetHeight(track));
        if (rtl) {
            frame.origin.x = CGRectGetWidth(self.meter.bounds) - CGRectGetMaxX(frame);
        }
        self.segments[i].frame = frame;
        self.segments[i].layer.cornerRadius = CGRectGetHeight(track) / 2.0;
        self.segments[i].hidden = length <= 0;
        x += length + (length > 0 ? 2.0 : 0);
    }
}

@end

@interface PFBCompatibilityReportViewController ()
// Opened as the stethoscope's sheet, which takes no more height than the report's content.
@property (nonatomic) BOOL inSheet;
@end

@implementation PFBCompatibilityReportViewController {
    // The rows by section: one section in both looks.
    NSArray<NSArray<PFBReportRow*>*>* _sections;
    // The new look's head, and its foot: the history, then Clear all.
    PFBReportShowcaseHeader* _showcaseHeader;
    UIView* _showcaseFooter;
    UILabel* _historyLabel;
    PFBShowcaseButton* _clearAllButton;
    // While the copy row shows Copied.
    BOOL _copied;
    // Whether the foot stands where it belongs for the content and width it was placed for.
    BOOL _footerPlaced;
    // In the new look's sheet, the head of Twitter's Tray in place of the bar.
    PFBNativeSheetHead* _trayHead;
}

+ (UINavigationController*)sheetFor:(UIWindow*)window {
    PFBCompatibilityReportViewController* report = [[self alloc] initWithStyle:UITableViewStyleGrouped];
    report.inSheet = YES;
    // Away from the settings, the report takes the look New Twitter settings gives them.
    report.nativeLook = [PFBSettings boolForKey:@"new_twitter_settings"];
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
        // Under the Tray head the sheet opens with no bar.
        navigation.navigationBarHidden = report->_trayHead != nil;
        report.view.frame = window.bounds;
        [report placeTrayHead];
        [report.tableView layoutIfNeeded];
        CGFloat bar = report->_trayHead ? report.tableView.contentInset.top
                                        : [navigation.navigationBar sizeThatFits:window.bounds.size].height;
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
    // The new look titles the report as the row that opens it, and holds its actions in the page.
    if (self.nativeLook) {
        PFBShowcaseSetTitle(self, [[PFBBundle sharedBundle] localizedStringForKey:@"COMPATIBILITY_TITLE"]);
    } else {
        self.title = [[PFBBundle sharedBundle] localizedStringForKey:@"COMPATIBILITY_REPORT_TITLE"];
    }
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    PFBReportSetUpTable(self.tableView);
    if (self.inSheet && self.nativeLook) {
        _trayHead = [[PFBNativeSheetHead alloc]
            initWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"COMPATIBILITY_TITLE"]
                     step:NO];
        [_trayHead.button addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        _trayHead.backgroundColor = self.view.backgroundColor;
        [self.tableView addSubview:_trayHead];
    }
    if (!self.nativeLook) {
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
    }
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
    // Opened as a sheet, the report gets a check button that closes it, or in the new look the
    // Tray head, which takes the bar's place.
    BOOL sheetRoot = self.navigationController.presentingViewController &&
                     self.navigationController.viewControllers.firstObject == self;
    if (sheetRoot && _trayHead) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    } else if (sheetRoot && !self.navigationItem.leftBarButtonItem) {
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
    PFBReportFitSheetAlongside(self);
}

// Twitter's tab bar settles once the page is in: the new look's foot is placed again then.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    PFBReportMeasureFit(self, @"settled");
    _footerPlaced = NO;
    [self.view setNeedsLayout];
}

// The page underneath shows the status on its Compatibility row; it redraws on return. Covered by
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
        _trayHead.backgroundColor = self.tableView.backgroundColor;
        [self rebuild];
        [self.tableView reloadData];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self placeTrayHead];
    [self layoutShowcase];
    PFBReportFitSheet(self);
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    [self placeTrayHead];
}

// The head takes the room above the rows and stays at the top while they scroll under it; pulled
// down, it goes with them.
- (void)placeTrayHead {
    if (!_trayHead) {
        return;
    }
    UITableView* table = self.tableView;
    CGFloat width = CGRectGetWidth(table.bounds);
    if (width <= 0) {
        return;
    }
    CGFloat height = [_trayHead systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                              withHorizontalFittingPriority:UILayoutPriorityRequired
                                    verticalFittingPriority:UILayoutPriorityFittingSizeLevel]
                         .height;
    if (fabs(table.contentInset.top - height) > 0.5) {
        BOOL atTop = table.contentOffset.y <= 0.5 - table.adjustedContentInset.top;
        UIEdgeInsets insets = table.contentInset;
        insets.top = height;
        table.contentInset = insets;
        if (atTop) {
            table.contentOffset = CGPointMake(table.contentOffset.x, -table.adjustedContentInset.top);
        }
    }
    CGFloat top = MAX(-height, table.contentOffset.y + table.safeAreaInsets.top);
    _trayHead.frame = CGRectMake(0, top, width, height);
    [table bringSubviewToFront:_trayHead];
}

- (void)rebuild {
    NSArray<PFBCompatResult*>* results = PFBCompatResults();
    if (self.nativeLook) {
        [self rebuildNative:results];
        return;
    }
    [self rebuildClassic:results];
    self.tableView.tableHeaderView = [self summaryHeaderFor:results];
}

// The problems first, then the options by verdict, then the counts.
- (void)rebuildClassic:(NSArray<PFBCompatResult*>*)results {
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
    PFBReportRow* untestedRow = PFBReportListRow(@"Not tested", notTested, PFBCompatVerdictNotTested, nil);
    untestedRow.detail = @"Not seen yet during the check.";
    [rows addObject:untestedRow];
    PFBReportRow* workingRow = PFBReportListRow(@"Working", working, PFBCompatVerdictOK, nil);
    workingRow.detail = @"Seen working on this build.";
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
    _sections = @[ rows ];
}

// The new look: the head's card, one row per verdict with the broken options first when there
// are any, the copy, then the history and Clear all at the foot.
- (void)rebuildNative:(NSArray<PFBCompatResult*>*)results {
    NSUInteger broken = 0;
    NSUInteger notTested = 0;
    NSUInteger working = 0;
    for (PFBCompatResult* result in results) {
        if (result.verdict == PFBCompatVerdictBroken) {
            broken++;
        } else if (result.verdict == PFBCompatVerdictNotTested) {
            notTested++;
        } else if (!result.internal) {
            working++;
        }
    }
    NSMutableArray<PFBReportRow*>* rows = [NSMutableArray array];
    if (broken > 0) {
        [rows addObject:PFBReportListRow(@"Broken", broken, PFBCompatVerdictBroken, @"xmark")];
    }
    [rows addObject:PFBReportListRow(@"Not tested", notTested, PFBCompatVerdictNotTested, @"circle.dashed")];
    [rows addObject:PFBReportListRow(@"Working", working, PFBCompatVerdictOK, @"checkmark")];
    PFBReportRow* copy = PFBReportRowMake(PFBReportRowCopy, _copied ? @"Copied" : @"Copy report", nil, nil);
    copy.iconName = _copied ? @"checkmark" : @"doc.on.doc";
    copy.enabled = YES;
    [rows addObject:copy];
    _sections = @[ rows ];

    _showcaseHeader = [[PFBReportShowcaseHeader alloc] initWithResults:results];
    [_showcaseHeader.check addTarget:self action:@selector(showTourTray:) forControlEvents:UIControlEventTouchUpInside];
    if (!_showcaseFooter) {
        _showcaseFooter = [[UIView alloc] init];
        _historyLabel = [[UILabel alloc] init];
        _historyLabel.numberOfLines = 0;
        _historyLabel.textAlignment = NSTextAlignmentNatural;
        _clearAllButton = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleDestructive];
        _clearAllButton.label = @"Clear all";
        [_clearAllButton addTarget:self action:@selector(confirmClearAll) forControlEvents:UIControlEventTouchUpInside];
        [_showcaseFooter addSubview:_historyLabel];
        [_showcaseFooter addSubview:_clearAllButton];
    }
    _historyLabel.text = PFBReportHistoryText();
    _historyLabel.font = PFBSettingsDetailFont();
    _historyLabel.textColor = PFBSettingsSubtitleColor();
    self.tableView.tableHeaderView = nil;
    _footerPlaced = NO;
    [self.view setNeedsLayout];
}

// The head at the table's width; at the foot, the history, then Clear all held to the bottom of the
// page above Twitter's tab bar, or right under the history in the sheet. The table lays itself out
// on every scroll, so both are placed again only for a new width or new content.
- (void)layoutShowcase {
    if (!_showcaseHeader) {
        return;
    }
    UITableView* table = self.tableView;
    CGFloat width = CGRectGetWidth(table.bounds);
    if (width <= 0) {
        return;
    }
    BOOL newWidth = fabs(CGRectGetWidth(_showcaseHeader.frame) - width) > 0.5;
    if (table.tableHeaderView != _showcaseHeader || newWidth) {
        CGFloat headerHeight = [_showcaseHeader layoutForWidth:width];
        _showcaseHeader.frame = CGRectMake(0, 0, width, headerHeight);
        table.tableHeaderView = _showcaseHeader;
    }
    if (_footerPlaced && !newWidth) {
        return;
    }
    _footerPlaced = YES;
    CGFloat inner = MAX(0, width - 40.0);
    // The foot starts where the rows' section ends, which the grouped table keeps below the last row;
    // the history goes 14 pt under that row, as the notes under the Filters lists do.
    NSInteger sections = table.numberOfSections;
    NSInteger rows = sections > 0 ? [table numberOfRowsInSection:sections - 1] : 0;
    CGFloat footerTop = sections > 0 ? CGRectGetMaxY([table rectForSection:sections - 1])
                                     : CGRectGetMaxY(_showcaseHeader.frame);
    NSIndexPath* last = rows > 0 ? [NSIndexPath indexPathForRow:rows - 1 inSection:sections - 1] : nil;
    CGFloat historyY = (last ? CGRectGetMaxY([table rectForRowAtIndexPath:last]) : footerTop) + 14.0 - footerTop;
    // The history starts where the rows' gray circles do.
    CGFloat noteWidth = MAX(0, width - 2 * kPFBShowcaseRowLeading);
    CGFloat historyHeight =
        _historyLabel.text.length ? ceil([_historyLabel sizeThatFits:CGSizeMake(noteWidth, CGFLOAT_MAX)].height) : 0;
    _historyLabel.frame = CGRectMake(kPFBShowcaseRowLeading, historyY, noteWidth, historyHeight);
    CGFloat capsuleHeight = [_clearAllButton sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
    CGFloat height = historyY + historyHeight + 28.0 + capsuleHeight + 16.0;
    if (!self.inSheet) {
        CGFloat limit = PFBShowcaseBottomLimit(table) - table.bounds.origin.y - table.adjustedContentInset.top;
        height = MAX(height, limit - footerTop);
    }
    _clearAllButton.frame = CGRectMake(20.0, height - 16.0 - capsuleHeight, inner, capsuleHeight);
    _showcaseFooter.frame = CGRectMake(0, 0, width, height);
    table.tableFooterView = _showcaseFooter;
}

- (UIView*)summaryHeaderFor:(NSArray<PFBCompatResult*>*)results {
    NSUInteger optionCount = 0;
    for (PFBCompatResult* r in results) {
        optionCount += r.internal ? 0 : 1;
    }
    PFBCompatReadState state = PFBCompatReadStatus();
    UIColor* tone = nil;
    NSString* symbol = nil;
    NSString* title = PFBReportVerdict(results, &tone, &symbol);
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
            status.text = PFBReportReadLine();
            status.textColor = PFBSettingsSubtitleColor();
        } else {
            UIImageView* warning =
                [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.circle.fill"]];
            warning.tintColor = [UIColor systemOrangeColor];
            warning.contentMode = UIViewContentModeScaleAspectFit;
            icon = warning;
            status.text = PFBReportReadLine();
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

- (PFBReportRow*)rowAt:(NSIndexPath*)indexPath {
    return _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_sections[(NSUInteger)section].count;
}

// The new look's rows carry a symbol in a gray circle: the verdict's in its color, the copy's in the
// text color. Working and Not tested take Twitter's glyphs, Working in Twitter's green.
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBReportRow* row = [self rowAt:indexPath];
    if (!self.nativeLook) {
        return PFBReportCell(tableView, indexPath, row, NO);
    }
    PFBShowcaseRowCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ShowcaseRow" forIndexPath:indexPath];
    BOOL list = row.kind == PFBReportRowList;
    [cell configureWithSymbol:row.iconName
                        title:row.title
                     subtitle:nil
                        value:row.value
                    accessory:list && row.enabled ? PFBShowcaseAccessoryChevron : PFBShowcaseAccessoryNone];
    if (list) {
        cell.symbolColor = row.verdict == PFBCompatVerdictBroken ? [UIColor systemRedColor]
                           : row.verdict == PFBCompatVerdictOK
                               ? [UIColor colorWithRed:0.0 green:186.0 / 255.0 blue:124.0 / 255.0 alpha:1.0]
                               : PFBSettingsSubtitleColor();
        cell.twitterGlyphName = row.verdict == PFBCompatVerdictOK          ? @"checkmark_circle"
                                : row.verdict == PFBCompatVerdictNotTested ? @"clock_dashed"
                                                                           : nil;
    }
    cell.selectionStyle = row.enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    // Copy report acts on a tap, so VoiceOver hears a button.
    if (row.kind == PFBReportRowCopy) {
        cell.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (BOOL)tableView:(UITableView*)tableView shouldHighlightRowAtIndexPath:(NSIndexPath*)indexPath {
    return [self rowAt:indexPath].enabled;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PFBReportRow* row = [self rowAt:indexPath];
    if (!row.enabled) {
        return;
    }
    if (row.kind == PFBReportRowList) {
        NSString* version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"";
        NSString* note = [NSString stringWithFormat:@"Options not seen yet on Twitter %@, or not since their code "
                                                    @"changed. The next tour or normal use proves them.",
                                                    version];
        if (row.verdict == PFBCompatVerdictOK) {
            note = [NSString stringWithFormat:@"Options seen working on Twitter %@.", version];
        } else if (row.verdict == PFBCompatVerdictBroken) {
            note = [NSString stringWithFormat:@"Options that stopped working on Twitter %@.", version];
        }
        PFBCompatibilityListViewController* list =
            [[PFBCompatibilityListViewController alloc] initWithVerdict:row.verdict
                                                                  title:row.title
                                                                   note:note
                                                                 native:self.nativeLook];
        [self.navigationController pushViewController:list animated:YES];
    } else if (row.kind == PFBReportRowClearAll) {
        [self confirmClearAll];
    } else if (row.kind == PFBReportRowCopy) {
        [self copyReport];
    }
}

- (void)confirmClearAll {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:@"Clear all"
                         message:@"Clears everything counted and closes Twitter. Reopen it and every option is "
                                 @"checked on its own, then this report opens. Your settings are kept."
                  preferredStyle:UIAlertControllerStyleAlert];
    PFBAlertAddAction(alert, @"Cancel", UIAlertActionStyleCancel, self.nativeLook, nil);
    PFBAlertAddAction(alert, @"Clear all", UIAlertActionStyleDestructive, self.nativeLook, ^{
        // No app can relaunch itself: quitting cleanly makes the next launch replay everything a
        // new install does.
        PFBCompatReset();
        PFBCompatScheduleTourAtLaunch();
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    });
    PFBAlertPresent(alert, self, self.nativeLook, nil);
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// The tours are offered from the checklist button, the popover's arrow on the icon:
// an image item's rendered view carries the rect the arrow needs.
- (void)showTourChoice:(UIBarButtonItem*)sender {
    UIView* anchor = nil;
    @try {
        id rendered = [sender valueForKey:@"view"];
        anchor = [rendered isKindOfClass:[UIView class]] ? rendered : nil;
    } @catch (__unused id exception) {
        anchor = nil;
    }
    [self showTourBubbleFrom:anchor item:sender];
}

- (void)showTourBubbleFrom:(UIView*)anchor item:(UIBarButtonItem*)item {
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
    if (anchor) {
        popover.sourceView = anchor;
        popover.sourceRect = anchor.bounds;
    } else {
        popover.barButtonItem = item;
    }
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    popover.delegate = choice;
    [self presentViewController:choice animated:YES completion:nil];
}

// The new look offers them in Twitter's Tray from Check options, the second one grayed out once
// nothing is left; the bubble stands in where the app has no Tray. A tour starts once the Tray
// has gone.
- (void)showTourTray:(UIButton*)sender {
    if (PFBCompatTourIsRunning() || self.presentedViewController) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSMutableArray* rows = [NSMutableArray array];
    for (NSNumber* tour in @[ @YES, @NO ]) {
        BOOL full = tour.boolValue;
        id row = PFBTrayRow(PFBTourChoiceTitle(full), PFBTourChoiceLine(full), full ? @"bulleted_list" : @"skip_forward",
                            !full && PFBCompatTourScreens(NO) == 0, ^{
                                PFBAfterPresentations(^{
                                    [weakSelf startTour:full];
                                });
                            });
        if (row) {
            [rows addObject:row];
        }
    }
    if (rows.count == 2 && PFBPresentTray(self, @"Check options", rows)) {
        return;
    }
    [self showTourBubbleFrom:sender item:nil];
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

// Copied shows a moment on the button, or in the new look on the copy row.
- (void)copyReport {
    [UIPasteboard generalPasteboard].string = PFBCompatReportText();
    if (self.nativeLook) {
        [self showCopied:YES];
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [weakSelf showCopied:NO];
        });
        return;
    }
    UIBarButtonItem* item = self.navigationItem.rightBarButtonItem;
    item.title = @"Copied";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      item.title = @"Copy";
    });
}

- (void)showCopied:(BOOL)copied {
    _copied = copied;
    NSArray<PFBReportRow*>* rows = _sections.firstObject;
    for (NSUInteger i = 0; i < rows.count; i++) {
        PFBReportRow* row = rows[i];
        if (row.kind != PFBReportRowCopy) {
            continue;
        }
        row.title = copied ? @"Copied" : @"Copy report";
        row.iconName = copied ? @"checkmark" : @"doc.on.doc";
        [self.tableView reconfigureRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:(NSInteger)i inSection:0] ]];
    }
}

@end
