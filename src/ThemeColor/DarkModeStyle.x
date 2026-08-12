//
//  DarkModeStyle.x
//  PrimeFreeBird
//
//  Dark mode style selector (System / Dim / Gray / Pure black).
//
//  The Dim color (#15202b) and the direct-background interception approach are
//  adapted from nyaathea's BHDimPalette and the BHTThemeDirectBackgroundHooks
//  system in PrimeFreeBird/tweak. Rather than recoloring palette getters (which
//  the navigation bars and chrome don't read), this intercepts the color
//  setters themselves and, only when the incoming color is one of Twitter's
//  dark backgrounds, swaps in the selected shade. Tinted colors, icons and
//  translucent overlays are left untouched by the filter.
//
//  Dark chrome is not one flat color: the app draws the base surface near
//  black, anything elevated a step lighter, and pressed or selected rows a
//  step lighter still. That grading is read from the incoming brightness and
//  answered with a matching shade, so sheets, cards and selection states keep
//  their separation instead of collapsing onto the background.
//

#import "ThemeColor/DarkModeStyle.h"
#import "Core/BHTSettings.h"
#import <objc/runtime.h>

@interface TAETwitterColorPaletteSettingInfo : NSObject
@property (readonly, nonatomic) BOOL isDark;
@end

@interface TAEColorSettings : NSObject
+ (instancetype)sharedSettings;
- (TAETwitterColorPaletteSettingInfo*)currentColorPalette;
@end

@interface TFNSolidColorView : UIView
- (void)setColor:(UIColor*)color;
- (void)setSolidColor:(UIColor*)color;
@end

@implementation DarkModeStyle

+ (NFBDarkModeStyle)selectedStyle {
    return (NFBDarkModeStyle)[BHTSettings integerForKey:@"dark_mode_style"];
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
typedef NS_ENUM(NSInteger, NFBBackgroundTier) {
    NFBBackgroundTierNone = 0,  // Not background chrome — left alone
    NFBBackgroundTierBase,      // The surface everything sits on
    NFBBackgroundTierElevated,  // Sheets, cards, toasts, incoming bubbles
    NFBBackgroundTierSelected   // Pressed rows, unread, highlighted Tweets
};

// Opaque and achromatic is what separates background chrome from everything
// else: a color with real hue is media, a brand card or an accent, and
// flattening it onto the background loses that. Brightness alone cannot tell
// them apart, which is why the spread between the strongest and weakest
// component is measured first. Above the ceiling the color is a fill or a
// separator that has to stay legible, so it is left alone as well.
static const CGFloat kNFBChromaAllowance = 0.04;
static const CGFloat kNFBDarkCeiling = 0.22;
static const CGFloat kNFBBaseCeiling = 0.05;
static const CGFloat kNFBElevatedCeiling = 0.14;

static NFBBackgroundTier NFBTierForColor(UIColor* color) {
    if (!color) {
        return NFBBackgroundTierNone;
    }
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        // Grayscale colors answer -getWhite:alpha: and nothing else.
        CGFloat white = 0.0;
        if (![color getWhite:&white alpha:&alpha]) {
            return NFBBackgroundTierNone;
        }
        red = green = blue = white;
    }
    if (alpha <= 0.95) {
        return NFBBackgroundTierNone;
    }
    CGFloat strongest = MAX(red, MAX(green, blue));
    CGFloat weakest = MIN(red, MIN(green, blue));
    if (strongest - weakest > kNFBChromaAllowance || strongest > kNFBDarkCeiling) {
        return NFBBackgroundTierNone;
    }
    if (strongest < kNFBBaseCeiling) {
        return NFBBackgroundTierBase;
    }
    if (strongest < kNFBElevatedCeiling) {
        return NFBBackgroundTierElevated;
    }
    return NFBBackgroundTierSelected;
}

// Component-wise, because two UIColors built from different color spaces are
// never equal to -isEqual: even when they paint the same pixels.
static BOOL NFBColorMatches(UIColor* color, UIColor* shade) {
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

static UIColor* NFBColorWithRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

// Each style is a ladder of three shades. The rungs are spaced by perceived
// lightness rather than by raw value — about five points of L* apart — which is
// what decides whether the eye separates two dark tones. Pure black keeps an
// exact #000000 base for OLED screens and lifts only what sits above it.
+ (UIColor*)shadeForTier:(NFBBackgroundTier)tier style:(NFBDarkModeStyle)style {
    if (style == NFBDarkModeStylePureBlack) {
        switch (tier) {
            case NFBBackgroundTierElevated:
                return NFBColorWithRGB(0x121212);
            case NFBBackgroundTierSelected:
                return NFBColorWithRGB(0x1E1E1E);
            default:
                return [UIColor blackColor];
        }
    }
    if (style == NFBDarkModeStyleGray) {
        switch (tier) {
            case NFBBackgroundTierElevated:
                return NFBColorWithRGB(0x232323);
            case NFBBackgroundTierSelected:
                return NFBColorWithRGB(0x2D2D2D);
            default:
                return NFBColorWithRGB(0x181818);
        }
    }
    switch (tier) {
        case NFBBackgroundTierElevated:
            return NFBColorWithRGB(0x1B2C3D);
        case NFBBackgroundTierSelected:
            return NFBColorWithRGB(0x23364C);
        default:
            return NFBColorWithRGB(0x15202B);
    }
}

+ (UIColor*)elevatedBackgroundColor {
    if (![self isDarkModeActive]) {
        return nil;
    }
    NFBDarkModeStyle style = [self selectedStyle];
    if (style == NFBDarkModeStyleSystem) {
        return nil;
    }
    return [self shadeForTier:NFBBackgroundTierElevated style:style];
}

+ (UIColor*)overrideForBackgroundColor:(UIColor*)color {
    if (![self isDarkModeActive]) {
        return nil;
    }
    NFBDarkModeStyle style = [self selectedStyle];
    if (style == NFBDarkModeStyleSystem) {
        return nil;
    }
    NFBBackgroundTier tier = NFBTierForColor(color);
    if (tier == NFBBackgroundTierNone) {
        return nil;
    }
    // A shade this file already produced is graded once and never again. The
    // gray and black ladders are achromatic and land inside their own bands, so
    // a second pass over the same color would push it up a rung.
    for (NFBBackgroundTier rung = NFBBackgroundTierBase;
         rung <= NFBBackgroundTierSelected; rung++) {
        if (NFBColorMatches(color, [self shadeForTier:rung style:style])) {
            return nil;
        }
    }
    return [self shadeForTier:tier style:style];
}

@end

// MARK: - Direct background interception

static UIColor* NFBReplacement(UIColor* incoming) {
    return [DarkModeStyle overrideForBackgroundColor:incoming];
}

%hook UIView

- (void)setBackgroundColor:(UIColor*)color {
    UIColor* replacement = NFBReplacement(color);
    %orig(replacement ?: color);
}

%end

%hook CALayer

- (void)setBackgroundColor:(CGColorRef)color {
    if (color) {
        UIColor* incoming = [UIColor colorWithCGColor:color];
        UIColor* replacement = NFBReplacement(incoming);
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
    UIColor* replacement = NFBReplacement(color);
    %orig(replacement ?: color);
}

- (void)setSolidColor:(UIColor*)color {
    UIColor* replacement = NFBReplacement(color);
    %orig(replacement ?: color);
}

%end
