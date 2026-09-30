#import "Support/HookHelpers.h"
#import <QuartzCore/QuartzCore.h>
#import "Sideload/PFBReplyWebViewState.h"
#import "Sideload/PFBWeakScriptMessageHandler.h"

@implementation PFBWeakScriptMessageHandler
- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}
@end
