#import "Support/HookHelpers.h"
#import <QuartzCore/QuartzCore.h>
#import "Sideload/PFBReplyWebViewState.h"
#import "Sideload/PFBIconRelay.h"

@implementation PFBIconRelay
+ (instancetype)shared {
    static PFBIconRelay* s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [PFBIconRelay new]; });
    return s;
}
- (void)userContentController:(WKUserContentController*)ucc
      didReceiveScriptMessage:(WKScriptMessage*)msg {
    if (![msg.name isEqualToString:@"pfbTap"]) { return; }
    NSInteger oi = [msg.body integerValue];
    NSString* js = [NSString stringWithFormat:
        @"(function(){var tb=document.querySelector('[data-testid=\"toolBar\"]');if(!tb)return;"
        @"var bs=tb.querySelectorAll('button,[role=\"button\"]');if(bs[%ld]){"
        @"bs[%ld].dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,view:window}));"
        @"}})();", (long)oi, (long)oi];
    [gPFBRelayWebView evaluateJavaScript:js completionHandler:nil];
}
@end
