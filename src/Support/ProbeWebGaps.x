// Probe for Block web ads, removed once read: the empty spaces ads leave on a page, from probe-gaps.js in every
// page and large frame, and whether the page engine is on each web view, as "probe gaps".

#import <WebKit/WebKit.h>
#import "Support/HookHelpers.h"

static NSString* const kPFBGapProbeTopic = @"probe gaps";
static const NSUInteger kPFBGapProbeCap = 1500;
static const void* kPFBGapProbeAddedKey = &kPFBGapProbeAddedKey;
static WKUserScript* gPFBGapProbeScript;

static void PFBGapProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBGapProbeTopic, line.length > 240 ? [line substringToIndex:240] : line, kPFBGapProbeCap);
}

static NSString* PFBGapProbeText(id value, NSUInteger limit) {
    NSString* text = [value isKindOfClass:[NSString class]] ? value : @"";
    return text.length > limit ? [text substringToIndex:limit] : text;
}

@interface PFBGapProbeHandler : NSObject <WKScriptMessageHandler>
@end

@implementation PFBGapProbeHandler

- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    NSDictionary* body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSString* prefix = [NSString stringWithFormat:@"%@ %@:", PFBGapProbeText(body[@"where"], 10), PFBGapProbeText(body[@"host"], 60)];
    for (id line in [body[@"lines"] isKindOfClass:[NSArray class]] ? body[@"lines"] : @[]) {
        PFBGapProbeLine([NSString stringWithFormat:@"%@ %@", prefix, PFBGapProbeText(line, 220)]);
    }
}

@end

static PFBGapProbeHandler* gPFBGapProbeHandler;

%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration*)configuration {
    WKUserContentController* controller = configuration.userContentController;
    if (controller && gPFBGapProbeScript && !objc_getAssociatedObject(controller, kPFBGapProbeAddedKey)) {
        objc_setAssociatedObject(controller, kPFBGapProbeAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [controller addUserScript:gPFBGapProbeScript];
        [controller addScriptMessageHandler:gPFBGapProbeHandler name:@"pfbGapProbe"];
    }
    return %orig;
}

// Each web page opened, and whether its web view has the page engine.
- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    NSURL* url = request.URL;
    if ([url.scheme hasPrefix:@"http"] && url.host.length && !PFBIsXDomain(url.host)) {
        BOOL engine = NO;
        for (WKUserScript* script in self.configuration.userContentController.userScripts) {
            engine = engine || [script.source containsString:@"pfbWebAdsEngine("];
        }
        PFBGapProbeLine([NSString stringWithFormat:@"opens %@, page engine %@", url.host, engine ? @"on" : @"off"]);
    }
    return %orig;
}

%end

%ctor {
    NSURL* url = [[PFBBundle sharedBundle] pathForFile:@"probe-gaps.js"];
    NSString* source = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
    if (source.length) {
        gPFBGapProbeHandler = [PFBGapProbeHandler new];
        gPFBGapProbeScript = [[WKUserScript alloc] initWithSource:source
                                                    injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                 forMainFrameOnly:NO];
    } else {
        PFBGapProbeLine(@"probe-gaps.js missing");
    }
    %init;
}
