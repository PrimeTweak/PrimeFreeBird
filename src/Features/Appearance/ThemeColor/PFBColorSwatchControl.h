// A pill-style accent color option: a colored capsule with the color name and
// a radio checkmark below it.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBColorSwatchControl : UIControl

@property (nonatomic, assign) NSInteger colorID;

- (void)setSwatchColor:(UIColor*)color;
- (void)setSwatchName:(NSString*)name;
- (void)setSwatchNeutral;
- (void)setSwatchSelected:(BOOL)selected;

@end

NS_ASSUME_NONNULL_END
