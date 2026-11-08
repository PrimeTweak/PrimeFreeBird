#import "Sideload/PFBWeakScriptMessageHandler.h"

@implementation PFBWeakScriptMessageHandler
- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}
@end
