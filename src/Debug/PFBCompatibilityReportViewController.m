// The Compatibility report screen, drawn like the settings pages: Chirp fonts and the
// app's palette. Row marks tell a verdict or, under Check, what the row reports.
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Support/TwitterChirpFont.h"
#import "Support/TWHeaders.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import <objc/runtime.h>
#import "Debug/PFBTourChoicePopover.h"

static id PFBCompatFontGroup(void) {
    return [PFBManager sharedFontGroup];
}

static UIFont* PFBCompatTitleFont(void) {
    return [PFBCompatFontGroup() performSelector:@selector(bodyBoldFont)];
}

static UIFont* PFBCompatDetailFont(void) {
    return [PFBCompatFontGroup() performSelector:@selector(subtext2Font)];
}

// The palette's secondary text color, as the settings rows use it.
static UIColor* PFBCompatSecondaryColor(void) {
    Class settingsClass = objc_getClass("TAEColorSettings");
    id palette = [[[settingsClass sharedSettings] currentColorPalette] colorPalette];
    UIColor* color = [palette performSelector:@selector(tabBarItemColor)];
    return color ?: [UIColor secondaryLabelColor];
}

// An orange dark enough to read on a light page; the system orange on a dark one.
static UIColor* PFBCompatWarningTextColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                   ? [UIColor systemOrangeColor]
                   : [UIColor colorWithRed:0.60 green:0.30 blue:0.0 alpha:1.0];
    }];
}

// One size for every row's symbol, so the summary row lines up with the options.
static UIImage* PFBRowSymbol(NSString* name) {
    UIImageSymbolConfiguration* config =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightRegular];
    return [UIImage systemImageNamed:name withConfiguration:config];
}

static UIImage* PFBVerdictImage(PFBCompatVerdict verdict) {
    NSString* name = @"checkmark.circle";
    if (verdict == PFBCompatVerdictBroken) {
        name = @"xmark.circle";
    } else if (verdict == PFBCompatVerdictNotTested) {
        name = @"minus.circle";
    }
    return PFBRowSymbol(name);
}

// "5 screens" still owing proofs on this build, or that none is left.
static NSString* PFBCompatScreensLeftText(void) {
    NSUInteger screens = PFBCompatTourScreens(NO);
    return screens ? [NSString stringWithFormat:@"%lu screen%@", (unsigned long)screens, screens == 1 ? @"" : @"s"]
                   : @"All proven";
}

static UIColor* PFBVerdictColor(PFBCompatVerdict verdict) {
    if (verdict == PFBCompatVerdictBroken) {
        return [UIColor systemRedColor];
    }
    return verdict == PFBCompatVerdictNotTested ? [UIColor systemOrangeColor] : [UIColor systemGreenColor];
}

// Whether the options without problems, and those not tested, are listed; both are
// folded on a fresh install.
static NSString* const kPFBCompatListOpenKey = @"pfb_compat_list_open";
static NSString* const kPFBCompatUntestedOpenKey = @"pfb_compat_untested_open";

@implementation PFBCompatibilityReportViewController {
    NSMutableArray<NSString*>* _sections;
    NSMutableArray<NSMutableArray<PFBCompatResult*>*>* _rows;
    NSInteger _okLabelSection;
    NSInteger _untestedSection;
    NSInteger _checkSection;
    BOOL _listOpen;
    BOOL _untestedOpen;
    NSString* _summaryText;
    NSString* _untestedText;
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
    self.title = @"Report";
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderTopPadding = 0.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    UIBarButtonItem* copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(copyReport)];
    copy.tag = PFBNativeGlassTag;
    UIBarButtonItem* tours = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checklist"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(showTourChoice:)];
    tours.accessibilityLabel = @"Check paths";
    tours.tag = PFBNativeGlassTag;
    self.navigationItem.rightBarButtonItems = @[ copy, tours ];
    _listOpen = [[NSUserDefaults standardUserDefaults] boolForKey:kPFBCompatListOpenKey];
    _untestedOpen = [[NSUserDefaults standardUserDefaults] boolForKey:kPFBCompatUntestedOpenKey];
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
    // Opened as a sheet, the report closes with a check, as in the other Prime tweaks.
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

// The page underneath shows the status on its Report row; it redraws on return.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    PFBDebuggerSetTriggerHidden(NO);
    PFBCompatRefreshStatus();
    NSArray* stack = self.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObject:self];
    UIViewController* below = (index != NSNotFound && index > 0) ? stack[index - 1] : stack.lastObject;
    if ([below isKindOfClass:[PFBModernSettingsPageViewController class]]) {
        [((PFBModernSettingsPageViewController*)below).tableView reloadData];
    }
}

