#import <UIKit/UIKit.h>

// A web login screen that loads twitter.com/login in a WKWebView and logs the
// session cookies as they appear. Measurement only: nothing is injected into
// the native session yet.
@interface WebLoginProbeViewController : UIViewController
+ (void)presentFrom:(UIViewController*)presenter;
+ (UINavigationController*)rootNavigationController;
@end
