// A settings page: builds its rows from PFBSettings and handles their actions.

#import "Settings/PFBModernSettingsPageViewController.h"
#import "Common/PFBBundle.h"
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Settings/PFBModernSettingsCells.h"
#import "Features/Timelines/PFBMutedWordsViewController.h"
#import "Common/PFBSettingsBackup.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Support/FLEXHeaders.h"

@interface PFBModernSettingsPageViewController ()
@property (nonatomic, copy) NSString* registryPageKey;
@end

// Reads an object property only when the method really returns an object.
static id PFBAskObject(id target, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    const char* type = [target methodSignatureForSelector:selector].methodReturnType;
    if (!type || strcmp(type, "@") != 0) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

// The account's profile photo, from the app's own user model. The 200 px variant
// keeps the 40 pt circle sharp.
static NSURL* PFBAccountAvatarURL(TFNTwitterAccount* account) {
    id entity = PFBAskObject(PFBAskObject(account, @"user"), @"profileImageMediaEntity");
    id address = PFBAskObject(entity, @"imageURLString") ?: PFBAskObject(entity, @"mediaURL");
    NSString* string = [address isKindOfClass:[NSURL class]] ? [address absoluteString]
                     : ([address isKindOfClass:[NSString class]] ? address : nil);
    if (!string.length) {
        static BOOL said;
        if (!said) {
            said = YES;
            PFBDebugLog(@"[session] avatar: the account carries no photo address");
        }
        return nil;
    }
    string = [string stringByReplacingOccurrencesOfString:@"_normal." withString:@"_200x200."];
    return [NSURL URLWithString:string];
}

@implementation PFBModernSettingsPageViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBThemeScreenEnter(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
}

#pragma mark - Lifecycle

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    return [self initWithAccount:account pageKey:nil];
}

- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey {
    if ((self = [super init])) {
        self.account = account;
        self.registryPageKey = pageKey;
        [self buildSettingsList];
        [self updateVisibleToggles];
    }
    return self;
}

// The Compatibility row shows a status that the checks update after launch.
- (void)pfbCompatDidChange:(NSNotification*)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

// While Twitter's binaries are read, the Report row's status leads with a spinner.
- (void)pfbShowCompatSpinner:(BOOL)show inCell:(PFBModernSettingsTableViewCell*)cell subtitle:(NSString*)subtitle {
    static const NSInteger kSpinnerTag = 90314;
    [[cell.contentView viewWithTag:kSpinnerTag] removeFromSuperview];
    if (!show || !cell.subtitleLabel || subtitle.length == 0) {
        return;
    }
    UIFont* font = cell.subtitleLabel.font ?: [UIFont systemFontOfSize:13.0];
    UIActivityIndicatorView* spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.tag = kSpinnerTag;
    spinner.transform = CGAffineTransformMakeScale(0.7, 0.7);
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:cell.subtitleLabel.leadingAnchor constant:7.0],
        [spinner.centerYAnchor constraintEqualToAnchor:cell.subtitleLabel.topAnchor constant:font.lineHeight / 2.0],
    ]];
    [spinner startAnimating];
    NSMutableParagraphStyle* indent = [[NSMutableParagraphStyle alloc] init];
    indent.firstLineHeadIndent = 20.0;
    cell.subtitleLabel.attributedText = [[NSAttributedString alloc]
        initWithString:subtitle
            attributes:@{
                NSParagraphStyleAttributeName : indent,
                NSFontAttributeName : font,
                NSForegroundColorAttributeName : cell.subtitleLabel.textColor ?: [UIColor secondaryLabelColor],
            }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pfbCompatDidChange:)
                                                 name:PFBCompatDidChangeNotification
                                               object:nil];
    [self setupNav];
    [self setupTable];
}

#pragma mark - Page Registry

- (NSString*)pageKey {
    return self.registryPageKey;
}

- (NSString*)pageTitleKey {
    return [PFBSettings titleKeyForPage:[self pageKey]];
}

- (NSString*)pageSubtitleKey {
    return [PFBSettings subtitleKeyForPage:[self pageKey]];
}

- (void)buildSettingsList {
    self.toggles = [PFBSettings settingsForPage:[self pageKey]];
}

#pragma mark - Setup

