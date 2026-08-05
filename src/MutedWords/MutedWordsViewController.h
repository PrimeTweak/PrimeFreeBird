//
//  MutedWordsViewController.h
//  PrimeFreeBird
//
//  Editor for the muted-words list: words, phrases and @accounts whose posts
//  are filtered out of the timeline.
//

#import <UIKit/UIKit.h>

@interface MutedWordsViewController : UITableViewController

// Compact mode drops the Options section and sizes itself for a popover, so
// the quick-access button on the timeline shows the same add/remove controls
// without a second implementation.
@property (nonatomic, assign, readonly) BOOL compact;
- (instancetype)initCompact;

@end
