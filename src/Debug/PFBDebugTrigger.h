#import <UIKit/UIKit.h>

// The button's target, as a UIControl needs one: a tap opens the capture, a drag moves the button.
@interface PFBDebugTrigger : NSObject
+ (instancetype)shared;
- (void)tapped;
- (void)dragged:(UIPanGestureRecognizer*)pan;
@end
