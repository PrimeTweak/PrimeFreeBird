// Dark mode styles (Dim #15202b, Gray, Pure black), applied by intercepting the
// backgrounds directly rather than recolouring palette getters, which the
// navigation chrome ignores.

#import "Common/PFBCompatibility.h"
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Common/PFBSettings.h"
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import "Support/TAEHeaders.h"

@interface TFNSolidColorView : UIView
- (void)setColor:(UIColor*)color;
@end

@interface TFNSearchBar : UISearchBar
@end

@implementation PFBDarkModeStyle

+ (PFBDarkModeStyleKind)selectedStyle {
    return (PFBDarkModeStyleKind)[PFBSettings integerForKey:@"dark_mode_style"];
}

+ (BOOL)isDarkModeActive {
    Class cls = objc_getClass("TAEColorSettings");
    if (![cls respondsToSelector:@selector(sharedSettings)]) {
        return NO;
    }
    TAEColorSettings* settings = [cls sharedSettings];
    if (![settings respondsToSelector:@selector(currentColorPalette)]) {
        return NO;
    }
    TAETwitterColorPaletteSettingInfo* info = [settings currentColorPalette];
    if ([info respondsToSelector:@selector(isDark)]) {
        return [info isDark];
    }
    return NO;
}

// The three depths dark chrome is drawn at.
typedef NS_ENUM(NSInteger, PFBBackgroundTier) {
    PFBBackgroundTierNone = 0,  // Not background chrome — left alone
    PFBBackgroundTierBase,      // The surface everything sits on
    PFBBackgroundTierElevated,  // Sheets, cards, toasts, incoming bubbles
    PFBBackgroundTierSelected   // Pressed rows, unread, highlighted Tweets
};

// Opaque and achromatic separates background chrome from media, brand cards and
// accents, which carry real hue. Brightness alone cannot tell them apart, so the
// spread between the strongest and weakest component is measured first.
static const CGFloat kPFBChromaAllowance = 0.04;
static const CGFloat kPFBDarkCeiling = 0.22;
static const CGFloat kPFBBaseCeiling = 0.05;
static const CGFloat kPFBElevatedCeiling = 0.14;

static PFBBackgroundTier PFBTierForColor(UIColor* color) {
    if (!color) {
        return PFBBackgroundTierNone;
    }
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        // Grayscale colors answer -getWhite:alpha: and nothing else.
        CGFloat white = 0.0;
        if (![color getWhite:&white alpha:&alpha]) {
            return PFBBackgroundTierNone;
        }
        red = green = blue = white;
    }
    if (alpha <= 0.95) {
        return PFBBackgroundTierNone;
    }
    CGFloat strongest = MAX(red, MAX(green, blue));
    CGFloat weakest = MIN(red, MIN(green, blue));
    if (strongest - weakest > kPFBChromaAllowance || strongest > kPFBDarkCeiling) {
        return PFBBackgroundTierNone;
    }
    if (strongest < kPFBBaseCeiling) {
        return PFBBackgroundTierBase;
    }
    if (strongest < kPFBElevatedCeiling) {
        return PFBBackgroundTierElevated;
    }
    return PFBBackgroundTierSelected;
}

// Component-wise, because two UIColors built from different color spaces are
// never equal to -isEqual: even when they paint the same pixels.
static BOOL PFBColorMatches(UIColor* color, UIColor* shade) {
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    CGFloat shadeRed = 0.0, shadeGreen = 0.0, shadeBlue = 0.0, shadeAlpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha] ||
        ![shade getRed:&shadeRed green:&shadeGreen blue:&shadeBlue
                 alpha:&shadeAlpha]) {
        return NO;
    }
    const CGFloat tolerance = 1.0 / 510.0;
    return fabs(red - shadeRed) < tolerance && fabs(green - shadeGreen) < tolerance &&
           fabs(blue - shadeBlue) < tolerance && fabs(alpha - shadeAlpha) < tolerance;
}

