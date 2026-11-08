#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface PFBWebSessionLoginViewController : UIViewController <WKNavigationDelegate>
@property(nonatomic, copy) void (^completion)(BOOL success);
@property(nonatomic, strong) WKWebView* loginWebView;
@property(nonatomic, strong) UIActivityIndicatorView* spinner;
@property(nonatomic, assign) BOOL finished;
@end
