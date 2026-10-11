// The accent color picker, cloned from the app's ColorThemePickerItem.

#import "Features/Appearance/ThemeColor/PFBColorThemeViewController.h"
#import <UIKit/UIKit.h>
#import "Features/Appearance/ThemeColor/PFBColorSwatchControl.h"

extern void PFBWhitenNavigationBarConfirm(UINavigationBar* bar);

#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/TWHeaders.h"
#import "Support/HookHelpers.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
extern void PFBBeginRawPaletteRead(void);
extern void PFBEndRawPaletteRead(void);
extern void PFBSyncAccentTheme(void);

// Mirrors PFBCurrentAccentColor's precedence (the custom override, then Twitter's own
// option) so the default swatch shows selected before any change.
static NSInteger CurrentSelectedColorOption(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"pfb_color_theme_selectedColor"]) {
        return [defaults integerForKey:@"pfb_color_theme_selectedColor"];
    }
    // 0 means "no explicit pick": Twitter sits on its own default, so no swatch
    // is highlighted and the window tint is left alone.
    return [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
}

enum { kAccentOptionCount = 6 };

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

    // Twitter's palette colors re-resolve on every trait or window-tint change and
    // go through the accent hooks again, without the raw-read guard. Light and dark
    // are frozen here into a local provider that never touches the palette again.
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

// Glass-mode controls resolve their accent from the primary color option index,
// natively in Swift, and never reach the palette hooks. A custom color therefore
// travels as the nearest option, or those surfaces fall back to blue.
static NSInteger NearestAccentOption(UIColor* color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        return 1;
    }
    NSInteger best = 1;
    CGFloat bestDistance = CGFLOAT_MAX;
    PFBBeginRawPaletteRead();
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
    PFBEndRawPaletteRead();
    return best;
}

@interface PFBColorThemeViewController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) NSMutableArray<PFBColorSwatchControl*>* swatches;
@property (nonatomic, strong) PFBColorSwatchControl* customSwatch;
@end

