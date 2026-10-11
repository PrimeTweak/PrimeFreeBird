#import <CoreGraphics/CoreGraphics.h>
#import "Debug/PFBDebugOverlayWindow.h"

@implementation PFBDebugOverlayWindow
// Everything except the button falls through to the app underneath, so the
// overlay costs nothing in use.
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end
