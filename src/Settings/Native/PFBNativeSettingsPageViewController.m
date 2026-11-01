// A settings page in Twitter's new look: a row per group of the page, each opening its group
// in a sheet.

#import "Settings/Native/PFBNativeSettingsPageViewController.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Settings/Native/PFBNativeSettingsSheetController.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/HookHelpers.h"

@interface PFBNativeSettingsPageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) Class pageClass;
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, copy) NSString* pageKey;
@property (nonatomic, copy) NSArray<NSDictionary*>* groups;
@property (nonatomic, strong) UITableView* tableView;
@end

@implementation PFBNativeSettingsPageViewController

+ (UIViewController*)controllerShowing:(UIViewController*)controller {
    if (![controller isKindOfClass:[PFBModernSettingsPageViewController class]] ||
        ((PFBModernSettingsPageViewController*)controller).inSheet) {
        return controller;
    }
    return [[self alloc] initWithPage:(PFBModernSettingsPageViewController*)controller];
}

- (instancetype)initWithPage:(PFBModernSettingsPageViewController*)page {
    if ((self = [super init])) {
        _pageClass = [page class];
        _account = page.account;
        _pageKey = [[page pageKey] copy];
        NSPredicate* headers = [NSPredicate predicateWithFormat:@"type == 'header'"];
        _groups = [[PFBSettings settingsForPage:_pageKey] filteredArrayUsingPredicate:headers];
        self.title = [[PFBBundle sharedBundle] localizedStringForKey:[page pageTitleKey]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = [PFBNativeSettingsRowStyle shared].rowHeight;
    self.tableView.tableFooterView = [[UIView alloc] init];
    [self.tableView registerClass:[PFBNativeSettingsRowCell class] forCellReuseIdentifier:@"NativeRow"];
    [self.view addSubview:self.tableView];
    [self applyTheme];
}

- (void)applyTheme {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView.backgroundColor = self.view.backgroundColor;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBThemeScreenEnter(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.groups.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBNativeSettingsRowCell* cell = [tableView dequeueReusableCellWithIdentifier:@"NativeRow"
                                                                     forIndexPath:indexPath];
    NSDictionary* group = self.groups[(NSUInteger)indexPath.row];
    [cell configureWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:group[@"titleKey"]]
                    iconName:group[@"icon"]
                   accessory:PFBNativeSettingsRowAccessoryMore];
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* group = self.groups[(NSUInteger)indexPath.row];
    PFBModernSettingsPageViewController* page = [[self.pageClass alloc] initWithAccount:self.account
                                                                                pageKey:self.pageKey
                                                                                  group:indexPath.row];
    [PFBNativeSettingsSheetController presentPage:page
                                           titled:[[PFBBundle sharedBundle] localizedStringForKey:group[@"titleKey"]]
                                             from:self];
}

@end