- (void)rebuild {
    _sections = [NSMutableArray array];
    _rows = [NSMutableArray array];
    _untestedSection = -1;
    NSArray<PFBCompatResult*>* results = PFBCompatResults();
    NSMutableArray<PFBCompatResult*>* broken = [NSMutableArray array];
    NSMutableArray<PFBCompatResult*>* notTested = [NSMutableArray array];
    NSUInteger okOptions = 0;
    for (PFBCompatResult* result in results) {
        if (result.verdict == PFBCompatVerdictBroken) {
            [broken addObject:result];
        } else if (result.verdict == PFBCompatVerdictNotTested) {
            [notTested addObject:result];
        } else if (!result.internal) {
            okOptions++;
        }
    }
    if (broken.count > 0) {
        [_sections addObject:@"Broken"];
        [_rows addObject:broken];
    }
    if (notTested.count > 0) {
        _untestedSection = (NSInteger)_sections.count;
        _untestedText = [NSString stringWithFormat:@"%lu option%@ not tested", (unsigned long)notTested.count,
                                                   notTested.count == 1 ? @"" : @"s"];
        [_sections addObject:@"Not tested"];
        [_rows addObject:_untestedOpen ? notTested : [NSMutableArray array]];
    }
    // The problems lead; every other option follows under its settings section.
    BOOL issues = broken.count + notTested.count > 0;
    _okLabelSection = (NSInteger)_sections.count;
    PFBCompatReadState state = PFBCompatReadStatus();
    NSString* tail = state == PFBCompatReadPending ? @" so far" : (state == PFBCompatReadFailed ? @" on the other checks" : @"");
    _summaryText = [NSString stringWithFormat:@"%lu %@option%@ OK%@", (unsigned long)okOptions,
                                               issues ? @"other " : @"", okOptions == 1 ? @"" : @"s", tail];
    [_sections addObject:@"Working"];
    [_rows addObject:[NSMutableArray array]];
    // The list stays folded until opened; the choice is kept.
    for (PFBCompatResult* result in _listOpen ? results : @[]) {
        if (result.verdict != PFBCompatVerdictOK) {
            continue;
        }
        if ((NSInteger)_sections.count - 1 == _okLabelSection ||
            ![_sections.lastObject isEqualToString:result.section]) {
            [_sections addObject:result.section];
            [_rows addObject:[NSMutableArray array]];
        }
        [_rows.lastObject addObject:result];
    }
    // The last tour and what is left, for reading; the tours start from the menu.
    _checkSection = (NSInteger)_sections.count;
    [_sections addObject:@"Check"];
    [_rows addObject:[NSMutableArray array]];
    [_sections addObject:@"History"];
    [_rows addObject:[NSMutableArray array]];
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
        tone = PFBCompatSecondaryColor();
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
    subline.text = [NSString stringWithFormat:@"iOS %@ \u00b7 %lu options", UIDevice.currentDevice.systemVersion,
                                              (unsigned long)optionCount];
    subline.font = PFBCompatDetailFont();
    subline.textColor = PFBCompatSecondaryColor();
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
        status.font = PFBCompatDetailFont();
        if (state == PFBCompatReadPending) {
            UIActivityIndicatorView* small =
                [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            small.transform = CGAffineTransformMakeScale(0.7, 0.7);
            [small startAnimating];
            icon = small;
            status.text = @"Checking Twitter\u2019s settings\u2026";
            status.textColor = PFBCompatSecondaryColor();
        } else {
            UIImageView* warning =
                [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.circle.fill"]];
            warning.tintColor = [UIColor systemOrangeColor];
            warning.contentMode = UIViewContentModeScaleAspectFit;
            icon = warning;
            status.text = @"Twitter\u2019s settings could not be read";
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
    return _sections.count;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == _checkSection) {
        return 2;  // Last tour, Remaining
    }
    if (section == _okLabelSection) {
        return 1;
    }
    if (section == _untestedSection) {
        return 1 + (NSInteger)_rows[section].count;
    }
    if (section == (NSInteger)_sections.count - 1) {
        return 1;  // History: Start over
    }
    return _rows[section].count;
}

// Section titles drawn like the settings pages' headers: Chirp bold, 20 pt.
- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* container = [[UIView alloc] init];
    container.backgroundColor = [PFBPalette currentBackgroundColor];
    UILabel* label = [[UILabel alloc] init];
    label.text = _sections[section];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20]);
    label.textColor = [UIColor labelColor];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6.0],
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return 52.0;
}

// The same gap under every section, so each title sits as far from the rows above.
- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    return 12.0;
}

