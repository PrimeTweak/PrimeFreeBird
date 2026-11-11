// Probe for Twitter 12.42.1: how Block web ads reaches Twitter's web views (lists, engine,
// pages), and whether 12.42.1 still has the method and switches three options rely on.
// Everything goes to the report's MEASUREMENTS; the file goes once they are read.

#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import "Support/HookHelpers.h"

@interface PFBProbeMessages : NSObject <WKScriptMessageHandler>
@end

typedef void (^PFBProbeListReply)(WKContentRuleList*, NSError*);

static CFTimeInterval gProbeStart;
static BOOL gProbeFresh;
static NSInteger gProbeViews;
static NSMutableSet<NSString*>* gProbeAsked;
static NSMutableSet<NSString*>* gProbeDelegates;
static PFBProbeMessages* gProbeMessages;
static const void* kProbeViewKey = &kProbeViewKey;
static const void* kProbeControllerKey = &kProbeControllerKey;
static NSString* const kProbeHandler = @"pfbWebAdsProbe";
static NSString* const kProbeFreshKey = @"PFBProbe1242FreshCompileDone";

static NSString* pfbProbeNow(void) {
    return [NSString stringWithFormat:@"+%.1f s", CACurrentMediaTime() - gProbeStart];
}

static void pfbProbe(NSString* topic, NSString* line) {
    PFBCompatMeasure(topic, line, 60);
}

static NSString* pfbProbeListName(NSString* identifier) {
    NSArray* parts = [identifier componentsSeparatedByString:@"."];
    return parts.count >= 4 ? [NSString stringWithFormat:@"%@.%@", parts[parts.count - 2], parts.lastObject] : identifier;
}

// The first two frames of Twitter's own code on the stack, by binary and nearest symbol.
static NSString* pfbProbeCaller(void) {
    NSString* bundle = NSBundle.mainBundle.bundlePath;
    Dl_info own;
    dladdr((const void*)&pfbProbeCaller, &own);
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for (NSNumber* address in [NSThread callStackReturnAddresses]) {
        Dl_info info;
        if (!dladdr((const void*)address.unsignedLongValue, &info) || !info.dli_fname) {
            continue;
        }
        NSString* path = @(info.dli_fname);
        if ((own.dli_fname && strcmp(info.dli_fname, own.dli_fname) == 0) || ![path hasPrefix:bundle]) {
            continue;
        }
        NSString* symbol = info.dli_sname ? @(info.dli_sname)
                                          : [NSString stringWithFormat:@"+0x%lx", (unsigned long)(address.unsignedLongValue - (uintptr_t)info.dli_fbase)];
        [frames addObject:[NSString stringWithFormat:@"%@ %@", path.lastPathComponent, [symbol substringToIndex:MIN(symbol.length, (NSUInteger)60)]]];
        if (frames.count == 2) {
            break;
        }
    }
    return frames.count ? [frames componentsJoinedByString:@" < "] : @"no frame of Twitter";
}

