#import "Common/PFBCompatibility.h"
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Settings/PFBTintedSwitch.h"

@implementation PFBTintedSwitch
 
- (void)pfbRefreshTint {
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
        [self pfbRefreshTint];
    }
}
 
- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self pfbRefreshTint];
}
 
@end
