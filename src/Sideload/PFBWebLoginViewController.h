#import <UIKit/UIKit.h>

// x.com's login flow and the desktop user agent both sign-in screens load it with, so x.com
// serves its desktop flow.
FOUNDATION_EXPORT NSString* const PFBWebLoginFlowURL;
FOUNDATION_EXPORT NSString* const PFBDesktopSafariUserAgent;

// The web login screen: x.com's login flow in a WKWebView under a native header;
// the session cookies are captured and handed to PFBLoginBridge.
@interface PFBWebLoginViewController : UIViewController
+ (void)presentFrom:(UIViewController*)presenter;
+ (UINavigationController*)rootNavigationController;
@end
