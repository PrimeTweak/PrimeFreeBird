// The accent color picker, laid out like Twitter's own color picker.

#import "Features/Appearance/ThemeColor/PFBColorThemeViewController.h"
#import <UIKit/UIKit.h>
#import "Features/Appearance/ThemeColor/PFBColorSwatchControl.h"

extern void PFBWhitenNavigationBarConfirm(UINavigationBar* bar);

#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/TWHeaders.h"
#import "Support/HookHelpers.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Features/Appearance/ThemeColor/PFBAccentPreviewView.h"
#import "Common/PFBSettings.h"
#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Debug/PFBDebugger.h"
#import "Support/PFBTwitterPopups.h"
extern void PFBBeginRawPaletteRead(void);
extern void PFBEndRawPaletteRead(void);
extern BOOL PFBAccentIsActive(void);

// A color as #RRGGBB in the given appearance, or "none".
static NSString* PFBResetProbeHex(id color, UITraitCollection* traits) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color isKindOfClass:[UIColor class]] ||
        ![[color resolvedColorWithTraitCollection:traits] getRed:&r green:&g blue:&b alpha:&a]) {
        return @"none";
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(MIN(MAX(r, 0.0), 1.0) * 255.0),
                                      (int)lround(MIN(MAX(g, 0.0), 1.0) * 255.0),
                                      (int)lround(MIN(MAX(b, 0.0), 1.0) * 255.0)];
}

// Writes to the debug journal, under [theme-reset], what Reset to default leaves: the stored keys,
// Twitter's option and colors, raw and as the app gets them, the accent the tweak derives, and
// every stored key naming a color.
static void PFBResetProbe(NSString* stage, UITraitCollection* traits) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    Class settingsClass = objc_getClass("TAEColorSettings");
    id settings = [settingsClass respondsToSelector:@selector(sharedSettings)] ? [settingsClass sharedSettings] : nil;
    SEL optionGetter = NSSelectorFromString(@"primaryColorOption");
    NSInteger option = [settings respondsToSelector:optionGetter]
                           ? ((NSInteger (*)(id, SEL))objc_msgSend)(settings, optionGetter)
                           : -1;
    id current = [settings respondsToSelector:@selector(currentColorPalette)] ? [settings currentColorPalette] : nil;
    id palette = [current respondsToSelector:@selector(colorPalette)] ? [current colorPalette] : nil;
    BOOL hasPrimary = [palette respondsToSelector:@selector(primaryColor)];
    BOOL hasOptions = [palette respondsToSelector:@selector(primaryColorForOption:)];
    NSMutableString* options = [NSMutableString string];
    PFBBeginRawPaletteRead();
    UIColor* raw = hasPrimary ? ((UIColor * (*)(id, SEL)) objc_msgSend)(palette, @selector(primaryColor)) : nil;
    for (NSUInteger i = 0; i <= 7; i++) {
        UIColor* color = hasOptions ? [palette primaryColorForOption:i] : nil;
        [options appendFormat:@" %lu=%@", (unsigned long)i, PFBResetProbeHex(color, traits)];
    }
    PFBEndRawPaletteRead();
    UIColor* used = hasPrimary ? ((UIColor * (*)(id, SEL)) objc_msgSend)(palette, @selector(primaryColor)) : nil;
    PFBDebugLog(@"[theme-reset] %@: custom=%d hex=%@ pick=%@ twitterKey=%@ resetDone=%d option=%ld active=%d raw=%@ "
                @"used=%@ brand=%@ current=%@ options:%@",
                stage, [defaults boolForKey:@"pfb_custom_is_active"],
                [defaults objectForKey:@"pfb_custom_accent_hex"] ?: @"none",
                [defaults objectForKey:@"pfb_color_theme_selectedColor"] ?: @"none",
                [defaults objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"] ?: @"none",
                [defaults boolForKey:@"pfb_color_reset_done"], (long)option, PFBAccentIsActive(),
                PFBResetProbeHex(raw, traits), PFBResetProbeHex(used, traits),
                PFBResetProbeHex(PFBBrandAccentColor(), traits), PFBResetProbeHex(PFBCurrentAccentColor(), traits),
                options);
    NSMutableArray<NSString*>* keys = [NSMutableArray array];
    [[defaults dictionaryRepresentation] enumerateKeysAndObjectsUsingBlock:^(NSString* key, id value, __unused BOOL* stop) {
      NSString* lower = key.lowercaseString;
      BOOL named = [lower containsString:@"color"] || [lower containsString:@"accent"];
      BOOL plain = [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]];
      if (named && plain && keys.count < 40) {
          [keys addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
      }
    }];
    [keys sortUsingSelector:@selector(compare:)];
    PFBDebugLog(@"[theme-reset] %@ keys: %@", stage, [keys componentsJoinedByString:@" "]);
}

