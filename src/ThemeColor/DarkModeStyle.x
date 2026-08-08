//
//  DarkModeStyle.x
//  PrimeFreeBird
//
//  Dark mode style selector (System / Dim).
//
//  The Dim color (#15202b) and the direct-background interception approach are
//  adapted from nyaathea's BHDimPalette and the BHTThemeDirectBackgroundHooks
//  system in PrimeFreeBird/tweak. Rather than recoloring palette getters (which
//  the navigation bars and chrome don't read), this intercepts the color
//  setters themselves and, only when the incoming color is one of Twitter's
//  dark backgrounds, swaps in the Dim color. Tinted colors, icons and
//  translucent overlays are left untouched by the brightness/alpha filter.
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

+ (UIColor*)dimColor {
    // Twitter's "Dim" background, #15202b.
    return [UIColor colorWithRed:0.082 green:0.125 blue:0.169 alpha:1.0];
}

+ (UIColor*)overrideBackgroundColor {
    if (![self isDarkModeActive]) {
        return nil;
    }
    NFBDarkModeStyle style = [self selectedStyle];
    if (style == NFBDarkModeStyleDim) {
        return [self dimColor];
    }
    if (style == NFBDarkModeStylePureBlack) {
        return [self pureBlackColor];
    }
    if (style == NFBDarkModeStyleGray) {
        return [self grayColor];
    }
    return nil;
}

+ (UIColor*)pureBlackColor {
    // Pure black #000000 for OLED screens.
    return [UIColor blackColor];
}

+ (UIColor*)grayColor {
    // Neutral dark gray (no blue tint), like Moe's Gray mode.
    return [UIColor colorWithRed:0.094 green:0.094 blue:0.094 alpha:1.0];
}

+ (BOOL)isDarkBackgroundColor:(UIColor*)color {
    if (!color) {
        return NO;
    }
    CGFloat white = 0.0;
    CGFloat alpha = 0.0;
    if (![color getWhite:&white alpha:&alpha]) {
        return NO;
    }
    return (alpha > 0.95 && white < 0.2);
}

@end

// MARK: - Direct background interception

static UIColor* NFBReplacement(UIColor* incoming) {
    UIColor* override = [DarkModeStyle overrideBackgroundColor];
    if (!override) {
        return nil;
    }
    if (![DarkModeStyle isDarkBackgroundColor:incoming]) {
        return nil;
    }
    return override;
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