- (void)setupNav {
    NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:[self pageTitleKey]];
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[PFBModernSettingsToggleCell class]
           forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[PFBModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[PFBModernSettingsCompactButtonCell class]
           forCellReuseIdentifier:@"CompactButtonCell"];
    [self.tableView registerClass:[PFBModernSettingsTabBarCell class]
           forCellReuseIdentifier:@"TabBarCell"];
    [self.tableView registerClass:[PFBModernSettingsSessionCardCell class]
           forCellReuseIdentifier:@"SessionCardCell"];
    [self.tableView registerClass:[PFBModernSettingsButtonPairCell class]
           forCellReuseIdentifier:@"ButtonPairCell"];
    [self.tableView registerClass:[PFBModernSettingsHeaderCell class]
           forCellReuseIdentifier:@"HeaderCell"];
    [self.view addSubview:self.tableView];
}

#pragma mark - Visible Toggles

- (void)updateVisibleToggles {
    NSMutableArray* visible = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        // Two relations, opposite directions: a row appears while its parent is
        // on, and disappears while its blocker is on.
        NSString* parentKey = toggleData[@"parentKey"];
        NSString* hiddenWhen = toggleData[@"hiddenWhen"];
        BOOL show = YES;
        if (parentKey) {
            // The parent's own state, declared default included. Reading the
            // CHILD's default here would decide a parent's state from a row that
            // is not the parent.
            show = [PFBSettings boolForKey:parentKey];
        }
        if (show && hiddenWhen && [PFBSettings boolForKey:hiddenWhen]) {
            show = NO;
        }
        if (show) {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleToggles.count;
}

// Title key defaults to KEY_TITLE; an explicit titleKey takes precedence.
- (NSString*)localizedTitleForEntry:(NSDictionary*)entry {
    NSString* titleKey = entry[@"titleKey"];
    if (!titleKey) {
        titleKey = [NSString stringWithFormat:@"%@_TITLE", [entry[@"key"] uppercaseString]];
    }
    return [[PFBBundle sharedBundle] localizedStringForKey:titleKey];
}

// The bundle returns the key itself when no string exists, which counts as no detail.
- (NSString*)localizedDetailForKey:(NSString*)key {
    NSString* detailKey = [NSString stringWithFormat:@"%@_DETAIL", [key uppercaseString]];
    NSString* detail = [[PFBBundle sharedBundle] localizedStringForKey:detailKey];
    return [detail isEqualToString:detailKey] ? @"" : detail;
}

// Localized at render time; the registry can't call localizedStringForKey
// without re-entering the settings lookup.
- (NSString*)defaultSubtitleForEntry:(NSDictionary*)entry {
    NSString* subtitleDefaultKey = entry[@"subtitleDefaultKey"];
    if (subtitleDefaultKey) {
        return [[PFBBundle sharedBundle] localizedStringForKey:subtitleDefaultKey];
    }
    return entry[@"subtitleDefault"];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* toggleData = self.visibleToggles[indexPath.row];
    NSString* type = toggleData[@"type"];
    if ([type isEqualToString:@"header"]) {
        PFBModernSettingsHeaderCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"HeaderCell"
                                            forIndexPath:indexPath];
        [cell configureWithTitle:[[PFBBundle sharedBundle]
                                     localizedStringForKey:toggleData[@"titleKey"]]];
        return cell;
    }
    if ([type isEqualToString:@"sessionCard"]) {
        PFBModernSettingsSessionCardCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"SessionCardCell"
                                            forIndexPath:indexPath];
        PFBBundle* bundle = [PFBBundle sharedBundle];
        // The session check is not tied to an account: whenever a usable web
        // session exists, the card names this page's account.
        BOOL signedIn = PFBHasUsableWebCredentials();
        NSString* handle = self.account.displayUsername;
        [cell configureWithHandle:(signedIn && handle.length)
                                      ? handle
                                      : [bundle localizedStringForKey:@"WEB_SESSION_NONE_TITLE"]
                         signedIn:signedIn
                           detail:[bundle localizedStringForKey:
                                              signedIn ? @"WEB_SESSION_LIVE_DETAIL"
                                                       : @"WEB_SESSION_NONE_DETAIL"]
                     primaryTitle:[bundle localizedStringForKey:@"WEB_SESSION_SIGN_IN_ACTION"]
                 destructiveTitle:[bundle localizedStringForKey:@"WEB_SESSION_CLEAR_ACTION"]];
        [cell loadAvatarFromURL:PFBAccountAvatarURL(self.account)];
        [cell addPrimaryTarget:self action:@selector(sessionSignInTapped:)];
        [cell addDestructiveTarget:self action:@selector(sessionClearTapped:)];
        return cell;
    }
    if ([type isEqualToString:@"buttonPair"]) {
        PFBModernSettingsButtonPairCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"ButtonPairCell"
                                            forIndexPath:indexPath];
        PFBBundle* bundle = [PFBBundle sharedBundle];
        [cell configureWithFirst:[bundle localizedStringForKey:toggleData[@"firstKey"]]
                          second:[bundle localizedStringForKey:toggleData[@"secondKey"]]];
        // Set on every pass: cells are recycled.
        [cell setSecondDestructive:[toggleData[@"secondDestructive"] boolValue]];
        [cell addFirstTarget:self action:NSSelectorFromString(toggleData[@"firstAction"])];
        [cell addSecondTarget:self action:NSSelectorFromString(toggleData[@"secondAction"])];
        return cell;
    }
    if ([type isEqualToString:@"tabBar"]) {
        PFBModernSettingsTabBarCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"TabBarCell"
                                            forIndexPath:indexPath];
        NSArray* tabs = [self tabsForEntry:toggleData];
        [cell configureWithTabs:tabs
                        caption:[[PFBBundle sharedBundle]
                                    localizedStringForKey:toggleData[@"captionKey"]]
                           hint:[[PFBBundle sharedBundle]
                                    localizedStringForKey:toggleData[@"hintKey"]]];
        [cell setCountText:[self hiddenCountTextForTabs:tabs]];
        [cell addTabTarget:self action:@selector(tabTapped:)];
        return cell;
    }
    if ([type isEqualToString:@"compactButton"]) {
        PFBModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
        }
        [cell configureWithTitle:title subtitle:subtitle];
        [self attachMenuIfNeeded:cell entry:toggleData];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        PFBModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell"
                                                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
        }
        NSString* subtitleKey = toggleData[@"subtitleKey"];
        if (subtitleKey) {
            subtitle = [[PFBBundle sharedBundle] localizedStringForKey:subtitleKey];
        }
        [cell configureWithTitle:title subtitle:subtitle iconName:nil];
        [self pfbShowCompatSpinner:[prefKey isEqualToString:PFBCompatStatusKey] &&
                                   PFBCompatReadStatus() == PFBCompatReadPending
                            inCell:cell
                          subtitle:subtitle];
        // No action means nowhere to go: the row states something and the
        // chevron would say otherwise.
        BOOL leadsSomewhere = toggleData[@"action"] != nil;
        // A destructive row acts in place rather than opening a page, so it reads
        // in red with no chevron. Set on every pass: cells are recycled.
        BOOL destructive = [toggleData[@"destructive"] boolValue];
        cell.titleLabel.textColor = destructive ? [UIColor systemRedColor] : [UIColor labelColor];
        [cell setShowsChevron:leadsSomewhere && !destructive];
        cell.selectionStyle = leadsSomewhere ? UITableViewCellSelectionStyleDefault
                                             : UITableViewCellSelectionStyleNone;
        [self attachMenuIfNeeded:cell entry:toggleData];
        return cell;
    } else {
        PFBModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell"
                                                                         forIndexPath:indexPath];
        NSString* key = toggleData[@"key"];
        NSString* title = [self localizedTitleForEntry:toggleData];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key]
                              ?: toggleData[@"default"] boolValue];
        // A row is held while another option is on, or while it waits; one that waits
        // still turns off, so it never stays on out of reach.
        BOOL waiting = [self rowIsWaiting:toggleData];
        NSString* blocker = toggleData[@"disabledWhen"];
        BOOL overridden = blocker && [PFBSettings boolForKey:blocker];
        // While the row is held, its detail says why instead, when it has that text.
        NSString* heldKey = [NSString stringWithFormat:@"%@_DETAIL_HELD", key.uppercaseString];
        NSString* held = [[PFBBundle sharedBundle] localizedStringForKey:heldKey];
        NSString* subtitle = (waiting || overridden) && ![held isEqualToString:heldKey]
                                 ? held
                                 : [self localizedDetailForKey:key];
        [cell configureWithTitle:title subtitle:subtitle];
        BOOL rowEnabled = !overridden && !(waiting && !isEnabled);
        [cell setRowEnabled:rowEnabled];
        // An option stored as a negative reads and writes flipped, so every
        // screen can name it the way it behaves.
        BOOL inverted = [toggleData[@"inverted"] boolValue];
        cell.toggleSwitch.on = inverted ? !isEnabled : isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell.toggleSwitch, @"inverted", @(inverted),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self
                      action:@selector(switchChanged:)
            forControlEvents:UIControlEventValueChanged];
        // A pill carries a second setting on the same row. It belongs to the
        // row's own switch, so it is only on screen while that switch is on.
        NSString* pillKey = toggleData[@"pillKey"];
        if (pillKey) {
            [cell setPillTitle:[self pillTitleForKey:pillKey]];
            objc_setAssociatedObject(cell.pillButton, @"pillKey", pillKey,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [cell addPillTarget:self action:@selector(pillTapped:)];
            [cell setPillVisible:(cell.toggleSwitch.on && rowEnabled) animated:NO];
        } else {
            [cell setPillVisible:NO animated:NO];
        }
        return cell;
    }
}

