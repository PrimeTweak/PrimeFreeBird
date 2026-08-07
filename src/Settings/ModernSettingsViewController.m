//
//  ModernSettingsViewController.m
//  PrimeFreeBird
//
//  Created by BandarHelal on 25/11/2021.
//

#import "Settings/ModernSettingsViewController.h"
#import "Core/TwitterChirpFont.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Settings/ModernSettingsCells.h"
#import "Settings/ModernSettingsPageViewController.h"
#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Settings/Pages/TweetsSettingsViewController.h"
#import "ThemeColor/Palette.h"

@interface ModernSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray* sections;
@end

extern NSInteger NFBColorThemeScreenVisible;

@implementation ModernSettingsViewController

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


#pragma mark - Section Headers

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        UIView* headerView = [[UIView alloc] init];
        headerView.backgroundColor = [Palette currentBackgroundColor];

        UILabel* subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"];
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentLeft;

        id fontGroup = [BHTManager sharedFontGroup];
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
    return nil;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return UITableViewAutomaticDimension;
    }
    return 0;
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
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_SUBTITLE"],
            @"icon": @"settings_stroke",
            @"action": @"showLayoutSettings"
        },
        @{
            @"title":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_SUBTITLE"],
            @"icon": @"paintbrush_stroke",
            @"action": @"showAppearanceSettings"
        },
        @{
            @"title":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_SUBTITLE"],
            @"icon": @"home_stroke",
            @"action": @"showTimelinesSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_SUBTITLE"],
            @"icon": @"quill",
            @"action": @"showTweetsSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_SUBTITLE"],
            @"icon": @"media_tab_stroke",
            @"action": @"showDownloadsSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_SUBTITLE"],
            @"icon": @"account",
            @"action": @"showProfilesSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_SUBTITLE"],
            @"icon": @"search_stroke",
            @"action": @"showSearchSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_SUBTITLE"],
            @"icon": @"tag_stroke",
            @"action": @"showBrandingSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_GROK_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_GROK_SUBTITLE"],
            @"icon": @"grok_icon_stroke",
            @"action": @"showGrokSettings"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAB_TITLE"],
            @"subtitle": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAB_SUBTITLE"],
            @"icon": @"flask",
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
    self.view.backgroundColor = [Palette currentBackgroundColor];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView")
            titleViewWithTitle:@NFB_PRODUCT_NAME
                      subtitle:self.account.displayUsername];
    } else {
        self.title = @NFB_PRODUCT_NAME;
    }
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"SettingsCell"];

   // Discreet credit footer acknowledging the upstream authors.
    UILabel* creditLabel = [[UILabel alloc] init];
    creditLabel.numberOfLines = 0;
    creditLabel.textAlignment = NSTextAlignmentCenter;
    creditLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:12];
    creditLabel.textColor = [UIColor tertiaryLabelColor];
    // Attribution stays prominent: this fork carries no licence of its own and
    // stands on BHTwitter and NeoFreeBird. The product name sits a touch larger
    // than the line below it, so the eye lands on it first.
    NSString* productName = @NFB_PRODUCT_NAME;
    NSString* attribution =
        @"\nBased on NeoFreeBird — original work by @nyaathea & @BandarHL";
    NSMutableAttributedString* credit = [[NSMutableAttributedString alloc]
        initWithString:[productName stringByAppendingString:attribution]];
    [credit addAttribute:NSFontAttributeName
                   value:[TwitterChirpFont(TwitterFontStyleBold) fontWithSize:14]
                   range:NSMakeRange(0, productName.length)];
    creditLabel.attributedText = credit;
    CGSize fitSize = [creditLabel sizeThatFits:CGSizeMake(self.view.bounds.size.width - 40, CGFLOAT_MAX)];
    creditLabel.frame = CGRectMake(0, 0, self.view.bounds.size.width, fitSize.height + 32);
    self.tableView.tableFooterView = creditLabel;
    
    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.sections.count;
    }
    return 0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == 0) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                                                            forIndexPath:indexPath];
        NSDictionary* sectionData = self.sections[indexPath.row];
        [cell configureWithTitle:sectionData[@"title"]
                        subtitle:sectionData[@"subtitle"]
                        iconName:sectionData[@"icon"]];
        return cell;
    }

    return nil;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSDictionary* sectionData = self.sections[indexPath.row];
        NSString* action = sectionData[@"action"];
        SEL selector = NSSelectorFromString(action);
        if ([self respondsToSelector:selector]) {
            IMP imp = [self methodForSelector:selector];
            void (*func)(id, SEL) = (void*)imp;
            func(self, selector);
        }
    }
}

#pragma mark - Navigation to Sub-pages

- (void)showLayoutSettings {
    ModernSettingsPageViewController* vc =
        [[ModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"general"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showLabSettings {
    ModernSettingsPageViewController* vc =
        [[ModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"lab"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAppearanceSettings {
    AppearanceSettingsViewController* vc =
        [[AppearanceSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTimelinesSettings {
    TimelinesSettingsViewController* vc =
        [[TimelinesSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showGrokSettings {
    ModernSettingsPageViewController* vc =
        [[ModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"grok"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDownloadsSettings {
    ModernSettingsPageViewController* vc =
        [[ModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"media_downloads"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfilesSettings {
    ProfilesSettingsViewController* vc =
        [[ProfilesSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTweetsSettings {
    TweetsSettingsViewController* vc =
        [[TweetsSettingsViewController alloc] initWithAccount:self.account];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBrandingSettings {
    ModernSettingsPageViewController* vc =
        [[ModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"branding"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showSearchSettings {
    ModernSettingsPageViewController* vc =
        [[ModernSettingsPageViewController alloc] initWithAccount:self.account
                                                          pageKey:@"search"];
    [self.navigationController pushViewController:vc animated:YES];
}
@end