static UIColor* PFBColorWithRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// Each style is a ladder of three shades, spaced by perceived lightness rather than
// raw value, about five points of L* apart. Pure black keeps an exact #000000 base
// and lifts only what sits above it.
+ (UIColor*)shadeForTier:(PFBBackgroundTier)tier style:(PFBDarkModeStyleKind)style {
    if (style == PFBDarkModeStylePureBlack) {
        switch (tier) {
            case PFBBackgroundTierElevated:
                return PFBColorWithRGB(0x121212);
            case PFBBackgroundTierSelected:
                return PFBColorWithRGB(0x1E1E1E);
            default:
                return [UIColor blackColor];
        }
    }
    if (style == PFBDarkModeStyleGray) {
        switch (tier) {
            case PFBBackgroundTierElevated:
                return PFBColorWithRGB(0x232323);
            case PFBBackgroundTierSelected:
                return PFBColorWithRGB(0x2D2D2D);
            default:
                return PFBColorWithRGB(0x181818);
        }
    }
    switch (tier) {
        case PFBBackgroundTierElevated:
            return PFBColorWithRGB(0x1B2C3D);
        case PFBBackgroundTierSelected:
            return PFBColorWithRGB(0x23364C);
        default:
            return PFBColorWithRGB(0x15202B);
    }
}

+ (UIColor*)elevatedBackgroundColor {
    if (![self isDarkModeActive]) {
        return nil;
    }
    PFBDarkModeStyleKind style = [self selectedStyle];
    if (style == PFBDarkModeStyleSystem) {
        PFBCOMPAT_OBSERVE(PFBCompat_dark_mode_style, @"dark palette read");
        return nil;
    }
    PFBCOMPAT_ACTION(PFBCompat_dark_mode_style, @"dark shade painted");
    return [self shadeForTier:PFBBackgroundTierElevated style:style];
}

+ (UIColor*)baseBackgroundColor {
    if (![self isDarkModeActive]) {
        return nil;
    }
    PFBDarkModeStyleKind style = [self selectedStyle];
    if (style == PFBDarkModeStyleSystem) {
        return nil;
    }
    return [self shadeForTier:PFBBackgroundTierBase style:style];
}

+ (UIColor*)overrideForBackgroundColor:(UIColor*)color {
    if (![self isDarkModeActive]) {
        return nil;
    }
    // Every background set in dark mode passes here: the palette read is the proof.
    PFBDarkModeStyleKind style = [self selectedStyle];
    if (style == PFBDarkModeStyleSystem) {
        PFBCOMPAT_OBSERVE(PFBCompat_dark_mode_style, @"dark palette read");
        return nil;
    }
    PFBBackgroundTier tier = PFBTierForColor(color);
    if (tier == PFBBackgroundTierNone) {
        return nil;
    }
    // A shade this file already produced is graded once and never again. The
    // gray and black ladders are achromatic and land inside their own bands, so
    // a second pass over the same color would push it up a rung.
    for (PFBBackgroundTier rung = PFBBackgroundTierBase;
         rung <= PFBBackgroundTierSelected; rung++) {
        if (PFBColorMatches(color, [self shadeForTier:rung style:style])) {
            return nil;
        }
    }
    PFBCOMPAT_ACTION(PFBCompat_dark_mode_style, @"dark shade painted");
    return [self shadeForTier:tier style:style];
}

@end

// MARK: - Direct background interception

static UIColor* PFBReplacement(UIColor* incoming) {
    return [PFBDarkModeStyle overrideForBackgroundColor:incoming];
}

%hook UIView

- (void)setBackgroundColor:(UIColor*)color {
    UIColor* replacement = PFBReplacement(color);
    %orig(replacement ?: color);
}

%end

// Probe: notes the layer classes whose background is set off the main thread (10A#A15),
// five at most, looking at 2000 such calls at most. Any thread.
static _Atomic int gPFBLayerProbeState;
static _Atomic unsigned gPFBLayerProbeLooks;
static _Atomic unsigned gPFBLayerProbeLines;