// What a controller holds of Block web ads: its lists, its engine and the web views using it.
static NSMutableDictionary* pfbProbeController(WKUserContentController* controller) {
    NSMutableDictionary* state = objc_getAssociatedObject(controller, kProbeControllerKey);
    if (!state) {
        state = [@{@"lists": @0, @"engine": @NO, @"views": [NSMutableArray array]} mutableCopy];
        objc_setAssociatedObject(controller, kProbeControllerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static NSString* pfbProbeViews(NSDictionary* state) {
    NSArray* views = state[@"views"];
    return views.count ? [@"web view #" stringByAppendingString:[views componentsJoinedByString:@", #"]] : @"no web view yet";
}

static NSString* pfbProbeHolds(NSDictionary* state) {
    return [NSString stringWithFormat:@"lists %@, engine %@", state[@"lists"], [state[@"engine"] boolValue] ? @"yes" : @"no"];
}

static NSString* const kProbeScript =
    @"(function () {\n"
     "  if (window.top !== window || !/^https?:$/.test(location.protocol)) { return; }\n"
     "  const channel = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pfbWebAdsProbe;\n"
     "  if (!channel) { return; }\n"
     "  const host = location.hostname;\n"
     "  channel.postMessage({ t: 'start', host });\n"
     "  const load = (url) => fetch(url, { mode: 'no-cors', cache: 'no-store', credentials: 'omit' }).then(() => 'loaded', () => 'refused');\n"
     "  const stamp = '?pfbprobe=' + Date.now();\n"
     "  Promise.all([load('https://securepubads.g.doubleclick.net/tag/js/gpt.js' + stamp), load(location.origin + '/favicon.ico' + stamp)])\n"
     "    .then(([ad, own]) => channel.postMessage({ t: 'check', host, ad, own }));\n"
     "})();";

@implementation PFBProbeMessages

- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    NSDictionary* body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSString* host = [body[@"host"] isKindOfClass:[NSString class]] ? [body[@"host"] substringToIndex:MIN([body[@"host"] length], (NSUInteger)60)] : nil;
    if (!host.length) {
        return;
    }
    NSNumber* number = message.webView ? objc_getAssociatedObject(message.webView, kProbeViewKey) : nil;
    NSString* view = number ? [@"#" stringByAppendingString:number.stringValue] : @"#?";
    NSDictionary* state = pfbProbeController(controller);
    if ([body[@"t"] isEqual:@"start"]) {
        pfbProbe(@"probe pages", [NSString stringWithFormat:@"%@ %@ %@ starts: %@", pfbProbeNow(), view, host, pfbProbeHolds(state)]);
    } else if ([body[@"t"] isEqual:@"check"]) {
        pfbProbe(@"probe pages", [NSString stringWithFormat:@"%@ %@ %@ test ad request %@, same-site control %@", pfbProbeNow(), view, host,
                                                          body[@"ad"], body[@"own"]]);
    }
}

@end

static void pfbProbeAsked(NSString* key, const char* how) {
    if (![key isKindOfClass:[NSString class]] || key.length < 10) {
        return;
    }
    unichar first = [key characterAtIndex:0];
    if (first != 'a' && first != 'h' && first != 'i' && first != 'w') {
        return;
    }
    BOOL watched = [key hasPrefix:@"ad_formats_"] || [key hasPrefix:@"hometimeline_pinned_tabs_"] ||
                   [key hasPrefix:@"ios_double_max_zoom"] ||
                   [key isEqualToString:@"wcl_unified_cards_likely_open_link_prefetch_enabled"] ||
                   [key isEqualToString:@"ios_liquid_glass_redesign_enabled"];
    if (!watched) {
        return;
    }
    @synchronized(gProbeAsked) {
        if ([gProbeAsked containsObject:key]) {
            return;
        }
        [gProbeAsked addObject:key];
    }
    pfbProbe(@"probe 12.42.1", [NSString stringWithFormat:@"%@ asked: %@ (%s)", pfbProbeNow(), key, how]);
}

static NSString* pfbProbeKeyReaders(NSString* className) {
    Class cls = NSClassFromString(className);
    unsigned count = 0;
    Method* methods = cls ? class_copyMethodList(cls, &count) : NULL;
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (unsigned index = 0; index < count; index++) {
        NSString* name = NSStringFromSelector(method_getName(methods[index]));
        if ([name hasSuffix:@"ForKey:"]) {
            [names addObject:name];
        }
    }
    free(methods);
    return [NSString stringWithFormat:@"%@ reads keys through: %@", className,
                                      names.count ? [[names sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "] : @"nothing"];
}

// Every selector of Twitter's own classes whose name speaks of a maximum zoom or 4K images.
static void pfbProbeScanSelectors(void) {
    CFTimeInterval start = CACurrentMediaTime();
    NSString* bundle = NSBundle.mainBundle.bundlePath;
    Dl_info own;
    dladdr((const void*)&pfbProbeScanSelectors, &own);
    NSUInteger images = 0;
    NSUInteger classes = 0;
    NSMutableOrderedSet<NSString*>* found = [NSMutableOrderedSet orderedSet];
    for (uint32_t image = 0; image < _dyld_image_count(); image++) {
        const char* path = _dyld_get_image_name(image);
        if (!path || ![@(path) hasPrefix:bundle] || (own.dli_fname && strcmp(path, own.dli_fname) == 0)) {
            continue;
        }
        images++;
        unsigned count = 0;
        const char** names = objc_copyClassNamesForImage(path, &count);
        for (unsigned index = 0; index < count; index++) {
            Class cls = objc_getClass(names[index]);
            for (Class side = cls; side; side = (side == cls ? object_getClass(cls) : Nil)) {
                unsigned methodCount = 0;
                Method* methods = class_copyMethodList(side, &methodCount);
                for (unsigned item = 0; item < methodCount; item++) {
                    const char* selector = sel_getName(method_getName(methods[item]));
                    if (strcasestr(selector, "maxzoom") || strcasestr(selector, "4kimage") || strcasestr(selector, "doublemax")) {
                        [found addObject:[NSString stringWithFormat:@"%s %c%s", names[index], side == cls ? '-' : '+', selector]];
                    }
                }
                free(methods);
            }
            classes++;
        }
        free(names);
    }
    pfbProbe(@"probe 12.42.1", [NSString stringWithFormat:@"selectors with MaxZoom, 4KImage or DoubleMax in %lu classes of %lu binaries of Twitter (%.1f s): %@",
                                                          (unsigned long)classes, (unsigned long)images, CACurrentMediaTime() - start,
                                                          found.count ? [found.array componentsJoinedByString:@", "] : @"none"]);
}

static void pfbProbeTwitterChecks(void) {
    Class account = NSClassFromString(@"TFNTwitterAccount");
    SEL zoom = NSSelectorFromString(@"isDoubleMaxZoomFor4KImagesEnabled");
    pfbProbe(@"probe 12.42.1", [NSString stringWithFormat:@"TFNTwitterAccount %@, -isDoubleMaxZoomFor4KImagesEnabled %@",
                                                          account ? @"present" : @"missing",
                                                          account && class_getInstanceMethod(account, zoom) ? @"present" : @"absent"]);
    pfbProbe(@"probe 12.42.1", pfbProbeKeyReaders(@"TFSFeatureSwitches"));
    pfbProbe(@"probe 12.42.1", pfbProbeKeyReaders(@"TFSInstrumentedFeatureSwitches"));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      pfbProbeScanSelectors();
    });
}

%hook WKContentRuleListStore

// On the first launch of this build, a list found compiled is compiled again, so its time shows.
- (void)lookUpContentRuleListForIdentifier:(NSString*)identifier completionHandler:(PFBProbeListReply)completion {
    if (![identifier hasPrefix:@"PFBWebAds."] || !completion) {
        %orig;
        return;
    }
    NSString* asked = pfbProbeNow();
    %orig(identifier, ^(WKContentRuleList* list, NSError* error) {
      pfbProbe(@"probe lists", [NSString stringWithFormat:@"%@ %@ %@ in iOS's store (asked at %@)%@", pfbProbeNow(), pfbProbeListName(identifier),
                                                        list ? @"found" : @"not found", asked, list && gProbeFresh ? @", compiled again" : @""]);
      completion(gProbeFresh ? nil : list, gProbeFresh ? nil : error);
    });
}

- (void)compileContentRuleListForIdentifier:(NSString*)identifier
                     encodedContentRuleList:(NSString*)rules
                          completionHandler:(PFBProbeListReply)completion {
    if (![identifier hasPrefix:@"PFBWebAds."] || !completion) {
        %orig;
        return;
    }
    NSString* asked = pfbProbeNow();
    CFTimeInterval start = CACurrentMediaTime();
    %orig(identifier, rules, ^(WKContentRuleList* list, NSError* error) {
      pfbProbe(@"probe lists", [NSString stringWithFormat:@"%@ %@ %@ %.1f s after it was asked at %@ (%lu KB)%@", pfbProbeNow(), pfbProbeListName(identifier),
                                                        list ? @"compiled" : @"failed", CACurrentMediaTime() - start, asked,
                                                        (unsigned long)(rules.length / 1024), error ? [@": " stringByAppendingString:error.localizedDescription] : @""]);
      completion(list, error);
    });
}

%end

%hook WKUserContentController

- (void)addContentRuleList:(WKContentRuleList*)list {
    %orig;
    if (![list.identifier hasPrefix:@"PFBWebAds."]) {
        return;
    }
    NSMutableDictionary* state = pfbProbeController(self);
    NSInteger lists = [state[@"lists"] integerValue] + 1;
    state[@"lists"] = @(lists);
    if (lists == 1) {
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ first list added for %@", pfbProbeNow(), pfbProbeViews(state)]);
    }
}

// The engine's script brings the probe's own, which reports each page as soon as it starts.
- (void)addUserScript:(WKUserScript*)script {
    %orig;
    if (![script.source containsString:@"\npfbWebAdsEngine("]) {
        return;
    }
    NSMutableDictionary* state = pfbProbeController(self);
    if ([state[@"engine"] boolValue]) {
        return;
    }
    state[@"engine"] = @YES;
    [self addUserScript:[[WKUserScript alloc] initWithSource:kProbeScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    [self addScriptMessageHandler:gProbeMessages name:kProbeHandler];
}

- (void)removeContentRuleList:(WKContentRuleList*)list {
    if ([list.identifier hasPrefix:@"PFBWebAds."]) {
        NSMutableDictionary* state = pfbProbeController(self);
        state[@"lists"] = @(MAX(0, [state[@"lists"] integerValue] - 1));
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ %@ removed from %@ by %@", pfbProbeNow(), pfbProbeListName(list.identifier),
                                                              pfbProbeViews(state), pfbProbeCaller()]);
    }
    %orig;
}

- (void)removeAllContentRuleLists {
    NSMutableDictionary* state = pfbProbeController(self);
    if ([state[@"lists"] integerValue]) {
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ all lists removed from %@ by %@", pfbProbeNow(), pfbProbeViews(state), pfbProbeCaller()]);
        state[@"lists"] = @0;
    }
    %orig;
}

- (void)removeAllUserScripts {
    NSMutableDictionary* state = pfbProbeController(self);
    if ([state[@"engine"] boolValue]) {
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ all scripts removed from %@ by %@", pfbProbeNow(), pfbProbeViews(state), pfbProbeCaller()]);
        state[@"engine"] = @NO;
    }
    %orig;
}

- (void)removeScriptMessageHandlerForName:(NSString*)name {
    if ([name hasPrefix:@"pfbWebAds"]) {
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ handler %@ removed from %@ by %@", pfbProbeNow(), name,
                                                              pfbProbeViews(pfbProbeController(self)), pfbProbeCaller()]);
    }
    %orig;
}

- (void)removeAllScriptMessageHandlers {
    NSMutableDictionary* state = pfbProbeController(self);
    if ([state[@"engine"] boolValue]) {
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ all handlers removed from %@ by %@", pfbProbeNow(), pfbProbeViews(state), pfbProbeCaller()]);
    }
    %orig;
}

%end

%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration*)configuration {
    WKWebView* view = %orig;
    if (view) {
        NSInteger number = ++gProbeViews;
        objc_setAssociatedObject(view, kProbeViewKey, @(number), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSMutableDictionary* state = pfbProbeController(configuration.userContentController ?: view.configuration.userContentController);
        [state[@"views"] addObject:@(number)];
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ web view #%ld (%@) made by %@: %@, shared by %@", pfbProbeNow(), (long)number,
                                                              NSStringFromClass([view class]), pfbProbeCaller(), pfbProbeHolds(state), pfbProbeViews(state)]);
    }
    return view;
}

