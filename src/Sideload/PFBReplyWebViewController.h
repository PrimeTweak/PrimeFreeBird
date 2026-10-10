#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// Custom reply web view. T1WebViewController's shouldAuthenticate path does not
// surface the web session on a sideloaded build, so the harvested cookies are
// seeded into its own store. It stays hidden until the composer is ready.
@interface PFBReplyWebViewController : UIViewController <WKNavigationDelegate, WKScriptMessageHandler>
@property(nonatomic, copy) NSString* statusID;
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, strong) UIActivityIndicatorView* spinner;
@property(nonatomic, assign) BOOL sentHandled;
@property(nonatomic, assign) BOOL revealed;
@end
