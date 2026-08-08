//
//  ColorSwatchControl.h
//  PrimeFreeBird
//
//  A pill-style accent-color option: a rounded colored capsule with the color
//  name inside, and a radio-style checkmark circle below it.
//

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
