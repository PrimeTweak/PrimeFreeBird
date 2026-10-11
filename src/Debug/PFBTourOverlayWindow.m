#import <UIKit/UIKit.h>
#import "Debug/PFBTourOverlayWindow.h"

@implementation PFBTourOverlayWindow
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end
