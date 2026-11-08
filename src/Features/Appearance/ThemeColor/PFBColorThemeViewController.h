// The accent color picker, laid out like Twitter's own color picker.

#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorThemeViewController : UIViewController
// Set before it shows: the new look's page, the colors as round options under a sample in the accent.
@property (nonatomic) BOOL nativeLook;
// The signed-in account, whose profile photo the sample shows in its top bar.
@property (nonatomic, strong, nullable) TFNTwitterAccount* account;
@end

NS_ASSUME_NONNULL_END
