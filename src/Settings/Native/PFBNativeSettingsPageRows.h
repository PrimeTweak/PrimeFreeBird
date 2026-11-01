// The rows of a settings page in Twitter's new look: one per group, opening the group in a sheet,
// and one per row that opens a screen, opening it from the page itself.

#import <UIKit/UIKit.h>

@class PFBModernSettingsPageViewController;

@interface PFBNativeSettingsPageRows : NSObject <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithPage:(PFBModernSettingsPageViewController*)page;

// Makes the table show these rows.
- (void)showInTable:(UITableView*)table;

@end
