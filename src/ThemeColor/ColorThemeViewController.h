//
//  ColorThemeViewController.h
//  PrimeFreeBird
//

#import <UIKit/UIKit.h>
#import "ColorSwatchControl.h"

NS_ASSUME_NONNULL_BEGIN

@interface ColorThemeViewController : UIViewController

@property (nonatomic, strong) NSMutableArray<ColorSwatchControl*>* swatches;
@property (nonatomic, strong) UIView* customColorDot;

@end

NS_ASSUME_NONNULL_END