- (void)setNavigationDelegate:(id<WKNavigationDelegate>)delegate {
    %orig;
    NSString* name = delegate ? NSStringFromClass([delegate class]) : nil;
    BOOL first = NO;
    if (name) {
        @synchronized(gProbeDelegates) {
            first = ![gProbeDelegates containsObject:name];
            [gProbeDelegates addObject:name];
        }
    }
    if (first) {
        SEL heard = NSSelectorFromString(@"_webView:contentRuleListWithIdentifier:performedAction:forURL:");
        NSNumber* number = objc_getAssociatedObject(self, kProbeViewKey);
        pfbProbe(@"probe web views", [NSString stringWithFormat:@"%@ web view #%@ navigation delegate %@: blocked loads %@", pfbProbeNow(), number ?: @"?",
                                                              name, [delegate respondsToSelector:heard] ? @"heard" : @"not heard"]);
    }
}

- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    NSNumber* number = objc_getAssociatedObject(self, kProbeViewKey);
    NSString* host = request.URL.host;
    if (host.length && !PFBIsXDomain(host)) {
        pfbProbe(@"probe pages", [NSString stringWithFormat:@"%@ #%@ loadRequest %@: %@", pfbProbeNow(), number ?: @"?", host,
                                                          pfbProbeHolds(pfbProbeController(self.configuration.userContentController))]);
    }
    return %orig;
}

