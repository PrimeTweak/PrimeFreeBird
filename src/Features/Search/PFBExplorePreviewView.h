// A sample of Twitter's Explore for the Tabs page: the search field beside the account's photo, the
// tabs kept in Explore with the line under the first, two trends, then the tab bar with Search chosen.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBExplorePreviewView : UIView
// The tabs' names as Explore shows them, in its order.
- (void)showTabs:(NSArray<NSString*>*)names;
// The account's profile photo beside the search field; the gray circle stays until it comes.
- (void)showReaderPhoto:(nullable UIImage*)photo;
@end

NS_ASSUME_NONNULL_END
