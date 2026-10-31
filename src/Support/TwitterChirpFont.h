// Access to the app's Chirp font faces.

#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Support/TAEHeaders.h"

typedef NS_ENUM(NSInteger, TwitterFontStyle) {
    TwitterFontStyleRegular,
    TwitterFontStyleSemibold,
    TwitterFontStyleBold
};

// Scales a font with the reader's text size, as Twitter's own screens do.
static inline UIFont* PFBScaledFont(UIFont* font) {
    return font ? [[UIFontMetrics defaultMetrics] scaledFontForFont:font] : nil;
}

// A font of Twitter's default font group by its getter, or the fallback when the group does
// not answer it.
static inline UIFont* PFBFontGroupFont(SEL getter, UIFont* fallback) {
    Class groupClass = objc_getClass("TFNUIDefaultFontGroup");
    id group = [groupClass respondsToSelector:@selector(sharedFontGroup)] ? [groupClass sharedFontGroup] : nil;
    id font = [group respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(group, getter) : nil;
    return [font isKindOfClass:[UIFont class]] ? font : fallback;
}

// The same font with digits of equal width, so counters and timers hold still as they run.
static inline UIFont* PFBTabularDigitsFont(UIFont* font) {
    UIFontDescriptor* descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
        UIFontDescriptorFeatureSettingsAttribute: @[ @{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)
        } ]
    }];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

// A Chirp face from Twitter's font group, or a system font when the group or the method
// is missing.
static inline UIFont* TwitterChirpFont(TwitterFontStyle style) {
    Class groupClass = objc_getClass("TFNUIDefaultFontGroup");
    TFNUIDefaultFontGroup* group =
        [groupClass respondsToSelector:@selector(sharedFontGroup)] ? [groupClass sharedFontGroup] : nil;

    switch (style) {
        case TwitterFontStyleBold:
            return ([group respondsToSelector:@selector(heavyFontOfSize:)] ? [group heavyFontOfSize:17] : nil)
                       ?: [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        case TwitterFontStyleSemibold:
            return ([group respondsToSelector:@selector(boldFontOfSize:)] ? [group boldFontOfSize:14] : nil)
                       ?: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        case TwitterFontStyleRegular:
        default:
            return ([group respondsToSelector:@selector(fontOfSize:)] ? [group fontOfSize:12] : nil)
                       ?: [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    }
}
