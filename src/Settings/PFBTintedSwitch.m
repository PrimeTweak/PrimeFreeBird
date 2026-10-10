#import "Common/PFBCompatibility.h"
#import "Settings/PFBModernSettingsCells.h"
#import <QuartzCore/QuartzCore.h>
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Support/TWHeaders.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Support/TwitterChirpFont.h"
#import "Debug/PFBDebugger.h"
#import "Settings/PFBTintedSwitch.h"

@implementation PFBTintedSwitch
 
- (void)pfb_refreshTint {
    UIColor* target = nil;
    if ([PFBSettings boolForKey:@"color_pfb_switches"]) {
        UIColor* accent = PFBCurrentAccentColor();
        // Freeze to a static color so it can't re-resolve through the hooks.
        target = [accent resolvedColorWithTraitCollection:self.traitCollection] ?: accent;
        PFBCOMPAT_ACTION(PFBCompat_color_pfb_switches, @"switch tinted");
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_color_pfb_switches, @"switch found");
    }
    if (self.onTintColor != target && ![self.onTintColor isEqual:target]) {
        [UIView performWithoutAnimation:^{
            self.onTintColor = target;
        }];
    }
}
 
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self pfb_refreshTint];
    }
}
 
- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self pfb_refreshTint];
}
 
@end
