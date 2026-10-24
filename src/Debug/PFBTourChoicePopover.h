#import <UIKit/UIKit.h>

// "Check options", pinned to the checklist button by its arrow like the other bar
// popovers: the two tours, the second grayed out once nothing is left to check.
@interface PFBTourChoicePopover : UIViewController <UIPopoverPresentationControllerDelegate>
@property(nonatomic, copy) void (^chosen)(BOOL full);
@end
