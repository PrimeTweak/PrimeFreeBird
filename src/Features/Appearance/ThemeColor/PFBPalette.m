// Color helpers around the app's active palette.

#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "Support/TAEHeaders.h"

@implementation PFBPalette

+ (TAETwitterColorPaletteSettingInfo*)currentPaletteInfo {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (![settingsClass respondsToSelector:@selector(sharedSettings)]) {
        return nil;
    }

    id settings = [settingsClass sharedSettings];
    if (![settings respondsToSelector:@selector(currentColorPalette)]) {
        return nil;
    }

    return [settings currentColorPalette];
}

+ (UIColor*)currentBackgroundColor {
    return [self colorFor:@selector(backgroundColor) fallback:[UIColor systemBackgroundColor]];
}

+ (UIColor*)colorFor:(SEL)getter fallback:(UIColor*)fallback {
    TAETwitterColorPaletteSettingInfo* info = [self currentPaletteInfo];
    id palette = [info respondsToSelector:@selector(colorPalette)] ? [info colorPalette] : nil;
    id color = [palette respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(palette, getter) : nil;
    return [color isKindOfClass:[UIColor class]] ? color : fallback;
}

@end
