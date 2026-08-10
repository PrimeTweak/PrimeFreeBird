//
//  ModernSettingsPageViewController.m
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPageViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"
#import "MutedWords/MutedWordsViewController.h"
#import "Core/BHTSettingsBackup.h"
#import "ThemeColor/Palette.h"
#import "Hooks/HookHelpers.h"

@interface ModernSettingsPageViewController () <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString* registryPageKey;
@end

extern NSInteger NFBColorThemeScreenVisible;

@implementation ModernSettingsPageViewController

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

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

#pragma mark - Page Registry

- (NSString*)pageKey {
    return self.registryPageKey;
}

- (NSString*)pageTitleKey {
    return [BHTSettings titleKeyForPage:[self pageKey]];
}

- (NSString*)pageSubtitleKey {
    return [BHTSettings subtitleKeyForPage:[self pageKey]];
}

- (void)buildSettingsList {
    self.toggles = [BHTSettings settingsForPage:[self pageKey]];
}

#pragma mark - Setup

- (void)setupNav {
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:[self pageTitleKey]];
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class]
           forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class]
           forCellReuseIdentifier:@"CompactButtonCell"];
    [self.tableView registerClass:[ModernSettingsHeaderCell class]
           forCellReuseIdentifier:@"HeaderCell"];
    [self.view addSubview:self.tableView];
}

#pragma mark - Visible Toggles

- (void)updateVisibleToggles {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* visible = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        NSString* parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [[defaults objectForKey:parentKey] ?: toggleData[@"default"] boolValue];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
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
    return [[BHTBundle sharedBundle] localizedStringForKey:titleKey];
}

// The bundle returns the key itself when no string exists, which counts as no detail.
- (NSString*)localizedDetailForKey:(NSString*)key {
    NSString* detailKey = [NSString stringWithFormat:@"%@_DETAIL", [key uppercaseString]];
    NSString* detail = [[BHTBundle sharedBundle] localizedStringForKey:detailKey];
    return [detail isEqualToString:detailKey] ? @"" : detail;
}

// Localized at render time; the registry can't call localizedStringForKey
// without re-entering the settings lookup.
- (NSString*)defaultSubtitleForEntry:(NSDictionary*)entry {
    NSString* subtitleDefaultKey = entry[@"subtitleDefaultKey"];
    if (subtitleDefaultKey) {
        return [[BHTBundle sharedBundle] localizedStringForKey:subtitleDefaultKey];
    }
    return entry[@"subtitleDefault"];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* toggleData = self.visibleToggles[indexPath.row];
    NSString* type = toggleData[@"type"];
    if ([type isEqualToString:@"header"]) {
        ModernSettingsHeaderCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"HeaderCell"
                                            forIndexPath:indexPath];
        [cell configureWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:toggleData[@"titleKey"]]];
        return cell;
    }
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell"
                                                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString* subtitleKey = toggleData[@"subtitleKey"];
        if (subtitleKey) {
            subtitle = [[BHTBundle sharedBundle] localizedStringForKey:subtitleKey];
        }
        NSString* iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell"
                                                                         forIndexPath:indexPath];
        NSString* key = toggleData[@"key"];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = [self localizedDetailForKey:key];
        [cell configureWithTitle:title subtitle:subtitle];
        [cell setIndented:[toggleData[@"indented"] boolValue]];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key]
                              ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(cell.toggleSwitch, @"prefKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addTarget:self
                      action:@selector(switchChanged:)
            forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

#pragma mark - UITableViewDelegate

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
    label.text = [[BHTBundle sharedBundle] localizedStringForKey:[self pageSubtitleKey]];
    label.numberOfLines = 0;
    id fontGroup = [BHTManager sharedFontGroup];
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

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [self updateAndAnimateChangesForKey:key];

        // The switch-tint toggle changes how every OTHER visible switch is
        // drawn, so re-run applyTheme on the live cells right away.
        if ([key isEqualToString:@"color_nfb_switches"]) {
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

        // These toggles change which surfaces follow the accent, so push the
        // accent through again instead of waiting for those views to rebuild.
        // This block previously sat NESTED inside the branch above — a
        // misplaced insertion — where its condition could never be true: dead
        // code, and the reason these two switches never reverted anything live.
        if ([key isEqualToString:@"color_twitter_icon_in_top_bar"] ||
            [key isEqualToString:@"tab_bar_theming"]) {
            extern void NFBSyncAccentTheme(void);
            NFBSyncAccentTheme();
        }

        if ([key isEqualToString:@"restore_tweet_button"]) {
            [self showRestartRequiredAlert];
        }
        if ([key isEqualToString:@"hide_trends"] ||
            [key isEqualToString:@"hide_tweet_button"]) {
            [self showRestartInfoAlert];
        }
    }
}

