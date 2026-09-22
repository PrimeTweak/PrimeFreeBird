// A pill-style accent colour option: a coloured capsule with the colour name and
// a radio checkmark below it.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ColorSwatchControl : UIControl

@property (nonatomic, assign) NSInteger colorID;

- (void)setSwatchColor:(UIColor*)color;
- (void)setSwatchName:(NSString*)name;
- (void)setSwatchNeutral;
- (void)setSwatchSelected:(BOOL)selected;

@end

NS_ASSUME_NONNULL_END
