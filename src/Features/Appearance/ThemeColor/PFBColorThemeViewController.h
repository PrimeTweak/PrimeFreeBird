// The accent color picker, laid out like Twitter's own color picker.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorThemeViewController : UIViewController
// Set before it shows: round options and rows, as Twitter's new settings draw theirs.
@property (nonatomic) BOOL nativeLook;
@end

NS_ASSUME_NONNULL_END