- (UIView*)tableView:(UITableView*)tableView viewForFooterInSection:(NSInteger)section {
    UIView* spacer = [[UIView alloc] init];
    spacer.backgroundColor = [PFBPalette currentBackgroundColor];
    return spacer;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == _checkSection) {
        BOOL last = indexPath.row == 0;
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                       reuseIdentifier:@"check"];
        cell.backgroundColor = [PFBPalette currentBackgroundColor];
        cell.textLabel.text = last ? @"Last tour" : @"Remaining";
        cell.textLabel.font = PFBCompatTitleFont();
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.text = last ? (PFBCompatTourLastRun() ?: @"No tour on this build yet")
                                         : PFBCompatScreensLeftText();
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.font = PFBCompatDetailFont();
        cell.detailTextLabel.textColor = PFBCompatSecondaryColor();
        cell.imageView.image = PFBRowSymbol(last ? @"clock" : @"scope");
        cell.imageView.tintColor = PFBCompatSecondaryColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (indexPath.section == (NSInteger)_sections.count - 1) {
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                       reuseIdentifier:@"action"];
        cell.backgroundColor = [PFBPalette currentBackgroundColor];
        cell.textLabel.text = @"Start over";
        cell.textLabel.font = PFBCompatTitleFont();
        cell.textLabel.textColor = [UIColor systemRedColor];
        return cell;
    }
    if (indexPath.section == _okLabelSection) {
        return [self summaryCellWithText:_summaryText
                                  symbol:@"checkmark.circle.fill"
                                    tint:[UIColor systemGreenColor]
                                    open:_listOpen];
    }
    if (indexPath.section == _untestedSection && indexPath.row == 0) {
        return [self summaryCellWithText:_untestedText
                                  symbol:@"minus.circle.fill"
                                    tint:[UIColor systemOrangeColor]
                                    open:_untestedOpen];
    }
    NSInteger row = indexPath.section == _untestedSection ? indexPath.row - 1 : indexPath.row;
    PFBCompatResult* result = _rows[indexPath.section][row];
    BOOL issue = result.verdict != PFBCompatVerdictOK;
    // A problem carries its reason under the name; the rest show On or Off on the right.
    UITableViewCell* cell =
        [[UITableViewCell alloc] initWithStyle:(issue ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1)
                               reuseIdentifier:(issue ? @"issue" : @"row")];
    cell.backgroundColor = [PFBPalette currentBackgroundColor];
    cell.textLabel.text = (issue && !result.internal && !result.enabled)
                              ? [result.title stringByAppendingString:@" \u00b7 Off"]
                              : result.title;
    cell.textLabel.font = PFBCompatTitleFont();
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = (issue || result.internal) ? result.detail : (result.enabled ? (result.alwaysOn ? @"Always on" : @"On") : @"Off");
    cell.detailTextLabel.numberOfLines = issue ? 0 : 1;
    cell.detailTextLabel.font = PFBCompatDetailFont();
    cell.detailTextLabel.textColor = PFBCompatSecondaryColor();
    cell.imageView.image = PFBVerdictImage(result.verdict);
    cell.imageView.tintColor = PFBVerdictColor(result.verdict);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// A summary row: the options' verdict mark, their count, and a chevron that folds them.
- (UITableViewCell*)summaryCellWithText:(NSString*)text symbol:(NSString*)symbol tint:(UIColor*)tint open:(BOOL)open {
    // Same symbol size, column and title font as the option rows below it.
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                   reuseIdentifier:@"summary"];
    cell.backgroundColor = [PFBPalette currentBackgroundColor];
    cell.textLabel.text = text;
    cell.textLabel.font = PFBCompatTitleFont();
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.image = PFBRowSymbol(symbol);
    cell.imageView.tintColor = tint;
    UIImageSymbolConfiguration* chevronSize =
        [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];
    UIImageView* chevron =
        [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:(open ? @"chevron.down" : @"chevron.right")
                                                   withConfiguration:chevronSize]];
    chevron.tintColor = [UIColor tertiaryLabelColor];
    cell.accessoryView = chevron;
    cell.accessibilityTraits |= UIAccessibilityTraitButton;
    cell.accessibilityValue = open ? @"Expanded" : @"Collapsed";
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL untestedSummary = indexPath.section == _untestedSection && indexPath.row == 0;
    if (indexPath.section == _okLabelSection || untestedSummary) {
        if (untestedSummary) {
            _untestedOpen = !_untestedOpen;
            [[NSUserDefaults standardUserDefaults] setBool:_untestedOpen forKey:kPFBCompatUntestedOpenKey];
        } else {
            _listOpen = !_listOpen;
            [[NSUserDefaults standardUserDefaults] setBool:_listOpen forKey:kPFBCompatListOpenKey];
        }
        [self rebuild];
        [UIView transitionWithView:tableView
                          duration:0.2
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
                            [tableView reloadData];
                        }
                        completion:nil];
        return;
    }
    if (indexPath.section == (NSInteger)_sections.count - 1) {
        [self confirmStartOver];
    }
}

- (void)confirmStartOver {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:@"Start over"
                         message:@"Clears everything counted and closes Twitter. Reopen it and every path is "
                                 @"checked on its own, then this report opens. Your settings are kept."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Start over"
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

// MARK: - Notice