@implementation PFBColorThemeViewController

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    detail.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
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
    PFBBeginRawPaletteRead();
    UIStackView* currentRow = nil;
    for (NSUInteger option = 1; option <= kAccentOptionCount; option++) {
        if ((option - 1) % 3 == 0) {
            currentRow = [[UIStackView alloc] init];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            currentRow.spacing = 12;
            [grid addArrangedSubview:currentRow];
        }
        PFBColorSwatchControl* swatch = [[PFBColorSwatchControl alloc] init];
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
    PFBEndRawPaletteRead();

    // The same pill and radio control as the six options above: neutral gray and
    // unchecked until a custom color is active, then wearing that color like any
    // other swatch.
    PFBColorSwatchControl* customSwatch = [[PFBColorSwatchControl alloc] init];
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
    customHint.text = [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_CUSTOM_HINT"];
    customHint.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    customHint.textColor = [UIColor secondaryLabelColor];
    customHint.numberOfLines = 0;
    customHint.userInteractionEnabled = NO;
    [self.view addSubview:customHint];
    UIButton* resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [resetButton setTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"THEME_RESET_TITLE"]
                 forState:UIControlStateNormal];
    // An outlined pill in neutral colors, so it never competes with the accent
    // swatches it resets.
    resetButton.titleLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    [resetButton setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    resetButton.backgroundColor = [UIColor systemBackgroundColor];
    resetButton.layer.cornerRadius = 20;
    resetButton.layer.borderWidth = 1.0;
    resetButton.layer.borderColor = [UIColor systemGray4Color].CGColor;
    resetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    resetButton.clipsToBounds = YES;
    [resetButton addTarget:self
                    action:@selector(resetToDefaultColor)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:resetButton];

    UILabel* resetHint = [UILabel new];
    resetHint.translatesAutoresizingMaskIntoConstraints = NO;
    resetHint.text = [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_RESET_HINT"];
    resetHint.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
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
            constraintEqualToAnchor:((PFBColorSwatchControl*)self.swatches.firstObject).widthAnchor],

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

// MARK: - Reset

- (void)resetToDefaultColor {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    // Clears every override so nothing declares an accent: the custom hex, the
    // picked option and Twitter's own stored option. With all three gone the window
    // tint is cleared and every swatch is left unselected.
    [defaults setBool:NO forKey:@"pfb_custom_is_active"];
    [defaults removeObjectForKey:@"pfb_custom_accent_hex"];
    [defaults removeObjectForKey:@"pfb_color_theme_selectedColor"];
    [defaults removeObjectForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    // Mark an explicit reset: fresh-install and post-reset share the same (empty)
    // key state, but reset must revert to native while fresh install defaults to
    // Twitter blue. PFBAccentIsActive reads this flag to tell the two apart.
    [defaults setBool:YES forKey:@"pfb_color_reset_done"];
    // A reset means "no accent": turn the three accent toggles OFF too, so the
    // toggle UI matches the reverted-to-native state (Selected tab, Switches,
    // Twitter icon).
    [defaults setBool:NO forKey:@"tab_bar_theming"];
    [defaults setBool:NO forKey:@"color_pfb_switches"];
    [defaults setBool:NO forKey:@"color_twitter_icon_in_top_bar"];
    [defaults synchronize];

    // 0 is Twitter's own default option, not the Blue swatch.
    id colorSettings = [objc_getClass("TAEColorSettings") sharedSettings];
    if ([colorSettings respondsToSelector:@selector(setPrimaryColorOption:)]) {
        [colorSettings setPrimaryColorOption:0];
    }

    PFBSyncAccentTheme();
    [self refreshSelection];
}

// MARK: - Visibility

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBThemeScreenEnter(self);
    // Returning to this screen triggers no bar layout and no refreshSelection, so a
    // glyph baked dark meanwhile stays dark. One pass now, and one more after the
    // transition has rebuilt the bar item.
    PFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    dispatch_async(dispatch_get_main_queue(), ^{
        PFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    });
}

// Leaving this screen does not relayout the timeline, so the accent is synced
// again here; otherwise a new color reaches the bird and the tab bar only at the
// next tab change.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
    PFBSyncAccentTheme();
}

// MARK: - Selection

- (void)refreshSelection {
    BOOL customActive = [[NSUserDefaults standardUserDefaults] boolForKey:@"pfb_custom_is_active"];
    NSInteger selected = CurrentSelectedColorOption();
    for (PFBColorSwatchControl* swatch in self.swatches) {
        BOOL isSelected = !customActive && (swatch.colorID == selected);
        [swatch setSwatchSelected:isSelected];
    }
    UIColor* customColor = PFBCustomAccentColor();
    if (customActive && customColor) {
        [self.customSwatch setSwatchColor:customColor];
    } else {
        [self.customSwatch setSwatchNeutral];
    }
    [self.customSwatch setSwatchSelected:customActive];
    // Twitter re-bakes the confirm glyph on the run loop after the accent notifications, so
    // the white bake runs now and once more next turn.
    PFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    dispatch_async(dispatch_get_main_queue(), ^{
        PFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    });
}

- (void)swatchTapped:(PFBColorSwatchControl*)swatch {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"pfb_custom_is_active"];
    [[NSUserDefaults standardUserDefaults] setInteger:swatch.colorID
                                               forKey:@"pfb_color_theme_selectedColor"];
    changeTwitterColor(swatch.colorID);
    PFBSyncAccentTheme();

    [self refreshSelection];
}

// MARK: - Custom color

- (void)openColorPicker {
    UIColorPickerViewController* picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    UIColor* existing = PFBCustomAccentColor();
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
    [NSUserDefaults.standardUserDefaults setObject:hex forKey:@"pfb_custom_accent_hex"];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"pfb_custom_is_active"];
    NSInteger nearest = NearestAccentOption(color);
    [NSUserDefaults.standardUserDefaults setInteger:nearest forKey:@"pfb_color_theme_selectedColor"];
    changeTwitterColor(nearest);
    PFBSyncAccentTheme();
    [self refreshSelection];
}

@end
