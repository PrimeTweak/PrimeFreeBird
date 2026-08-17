#import <UIKit/UIKit.h>

// The hidden-notifications list, in two shapes from one class — exactly like
// the muted-words screen he validated: pushed full screen from Settings, or
// presented as a popover from the bar button (compact: no header, no opaque
// background, size measured from the content).
@interface HiddenNotificationsViewController : UITableViewController
- (instancetype)initCompact;
@end
