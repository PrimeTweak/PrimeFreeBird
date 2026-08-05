//
//  ColorThemeViewController.m
//  PrimeFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//  Modified by actuallyaridan on 25/05/2025.
//
//  Clones the native accent picker (ColorThemePickerItem).
//

#import "ColorThemeViewController.h"
#import <UIKit/UIKit.h>
#import "ColorSwatchControl.h"

extern NSInteger NFBColorThemeScreenVisible;
extern void NFBWhitenNavigationBarConfirm(UINavigationBar* bar);

// Defined in Branding.x; tagging the confirm glyph routes Twitter's re-bakes
// through the whitening setImage: hook there.
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"
extern void NFBBeginRawPaletteRead(void);
extern void NFBEndRawPaletteRead(void);
extern void NFBSyncAccentTheme(void);

// Mirrors CurrentAccentColor's precedence (our override, then Twitter's own
// option) so the default swatch shows selected before any change.
static NSInteger CurrentSelectedColorOption(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
        return [defaults integerForKey:@"bh_color_theme_selectedColor"];
    }
    // 0 means "no explicit pick": Twitter sits on its own default, so no swatch
    // is highlighted and the window tint is left alone.
    return [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
}

// The accent picker ships no localized colour names, so the swatches borrow the
// Fleets accessibility labels for the same six colours.
static const NSUInteger kAccentOptionCount = 6;

// Human-readable names shown inside the pills.
static NSString* const kAccentDisplayNames[kAccentOptionCount] = {@"Blue", @"Yellow", @"Red",
                                                                  @"Purple", @"Orange", @"Green"};
static UIColor* NativeAccentColor(NSUInteger option) {
    id palette =
        [[[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette] colorPalette];
    UIColor* color = [palette primaryColorForOption:option];
    if (![color isKindOfClass:[UIColor class]]) {
        return nil;
    }

    // Twitter's palette colours are DYNAMIC: they re-resolve on every trait or
    // window-tint change, going through our accent hooks again — without the
    // raw-read guard. That repainted every swatch with the custom accent the
    // moment a colour was picked. Freeze light and dark NOW (guard is up here)
    // into a local provider that never touches the palette again.
    UIColor* lightC = [color
        resolvedColorWithTraitCollection:
            [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]];
    UIColor* darkC = [color
        resolvedColorWithTraitCollection:
            [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? darkC : lightC;
    }];
}

// Glass-mode controls resolve their accent from the primary colour OPTION
// index, natively in Swift — they never reach our palette hooks. A custom
// colour therefore has to travel as the option that looks closest to it,
// otherwise those surfaces fall back to blue (option 1).
static NSInteger NearestAccentOption(UIColor* color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        return 1;
    }
    NSInteger best = 1;
    CGFloat bestDistance = CGFLOAT_MAX;
    NFBBeginRawPaletteRead();
    for (NSInteger option = 1; option <= (NSInteger)kAccentOptionCount; option++) {
        UIColor* native = [NativeAccentColor(option)
            resolvedColorWithTraitCollection:UITraitCollection.currentTraitCollection];
        CGFloat nr = 0, ng = 0, nb = 0, na = 0;
        if (!native || ![native getRed:&nr green:&ng blue:&nb alpha:&na]) {
            continue;
        }
        CGFloat d = (r - nr) * (r - nr) + (g - ng) * (g - ng) + (b - nb) * (b - nb);
        if (d < bestDistance) {
            bestDistance = d;
            best = option;
        }
    }
    NFBEndRawPaletteRead();
    return best;
}

// Forward declaration: defined lower in the file, used earlier in viewDidLoad.
static UIColor* customAccentColorFromDefaults(void);

@interface ColorThemeViewController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) UIButton* resetButton;
@property (nonatomic, strong) ColorSwatchControl* customSwatch;
@end

@implementation ColorThemeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [Palette currentBackgroundColor];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    detail.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;
    [self.view addSubview:detail];
