// Shared helpers: color option, view snapshot, iPad test, top controller and accents.

#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "Support/TAEHeaders.h"

@interface SFSafariViewController ()
- (NSURL*)initialURL;
@end

static inline void changeTwitterColor(NSInteger colorID) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];

    [defaults setObject:@(colorID)
                 forKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    [colorSettings setPrimaryColorOption:colorID];
}
static inline UIImage* imageFromView(UIView* view) {
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];
    bool opaque = [colorSettings.currentColorPalette isDark] ? true : false;
    UIGraphicsBeginImageContextWithOptions(view.frame.size, opaque, 0.0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:false];
    UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

static inline BOOL is_iPad() {
    if ([(NSString*)[UIDevice currentDevice].model hasPrefix:@"iPad"]) {
        return YES;
    }
    return NO;
}

// The controller shown above cont: the last one presented from it, or that one's visible
// child when it is a navigation controller; nil when it is cont itself.
static inline UIViewController* _Nullable _topMostController(
    UIViewController* _Nullable cont) {
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
static inline UIViewController* _Nullable topMostController() {
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
