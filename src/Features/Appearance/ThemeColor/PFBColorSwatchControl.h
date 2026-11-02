// A pill-style accent color option: a colored capsule above a radio check.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorSwatchControl : UIControl

@property (nonatomic, assign) NSInteger colorID;

// The new look's option instead: a round color with its name under it, and a check inside it
// once chosen.
- (instancetype)initRound;

- (void)setSwatchColor:(UIColor*)color;
- (void)setSwatchName:(NSString*)name;
- (void)setSwatchNeutral;
- (void)setSwatchSelected:(BOOL)selected;

@end

NS_ASSUME_NONNULL_END