#pragma mark - UITableViewDelegate

// A row with nothing to open should not light up under the finger either. The
// table is asked rather than the cell, so this also covers keyboard focus and
// VoiceOver, which read highlightability rather than the chevron.
- (BOOL)tableView:(UITableView*)tableView
    shouldHighlightRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.row >= (NSInteger)self.visibleToggles.count) {
        return YES;
    }
    NSDictionary* data = self.visibleToggles[indexPath.row];
    NSString* type = data[@"type"];
    if (([type isEqualToString:@"button"] ||
         [type isEqualToString:@"compactButton"]) &&
        data[@"action"] == nil) {
        return NO;
    }
    return YES;
}

- (void)attachMenuIfNeeded:(UITableViewCell*)cell entry:(NSDictionary*)entry {
    static const NSInteger kMenuButtonTag = 0x4D454E55;
    UIButton* button = [cell.contentView viewWithTag:kMenuButtonTag];
    NSString* provider = entry[@"menu"];
    SEL selector = provider ? NSSelectorFromString(provider) : NULL;
    if (!selector || ![self respondsToSelector:selector]) {
        [button removeFromSuperview];
        return;
    }
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = kMenuButtonTag;
        button.showsMenuAsPrimaryAction = YES;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        ]];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    button.menu = [self performSelector:selector];