static void PFBLayerThreadProbe(CALayer* layer) {
    int state = atomic_load_explicit(&gPFBLayerProbeState, memory_order_relaxed);
    if (state == 0) {
        state = PFBDebugIsRecording() ? 1 : 2;
        atomic_store_explicit(&gPFBLayerProbeState, state, memory_order_relaxed);
    }
    if (state != 1) {
        return;
    }
    if (atomic_fetch_add_explicit(&gPFBLayerProbeLooks, 1, memory_order_relaxed) >= 2000 ||
        atomic_load_explicit(&gPFBLayerProbeLines, memory_order_relaxed) >= 5) {
        atomic_store_explicit(&gPFBLayerProbeState, 2, memory_order_relaxed);
        return;
    }
    NSString* layerName = NSStringFromClass([layer class]);
    NSString* key = [@"10A#A15 " stringByAppendingString:layerName];
    if (!PFBProbeWants(key)) {
        return;
    }
    atomic_fetch_add_explicit(&gPFBLayerProbeLines, 1, memory_order_relaxed);
    id delegate = layer.delegate;
    const char* queue = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    PFBProbeNote(key, @"10A#A15 CALayer background set off the main thread: layer %@, delegate %@, queue %s",
                 layerName, PFBProbeClassName(delegate), queue && queue[0] ? queue : "unnamed");
}

%hook CALayer

- (void)setBackgroundColor:(CGColorRef)color {
    // Probe: notes a background set off the main thread.
    if (atomic_load_explicit(&gPFBLayerProbeState, memory_order_relaxed) != 2 && !pthread_main_np()) {
        PFBLayerThreadProbe(self);
    }
    if (color) {
        UIColor* incoming = [UIColor colorWithCGColor:color];
        UIColor* replacement = PFBReplacement(incoming);
        if (replacement) {
            %orig(replacement.CGColor);
            return;
        }
    }
    %orig(color);
}

%end

%hook TFNSolidColorView

- (void)setColor:(UIColor*)color {
    UIColor* replacement = PFBReplacement(color);
    %orig(replacement ?: color);
}

%end

// MARK: - Search pill

// The search pill is a stretchable background image owned by a private image view,
// not a color any setter carries, so no filter reaches it. Redrawn here in the
// elevated shade with round caps that survive the stretch.

static UIImage* PFBSearchPillImage(void) {
    static UIImage* cached = nil;
    static PFBDarkModeStyleKind cachedStyle = PFBDarkModeStyleSystem;
    UIColor* shade = [PFBDarkModeStyle elevatedBackgroundColor];
    if (!shade) {
        return nil;
    }
    PFBDarkModeStyleKind style = [PFBDarkModeStyle selectedStyle];
    if (cached && cachedStyle == style) {
        return cached;
    }
    const CGFloat diameter = 44.0;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(diameter, diameter)];
    UIImage* pill =
        [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [shade setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, diameter, diameter)
                                        cornerRadius:diameter / 2.0] fill];
        }];
    cached = [pill resizableImageWithCapInsets:UIEdgeInsetsMake(diameter / 2.0,
                                                                diameter / 2.0,
                                                                diameter / 2.0,
                                                                diameter / 2.0)
                                  resizingMode:UIImageResizingModeStretch];
    cachedStyle = style;
    return cached;
}

static void PFBApplySearchPill(UISearchBar* searchBar) {
    UIImage* pill = PFBSearchPillImage();
    if (pill && [searchBar isKindOfClass:[UISearchBar class]]) {
        [searchBar setSearchFieldBackgroundImage:pill forState:UIControlStateNormal];
    }
}

// The substitution below belongs to the search field alone: the same UIKit view
// backs other text fields, and those keep their own image.
static BOOL PFBIsSearchFieldBackground(UIView* view) {
    Class searchBarClass = NSClassFromString(@"TFNSearchBar");
    if (!searchBarClass) {
        return NO;
    }
    for (UIView* ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:searchBarClass]) {
            return YES;
        }
    }
    return NO;
}

