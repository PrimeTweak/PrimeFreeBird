#import <UIKit/UIKit.h>

// "Check paths", pinned to the checklist button by its arrow like the other bar
// popovers: the two tours, the second grayed out once this build owes no proof.
@interface PFBTourChoicePopover : UIViewController <UIPopoverPresentationControllerDelegate>
@property(nonatomic, copy) void (^chosen)(BOOL full);
@end
