//
//  DarkModeStyle.h
//  PrimeFreeBird
//
//  Dark mode style selector (System / Dim / Gray / Pure black).
//
//  Approach and Dim color (#15202b) adapted from nyaathea's BHDimPalette and
//  the BHTThemeDirectBackgroundHooks system in PrimeFreeBird/tweak.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NFBDarkModeStyle) {
    NFBDarkModeStyleSystem    = 0, // Native black
    NFBDarkModeStyleDim       = 1, // "Dim" blue-grey (#15202b)
    NFBDarkModeStyleGray      = 2, // Neutral gray (no blue tint)
    NFBDarkModeStylePureBlack = 3  // #000000 OLED
};

@interface DarkModeStyle : NSObject

+ (NFBDarkModeStyle)selectedStyle;
+ (BOOL)isDarkModeActive;

// The shade that replaces an incoming background color, or nil to leave it
// alone. Dark chrome is graded into three depths — base, elevated, selected —
// and the incoming brightness decides which one it gets.
+ (UIColor* _Nullable)overrideForBackgroundColor:(UIColor*)color;

// The shade for surfaces sitting above the base one — sheets, cards, selected
// rows — for callers that paint their own instead of going through a color
// the filter can see. Nil when no dark style is active.
+ (UIColor* _Nullable)elevatedBackgroundColor;

// The shade of the base surface, for callers that paint chrome no color setter
// reaches. Nil when no dark style is active.
+ (UIColor* _Nullable)baseBackgroundColor;

@end