// Mirrors PFBCurrentAccentColor's precedence: the stored pick, then Twitter's own option.
static NSInteger CurrentSelectedColorOption(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"pfb_color_theme_selectedColor"]) {
        return [defaults integerForKey:@"pfb_color_theme_selectedColor"];
    }
    // 0 means "no explicit pick": Twitter sits on its own default, so no swatch
    // is highlighted.
    return [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
}

enum { kAccentOptionCount = 6 };

// The names inside the pills, in Twitter's words from its own color settings.
static NSString* const kAccentNameKeys[kAccentOptionCount] = {
    @"SETTINGS_DISPLAY_COLOR_BLUE",   @"SETTINGS_DISPLAY_COLOR_YELLOW", @"SETTINGS_DISPLAY_COLOR_RED",
    @"SETTINGS_DISPLAY_COLOR_PURPLE", @"SETTINGS_DISPLAY_COLOR_ORANGE", @"SETTINGS_DISPLAY_COLOR_GREEN"};
static UIColor* NativeAccentColor(NSUInteger option) {
    id palette =
        [[[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette] colorPalette];
    UIColor* color = [palette respondsToSelector:@selector(primaryColorForOption:)]
                         ? [palette primaryColorForOption:option]
                         : nil;
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
@property (nonatomic, strong) UIButton* resetButton;
// The new look's page: its line, the sample on its card, the colors with the chosen one's name,
// and Reset to default at the bottom.
@property (nonatomic, strong) UIScrollView* nativeScroll;
@property (nonatomic, strong) UILabel* introLabel;
@property (nonatomic, strong) UIView* previewCard;
@property (nonatomic, strong) PFBAccentPreviewView* preview;
@property (nonatomic, strong) UILabel* colorName;
@property (nonatomic, strong) PFBShowcaseButton* resetCapsule;
@end

@implementation PFBColorThemeViewController

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    if (self.nativeLook) {
        [self buildNativeLook];
        [self refreshSelection];
        return;
    }

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    detail.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;
    [self.view addSubview:detail];
    // Two rows of three color pills (Blue/Yellow/Red, Purple/Orange/Green).
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
        NSString* name = [[PFBBundle sharedBundle] localizedTwitterStringForKey:kAccentNameKeys[option - 1]];
        swatch.accessibilityLabel = name;
        [swatch setSwatchColor:NativeAccentColor(option)];
        [swatch setSwatchName:name];
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
    NSString* customName = [[PFBBundle sharedBundle] localizedStringForKey:@"THEME_CUSTOM_NAME"];
    customSwatch.accessibilityLabel = customName;
    [customSwatch setSwatchName:customName];
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
    resetButton.backgroundColor = [UIColor clearColor];
    resetButton.layer.cornerRadius = 20;
    resetButton.layer.borderWidth = 1.0;
    resetButton.layer.borderColor = [UIColor systemGray4Color].CGColor;
    resetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    resetButton.clipsToBounds = YES;
    [resetButton addTarget:self
                    action:@selector(confirmResetToDefaultColor)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:resetButton];
    self.resetButton = resetButton;

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

// MARK: - New look

// The page scrolls under the bar; Reset to default stays at its bottom.
- (void)buildNativeLook {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIScrollView* scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    self.nativeScroll = scroll;

    self.introLabel = PFBShowcaseIntroLabel();
    self.introLabel.text = [bundle localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    self.previewCard = PFBShowcaseCard();
    self.preview = [[PFBAccentPreviewView alloc] init];
    [self.previewCard addSubview:self.preview];
    [scroll addSubview:self.introLabel];
    [scroll addSubview:self.previewCard];

    self.swatches = [NSMutableArray new];
    PFBBeginRawPaletteRead();
    for (NSUInteger option = 1; option <= kAccentOptionCount; option++) {
        PFBColorSwatchControl* swatch = [[PFBColorSwatchControl alloc] initRound];
        swatch.colorID = option;
        swatch.isAccessibilityElement = YES;
        swatch.accessibilityLabel = [bundle localizedTwitterStringForKey:kAccentNameKeys[option - 1]];
        [swatch setSwatchColor:NativeAccentColor(option)];
        [swatch addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:swatch];
        [self.swatches addObject:swatch];
    }
    PFBEndRawPaletteRead();
    PFBColorSwatchControl* custom = [[PFBColorSwatchControl alloc] initRainbow];
    custom.colorID = -1;
    custom.isAccessibilityElement = YES;
    custom.accessibilityLabel = [bundle localizedStringForKey:@"THEME_CUSTOM_NAME"];
    [custom addTarget:self action:@selector(openColorPicker) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:custom];
    self.customSwatch = custom;

    self.colorName = [[UILabel alloc] init];
    self.colorName.textAlignment = NSTextAlignmentCenter;
    self.colorName.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    [scroll addSubview:self.colorName];

    self.resetCapsule = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleOutline];
    self.resetCapsule.label = [bundle localizedStringForKey:@"THEME_RESET_TITLE"];
    [self.resetCapsule addTarget:self
                          action:@selector(confirmResetToDefaultColor)
                forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetCapsule];
    [self applyNativeColors];
}

- (void)applyNativeColors {
    self.view.backgroundColor = [PFBPalette currentBackgroundColor];
    // The capsule floats over the page as it scrolls, so it stands on the page's ground.
    self.resetCapsule.groundColor = self.view.backgroundColor;
    self.introLabel.textColor = PFBSettingsSubtitleColor();
    self.colorName.textColor = PFBSettingsSubtitleColor();
}

// The line, the card, then the seven colors on one row with the chosen one's name under them.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIScrollView* scroll = self.nativeScroll;
    if (!scroll) {
        return;
    }
    CGFloat width = CGRectGetWidth(scroll.bounds);
    CGFloat side = 20.0;
    CGFloat inner = MAX(0, width - 2 * side);
    CGFloat introHeight = ceil([self.introLabel sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    self.introLabel.frame = CGRectMake(side, 12.0, inner, introHeight);
    CGFloat previewHeight = [self.preview sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
    self.previewCard.frame = CGRectMake(side, CGRectGetMaxY(self.introLabel.frame) + 20.0, inner, previewHeight);
    self.preview.frame = self.previewCard.bounds;

    NSArray<PFBColorSwatchControl*>* row = [self.swatches arrayByAddingObject:self.customSwatch];
    CGFloat cell = inner / (CGFloat)row.count;
    CGFloat ring = MIN(54.0, floor(cell - 2.0));
    CGFloat rowY = CGRectGetMaxY(self.previewCard.frame) + 24.0;
    BOOL rtl = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (NSUInteger i = 0; i < row.count; i++) {
        NSUInteger slot = rtl ? row.count - 1 - i : i;
        row[i].frame = CGRectMake(side + cell * (CGFloat)slot + (cell - ring) / 2.0, rowY, ring, ring);
    }
    self.colorName.frame = CGRectMake(side, rowY + ring + 8.0, inner, ceil(self.colorName.font.lineHeight));
    scroll.contentSize = CGSizeMake(width, CGRectGetMaxY(self.colorName.frame) + 24.0);

    // Above Twitter's tab bar when it shows; the page scrolls clear of the capsule.
    CGFloat capsuleHeight = [self.resetCapsule sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
    CGFloat capsuleY = PFBShowcaseBottomLimit(self.view) - 16.0 - capsuleHeight;
    self.resetCapsule.frame = CGRectMake(side, capsuleY, inner, capsuleHeight);
    UIEdgeInsets insets = scroll.contentInset;
    insets.bottom = MAX(0, CGRectGetMaxY(self.view.bounds) - self.view.safeAreaInsets.bottom - capsuleY + 12.0);
    if (fabs(insets.bottom - scroll.contentInset.bottom) > 0.5) {
        scroll.contentInset = insets;
    }
}

// Twitter's tab bar settles once the page is in: the capsule is placed again then.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view setNeedsLayout];
}

// The ground and the gray lines are palette colors, read again when light and dark switch.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.resetButton.layer.borderColor =
        [[UIColor systemGray4Color] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    if (self.nativeScroll &&
        [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self applyNativeColors];
        [self refreshSelection];
    }
}

// MARK: - Reset

// The reset also turns off Selected tab, Switches and Twitter icon, so it asks first.
- (void)confirmResetToDefaultColor {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* confirm =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"THEME_RESET_CONFIRM_TITLE"]
                                            message:[bundle localizedStringForKey:@"THEME_RESET_CONFIRM_MESSAGE"]
                                     preferredStyle:UIAlertControllerStyleAlert];
    PFBAlertAddAction(confirm, [bundle localizedStringForKey:@"CANCEL_ACTION"], UIAlertActionStyleCancel, self.nativeLook,
                      nil);
    __weak typeof(self) weakSelf = self;
    PFBAlertAddAction(confirm, [bundle localizedStringForKey:@"THEME_RESET_ACTION"], UIAlertActionStyleDestructive,
                      self.nativeLook, ^{
                          [weakSelf resetToDefaultColor];
                      });
    PFBAlertPresent(confirm, self, self.nativeLook, nil);
}

- (void)resetToDefaultColor {
    UITraitCollection* traits = self.traitCollection;
    PFBResetProbe(@"before", traits);
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
    PFBResetProbe(@"after", traits);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBResetProbe(@"after 1 s", traits);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PFBResetProbe(@"after 3 s", traits);
    });
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
    if (self.nativeScroll) {
        [self refreshNativeSample:customActive selected:selected];
    }
    // Twitter re-bakes the confirm glyph on the run loop after the accent notifications, so
    // the white bake runs now and once more next turn.
    PFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    dispatch_async(dispatch_get_main_queue(), ^{
        PFBWhitenNavigationBarConfirm(self.navigationController.navigationBar);
    });
}

