// The margin shared by the muted words screen and its cells.
#import <UIKit/UIKit.h>

// The table's layout margins resolve to about 20 points inside a cell and about 8
// on a section header's bare view, and neither matches the 10 the rest of the
// settings uses. One number, applied everywhere.
static const CGFloat kPFBMutedSideMargin = 10.0;