- (void)showAppIconViewController:(NSDictionary*)sender {
    Class AppIconViewControllerClass = objc_getClass("AppIconViewController");
    if (AppIconViewControllerClass) {
        UIViewController* appIconVC = [[AppIconViewControllerClass alloc] init];
        if (self.account) {
            [appIconVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[BHTBundle sharedBundle]
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
    MutedWordsViewController* editor = [[MutedWordsViewController alloc] init];
    [self.navigationController pushViewController:editor animated:YES];
}

// MARK: - Settings backup

- (void)showBadgeSurvey:(NSDictionary*)sender {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* message = [NSString
        stringWithFormat:@"tick %ld\ntoggle %ld\nresolved %ld\ndesc %ld\nhome "
                         @"%ld\npass %ld\nseen %ld\nstatus %ld\ncontext "
                         @"%ld\nnamed %ld\n\n%@\n%@",
                         (long)[defaults integerForKey:@"nfb_badge_tick"],
                         (long)[defaults integerForKey:@"nfb_badge_toggle"],
                         (long)[defaults integerForKey:@"nfb_badge_resolved"],
                         (long)[defaults integerForKey:@"nfb_badge_desc"],
                         (long)[defaults integerForKey:@"nfb_badge_home"],
                         (long)[defaults integerForKey:@"nfb_badge_pass"],
                         (long)[defaults integerForKey:@"nfb_badge_seen"],
                         (long)[defaults integerForKey:@"nfb_badge_status"],
                         (long)[defaults integerForKey:@"nfb_badge_context"],
                         (long)[defaults integerForKey:@"nfb_badge_named"],
                         [defaults stringForKey:@"nfb_badge_sample"] ?: @"(no sample)",
                         [defaults stringForKey:@"nfb_badge_lists"] ?: @"(no lists)"];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:@"Badge survey"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction* action) {
        for (NSString* key in @[
                 @"nfb_badge_tick", @"nfb_badge_toggle", @"nfb_badge_resolved",
                 @"nfb_badge_desc", @"nfb_badge_home", @"nfb_badge_pass",
                 @"nfb_badge_seen", @"nfb_badge_status", @"nfb_badge_context",
                 @"nfb_badge_named", @"nfb_badge_sample", @"nfb_badge_lists"
             ]) {
            [defaults removeObjectForKey:key];
        }
    }]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:@"OK_ACTION"]
                                   style:UIAlertActionStyleDefault
                                 handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showExportSettings:(NSDictionary*)sender {
    NSData* data = [BHTSettingsBackup exportData];
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
    NSInteger applied = [BHTSettingsBackup importData:data];
    BHTBundle* bundle = [BHTBundle sharedBundle];
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
        // The same pair Theme.x listens to after a live colour change, so the
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

// Opens the interactive web login. Harvest + store happens inside; on success a short
// confirmation is shown so the user knows the session was saved.
- (void)showWebSessionLogin:(NSDictionary*)sender {
    __weak typeof(self) weakSelf = self;
    presentWebSessionLogin(^(BOOL success) {
        if (!success) {
            return;
        }
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        UIAlertController* done = [UIAlertController
            alertControllerWithTitle:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"WEB_SESSION_SAVED_TITLE"]
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"WEB_SESSION_SAVED_MESSAGE"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                           localizedStringForKey:@"OK_ACTION"]
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
        [strongSelf presentViewController:done animated:YES completion:nil];
    });
}

// Deletes the stored web session, behind a destructive confirmation.
- (void)clearWebSession:(NSDictionary*)sender {
    UIAlertController* confirm = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:@"WEB_SESSION_CLEAR_TITLE"]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:@"WEB_SESSION_CLEAR_CONFIRM"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction
                           actionWithTitle:[[BHTBundle sharedBundle]
                                               localizedStringForKey:@"WEB_SESSION_CLEAR_ACTION"]
                                     style:UIAlertActionStyleDestructive
                                   handler:^(__unused UIAlertAction* action) {
                                       clearWebSession();
                                   }]];
    [confirm addAction:[UIAlertAction
                           actionWithTitle:[[BHTBundle sharedBundle]
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

// Lives in the base class so the General page can present it now that the
// link settings moved there.
- (void)showSharingDomainPrompt:(NSDictionary*)data {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* currentHost = [defaults objectForKey:@"sharing_domain"];

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle]
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
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [alert
        addAction:[UIAlertAction
                      actionWithTitle:[[BHTBundle sharedBundle]
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

// Informational only (master Explore-tabs switch): tells the user a restart
// is needed for the change to fully apply. One OK button, dismisses the
// alert and nothing else — the app never closes itself here.
- (void)showRestartInfoAlert {
    BHTBundle* bundle = [BHTBundle sharedBundle];
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
    BHTBundle* bundle = [BHTBundle sharedBundle];
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
                                     // best we can do is quit cleanly and let the user tap
                                     // the icon — same approach as the dark-style reset.
                                     [[NSUserDefaults standardUserDefaults] synchronize];
                                     exit(0);
                                 }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Gluing a checkmark onto the title pushes the word off the axis every other
// option sits on — the mark ends up costing the alignment of the whole list.
// UIAlertAction carries a private "checked" flag that draws the system's own
// checkmark against the trailing edge and leaves the title centred, which is
// how iOS marks a choice in its own pickers.
//
// Private means it is asked for by name rather than assumed: the setter KVC
// would reach for is looked up once, and if a future iOS no longer has it the
// current option is set as the alert's preferred action and comes out bold
// instead. Neither branch touches the title, so the list stays aligned either
// way — and a bold option instead of a checkmark is the signal that the flag
// is gone.
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
        if ([toggleData[@"parentKey"] isEqualToString:key]) {
            [children addObject:toggleData];
        }
    }
    if (children.count == 0) {
        [self.tableView endUpdates];
        return;
    }
    BOOL isAdding = newVisibleToggles.count > oldVisibleToggles.count;
    // Children are registered directly after their parent, so their rows are contiguous below it.
    NSMutableArray* indexPaths = [NSMutableArray array];
    for (int i = 0; i < children.count; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:toggleIndex + 1 + i inSection:0]];
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

@end
