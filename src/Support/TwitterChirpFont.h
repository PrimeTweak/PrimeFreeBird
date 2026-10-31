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

// A Chirp face from Twitter's font group, or a system font when the group gives none.
static inline UIFont* TwitterChirpFont(TwitterFontStyle style) {
    TFNUIDefaultFontGroup* group =
        [objc_getClass("TFNUIDefaultFontGroup") sharedFontGroup];

    switch (style) {
        case TwitterFontStyleBold:
            return [group heavyFontOfSize:17]
                       ?: [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        case TwitterFontStyleSemibold:
            return [group boldFontOfSize:14]
                       ?: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        case TwitterFontStyleRegular:
        default:
            return [group fontOfSize:12]
                       ?: [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    }
}
