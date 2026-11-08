#import <UIKit/UIKit.h>

// The hidden-notifications list, presented as a compact popover from the bar
// button, with no header and a size measured from the content.
@interface PFBHiddenNotificationsViewController : UITableViewController
- (instancetype)initCompact;
@end
