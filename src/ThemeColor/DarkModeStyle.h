//
//  DarkModeStyle.h
//  PrimeFreeBird
//
//  Dark mode style selector (System / Dim).
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
+ (UIColor*)overrideBackgroundColor;
+ (BOOL)isDarkBackgroundColor:(UIColor*)color;

@end