#pragma clang diagnostic pop
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* data = self.visibleToggles[indexPath.row];
    if ([data[@"type"] isEqualToString:@"button"] ||
        [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString* actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
                // Pass the row's indexPath so value-editing actions can reload
                // their own row afterwards (e.g. the sharing domain prompt).
                NSMutableDictionary* payload = [data mutableCopy];
                payload[@"indexPath"] = indexPath;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action
                           withObject:payload];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [[PFBBundle sharedBundle] localizedStringForKey:[self pageSubtitleKey]];
    label.numberOfLines = 0;
    id fontGroup = [PFBManager sharedFontGroup];
    label.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    label.textColor = subtitleColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                            constant:10],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                             constant:-10],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor
                                        constant:8],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor
                                           constant:-8]
    ]];
    return header;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

#pragma mark - Switch Handling

// A row another option holds must redraw the moment that option moves,
// otherwise it stays enabled until the page is left.
// A row waiting on something the app knows at run time rather than on a stored option;
// the conditions are named, so the registry stays declarative.
- (BOOL)rowIsWaiting:(NSDictionary*)entry {
    NSString* requires = entry[@"blockedUnless"];
    return requires && !([requires isEqualToString:@"web_session"] ? PFBHasUsableWebCredentials()
                                                                   : [PFBSettings boolForKey:requires]);
}

