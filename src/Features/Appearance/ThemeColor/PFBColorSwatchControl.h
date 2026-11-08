// A pill-style accent color option: a colored capsule above a radio check.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorSwatchControl : UIControl

@property (nonatomic, assign) NSInteger colorID;

// The new look's options instead: a round color at a fixed size, which the bar holding the options
// marks once chosen. The rainbow one holds the custom color in its middle.
- (instancetype)initRound;
- (instancetype)initRainbow;

- (void)setSwatchColor:(UIColor*)color;
- (void)setSwatchName:(NSString*)name;
- (void)setSwatchNeutral;
- (void)setSwatchSelected:(BOOL)selected;

@end

NS_ASSUME_NONNULL_END
