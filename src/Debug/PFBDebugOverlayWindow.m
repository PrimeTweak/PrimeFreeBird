#import "Debug/PFBDebugger.h"
#import "Support/Generated/PFBHookManifest.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import "Support/HookHelpers.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <sys/utsname.h>
#import "Debug/PFBDebugOverlayWindow.h"

@implementation PFBDebugOverlayWindow
// Everything except the button falls through to the app underneath, so the
// overlay costs nothing in use.
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end
