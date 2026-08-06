//
//  AppearanceSettingsViewController.m
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Settings/OptionPickerViewController.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"
#import "ThemeColor/DarkModeStyle.h"

@interface AppearanceSettingsViewController () <UIFontPickerViewControllerDelegate>
@end

@implementation AppearanceSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 60;
}

- (NSString*)pageKey {
    return @"appearance";
}

#pragma mark - Sub-page Navigation

- (void)showThemeViewController:(NSDictionary*)sender {
    Class ColorThemeViewControllerClass = objc_getClass("ColorThemeViewController");
    if (ColorThemeViewControllerClass) {
        UIViewController* themeVC = [[ColorThemeViewControllerClass alloc] init];
        if (self.account) {
            [themeVC.navigationItem
                setTitleView:
                    [objc_getClass("TFNTitleView")
                        titleViewWithTitle:[[BHTBundle sharedBundle]
                                               localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_TITLE"]
                                  subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:themeVC animated:YES];
    }
}

- (void)showCustomTabBarVC:(NSDictionary*)sender {
    Class CustomTabBarViewControllerClass = objc_getClass("CustomTabBarViewController");
    if (CustomTabBarViewControllerClass) {
        UIViewController* customTabBarVC = [[CustomTabBarViewControllerClass alloc] init];
        if (self.account) {
            [customTabBarVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:
                                                            @"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
                                           subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:customTabBarVC animated:YES];
    }
}

// Two choices, shown in the fork's own popover so the type stays Chirp.

- (UITableViewCell*)cellForEntry:(NSDictionary*)entry {
    NSIndexPath* indexPath = entry[@"indexPath"];
    return [indexPath isKindOfClass:[NSIndexPath class]]
               ? [self.tableView cellForRowAtIndexPath:indexPath]
               : nil;
}

- (void)showDarkModeStylePicker:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSArray<NSString*>* titleKeys = @[
        @"DARK_MODE_STYLE_SYSTEM",
        @"DARK_MODE_STYLE_DIM",
        @"DARK_MODE_STYLE_GRAY",
        @"DARK_MODE_STYLE_PURE_BLACK"
    ];
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    for (NSString* key in titleKeys) {
        [titles addObject:[bundle localizedStringForKey:key]];
    }

    __weak typeof(self) weakSelf = self;
    OptionPickerViewController* picker = [[OptionPickerViewController alloc]
        initWithTitle:[bundle localizedStringForKey:@"DARK_MODE_STYLE_TITLE"]
              message:[bundle localizedStringForKey:@"DARK_MODE_STYLE_DETAIL"]
              options:titles
        selectedIndex:[BHTSettings integerForKey:@"dark_mode_style"]
              handler:^(NSInteger index) {
                  [[NSUserDefaults standardUserDefaults] setInteger:index
                                                             forKey:@"dark_mode_style"];
                  [[NSUserDefaults standardUserDefaults] synchronize];
                  [weakSelf.tableView reloadData];
                  [weakSelf showRestartRequiredAlert];
              }];
    [picker presentFrom:self sourceView:[self cellForEntry:sender]];
}

- (void)showInterfaceStylePicker:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSArray<NSString*>* titleKeys = @[
        @"INTERFACE_STYLE_STANDARD",
        @"INTERFACE_STYLE_LIQUID_GLASS"
    ];
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    for (NSString* key in titleKeys) {
        [titles addObject:[bundle localizedStringForKey:key]];
    }
    // Index 0 = Standard (glass off), index 1 = Liquid Glass (glass on).
    BOOL wasEnabled = [BHTSettings boolForKey:@"enable_liquid_glass"];

    __weak typeof(self) weakSelf = self;
    OptionPickerViewController* picker = [[OptionPickerViewController alloc]
        initWithTitle:[bundle localizedStringForKey:@"INTERFACE_STYLE_TITLE"]
              message:[bundle localizedStringForKey:@"INTERFACE_STYLE_DETAIL"]
              options:titles
        selectedIndex:(wasEnabled ? 1 : 0)
              handler:^(NSInteger index) {
                  BOOL nowEnabled = (index == 1);
                  [[NSUserDefaults standardUserDefaults] setBool:nowEnabled
                                                          forKey:@"enable_liquid_glass"];
                  [[NSUserDefaults standardUserDefaults] synchronize];
                  [weakSelf.tableView reloadData];
                  // Only prompt for a restart when the mode actually changed.
                  if (wasEnabled != nowEnabled) {
                      [weakSelf showRestartRequiredAlert];
                  }
              }];
    [picker presentFrom:self sourceView:[self cellForEntry:sender]];
}

#pragma mark - Tab Bar Refresh

- (void)refreshAllTabViewsWithTheming {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsWithThemingInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsWithThemingInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        if ([view respondsToSelector:@selector(_t1_updateImageViewAnimated:)]) {
            [view performSelector:@selector(_t1_updateImageViewAnimated:) withObject:@(NO)];
        }
        if ([view respondsToSelector:@selector(_t1_updateTitleLabel)]) {
            [view performSelector:@selector(_t1_updateTitleLabel)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutForTabBar)]) {
            [view performSelector:@selector(_t1_layoutForTabBar)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMinimized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMinimized)];
        }

        // Clearing the override lets the label fall back to its default color.
        if (![BHTSettings boolForKey:@"tab_bar_theming"]) {
            UILabel* titleLabel = [view valueForKey:@"titleLabel"];
            if (titleLabel) {
                titleLabel.textColor = nil;
            }
        }
    }

    for (UIView* subview in view.subviews) {
        [self refreshTabViewsWithThemingInView:subview];
    }
}

