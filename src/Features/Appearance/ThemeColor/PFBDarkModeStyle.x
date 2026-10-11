// Dark mode styles (Dim #15202b, Gray, Pure black), applied by intercepting the
// backgrounds directly rather than recolouring palette getters, which the
// navigation chrome ignores.

#import "Common/PFBCompatibility.h"
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Common/PFBSettings.h"
#import <objc/runtime.h>
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

%hook CALayer

- (void)setBackgroundColor:(CGColorRef)color {
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
    if (pill) {
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

%hook TFNSearchBar

- (void)layoutSubviews {
    %orig;
    PFBApplySearchPill((UISearchBar*)self);
    PFBFlattenSearchBarChrome((UIView*)self);
}

- (void)didMoveToWindow {
    %orig;
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
