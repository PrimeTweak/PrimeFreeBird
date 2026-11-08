// The parts of the new look's showcase pages: a line under the title, a soft card that holds
// Liquid Glass, rows with a symbol in a gray circle, and capsule buttons.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Whether the new look draws Liquid Glass: iOS 26 or later, with Visual style as it stood at launch.
BOOL PFBShowcaseUsesGlass(void);

// The page's line under its title, aligned as Twitter aligns its settings descriptions.
UILabel* PFBShowcaseIntroLabel(void);

// Titles a page as Twitter's new settings title theirs: Chirp Bold at 18 pt in the label color,
// in place of the bar's own title.
void PFBShowcaseSetTitle(UIViewController* controller, NSString* title);

// The soft card the glass stands on.
UIView* PFBShowcaseCard(void);

// How far down a control pinned to the page may reach, in the view's coordinates: above the
// safe area, and above Twitter's floating tab bar while it shows over the page.
CGFloat PFBShowcaseBottomLimit(UIView* view);

// A glass surface; a light one with a hairline when glass is off. A negative radius makes a capsule.
@interface PFBShowcaseSurface : UIView
- (instancetype)initWithCornerRadius:(CGFloat)radius;
// Where content goes: the glass's own content view, or the surface itself.
@property (nonatomic, readonly) UIView* contentView;
@end

typedef NS_ENUM(NSInteger, PFBShowcaseButtonStyle) {
    // A glass capsule, as the controls on a card.
    PFBShowcaseButtonStyleGlass,
    // An outlined capsule, as Twitter's Restore to default.
    PFBShowcaseButtonStyleOutline,
    // The outlined capsule of an action that erases, in red.
    PFBShowcaseButtonStyleDestructive,
    // Twitter's filled primary capsule, as a chosen chip.
    PFBShowcaseButtonStyleFilled,
};

// A capsule with a symbol, a title or both, centered; its menu, when set, opens on a tap.
@interface PFBShowcaseButton : UIButton
+ (instancetype)buttonWithStyle:(PFBShowcaseButtonStyle)style;
@property (nonatomic) PFBShowcaseButtonStyle style;
@property (nonatomic, copy, nullable) NSString* label;
@property (nonatomic, copy, nullable) NSString* symbolName;
// A symbol after the label, as the chevrons of a menu.
@property (nonatomic, copy, nullable) NSString* trailingSymbolName;
@property (nonatomic, strong) UIFont* labelFont;
// The ground under an outlined capsule that floats over a page; clear unless set.
@property (nonatomic, strong, nullable) UIColor* groundColor;
@end

typedef NS_ENUM(NSInteger, PFBShowcaseAccessory) {
    PFBShowcaseAccessoryNone,
    // The row leads to a page.
    PFBShowcaseAccessoryChevron,
    // The row opens a menu in place.
    PFBShowcaseAccessoryMenu,
    // The row opens a sheet.
    PFBShowcaseAccessoryMore,
};

// Where a row's gray circle starts; the notes under the rows start there too.
static const CGFloat kPFBShowcaseRowLeading = 24.0;

// A row: a symbol in a gray circle, a title with an optional line under it, then a value, a
// glyph, or a control of its own.
@interface PFBShowcaseRowCell : UITableViewCell
- (void)configureWithSymbol:(nullable NSString*)symbol
                      title:(NSString*)title
                   subtitle:(nullable NSString*)subtitle
                      value:(nullable NSString*)value
                  accessory:(PFBShowcaseAccessory)accessory;
// The symbol's color; nil for the text color.
@property (nonatomic, strong, nullable) UIColor* symbolColor;
// A Twitter glyph drawn in the circle in place of the symbol, which stays as the fallback.
@property (nonatomic, copy, nullable) NSString* twitterGlyphName;
// A switch or a button standing after the text. VoiceOver reads the row as that control alone,
// so its label and hint carry the row's words.
@property (nonatomic, strong, nullable) UIView* trailingView;
// Lines the title may take, 1 unless set.
@property (nonatomic) NSInteger titleLines;
@end

NS_ASSUME_NONNULL_END
