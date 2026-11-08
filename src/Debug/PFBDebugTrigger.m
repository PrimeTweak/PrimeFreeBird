#import "Debug/PFBDebugger.h"
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
    CGPoint center = button.center;
    center.x += delta.x;
    center.y += delta.y;
    CGRect bounds = button.superview.bounds;
    CGFloat inset = button.bounds.size.width / 2 + 4;
    center.x = MAX(inset, MIN(bounds.size.width - inset, center.x));
    center.y = MAX(inset, MIN(bounds.size.height - inset, center.y));
    button.center = center;
    [pan setTranslation:CGPointZero inView:button.superview];
}

@end
