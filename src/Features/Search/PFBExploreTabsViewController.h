// The Tabs page of Search: a sample of Explore, the tabs it keeps and the hidden ones as chips, each
// tapped to move it, then the hints and Restore to default.

#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

NS_ASSUME_NONNULL_BEGIN

@interface PFBExploreTabsViewController : UIViewController
// The signed-in account, whose profile photo the sample shows beside the search field.
@property (nonatomic, strong, nullable) TFNTwitterAccount* account;
@end

NS_ASSUME_NONNULL_END
