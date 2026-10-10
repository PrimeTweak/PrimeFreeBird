#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#import <objc/message.h>
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Debug/PFBTourOverlayWindow.h"

@implementation PFBTourOverlayWindow
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end
