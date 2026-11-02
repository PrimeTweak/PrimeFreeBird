// The accent color picker, laid out like Twitter's own color picker.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorThemeViewController : UIViewController
// Set before it shows: the new look's page, the colors as round options under a sample in the accent.
@property (nonatomic) BOOL nativeLook;
@end

NS_ASSUME_NONNULL_END