%end

%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    pfbProbeAsked(key, "boolForKey");
    return %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    pfbProbeAsked(key, "integerForKey");
    return %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    pfbProbeAsked(key, "numberForKey");
    return %orig;
}

- (id)rawValueForKey:(NSString*)key {
    pfbProbeAsked(key, "rawValueForKey");
    return %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    pfbProbeAsked(key, "unsafePeekBoolForKey");
    return %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    pfbProbeAsked(key, "unsafePeekIntegerForKey");
    return %orig;
}

- (double)doubleForKey:(NSString*)key {
    pfbProbeAsked(key, "doubleForKey");
    return %orig;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    pfbProbeAsked(key, "unsafePeekDoubleForKey");
    return %orig;
}

- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    pfbProbeAsked(key, "hasNonDefaultValueForKey");
    return %orig;
}

%end

%hook TFSInstrumentedFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented boolForKey");
    return %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented integerForKey");
    return %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented numberForKey");
    return %orig;
}

- (id)rawValueForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented rawValueForKey");
    return %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented unsafePeekBoolForKey");
    return %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented unsafePeekIntegerForKey");
    return %orig;
}

- (double)doubleForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented doubleForKey");
    return %orig;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented unsafePeekDoubleForKey");
    return %orig;
}

- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    pfbProbeAsked(key, "instrumented hasNonDefaultValueForKey");
    return %orig;
}

%end

%ctor {
    gProbeStart = CACurrentMediaTime();
    gProbeAsked = [NSMutableSet set];
    gProbeDelegates = [NSMutableSet set];
    gProbeMessages = [PFBProbeMessages new];
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    gProbeFresh = ![defaults boolForKey:kProbeFreshKey];
    [defaults setBool:YES forKey:kProbeFreshKey];
    %init;
    pfbProbe(@"probe lists", [NSString stringWithFormat:@"probe on, lists compiled again this launch: %@", gProbeFresh ? @"yes" : @"no"]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pfbProbeTwitterChecks();
    });
}