// A bar carrying a search field is drawn with a blur, so no color setter reaches
// it and it stays in Twitter's gray beside a recoloured page. Flattened here from
// the search field upward; a bar without one is never touched.
static void PFBPaintBarOpaque(UIView* view, UIColor* shade) {
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        ((UIVisualEffectView*)view).effect = nil;
        view.backgroundColor = shade;
    } else if ([NSStringFromClass([view class]) containsString:@"BarBackground"]) {
        view.backgroundColor = shade;
    }
    for (UIView* subview in view.subviews) {
        PFBPaintBarOpaque(subview, shade);
    }
}

static void PFBFlattenSearchBarChrome(UIView* searchBar) {
    UIColor* shade = [PFBDarkModeStyle baseBackgroundColor];
    if (!shade) {
        return;
    }
    for (UIView* ancestor = searchBar.superview; ancestor;
         ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:[UINavigationBar class]]) {
            ancestor.backgroundColor = shade;
            PFBPaintBarOpaque(ancestor, shade);
            return;
        }
    }
}

// Probe: once per screen (four at most), whatever the dark style, whether a search bar
// sits in a navigation bar and how many of that bar's effect views PFBPaintBarOpaque
// would reach, and how many of them sit inside a button (10A#A7). Read only.
static NSUInteger gPFBSearchBarProbeLines;

static void PFBEffectViewsProbe(UIView* view, UIView* bar, NSUInteger* total, NSUInteger* inButton,
                                NSMutableString* first) {
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        (*total)++;
        for (UIView* up = view.superview; up && up != bar; up = up.superview) {
            NSString* name = NSStringFromClass([up class]);
            if ([up isKindOfClass:[UIControl class]] || [name containsString:@"Button"]) {
                (*inButton)++;
                if (!first.length) {
                    [first setString:name];
                }
                break;
            }
        }
    }
    for (UIView* subview in view.subviews) {
        PFBEffectViewsProbe(subview, bar, total, inButton, first);
    }
}

static void PFBSearchBarProbe(UIView* searchBar) {
    if (!PFBDebugIsRecording() || gPFBSearchBarProbeLines >= 4 || !NSThread.isMainThread ||
        !searchBar.window) {
        return;
    }
    UIViewController* controller = PFBProbeControllerOfView(searchBar);
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = ((UINavigationController*)controller).topViewController;
    }
    NSString* screen = PFBProbeScreenName(controller);
    NSString* key = [@"10A#A7 " stringByAppendingString:screen];
    if (!PFBProbeWants(key)) {
        return;
    }
    UIView* bar = searchBar.superview;
    while (bar && ![bar isKindOfClass:[UINavigationBar class]]) {
        bar = bar.superview;
    }
    NSUInteger total = 0;
    NSUInteger inButton = 0;
    NSMutableString* first = [NSMutableString string];
    if (bar) {
        PFBEffectViewsProbe(bar, bar, &total, &inButton, first);
    }
    gPFBSearchBarProbeLines++;
    PFBProbeNote(key, @"10A#A7 TFNSearchBar on %@: navigation bar %@; effect views under it %lu, inside a button %lu (first: %@)",
                 screen, bar ? @"found" : @"none", (unsigned long)total, (unsigned long)inButton,
                 first.length ? first : @"none");
}

%hook TFNSearchBar

- (void)layoutSubviews {
    %orig;
    PFBApplySearchPill((UISearchBar*)self);
    PFBFlattenSearchBarChrome((UIView*)self);
}

- (void)didMoveToWindow {
    %orig;
    // Probe: notes this search bar's screen and the effect views of its bar.
    PFBSearchBarProbe((UIView*)self);
    PFBApplySearchPill((UISearchBar*)self);
    PFBFlattenSearchBarChrome((UIView*)self);
}

%end

// The search bar puts its stock image back after laying out, so the public
// setter alone does not survive the final pass.
%hook _UITextFieldImageBackgroundView

- (void)setImage:(UIImage*)image {
    UIImage* pill =
        PFBIsSearchFieldBackground((UIView*)self) ? PFBSearchPillImage() : nil;
    %orig(pill ?: image);
}

%end
