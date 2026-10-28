// The app icon picker screen.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBAppIconViewController : UIViewController

// Puts Twitter's own icon back when another one is in use, as the picker does, then runs
// done on the main queue.
+ (void)restorePrimaryIconThen:(void (^)(void))done;

@end

NS_ASSUME_NONNULL_END