- (void)reloadRowsHeldBy:(NSString*)key {
    NSMutableArray<NSIndexPath*>* paths = [NSMutableArray array];
    [self.visibleToggles enumerateObjectsUsingBlock:^(NSDictionary* entry,
                                                      NSUInteger row, BOOL* stop) {
        if ([entry[@"disabledWhen"] isEqualToString:key]) {
            [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
        }
    }];
    if (paths.count) {
        [self.tableView reloadRowsAtIndexPaths:paths
                              withRowAnimation:UITableViewRowAnimationFade];
    }
}

// The tabs of the Explore bar, in the order the app shows them. Each carries
// the preference key that hides it.
- (NSArray<NSDictionary*>*)tabsForEntry:(NSDictionary*)entry {
    NSMutableArray* out = [NSMutableArray array];
    for (NSString* key in entry[@"tabKeys"]) {
        NSString* nameKey =
            [NSString stringWithFormat:@"%@_TAB_NAME", key.uppercaseString];
        [out addObject:@{
            @"key" : key,
            @"name" : [[PFBBundle sharedBundle] localizedStringForKey:nameKey]
        }];
    }
    return out;
}

- (NSString*)hiddenCountTextForTabs:(NSArray<NSDictionary*>*)tabs {
    NSUInteger hidden = 0;
    for (NSDictionary* tab in tabs) {
        if ([PFBSettings boolForKey:tab[@"key"]]) {
            hidden++;
        }
    }
    if (hidden == 0) {
        return [[PFBBundle sharedBundle] localizedStringForKey:@"EXPLORE_TABS_NONE_HIDDEN"];
    }
    return [NSString
        stringWithFormat:[[PFBBundle sharedBundle]
                             localizedStringForKey:@"EXPLORE_TABS_HIDDEN_COUNT"],
                         (unsigned long)hidden];
}

// The card acts on the session and then redraws: the rows that depend on it
// have no other way to learn that it changed.
- (void)sessionSignInTapped:(UIButton*)sender {
    PFBPresentWebSessionLogin(^(__unused BOOL success) {
      [self updateVisibleToggles];
      [self.tableView reloadData];
    });
}

- (void)sessionClearTapped:(UIButton*)sender {
    [self PFBClearWebSession:nil];
}

- (void)tabTapped:(UIButton*)sender {
    NSString* key = objc_getAssociatedObject(sender, @"tabKey");
    if (!key) {
        return;
    }
    UIView* walk = sender;
    while (walk && ![walk isKindOfClass:[PFBModernSettingsTabBarCell class]]) {
        walk = walk.superview;
    }
    PFBModernSettingsTabBarCell* host = (PFBModernSettingsTabBarCell*)walk;
    NSIndexPath* hostPath = host ? [self.tableView indexPathForCell:host] : nil;
    NSArray* allTabs = hostPath ? [self tabsForEntry:self.visibleToggles[hostPath.row]] : nil;

    // Striking the last tab left would leave a bar with nothing in it, and a
    // pager with nothing to show. Hiding all of Explore is a switch of its own,
    // so the refusal points at it instead of silently doing it.
    if (!([PFBSettings boolForKey:key])) {
        NSUInteger kept = 0;
        for (NSDictionary* tab in allTabs) {
            if (![PFBSettings boolForKey:tab[@"key"]]) {
                kept++;
            }
        }
        if (kept <= 1) {
            [host refuseTab:sender
                withMessage:[[PFBBundle sharedBundle]
                                localizedStringForKey:@"EXPLORE_TABS_KEEP_ONE"]];
            return;
        }
    }

    [[NSUserDefaults standardUserDefaults] setBool:![PFBSettings boolForKey:key]
                                            forKey:key];
    // Repainting the live cell keeps the strike-through immediate; reloading the
    // row would flash the whole bar for one tap.
    [host refreshTabs];
    if (allTabs) {
        [host setCountText:[self hiddenCountTextForTabs:allTabs]];
    }
}

// The pill reads out its own state, so neither position has to be guessed.
- (NSString*)pillTitleForKey:(NSString*)key {
    NSString* suffix = [PFBSettings boolForKey:key] ? @"_PILL_ON" : @"_PILL_OFF";
    return [[PFBBundle sharedBundle]
        localizedStringForKey:[NSString stringWithFormat:@"%@%@",
                                                         key.uppercaseString,
                                                         suffix]];
}

- (void)pillTapped:(UIButton*)sender {
    NSString* key = objc_getAssociatedObject(sender, @"pillKey");
    if (!key) {
        return;
    }
    BOOL next = ![PFBSettings boolForKey:key];
    [[NSUserDefaults standardUserDefaults] setBool:next forKey:key];
    [sender setTitle:[self pillTitleForKey:key] forState:UIControlStateNormal];
}

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        BOOL inverted = [objc_getAssociatedObject(sender, @"inverted") boolValue];
        [[NSUserDefaults standardUserDefaults]
            setBool:(inverted ? !sender.isOn : sender.isOn)
             forKey:key];
        [self updateAndAnimateChangesForKey:key];

        [self reloadRowsHeldBy:key];

        // A row carrying a pill keeps its cell: reloading it would cut the fade
        // short, so the pill is moved on the live cell instead.
        UIView* walk = sender;
        while (walk && ![walk isKindOfClass:[PFBModernSettingsToggleCell class]]) {
            walk = walk.superview;
        }
        PFBModernSettingsToggleCell* liveCell = (PFBModernSettingsToggleCell*)walk;
        if (liveCell &&
            objc_getAssociatedObject(liveCell.pillButton, @"pillKey")) {
            [liveCell setPillVisible:sender.isOn animated:YES];
        }
        // A waiting row just turned off cannot be turned back on yet.
        NSIndexPath* livePath = liveCell ? [self.tableView indexPathForCell:liveCell] : nil;
        if (!sender.isOn && livePath && (NSUInteger)livePath.row < self.visibleToggles.count &&
            [self rowIsWaiting:self.visibleToggles[(NSUInteger)livePath.row]]) {
            [liveCell setRowEnabled:NO];
        }

        // The switch-tint toggle changes how every OTHER visible switch is
        // drawn, so re-run applyTheme on the live cells right away.
        if ([key isEqualToString:@"color_pfb_switches"]) {
            SEL applyThemeSel = @selector(applyTheme);
            for (UITableViewCell* cell in self.tableView.visibleCells) {
                if ([cell respondsToSelector:applyThemeSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [cell performSelector:applyThemeSel];
#pragma clang diagnostic pop
                }
            }
        }

        // Reset raises a flag that keeps the accent inactive, so it reverts to
        // native. Switching a toggle back on states the same intent as picking a
        // color, so the flag is cleared here or nothing would be painted.
        if (sender.isOn &&
            ([key isEqualToString:@"tab_bar_theming"] ||
             [key isEqualToString:@"color_pfb_switches"] ||
             [key isEqualToString:@"color_twitter_icon_in_top_bar"])) {
            [[NSUserDefaults standardUserDefaults]
                removeObjectForKey:@"pfb_color_reset_done"];
        }

        // These toggles change which surfaces follow the accent, so push the
        // accent through again instead of waiting for those views to rebuild.
        if ([key isEqualToString:@"color_twitter_icon_in_top_bar"] ||
            [key isEqualToString:@"tab_bar_theming"]) {
            extern void PFBSyncAccentTheme(void);
            PFBSyncAccentTheme();
        }

        if ([key isEqualToString:@"restore_tweet_button"]) {
            [self showRestartRequiredAlert];
        }
        // Only on the way on: turning one of these off gives the app back its
        // own behavior, which needs no warning, and a modal on every flip makes
        // the section unusable to settle.
        if (sender.isOn && ([key isEqualToString:@"hide_explore_all"] ||
                            [key isEqualToString:@"choose_explore_tabs"] ||
                            [key isEqualToString:@"hide_tweet_button"])) {
            [self showRestartInfoAlert];
        }
    }
}

