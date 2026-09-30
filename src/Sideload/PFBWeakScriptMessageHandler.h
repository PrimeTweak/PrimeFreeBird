#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// Weak proxy so the user-content-controller doesn't retain the view controller (which would
// leak it). The controller stays the real handler; this just forwards without a strong ref.
@interface PFBWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> target;
@end
