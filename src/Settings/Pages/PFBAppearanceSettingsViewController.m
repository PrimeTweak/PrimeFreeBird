// The Appearance page: interface style, fonts, accent color, dark mode style and the tab bar editor.

#import "Settings/Pages/PFBAppearanceSettingsViewController.h"
#import <objc/message.h>
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Support/HookHelpers.h"
#import "Features/Appearance/ThemeColor/PFBColorThemeViewController.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.h"
#import "Settings/PFBModernSettingsCells.h"

// The dark shades, in the order dark_mode_style stores them.
static NSArray<NSString*>* PFBDarkModeStyleKeys(void) {
    return @[ @"DARK_MODE_STYLE_SYSTEM", @"DARK_MODE_STYLE_DIM", @"DARK_MODE_STYLE_GRAY", @"DARK_MODE_STYLE_PURE_BLACK" ];
}

// Standard, then Liquid Glass, as enable_liquid_glass is off or on.
static NSArray<NSString*>* PFBInterfaceStyleKeys(void) {
    return @[ @"INTERFACE_STYLE_STANDARD", @"INTERFACE_STYLE_LIQUID_GLASS" ];
}

static NSInteger PFBInterfaceStyleCurrent(void) {
    return [PFBSettings boolForKey:@"enable_liquid_glass"] ? 1 : 0;
}

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

// In a sheet, Visual style and Background color show their choice and open a menu, as Retweets
// does; the classic look keeps their alerts.
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* entry = self.visibleToggles[indexPath.row];
    NSDictionary<NSString*, NSString*>* menus = @{
        @"showInterfaceStylePicker:": @"interfaceStyleMenu",
        @"showDarkModeStylePicker:": @"darkModeStyleMenu",
    };
    NSString* menu = self.inSheet && entry[@"action"] ? menus[entry[@"action"]] : nil;
    if (!menu) {
        return [super tableView:tableView cellForRowAtIndexPath:indexPath];
    }
    BOOL glass = [menu isEqualToString:@"interfaceStyleMenu"];
    NSArray<NSString*>* choices = glass ? PFBInterfaceStyleKeys() : PFBDarkModeStyleKeys();
    NSInteger current = glass ? PFBInterfaceStyleCurrent() : [PFBSettings integerForKey:@"dark_mode_style"];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    PFBModernSettingsCompactButtonCell* cell = [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                                                               forIndexPath:indexPath];
    [cell configureWithTitle:[bundle localizedStringForKey:entry[@"titleKey"]]
                    subtitle:[bundle localizedStringForKey:choices[current >= 0 && current < (NSInteger)choices.count
                                                                       ? (NSUInteger)current
                                                                       : 0]]
                      detail:[bundle localizedStringForKey:entry[@"subtitleKey"]]];
    NSMutableDictionary* withMenu = [entry mutableCopy];
    withMenu[@"menu"] = menu;
    [self attachMenuIfNeeded:cell entry:withMenu];
    return cell;
}

#pragma mark - Sub-page Navigation

// The new look titles its screens alone, as it titles its pages.
- (void)showThemeViewController:(NSDictionary*)sender {
    PFBColorThemeViewController* themeVC = [[PFBColorThemeViewController alloc] init];
    themeVC.nativeLook = self.nativeLook;
    NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_TITLE"];
    if (self.nativeLook) {
        themeVC.title = title;
    } else if (self.account) {
        [themeVC.navigationItem
            setTitleView:[objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                                   subtitle:self.account.displayUsername]];
    }
    [self.navigationController pushViewController:themeVC animated:YES];
}

