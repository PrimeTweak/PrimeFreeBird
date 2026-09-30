#import "Debug/PFBDebugger.h"
#import "Support/Generated/PFBHookManifest.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import "Support/HookHelpers.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <sys/utsname.h>
#import "Debug/PFBDebugTrigger.h"

@implementation PFBDebugTrigger

+ (instancetype)shared {
    static PFBDebugTrigger* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [PFBDebugTrigger new]; });
    return shared;
}

- (void)tapped {
    PFBDebuggerCaptureAndPresent();
}

// Dragged rather than fixed: a diagnostics button that covers the thing being
// diagnosed is worse than none.
- (void)dragged:(UIPanGestureRecognizer*)pan {
    UIView* button = pan.view;
    CGPoint delta = [pan translationInView:button.superview];
    CGPoint centre = button.center;
    centre.x += delta.x;
    centre.y += delta.y;
    CGRect bounds = button.superview.bounds;
    CGFloat inset = button.bounds.size.width / 2 + 4;
    centre.x = MAX(inset, MIN(bounds.size.width - inset, centre.x));
    centre.y = MAX(inset, MIN(bounds.size.height - inset, centre.y));
    button.center = centre;
    [pan setTranslation:CGPointZero inView:button.superview];
}

@end
