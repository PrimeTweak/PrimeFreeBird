// The tab editor: a grid of every available tab above a reorderable preview row.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBCustomTabBarViewController : UIViewController

// Set before it shows when the editor opens from the new look's settings, whose alerts are
// Twitter's own.
@property (nonatomic) BOOL nativeLook;

@end

NS_ASSUME_NONNULL_END
