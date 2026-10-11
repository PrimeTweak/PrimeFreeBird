// The settings root: the list of pages.

#import "Settings/PFBModernSettingsViewController.h"
#import "Support/TwitterChirpFont.h"
#import "Common/PFBBundle.h"
#import "Settings/PFBModernSettingsCells.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Settings/Pages/PFBAppearanceSettingsViewController.h"
#import "Settings/Pages/PFBProfilesSettingsViewController.h"
#import "Settings/Pages/PFBTimelinesSettingsViewController.h"
#import "Settings/Pages/PFBTweetsSettingsViewController.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Support/HookHelpers.h"

@interface PFBModernSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray* sections;
@end

@implementation PFBModernSettingsViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBThemeScreenEnter(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
}


#pragma mark - Section Headers

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* headerView = [[UIView alloc] init];
    headerView.backgroundColor = [PFBPalette currentBackgroundColor];

    UILabel* subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = [[PFBBundle sharedBundle] localizedStringForKey:@"PFB_SETTINGS_DETAIL"];
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.textAlignment = NSTextAlignmentLeft;

    id fontGroup = [PFBManager sharedFontGroup];
    subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];

    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    subtitleLabel.textColor = subtitleColor;

    [headerView addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                                    constant:10],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                                     constant:-10],
        [subtitleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor
                                                constant:16],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor
                                                   constant:-16]
    ]];

    return headerView;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

#pragma mark - Lifecycle & Setup

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    self = [super init];
    if (self) {
        _account = account;
        [self setupSections];
    }
    return self;
}

- (void)setupSections {
    self.sections = @[
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_SUBTITLE"],
            @"icon": @"settings_stroke",
            @"action": @"showLayoutSettings"
        },
        @{
            @"title":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_SUBTITLE"],
            @"icon": @"paintbrush_stroke",
            @"action": @"showAppearanceSettings"
        },
        @{
            @"title":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_SUBTITLE"],
            @"icon": @"home_stroke",
            @"action": @"showTimelinesSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_SUBTITLE"],
            @"icon": @"quill",
            @"action": @"showTweetsSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_SUBTITLE"],
            @"icon": @"media_tab_stroke",
            @"action": @"showDownloadsSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_SUBTITLE"],
            @"icon": @"person_stroke",
            @"action": @"showProfilesSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_SUBTITLE"],
            @"icon": @"search_stroke",
            @"action": @"showSearchSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MESSAGES_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MESSAGES_SUBTITLE"],
            @"icon": @"messages_stroke",
            @"action": @"showGrokSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_TITLE"],
            @"subtitle":
                [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_SUBTITLE"],
            @"icon": @"tag_stroke",
            @"action": @"showBrandingSettings"
        },
        @{
            @"title": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAB_TITLE"],
            @"subtitle": [[PFBBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAB_SUBTITLE"],
            @"icon": @"hammer_stroke",
            @"action": @"showLabSettings"
        },
    ];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigationBar];
    [self setupTableView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChange:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contentSizeCategoryDidChange:(NSNotification*)notification {
    [self.tableView reloadData];
}

- (void)setupNavigationBar {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView")
            titleViewWithTitle:@PFB_PRODUCT_NAME
                      subtitle:self.account.displayUsername];
    } else {
        self.title = @PFB_PRODUCT_NAME;
    }
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    [self.tableView registerClass:[PFBModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"SettingsCell"];

    // Footer: PrimeFreeBird's name and version, then the credit to the original work. The
    // text starts right under the list's own bottom spacing, so it falls on the rhythm of
    // the rows, with room left below it.
    UILabel* creditLabel = [[UILabel alloc] init];
    creditLabel.numberOfLines = 0;
    creditLabel.textAlignment = NSTextAlignmentCenter;
    creditLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:12];
    creditLabel.textColor = [UIColor tertiaryLabelColor];
    NSString* productLine = @PFB_VERSION_STRING;
    NSString* attribution =
        @"\nBased on NeoFreeBird — original work by @nyaathea & @BandarHL";
    NSMutableAttributedString* credit = [[NSMutableAttributedString alloc]
        initWithString:[productLine stringByAppendingString:attribution]];
    [credit addAttribute:NSFontAttributeName
                   value:[TwitterChirpFont(TwitterFontStyleBold) fontWithSize:14]
                   range:NSMakeRange(0, productLine.length)];
    creditLabel.attributedText = credit;
    CGFloat footerWidth = self.view.bounds.size.width;
    CGSize fitSize = [creditLabel sizeThatFits:CGSizeMake(footerWidth - 40, CGFLOAT_MAX)];
    creditLabel.frame = CGRectMake(20, 0, footerWidth - 40, fitSize.height);
    creditLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView* footer =
        [[UIView alloc] initWithFrame:CGRectMake(0, 0, footerWidth, fitSize.height + 16)];
    [footer addSubview:creditLabel];
    self.tableView.tableFooterView = footer;
    
    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                                                        forIndexPath:indexPath];
    NSDictionary* sectionData = self.sections[indexPath.row];
    [cell configureWithTitle:sectionData[@"title"]
                    subtitle:sectionData[@"subtitle"]
                    iconName:sectionData[@"icon"]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary* sectionData = self.sections[indexPath.row];
    NSString* action = sectionData[@"action"];
    SEL selector = NSSelectorFromString(action);
    if ([self respondsToSelector:selector]) {
        IMP imp = [self methodForSelector:selector];
        void (*func)(id, SEL) = (void*)imp;
        func(self, selector);
    }
}

#pragma mark - Navigation to Sub-pages

- (void)showLayoutSettings {
    PFBModernSettingsPageViewController* vc =
        [[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"general"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showLabSettings {
    PFBModernSettingsPageViewController* vc =
        [[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"lab"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAppearanceSettings {
    PFBAppearanceSettingsViewController* vc =
        [[PFBAppearanceSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTimelinesSettings {
    PFBTimelinesSettingsViewController* vc =
        [[PFBTimelinesSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showGrokSettings {
    PFBModernSettingsPageViewController* vc =
        [[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"grok"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDownloadsSettings {
    PFBModernSettingsPageViewController* vc =
        [[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"media_downloads"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfilesSettings {
    PFBProfilesSettingsViewController* vc =
        [[PFBProfilesSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTweetsSettings {
    PFBTweetsSettingsViewController* vc =
        [[PFBTweetsSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBrandingSettings {
    PFBModernSettingsPageViewController* vc =
        [[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"branding"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showSearchSettings {
    PFBModernSettingsPageViewController* vc =
        [[PFBModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"search"];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
