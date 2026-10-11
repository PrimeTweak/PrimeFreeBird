// The Appearance page: accent color, dark mode style and tab bar editor entries.

#import "Settings/Pages/PFBAppearanceSettingsViewController.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Features/Appearance/ThemeColor/PFBColorThemeViewController.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.h"

@interface PFBAppearanceSettingsViewController () <UIFontPickerViewControllerDelegate>
@end

@implementation PFBAppearanceSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 60;
}

- (NSString*)pageKey {
    return @"appearance";
}

#pragma mark - Sub-page Navigation

- (void)showThemeViewController:(NSDictionary*)sender {
    UIViewController* themeVC = [[PFBColorThemeViewController alloc] init];
    if (self.account) {
        [themeVC.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[PFBBundle sharedBundle]
                                           localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_TITLE"]
                              subtitle:self.account.displayUsername]];
    }
    [self.navigationController pushViewController:themeVC animated:YES];
}

- (void)showCustomTabBarVC:(NSDictionary*)sender {
    UIViewController* customTabBarVC = [[PFBCustomTabBarViewController alloc] init];
    if (self.account) {
        [customTabBarVC.navigationItem
            setTitleView:[objc_getClass("TFNTitleView")
                             titleViewWithTitle:[[PFBBundle sharedBundle]
                                                    localizedStringForKey:
                                                        @"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
                                       subtitle:self.account.displayUsername]];
    }
    [self.navigationController pushViewController:customTabBarVC animated:YES];
}

- (void)showDarkModeStylePicker:(NSDictionary*)sender {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* sheet = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"DARK_MODE_STYLE_TITLE"]
                         message:[bundle localizedStringForKey:@"DARK_MODE_STYLE_DETAIL"]
                  preferredStyle:UIAlertControllerStyleAlert];

    NSArray<NSString*>* titleKeys = @[
        @"DARK_MODE_STYLE_SYSTEM",
        @"DARK_MODE_STYLE_DIM",
        @"DARK_MODE_STYLE_GRAY",
        @"DARK_MODE_STYLE_PURE_BLACK"
    ];
    NSInteger current = [PFBSettings integerForKey:@"dark_mode_style"];

    PFBAppearanceSettingsViewController* page = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        [self addOption:[bundle localizedStringForKey:titleKeys[i]]
               selected:(i == current)
               toPicker:sheet
                handler:^{
                    // Picking the shade already in use changes nothing to restart for.
                    if (i == current) {
                        return;
                    }
                    [[NSUserDefaults standardUserDefaults] setInteger:i
                                                               forKey:@"dark_mode_style"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [page showRestartRequiredAlert];
                }];
    }

    [sheet addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showInterfaceStylePicker:(NSDictionary*)sender {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* sheet = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"INTERFACE_STYLE_TITLE"]
                         message:[bundle localizedStringForKey:@"INTERFACE_STYLE_DETAIL"]
                  preferredStyle:UIAlertControllerStyleAlert];

    NSArray<NSString*>* titleKeys = @[
        @"INTERFACE_STYLE_STANDARD",
        @"INTERFACE_STYLE_LIQUID_GLASS"
    ];
    // Index 0 = Standard (glass off), index 1 = Liquid Glass (glass on).
    NSInteger current = [PFBSettings boolForKey:@"enable_liquid_glass"] ? 1 : 0;

    PFBAppearanceSettingsViewController* page = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        [self addOption:[bundle localizedStringForKey:titleKeys[i]]
               selected:(i == current)
               toPicker:sheet
                handler:^{
                    BOOL wasEnabled = [PFBSettings boolForKey:@"enable_liquid_glass"];
                    BOOL nowEnabled = (i == 1);
                    [[NSUserDefaults standardUserDefaults] setBool:nowEnabled
                                                            forKey:@"enable_liquid_glass"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    // Only prompt for a restart when the mode actually changed.
                    if (wasEnabled != nowEnabled) {
                        [page showRestartRequiredAlert];
                    }
                }];
    }

    [sheet addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
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
        if (![PFBSettings boolForKey:@"tab_bar_theming"]) {
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

        if (![PFBSettings boolForKey:@"tab_bar_theming"]) {
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
                    titleViewWithTitle:[[PFBBundle sharedBundle]
                                           localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[PFBBundle sharedBundle] localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"];
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
                    titleViewWithTitle:[[PFBBundle sharedBundle]
                                           localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[PFBBundle sharedBundle] localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

// Clears the regular and bold choices so Twitter's own font returns, and the font
// picker's recents with them; the Custom fonts toggle is left as it is.
- (void)useDefaultFont:(NSDictionary*)sender {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:@"DEFAULT_FONT_OPTION_TITLE"];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:title
                         message:[bundle localizedStringForKey:@"DEFAULT_FONT_CONFIRM_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];
    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:title
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction* action) {
                                                NSUserDefaults* defaults =
                                                    [NSUserDefaults standardUserDefaults];
                                                [defaults removeObjectForKey:@"pfb_font_1"];
                                                [defaults removeObjectForKey:@"pfb_font_2"];
                                                [defaults removeObjectForKey:@"UIFontPickerRecentFamilies"];
                                                [weakSelf updateVisibleToggles];
                                                [weakSelf.tableView reloadData];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController*)viewController {
    NSString* fontName =
        viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorNameAttribute];
    NSString* fontFamily =
        viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorFamilyAttribute];
    NSString* fontType = objc_getAssociatedObject(viewController, @"fontType");
    if ([fontType isEqualToString:@"bold"]) {
        [[NSUserDefaults standardUserDefaults] setObject:fontName forKey:@"pfb_font_2"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:fontFamily forKey:@"pfb_font_1"];
    }
    [self updateVisibleToggles];
    [self.tableView reloadData];
    [viewController.navigationController popViewControllerAnimated:YES];
}

@end
