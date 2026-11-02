// The Filters screen: muted words and accounts, kept languages, hidden conversations.

#import <UIKit/UIKit.h>

@interface PFBMutedWordsViewController : UITableViewController

// Compact mode drops the Options section and sizes itself for a popover, so
// the quick-access button on the timeline shows the same add/remove controls
// without a second implementation.
- (instancetype)initCompact;

// Set before the full screen shows: the new look of Twitter's settings, with the options in a sheet.
@property (nonatomic) BOOL nativeLook;

@end