// Twitter's own tab editor under its Liquid Glass navigation, which brings its own title and
// account line; PrimeFreeBird's editor otherwise.
- (void)showCustomTabBarVC:(NSDictionary*)sender {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIViewController* customTabBarVC = [PFBCustomTabBarUtility editorForAccount:self.account];
    if (!customTabBarVC) {
        UIAlertController* alert =
            [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
                                                message:[bundle localizedStringForKey:@"UNKNOWN_ERROR"]
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK_ACTION"]
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (self.account && [customTabBarVC isKindOfClass:[PFBCustomTabBarViewController class]]) {
        [customTabBarVC.navigationItem
            setTitleView:[objc_getClass("TFNTitleView")
                             titleViewWithTitle:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
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

    NSArray<NSString*>* titleKeys = PFBDarkModeStyleKeys();
    NSInteger current = [PFBSettings integerForKey:@"dark_mode_style"];

    PFBAppearanceSettingsViewController* page = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        [self addOption:[bundle localizedStringForKey:titleKeys[i]]
               selected:(i == current)
               toPicker:sheet
                handler:^{
                    [page chooseDarkModeStyle:i];
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

    NSArray<NSString*>* titleKeys = PFBInterfaceStyleKeys();
    NSInteger current = PFBInterfaceStyleCurrent();

    PFBAppearanceSettingsViewController* page = self;
    for (NSInteger i = 0; i < (NSInteger)titleKeys.count; i++) {
        [self addOption:[bundle localizedStringForKey:titleKeys[i]]
               selected:(i == current)
               toPicker:sheet
                handler:^{
                    [page chooseInterfaceStyle:i];
                }];
    }

    [sheet addAction:[UIAlertAction
                         actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [self presentViewController:sheet animated:YES completion:nil];
}

// Picking the shade already in use changes nothing to restart for.
- (void)chooseDarkModeStyle:(NSInteger)shade {
    if (shade == [PFBSettings integerForKey:@"dark_mode_style"]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setInteger:shade forKey:@"dark_mode_style"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (self.inSheet) {
        [self refreshRowsInPlace];
    }
    [self showRestartRequiredAlert];
}

- (void)chooseInterfaceStyle:(NSInteger)style {
    BOOL wasEnabled = [PFBSettings boolForKey:@"enable_liquid_glass"];
    BOOL nowEnabled = (style == 1);
    if (nowEnabled && wasEnabled && !PFBNativeGlassAsked()) {
        PFBCompatMeasure(@"visual style", @"Liquid Glass chosen again during its safe mode: no restart asked", 2);
    }
    [[NSUserDefaults standardUserDefaults] setBool:nowEnabled forKey:@"enable_liquid_glass"];
    if (nowEnabled) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PFBNativeGlassEarlyExitsKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (self.inSheet) {
        [self refreshRowsInPlace];
    }
    if (wasEnabled != nowEnabled) {
        [self showRestartRequiredAlert];
    }
}

// The pickers' choices in a menu that marks the current one.
- (UIMenu*)menuTitled:(NSString*)titleKey
              choices:(NSArray<NSString*>*)choiceKeys
              current:(NSInteger)current
               choose:(void (^)(NSInteger choice))choose {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    for (NSInteger choice = 0; choice < (NSInteger)choiceKeys.count; choice++) {
        UIAction* action = [UIAction actionWithTitle:[bundle localizedStringForKey:choiceKeys[(NSUInteger)choice]]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction* chosen) {
                                                 choose(choice);
                                             }];
        action.state = choice == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:[bundle localizedStringForKey:titleKey] children:actions];
}

- (UIMenu*)interfaceStyleMenu {
    __weak typeof(self) weakSelf = self;
    return [self menuTitled:@"INTERFACE_STYLE_TITLE"
                    choices:PFBInterfaceStyleKeys()
                    current:PFBInterfaceStyleCurrent()
                     choose:^(NSInteger choice) {
                         [weakSelf chooseInterfaceStyle:choice];
                     }];
}

- (UIMenu*)darkModeStyleMenu {
    __weak typeof(self) weakSelf = self;
    return [self menuTitled:@"DARK_MODE_STYLE_TITLE"
                    choices:PFBDarkModeStyleKeys()
                    current:[PFBSettings integerForKey:@"dark_mode_style"]
                     choose:^(NSInteger choice) {
                         [weakSelf chooseDarkModeStyle:choice];
                     }];
}

#pragma mark - Tab Bar Refresh

- (void)refreshAllTabViewsWithImages:(BOOL)images {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsInView:window.rootViewController.view images:images];
        }
    }
}

// Every tab of the bar redraws its label and layout; with `images`, its image and its
// minimized badge too.
- (void)refreshTabViewsInView:(UIView*)view images:(BOOL)images {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        if (images && [view respondsToSelector:@selector(_t1_updateImageViewAnimated:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(view, @selector(_t1_updateImageViewAnimated:), NO);
        }
        if ([view respondsToSelector:@selector(_t1_layoutForTabBar)]) {
            [view performSelector:@selector(_t1_layoutForTabBar)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }
        if (images && [view respondsToSelector:@selector(_t1_layoutBadgeViewMinimized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMinimized)];
        }

    }

    for (UIView* subview in view.subviews) {
        [self refreshTabViewsInView:subview images:images];
    }
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"tab_bar_theming"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViewsWithImages:YES];
        });
    } else if ([key isEqualToString:@"restore_tab_labels"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViewsWithImages:NO];
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
    if (self.account && !self.nativeLook) {
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
    if (self.account && !self.nativeLook) {
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
