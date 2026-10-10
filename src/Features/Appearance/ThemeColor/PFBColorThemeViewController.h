// The accent color picker, cloned from the app's ColorThemePickerItem.

#import <UIKit/UIKit.h>
#import "Features/Appearance/ThemeColor/PFBColorSwatchControl.h"

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorThemeViewController : UIViewController

@property (nonatomic, strong) NSMutableArray<PFBColorSwatchControl*>* swatches;

@end

NS_ASSUME_NONNULL_END
