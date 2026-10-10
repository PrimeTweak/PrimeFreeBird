#import <UIKit/UIKit.h>

// The web login screen: x.com's login flow in a WKWebView under a native header;
// the session cookies are captured and handed to PFBLoginBridge.
@interface PFBWebLoginProbeViewController : UIViewController
+ (void)presentFrom:(UIViewController*)presenter;
+ (UINavigationController*)rootNavigationController;
@end
