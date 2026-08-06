//
//  AppearanceSettingsViewController.m
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
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

- (void)showDarkModeStylePicker:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIAlertController* sheet = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"DARK_MODE_STYLE_TITLE"]
                         message:[bundle localizedStringForKey:@"DARK_MODE_STYLE_DETAIL"]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSString*>* titleKeys = @[
        @"DARK_MODE_STYLE_SYSTEM",
        @"DARK_MODE_STYLE_DIM",
        @"DARK_MODE_STYLE_GRAY",
        @"DARK_MODE_STYLE_PURE_BLACK"
    ];
    NSInteger current = [BHTSettings integerForKey:@"dark_mode_style"];

    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        NSString* title = [bundle localizedStringForKey:titleKeys[i]];
        if (i == current) {
            title = [NSString stringWithFormat:@"\u2713 %@", title];
        }
        UIAlertAction* action =
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction* a) {
                                       [[NSUserDefaults standardUserDefaults]
                                           setInteger:i
                                               forKey:@"dark_mode_style"];
                                       [[NSUserDefaults standardUserDefaults] synchronize];
                                       [self showRestartRequiredAlert];
                                   }];
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    // Anchored on the row that was tapped. Pointing at the middle of the screen
    // is what made these land in a random spot.
    NSIndexPath* indexPath = sender[@"indexPath"];
    UITableViewCell* cell = [indexPath isKindOfClass:[NSIndexPath class]]
                                ? [self.tableView cellForRowAtIndexPath:indexPath]
                                : nil;
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect =
        cell ? cell.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), 0, 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections =
        UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showInterfaceStylePicker:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIAlertController* sheet = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"INTERFACE_STYLE_TITLE"]
                         message:[bundle localizedStringForKey:@"INTERFACE_STYLE_DETAIL"]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSString*>* titleKeys = @[
        @"INTERFACE_STYLE_STANDARD",
        @"INTERFACE_STYLE_LIQUID_GLASS"
    ];
    // Index 0 = Standard (glass off), index 1 = Liquid Glass (glass on).
    NSInteger current = [BHTSettings boolForKey:@"enable_liquid_glass"] ? 1 : 0;

    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        NSString* title = [bundle localizedStringForKey:titleKeys[i]];
        if (i == current) {
            title = [NSString stringWithFormat:@"\u2713 %@", title];
        }
        UIAlertAction* action =
            [UIAlertAction actionWithTitle:title
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction* a) {
                                       BOOL wasEnabled =
                                           [BHTSettings boolForKey:@"enable_liquid_glass"];
                                       BOOL nowEnabled = (i == 1);
                                       [[NSUserDefaults standardUserDefaults]
                                           setBool:nowEnabled
                                            forKey:@"enable_liquid_glass"];
                                       [[NSUserDefaults standardUserDefaults] synchronize];
                                       // Only prompt for a restart when the mode actually changed.
                                       if (wasEnabled != nowEnabled) {
                                           [self showRestartRequiredAlert];
                                       }
                                   }];
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    // Anchored on the row that was tapped. Pointing at the middle of the screen
    // is what made these land in a random spot.
    NSIndexPath* indexPath = sender[@"indexPath"];
    UITableViewCell* cell = [indexPath isKindOfClass:[NSIndexPath class]]
                                ? [self.tableView cellForRowAtIndexPath:indexPath]
                                : nil;
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect =
        cell ? cell.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), 0, 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections =
        UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
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
