// Helpers shared across files: Twitter's color option, a view snapshot, the iPad test,
// the top view controller, the accent colors and Safari's private initialURL.

#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "Support/TAEHeaders.h"

@interface SFSafariViewController ()
- (NSURL*)initialURL;
@end

static void changeTwitterColor(NSInteger colorID) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];

    [defaults setObject:@(colorID)
                 forKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    [colorSettings setPrimaryColorOption:colorID];
}
static UIImage* imageFromView(UIView* view) {
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];
    bool opaque = [colorSettings.currentColorPalette isDark] ? true : false;
    UIGraphicsBeginImageContextWithOptions(view.frame.size, opaque, 0.0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:false];
    UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

static BOOL is_iPad() {
    if ([(NSString*)[UIDevice currentDevice].model hasPrefix:@"iPad"]) {
        return YES;
    }
    return NO;
}

// https://github.com/julioverne/MImport/blob/0275405812ff41ed2ca56e98f495fd05c38f41f2/mimporthook/MImport.xm#L59
static UIViewController* _Nullable _topMostController(
    UIViewController* _Nonnull cont) {
    UIViewController* topController = cont;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    if ([topController isKindOfClass:[UINavigationController class]]) {
        UIViewController* visible =
            ((UINavigationController*)topController).visibleViewController;
        if (visible) {
            topController = visible;
        }
    }
    return (topController != cont ? topController : nil);
}
static UIViewController* _Nonnull topMostController() {
    UIViewController* topController =
        [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController* next = nil;
    while ((next = _topMostController(topController)) != nil) {
        topController = next;
    }
    return topController;
}

// Defined in Support/HookHelpers.m
extern UIColor* PFBCurrentAccentColor(void);

// The accent for surfaces that carry Twitter's branding, Twitter's brand blue when no
// accent is picked. Kept apart from PFBCurrentAccentColor, which feeds the window tint
// that UIKit controls inherit; their blue must stay iOS blue.
extern UIColor* PFBBrandAccentColor(void);
