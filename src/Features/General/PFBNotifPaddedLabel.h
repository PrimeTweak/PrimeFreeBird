#import <UIKit/UIKit.h>

// A label that carries its own horizontal padding, declared through its intrinsic
// size so Auto Layout keeps placing it. Measuring the padding by hand ties it to a
// neighbour that may not be there.
@interface PFBNotifPaddedLabel : UILabel
@end
