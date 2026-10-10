#import <UIKit/UIKit.h>

// Lays its subviews out in a flow and reports the resulting height as its intrinsic
// size, so Auto Layout sizes the cell through the normal self-sizing path. A
// re-measure started inside a layout pass lands mid-animation and jumps the row.
@interface PFBTabFlowView : UIView
@property (nonatomic, assign) CGFloat lineHeight;
@property (nonatomic, assign) CGFloat gap;
@property (nonatomic, assign) CGFloat reportedHeight;
@end
