// The native tab-customization colour tokens, with system fallbacks when a
// selector disappears after an app update.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

UIColor* CustomTabBarCardBackgroundColor(void); // grid tile background
UIColor* CustomTabBarInactiveCardBackgroundColor(
    void);                                        // fixed (Home) tile background
UIColor* CustomTabBarCardShadowColor(void);       // grid tile shadow
UIColor* CustomTabBarShadowColor(void);           // preview cell shadow
UIColor* CustomTabBarIconColor(void);             // tab icon fill
UIColor* CustomTabBarScreenBackgroundColor(void); // screen background
UIColor* CustomTabBarSeparatorColor(void);        // preview hairline separator

NS_ASSUME_NONNULL_END