- (void)refreshAllTabViews {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        if ([view respondsToSelector:@selector(_t1_updateTitleLabel)]) {
            [view performSelector:@selector(_t1_updateTitleLabel)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutForTabBar)]) {
            [view performSelector:@selector(_t1_layoutForTabBar)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }

        if (![BHTSettings boolForKey:@"tab_bar_theming"]) {
            UILabel* titleLabel = [view valueForKey:@"titleLabel"];
            if (titleLabel) {
                titleLabel.textColor = nil;
            }
        }
    }

    for (UIView* subview in view.subviews) {
        [self refreshTabViewsInView:subview];
    }
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"tab_bar_theming"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViewsWithTheming];
        });
    } else if ([key isEqualToString:@"restore_tab_labels"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViews];
        });
    }
}

#pragma mark - Font Pickers

- (void)showRegularFontPicker:(NSDictionary*)sender {
    UIFontPickerViewControllerConfiguration* configuration =
        [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    [configuration setIncludeFaces:NO];
    UIFontPickerViewController* fontPicker =
        [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    objc_setAssociatedObject(fontPicker, @"fontType", @"regular", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.account) {
        [fontPicker.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)showBoldFontPicker:(NSDictionary*)sender {
    UIFontPickerViewControllerConfiguration* configuration =
        [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setIncludeFaces:YES];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    UIFontPickerViewController* fontPicker =
        [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    objc_setAssociatedObject(fontPicker, @"fontType", @"bold", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.account) {
        [fontPicker.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController*)viewController {
    NSString* fontName =
        viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorNameAttribute];
    NSString* fontFamily =
        viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorFamilyAttribute];
    NSString* fontType = objc_getAssociatedObject(viewController, @"fontType");
    if ([fontType isEqualToString:@"bold"]) {
        [[NSUserDefaults standardUserDefaults] setObject:fontName forKey:@"bhtwitter_font_2"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:fontFamily forKey:@"bhtwitter_font_1"];
    }
    [self updateVisibleToggles];
    [self.tableView reloadData];
    [viewController.navigationController popViewControllerAnimated:YES];
}

@end
