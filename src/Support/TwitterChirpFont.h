// Access to the app's Chirp font faces.

#import <UIKit/UIKit.h>
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

// A Chirp face from Twitter's own font group (TFNUIDefaultFontGroup) rather than
// fragile variable-font instance names; falls back to system fonts.
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
