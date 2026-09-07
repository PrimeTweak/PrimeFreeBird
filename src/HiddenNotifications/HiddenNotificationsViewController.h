#import <UIKit/UIKit.h>

// The hidden-notifications list, in two shapes from one class, like the muted-words
// screen: pushed full screen from Settings, or presented as a compact popover from
// the bar button, with no header and a size measured from the content.
@interface HiddenNotificationsViewController : UITableViewController
- (instancetype)initCompact;
@end
