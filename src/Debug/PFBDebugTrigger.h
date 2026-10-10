#import <UIKit/UIKit.h>

// The button's target lives on an object because a UIControl needs one; it does
// nothing but forward to the capture, and drags itself out of the way.
@interface PFBDebugTrigger : NSObject
+ (instancetype)shared;
- (void)tapped;
- (void)dragged:(UIPanGestureRecognizer*)pan;
@end
