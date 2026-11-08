#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// The icon bar posts the tapped toolbar index, relayed as a bubbling click onto x.com's
// hidden toolbar button (React catches it even when display:none).
@interface PFBIconRelay : NSObject <WKScriptMessageHandler>
+ (instancetype)shared;
@end
