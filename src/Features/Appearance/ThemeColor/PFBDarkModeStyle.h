// Dark mode style selector: System, Dim, Gray, Pure black.

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PFBDarkModeStyleKind) {
    PFBDarkModeStyleSystem    = 0, // Native black
    PFBDarkModeStyleDim       = 1, // "Dim" blue-gray (#15202b)
    PFBDarkModeStyleGray      = 2, // Neutral gray (no blue tint)
    PFBDarkModeStylePureBlack = 3  // #000000 OLED
};

@interface PFBDarkModeStyle : NSObject

+ (PFBDarkModeStyleKind)selectedStyle;
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
