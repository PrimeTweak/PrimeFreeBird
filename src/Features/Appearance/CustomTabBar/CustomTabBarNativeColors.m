// The native tab-customization color tokens, with system fallbacks.

#import "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.h"
#import <objc/runtime.h>

@interface UIColor (NativeTokens)
+ (id)twitterColors;
+ (id)tfnuiColors;
@end

@interface NSObject (NativeTokens)
- (UIColor*)subscriptionMarketingFeatureCardBackgroundColor;
- (UIColor*)subscriptionMarketingFeatureCardShadowColor;
- (UIColor*)tabCustomizationInactiveGridCellContainerBackgroundColor;
- (UIColor*)backgroundColor;
- (UIColor*)navigationBarShadowColor;
- (UIColor*)textColor;
+ (UIColor*)itemColor;
@end

static UIColor* Resolve(id provider, SEL selector, UIColor* fallback) {
    if (provider && [provider respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIColor* color = [provider performSelector:selector];
#pragma clang diagnostic pop
        if ([color isKindOfClass:[UIColor class]]) {
            return color;
        }
    }
    return fallback;
}

static id TwitterColors(void) {
    return [UIColor respondsToSelector:@selector(twitterColors)]
               ? [UIColor twitterColors]
               : nil;
}

UIColor* PFBCustomTabBarCardBackgroundColor(void) {
    return Resolve(TwitterColors(),
                   @selector(subscriptionMarketingFeatureCardBackgroundColor),
                   [UIColor systemBackgroundColor]);
}

UIColor* PFBCustomTabBarInactiveCardBackgroundColor(void) {
    return Resolve(
        TwitterColors(),
        @selector(tabCustomizationInactiveGridCellContainerBackgroundColor),
        [UIColor secondarySystemBackgroundColor]);
}

UIColor* PFBCustomTabBarCardShadowColor(void) {
    return Resolve(TwitterColors(),
                   @selector(subscriptionMarketingFeatureCardShadowColor),
                   [UIColor blackColor]);
}

UIColor* PFBCustomTabBarShadowColor(void) {
    return PFBCustomTabBarCardShadowColor();
}

UIColor* PFBCustomTabBarIconColor(void) {
    return Resolve(objc_getClass("T1TabView"), @selector(itemColor),
                   [UIColor labelColor]);
}

UIColor* PFBCustomTabBarScreenBackgroundColor(void) {
    return Resolve(TwitterColors(), @selector(backgroundColor),
                   [UIColor systemBackgroundColor]);
}

UIColor* PFBCustomTabBarSeparatorColor(void) {
    return Resolve(TwitterColors(), @selector(navigationBarShadowColor),
                   [UIColor separatorColor]);
}
