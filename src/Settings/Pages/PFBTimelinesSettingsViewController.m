// The Timelines settings page.

#import "Settings/Pages/PFBTimelinesSettingsViewController.h"
#import "Support/HookHelpers.h"

@implementation PFBTimelinesSettingsViewController

- (NSString*)pageKey {
    return @"timelines";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"hide_custom_timelines"]) {
        PFBApplyHideCustomTimelinesSetting();
    }
}

@end