// The chosen color's name under the row, and the sample in that color.
- (void)refreshNativeSample:(BOOL)customActive selected:(NSInteger)selected {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    if (customActive) {
        self.colorName.text = [bundle localizedStringForKey:@"THEME_CUSTOM_NAME"];
    } else if (selected >= 1 && selected <= (NSInteger)kAccentOptionCount) {
        self.colorName.text = [bundle localizedTwitterStringForKey:kAccentNameKeys[selected - 1]];
    } else {
        self.colorName.text = [bundle localizedStringForKey:@"THEME_DEFAULT_NAME"];
    }
    // VoiceOver hears every color as a button and the chosen one as selected.
    for (PFBColorSwatchControl* swatch in self.swatches) {
        BOOL chosen = !customActive && swatch.colorID == selected;
        swatch.accessibilityTraits = UIAccessibilityTraitButton | (chosen ? UIAccessibilityTraitSelected : 0);
    }
    self.customSwatch.accessibilityTraits = UIAccessibilityTraitButton | (customActive ? UIAccessibilityTraitSelected : 0);
    UIColor* accent = (customActive ? PFBCustomAccentColor() : nil) ?: PFBBrandAccentColor();
    [self.preview applyAccent:accent
             tintsSelectedTab:[PFBSettings boolForKey:@"tab_bar_theming"]
                    tintsLogo:[PFBSettings boolForKey:@"color_twitter_icon_in_top_bar"]];
    [self.view setNeedsLayout];
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

// Called on every step of a drag and once more on release; only the released color is
// applied, since each application pushes the accent through the whole app.
- (void)colorPickerViewController:(UIColorPickerViewController*)viewController
                   didSelectColor:(UIColor*)color
                     continuously:(BOOL)continuously {
    if (continuously) {
        return;
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    // A wide-gamut pick comes back in extended sRGB, outside 0 to 1; the hex holds sRGB.
    r = MIN(MAX(r, 0.0), 1.0);
    g = MIN(MAX(g, 0.0), 1.0);
    b = MIN(MAX(b, 0.0), 1.0);
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
