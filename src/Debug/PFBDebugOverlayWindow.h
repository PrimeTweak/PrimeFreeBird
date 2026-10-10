#import <UIKit/UIKit.h>

// Its own window so it survives every screen change, above everything, and
// never becomes key — the capture must read the app's window, not this one.
@interface PFBDebugOverlayWindow : UIWindow
@end