// 3×2 grid of color pills (Blue/Yellow/Red · Purple/Orange/Green).
    UIStackView* grid = [[UIStackView alloc] init];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.distribution = UIStackViewDistributionFillEqually;
    grid.spacing = 16;
    [self.view addSubview:grid];

    self.swatches = [NSMutableArray new];
    NFBBeginRawPaletteRead();
    UIStackView* currentRow = nil;
    for (NSUInteger option = 1; option <= kAccentOptionCount; option++) {
        if ((option - 1) % 3 == 0) {
            currentRow = [[UIStackView alloc] init];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            currentRow.spacing = 12;
            [grid addArrangedSubview:currentRow];
        }
        ColorSwatchControl* swatch = [[ColorSwatchControl alloc] init];
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        swatch.colorID = option;
        swatch.isAccessibilityElement = YES;
        swatch.accessibilityLabel = kAccentDisplayNames[option - 1];
        [swatch setSwatchColor:NativeAccentColor(option)];
        [swatch setSwatchName:kAccentDisplayNames[option - 1]];
        [swatch addTarget:self
                     action:@selector(swatchTapped:)
           forControlEvents:UIControlEventTouchUpInside];
        [currentRow addArrangedSubview:swatch];
        [self.swatches addObject:swatch];
    }
    NFBEndRawPaletteRead();

    // "Custom": the exact same pill+radio control as the six options above —
    // neutral grey and unchecked until a custom colour is actually active,
    // then it wears that colour like any other swatch. (His requests: after a
    // reset it must look colourless, match the other pills' size, and carry a
    // real selection circle.)
    ColorSwatchControl* customSwatch = [[ColorSwatchControl alloc] init];
    customSwatch.translatesAutoresizingMaskIntoConstraints = NO;
    customSwatch.colorID = -1;
    customSwatch.isAccessibilityElement = YES;
    customSwatch.accessibilityLabel = @"Custom";
    [customSwatch setSwatchName:@"Custom"];
    [customSwatch addTarget:self
                     action:@selector(openColorPicker)
           forControlEvents:UIControlEventTouchUpInside];
    self.customSwatch = customSwatch;
    [self.view addSubview:customSwatch];

    UILabel* customHint = [UILabel new];
    customHint.translatesAutoresizingMaskIntoConstraints = NO;
    customHint.text = @"Pick any color for links, buttons, and highlights.";
    customHint.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    customHint.textColor = [UIColor secondaryLabelColor];
    customHint.numberOfLines = 0;
    customHint.userInteractionEnabled = NO;
    [self.view addSubview:customHint];
    UIButton* resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton setTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"THEME_RESET_TITLE"]
                 forState:UIControlStateNormal];
    // A filled pill, matching the swatch pills above rather than sitting there
    // as loose text. Neutral fill so it never competes with the accent colours
    // it resets.
    resetButton.titleLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15];
    [resetButton setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    // Quiet, but still a button: a soft fill keeps the pill shape without
    // competing with the swatches above it.
    resetButton.backgroundColor = [UIColor systemBackgroundColor];
    resetButton.layer.cornerRadius = 20;
    resetButton.layer.borderWidth = 1.0;
    resetButton.layer.borderColor = [UIColor systemGray4Color].CGColor;
    resetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    resetButton.clipsToBounds = YES;
    [resetButton addTarget:self
                    action:@selector(resetToDefaultColor)
          forControlEvents:UIControlEventTouchUpInside];
    self.resetButton = resetButton;
    [self.view addSubview:resetButton];

    UILabel* resetHint = [UILabel new];
    resetHint.translatesAutoresizingMaskIntoConstraints = NO;
    resetHint.text = @"Removes the accent color and restores the default appearance.";
    resetHint.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    resetHint.textColor = [UIColor secondaryLabelColor];
    resetHint.numberOfLines = 0;
    resetHint.textAlignment = NSTextAlignmentNatural;
    resetHint.userInteractionEnabled = NO;
    [self.view addSubview:resetHint];

    [NSLayoutConstraint activateConstraints:@[
        [detail.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                         constant:16],
        [detail.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [grid.topAnchor constraintEqualToAnchor:detail.bottomAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [grid.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [customSwatch.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:28],
        [customSwatch.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        // Same width as a grid pill — anchored to the first one, so the two
        // can never drift apart.
        [customSwatch.widthAnchor
            constraintEqualToAnchor:((ColorSwatchControl*)self.swatches.firstObject).widthAnchor],

        // The hint sits beside the PILL half of the control (its top 40pt),
        // not the radio circle below it.
        [customHint.leadingAnchor constraintEqualToAnchor:customSwatch.trailingAnchor constant:14],
        [customHint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [customHint.centerYAnchor constraintEqualToAnchor:customSwatch.topAnchor constant:20],

        [resetButton.topAnchor constraintEqualToAnchor:customSwatch.bottomAnchor constant:28],
        [resetButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [resetButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                   constant:-16],
        [resetButton.heightAnchor constraintEqualToConstant:40],

        [resetHint.topAnchor constraintEqualToAnchor:resetButton.bottomAnchor constant:12],
        [resetHint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [resetHint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]
    ]];

    [self refreshSelection];
}

#pragma mark - Selection

- (void)resetToDefaultColor {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    // Clear every override so NOTHING declares an accent any more: the custom
    // hex, our picked option, and Twitter's own stored option. With all three
    // gone the window tint is cleared, which is what puts iOS controls (the
    // Confirm button top right) back on the system blue, and leaves every
    // swatch unselected.
    [defaults setBool:NO forKey:@"bh_custom_is_active"];
    [defaults removeObjectForKey:@"bh_custom_accent_hex"];
    [defaults removeObjectForKey:@"bh_color_theme_selectedColor"];
    [defaults removeObjectForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    // Mark an explicit reset: fresh-install and post-reset share the same (empty)
    // key state, but reset must revert to native while fresh install defaults to
    // Twitter blue. NFBAccentIsActive reads this flag to tell the two apart.
    [defaults setBool:YES forKey:@"nfb_color_reset_done"];
    // A reset means "no accent": turn the three accent toggles OFF too, so the
    // toggle UI matches the reverted-to-native state (Selected tab, Switches,
    // Twitter icon).
    [defaults setBool:NO forKey:@"tab_bar_theming"];
    [defaults setBool:NO forKey:@"color_nfb_switches"];
    [defaults setBool:NO forKey:@"color_twitter_icon_in_top_bar"];
    [defaults synchronize];

    // 0 is Twitter's own default option, not our blue swatch.
    id colorSettings = [objc_getClass("TAEColorSettings") sharedSettings];
    if ([colorSettings respondsToSelector:@selector(setPrimaryColorOption:)]) {
        [colorSettings setPrimaryColorOption:0];
    }

    NFBSyncAccentTheme();
    [self refreshSelection];
    [self reapplyTabBarAccent];
}

// Coming back from this screen does not relayout the timeline, so a colour
// picked here only reached the bird and the tab bar on the next tab change.
// Re-running the sync once we are off-screen catches them while they are.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NFBColorThemeScreenVisible++;
    // Returning to this screen triggers no bar layout and no refreshSelection,
    // so a dark glyph Twitter baked while we were away stayed dark — his BLACK
    // check on return, yellow only. Pass now, and once more after the
    // transition has rebuilt the bar item.
    NFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (NFBColorThemeScreenVisible > 0) {
        NFBColorThemeScreenVisible--;
    }
    NFBSyncAccentTheme();
}

- (void)refreshSelection {
    BOOL customActive = [[NSUserDefaults standardUserDefaults] boolForKey:@"bh_custom_is_active"];
    NSInteger selected = CurrentSelectedColorOption();
    for (ColorSwatchControl* swatch in self.swatches) {
        BOOL isSelected = !customActive && (swatch.colorID == selected);
        [swatch setSwatchSelected:isSelected];
    }
    UIColor* customColor = customAccentColorFromDefaults();
    if (customActive && customColor) {
        [self.customSwatch setSwatchColor:customColor];
    } else {
        [self.customSwatch setSwatchNeutral];
    }
    [self.customSwatch setSwatchSelected:customActive];
    // Always available: reset is NOT the same thing as the blue swatch — blue
    // is an ACTIVE accent (blue bird, blue tabs), reset restores the fully
    // native look (black chrome, iOS-blue confirm). His request.
    self.resetButton.hidden = NO;
    // Twitter re-bakes the confirm glyph on the runloop AFTER our colour
    // notifications; run the white-bake now and once more next turn so the
    // fresh dark bake never reaches the screen.
    NFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    });
}

- (void)swatchTapped:(ColorSwatchControl*)swatch {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"bh_custom_is_active"];
    [[NSUserDefaults standardUserDefaults] setInteger:swatch.colorID
                                               forKey:@"bh_color_theme_selectedColor"];
    changeTwitterColor(swatch.colorID);
    NFBSyncAccentTheme();

    [self refreshSelection];
    [self reapplyTabBarAccent];
}

#pragma mark - Reset

// Re-tint the live tab bar icons to the new accent.
- (void)reapplyTabBarAccent {
    Class t1TabBarVCClass = NSClassFromString(@"T1TabBarViewController");
    if (!t1TabBarVCClass) return;

    UIWindow* window = nil;
    for (UIWindowScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            if ([scene.delegate respondsToSelector:@selector(window)]) {
                window = [(id)scene.delegate window];
            } else {
                for (UIWindow* w in [(id)scene windows]) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
            }
            if (window) break;
        }
    }
    if (!window) return;

    NSMutableArray* stack = [NSMutableArray arrayWithObject:window.rootViewController];
    while (stack.count) {
        UIViewController* vc = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([vc isKindOfClass:t1TabBarVCClass] && [vc respondsToSelector:@selector(tabViews)]) {
            for (id tab in [vc valueForKey:@"tabViews"]) {
                if ([tab respondsToSelector:@selector(applyCurrentThemeToIcon)]) {
                    [tab performSelector:@selector(applyCurrentThemeToIcon)];
                }
            }
        }
        if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
        if ([vc isKindOfClass:[UINavigationController class]])
            [stack addObjectsFromArray:((UINavigationController*)vc).viewControllers];
        if ([vc isKindOfClass:[UITabBarController class]])
            [stack addObjectsFromArray:((UITabBarController*)vc).viewControllers];
        [stack addObjectsFromArray:vc.childViewControllers];
    }
}

static UIColor* customAccentColorFromDefaults(void) {
    NSString* hex = [NSUserDefaults.standardUserDefaults objectForKey:@"bh_custom_accent_hex"];
    if (![hex isKindOfClass:[NSString class]] || hex.length < 6) {
        return nil;
    }
    unsigned int rgb = 0;
    NSScanner* scanner = [NSScanner scannerWithString:hex];
    [scanner setScanLocation:[hex hasPrefix:@"#"] ? 1 : 0];
    if (![scanner scanHexInt:&rgb]) {
        return nil;
    }
    return [UIColor colorWithRed:((rgb & 0xFF0000) >> 16) / 255.0
                           green:((rgb & 0x00FF00) >> 8) / 255.0
                            blue:(rgb & 0x0000FF) / 255.0
                           alpha:1.0];
}

- (void)openColorPicker {
    UIColorPickerViewController* picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    UIColor* existing = customAccentColorFromDefaults();
    if (existing) {
        picker.selectedColor = existing;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController*)viewController {
    UIColor* color = viewController.selectedColor;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSString* hex = [NSString stringWithFormat:@"%02X%02X%02X",
                     (int)(r * 255), (int)(g * 255), (int)(b * 255)];
    [NSUserDefaults.standardUserDefaults setObject:hex forKey:@"bh_custom_accent_hex"];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"bh_custom_is_active"];
    NSInteger nearest = NearestAccentOption(color);
    [NSUserDefaults.standardUserDefaults setInteger:nearest forKey:@"bh_color_theme_selectedColor"];
    changeTwitterColor(nearest);
    NFBSyncAccentTheme();
    [self refreshSelection];
    [self reapplyTabBarAccent];
}

@end
