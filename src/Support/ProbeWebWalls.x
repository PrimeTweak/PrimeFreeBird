// Probe for Block web ads, removed once read: how a wall against ad blockers is made, from probe-walls.js in
// every page and frame, whether the page engine is on each web view and what it reports, as "probe walls".

#import <WebKit/WebKit.h>
#import "Support/HookHelpers.h"

static NSString* const kPFBWallProbeTopic = @"probe walls";
static const NSUInteger kPFBWallProbeCap = 600;
static const void* kPFBWallProbeAddedKey = &kPFBWallProbeAddedKey;
static WKUserScript* gPFBWallProbeScript;

static void PFBWallProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBWallProbeTopic, line.length > 240 ? [line substringToIndex:240] : line, kPFBWallProbeCap);
}

// The last four hex digits of an object's address, to tell web views apart in the lines.
static unsigned long PFBWallProbeTag(id object) {
    uintptr_t address = (uintptr_t)(__bridge void*)object;
    return (unsigned long)(address % 0x10000);
}

static BOOL PFBWallProbeHasEngine(WKUserContentController* controller) {
    for (WKUserScript* script in controller.userScripts) {
        if ([script.source containsString:@"pfbWebAdsEngine("]) {
            return YES;
        }
    }
    return NO;
}

static NSString* PFBWallProbeText(id value, NSUInteger limit) {
    NSString* text = [value isKindOfClass:[NSString class]] ? value : @"";
    return text.length > limit ? [text substringToIndex:limit] : text;
}

@interface PFBWallProbeHandler : NSObject <WKScriptMessageHandler>
@end

@implementation PFBWallProbeHandler

- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    NSDictionary* body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSString* prefix = [NSString stringWithFormat:@"%@ %@:", PFBWallProbeText(body[@"where"], 10), PFBWallProbeText(body[@"host"], 60)];
    for (id line in [body[@"lines"] isKindOfClass:[NSArray class]] ? body[@"lines"] : @[]) {
        PFBWallProbeLine([NSString stringWithFormat:@"%@ %@", prefix, PFBWallProbeText(line, 220)]);
    }
}

@end

static PFBWallProbeHandler* gPFBWallProbeHandler;

%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration*)configuration {
    WKUserContentController* controller = configuration.userContentController;
    if (controller && gPFBWallProbeScript && !objc_getAssociatedObject(controller, kPFBWallProbeAddedKey)) {
        objc_setAssociatedObject(controller, kPFBWallProbeAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [controller addUserScript:gPFBWallProbeScript];
        [controller addScriptMessageHandler:gPFBWallProbeHandler name:@"pfbWallProbe"];
    }
    return %orig;
}

// Each web page opened: on which web view, and whether that view has the page engine.
- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    NSURL* url = request.URL;
    if ([url.scheme hasPrefix:@"http"] && url.host.length && !PFBIsXDomain(url.host)) {
        WKUserContentController* controller = self.configuration.userContentController;
        PFBWallProbeLine([NSString stringWithFormat:@"web view %@ %04lx opens %@, page engine %@, %lu page scripts", NSStringFromClass(self.class),
                                                    PFBWallProbeTag(self), url.host, PFBWallProbeHasEngine(controller) ? @"on" : @"off",
                                                    (unsigned long)controller.userScripts.count]);
    }
    return %orig;
}

%end

// What the page engine reports: a page, a frame's errors or a wall taken off.
%hook PFBWebAdReports

- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    NSDictionary* body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSArray* errors = [body[@"errors"] isKindOfClass:[NSArray class]] ? body[@"errors"] : @[];
    PFBWallProbeLine([NSString stringWithFormat:@"engine report %@ from %@, %lu errors%@", PFBWallProbeText(body[@"t"], 10),
                                                PFBWallProbeText(body[@"host"], 60), (unsigned long)errors.count,
                                                [body[@"what"] isKindOfClass:[NSString class]] ? [@", " stringByAppendingString:PFBWallProbeText(body[@"what"], 120)] : @""]);
    %orig;
}

%end

%ctor {
    NSURL* url = [[PFBBundle sharedBundle] pathForFile:@"probe-walls.js"];
    NSString* source = url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
    if (source.length) {
        gPFBWallProbeHandler = [PFBWallProbeHandler new];
        gPFBWallProbeScript = [[WKUserScript alloc] initWithSource:source
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                  forMainFrameOnly:NO];
    } else {
        PFBWallProbeLine(@"probe-walls.js missing");
    }
    %init;
}
