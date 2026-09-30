// The native tab-customization color tokens, with system fallbacks when a
// selector disappears after an app update.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

UIColor* PFBCustomTabBarCardBackgroundColor(void); // grid tile background
UIColor* PFBCustomTabBarInactiveCardBackgroundColor(
    void);                                        // fixed (Home) tile background
UIColor* PFBCustomTabBarCardShadowColor(void);       // grid tile shadow
UIColor* PFBCustomTabBarShadowColor(void);           // preview cell shadow
UIColor* PFBCustomTabBarIconColor(void);             // tab icon fill
UIColor* PFBCustomTabBarScreenBackgroundColor(void); // screen background
UIColor* PFBCustomTabBarSeparatorColor(void);        // preview hairline separator

NS_ASSUME_NONNULL_END