- (void)showAppIconViewController:(NSDictionary*)sender {
    Class AppIconViewControllerClass = objc_getClass("PFBAppIconViewController");
    if (AppIconViewControllerClass) {
        UIViewController* appIconVC = [[AppIconViewControllerClass alloc] init];
        if (self.account) {
            [appIconVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[PFBBundle sharedBundle]
                                                        localizedTwitterStringForKey:
                                                            @"SUBSCRIPTION_APP_ICON_SETTINGS_TITLE"]
                                           subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:appIconVC animated:YES];
    }
}

// MARK: - Muted words

// Pushes the muted-words editor; the list itself lives in NSUserDefaults.
- (void)showMutedWords:(NSDictionary*)sender {
    PFBMutedWordsViewController* editor = [[PFBMutedWordsViewController alloc] init];
    [self.navigationController pushViewController:editor animated:YES];
}

// MARK: - Settings backup

- (void)showExportSettings:(NSDictionary*)sender {
    NSData* data = [PFBSettingsBackup exportData];
    if (!data) {
        return;
    }
    NSString* path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"PrimeFreeBird-settings.json"];
    NSURL* url = [NSURL fileURLWithPath:path];
    if (![data writeToURL:url atomically:YES]) {
        return;
    }
    UIActivityViewController* share =
        [[UIActivityViewController alloc] initWithActivityItems:@[ url ]
                                          applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(self.view.bounds),
                   CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

- (void)showImportSettings:(NSDictionary*)sender {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[ @"public.json", @"public.plain-text" ]
                       inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSURL* url = urls.firstObject;
    if (!url) {
        return;
    }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData* data = [NSData dataWithContentsOfURL:url];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    NSInteger applied = [PFBSettingsBackup importData:data];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title;
    NSString* message;
    if (applied < 0) {
        title = [bundle localizedStringForKey:@"IMPORT_SETTINGS_FAILED_TITLE"];
        message = [bundle localizedStringForKey:@"IMPORT_SETTINGS_FAILED_MESSAGE"];
    } else {
        title = [bundle localizedStringForKey:@"IMPORT_SETTINGS_DONE_TITLE"];
        message = [NSString
            stringWithFormat:
                [bundle localizedStringForKey:@"IMPORT_SETTINGS_DONE_MESSAGE"],
                (unsigned long)applied];
        // The same pair Theme.x listens to after a live color change, so the
        // restored accent repaints without waiting for the restart.
        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
        [center postNotificationName:@"TFNDynamicColorsWillReloadNotification"
                              object:nil];
        [center postNotificationName:@"TFNDynamicColorsDidReloadNotification"
                              object:nil];
        [center postNotificationName:
                    @"TAEColorSettingsDidChangeUserDefaultsNotification"
                              object:nil];
        [self.tableView reloadData];
    }
    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert
        addAction:[UIAlertAction
                      actionWithTitle:[bundle localizedStringForKey:@"OK_ACTION"]
                                style:UIAlertActionStyleDefault
                              handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// MARK: - Web session

// Deletes the stored web session, behind a destructive confirmation.
- (void)PFBClearWebSession:(NSDictionary*)sender {
    __weak typeof(self) weakSelf = self;
    UIAlertController* confirm = [UIAlertController
        alertControllerWithTitle:[[PFBBundle sharedBundle]
                                     localizedStringForKey:@"WEB_SESSION_CLEAR_TITLE"]
                         message:[[PFBBundle sharedBundle]
                                     localizedStringForKey:@"WEB_SESSION_CLEAR_CONFIRM"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction
                           actionWithTitle:[[PFBBundle sharedBundle]
                                               localizedStringForKey:@"WEB_SESSION_CLEAR_ACTION"]
                                     style:UIAlertActionStyleDestructive
                                   handler:^(__unused UIAlertAction* action) {
                                       PFBClearWebSession();
                                       // The card and the rows gated on the
                                       // session have no other way to learn it
                                       // is gone. Sign-in already does this.
                                       [weakSelf updateVisibleToggles];
                                       [weakSelf.tableView reloadData];
                                   }]];
    [confirm addAction:[UIAlertAction
                           actionWithTitle:[[PFBBundle sharedBundle]
                                               localizedStringForKey:@"CANCEL_ACTION"]
                                     style:UIAlertActionStyleCancel
                                   handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

// Reduces user input like "https://fxtwitter.com/" to a bare host, so the
// value can be assigned straight to NSURLComponents.host when rewriting.
- (NSString*)sharingDomainFromInput:(NSString*)input {
    NSString* domain =
        [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSRange schemeRange = [domain rangeOfString:@"://"];
    if (schemeRange.location != NSNotFound) {
        domain = [domain substringFromIndex:NSMaxRange(schemeRange)];
    }

    NSRange pathRange = [domain rangeOfString:@"/"];
    if (pathRange.location != NSNotFound) {
        domain = [domain substringToIndex:pathRange.location];
    }

    return domain;
}

// Lives in the base class so the General page, which holds the link settings,
// can present it.
- (void)showSharingDomainPrompt:(NSDictionary*)data {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* currentHost = [defaults objectForKey:@"sharing_domain"];

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[[PFBBundle sharedBundle]
                                                        localizedStringForKey:@"SHARING_DOMAIN_TITLE"]
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
        textField.text = currentHost;
        textField.placeholder = @"x.com";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [alert addAction:[UIAlertAction
                         actionWithTitle:[[PFBBundle sharedBundle]
                                             localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [alert
        addAction:[UIAlertAction
                      actionWithTitle:[[PFBBundle sharedBundle]
                                          localizedTwitterStringForKey:@"SAVE_ACTION_LABEL"]
                                style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction* action) {
                                  NSString* domain =
                                      [self sharingDomainFromInput:alert.textFields.firstObject.text];

                                  if (domain.length > 0) {
                                      [defaults setObject:domain forKey:@"sharing_domain"];
                                  } else {
                                      [defaults removeObjectForKey:@"sharing_domain"];
                                  }
                                  [defaults synchronize];

                                  NSIndexPath* indexPath = data[@"indexPath"];
                                  if (indexPath) {
                                      [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                                            withRowAnimation:UITableViewRowAnimationNone];
                                  }
                              }]];

    [self presentViewController:alert animated:YES completion:nil];
}

// Informational only: tells the user a restart is needed for the change to
// fully apply. One OK button, dismisses the alert and nothing else — the app
// never closes itself here.
- (void)showRestartInfoAlert {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"RESTART_REQUIRED_ALERT_TITLE"]
                         message:[bundle localizedStringForKey:@"RESTART_INFO_ALERT_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                   style:UIAlertActionStyleDefault
                                 handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRestartRequiredAlert {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"RESTART_REQUIRED_ALERT_TITLE"]
                         message:[bundle localizedStringForKey:@"RESTART_REQUIRED_ALERT_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedStringForKey:@"RESTART_LATER_ACTION"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction* action) {
                                     // iOS gives an app no way to relaunch itself, so the
                                     // remaining option is to quit cleanly and let the user tap
                                     // the icon — same approach as the dark-style restart reminder.
                                     [[NSUserDefaults standardUserDefaults] synchronize];
                                     exit(0);
                                 }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// UIAlertAction carries a private checked flag that draws the system checkmark
// against the trailing edge and leaves the title centered. It is looked up by name;
// without it the current option becomes the preferred action and comes out bold.
- (void)addOption:(NSString*)title
         selected:(BOOL)selected
         toPicker:(UIAlertController*)picker
          handler:(void (^)(void))handler {
    if (!picker || !title) {
        return;
    }
    UIAlertAction* action = [UIAlertAction actionWithTitle:title
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction* a) {
                                                       if (handler) {
                                                           handler();
                                                       }
                                                   }];
    [picker addAction:action];
    if (!selected) {
        return;
    }
    static BOOL checkable = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        checkable = [UIAlertAction
            instancesRespondToSelector:NSSelectorFromString(@"setChecked:")];
    });
    if (checkable) {
        [action setValue:@YES forKey:@"checked"];
    } else {
        picker.preferredAction = action;
    }
}

- (void)updateAndAnimateChangesForKey:(NSString*)key {
    NSArray* oldVisibleToggles = self.visibleToggles;
    [self updateVisibleToggles];
    NSArray* newVisibleToggles = self.visibleToggles;
    [self.tableView beginUpdates];
    __block NSInteger toggleIndex = -1;
    [oldVisibleToggles enumerateObjectsUsingBlock:^(NSDictionary* _Nonnull obj, NSUInteger idx,
                                                    BOOL* _Nonnull stop) {
        if ([obj[@"key"] isEqualToString:key]) {
            toggleIndex = idx;
            *stop = YES;
        }
    }];
    if (toggleIndex == -1) {
        [self.tableView endUpdates];
        [self.tableView reloadData];
        return;
    }
    NSMutableArray* children = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        if ([toggleData[@"parentKey"] isEqualToString:key] ||
            [toggleData[@"hiddenWhen"] isEqualToString:key]) {
            [children addObject:toggleData];
        }
    }
    if (children.count == 0) {
        [self.tableView endUpdates];
        return;
    }
    BOOL isAdding = newVisibleToggles.count > oldVisibleToggles.count;
    // Children are not necessarily contiguous below their parent, so each child's
    // row is looked up where it actually is: in the new list when appearing, in the
    // old one when going away.
    NSArray* reference = isAdding ? newVisibleToggles : oldVisibleToggles;
    NSMutableArray* indexPaths = [NSMutableArray array];
    [reference enumerateObjectsUsingBlock:^(NSDictionary* entry, NSUInteger row,
                                            BOOL* stop) {
      if ([entry[@"parentKey"] isEqualToString:key] ||
          [entry[@"hiddenWhen"] isEqualToString:key]) {
          [indexPaths addObject:[NSIndexPath indexPathForRow:(NSInteger)row
                                                   inSection:0]];
      }
    }];
    if (indexPaths.count == 0) {
        [self.tableView endUpdates];
        return;
    }
    if (isAdding) {
        [self.tableView insertRowsAtIndexPaths:indexPaths
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView deleteRowsAtIndexPaths:indexPaths
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.tableView endUpdates];
}


// MARK: - Diagnostics

// Opens the Compatibility page.
- (void)showCompatibility:(NSDictionary*)sender {
    [self.navigationController
        pushViewController:[[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                                             pageKey:@"compatibility"]
                  animated:YES];
}

- (void)showCompatibilityReport:(NSDictionary*)sender {
    [self.navigationController
        pushViewController:[[PFBCompatibilityReportViewController alloc]
                               initWithStyle:UITableViewStyleGrouped]
                  animated:YES];
}

@end
