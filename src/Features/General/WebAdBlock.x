// Block web ads: EasyList, EasyPrivacy and Fanboy's Annoyance list, made by tools/easylist-webkit.py
// into WebKit content blockers compiled once by iOS, and into rules for web-ads-engine.js, which
// runs at the start of each page. Both leave X's own pages alone, the tweak's web views included.

#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "Support/HookHelpers.h"

@interface PFBWebAdReports : NSObject <WKScriptMessageHandler>
@end

static NSArray<WKContentRuleList*>* gPFBWebAdLists;
static NSHashTable<WKUserContentController*>* gPFBWebAdWaiting;
static WKUserScript* gPFBWebAdScript;
static PFBWebAdReports* gPFBWebAdReports;
static BOOL gPFBWebAdLoading;
static const void* kPFBWebAdViewKey = &kPFBWebAdViewKey;
static const void* kPFBWebAdControllerKey = &kPFBWebAdControllerKey;
static const void* kPFBWebAdBlockedKey = &kPFBWebAdBlockedKey;
static NSString* const kPFBWebAdHandler = @"pfbWebAds";
static const NSUInteger kPFBWebAdHasScript = 1;
static const NSUInteger kPFBWebAdHasLists = 2;

// Links that open in the browser of the phone never reach a web view of Twitter.
static BOOL pfbWebAdsWanted(void) {
    return [PFBSettings boolForKey:@"block_web_ads"] && ![PFBSettings boolForKey:@"always_open_safari"];
}

static void pfbWebAdsNote(NSString* text) {
    PFBCompatMeasure(@"web ads", text, 8);
}

// A controller shared by several web views gets the engine, its report and the lists once.
static void pfbWebAdsAttach(WKUserContentController* controller) {
    NSUInteger done = [objc_getAssociatedObject(controller, kPFBWebAdControllerKey) unsignedIntegerValue];
    if (!(done & kPFBWebAdHasScript) && gPFBWebAdScript) {
        [controller addUserScript:gPFBWebAdScript];
        [controller addScriptMessageHandler:gPFBWebAdReports name:kPFBWebAdHandler];
        done |= kPFBWebAdHasScript;
    }
    if (!(done & kPFBWebAdHasLists) && gPFBWebAdLists.count) {
        for (WKContentRuleList* list in gPFBWebAdLists) {
            [controller addContentRuleList:list];
        }
        done |= kPFBWebAdHasLists;
    }
    objc_setAssociatedObject(controller, kPFBWebAdControllerKey, @(done), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The engine and its rules make one script, run at the start of every page and frame.
static void pfbWebAdsMakeScript(void) {
    NSURL* engineURL = [[PFBBundle sharedBundle] pathForFile:@"web-ads-engine.js"];
    NSURL* rulesURL = [[PFBBundle sharedBundle] pathForFile:@"web-ads-page.json"];
    NSString* engine = engineURL ? [NSString stringWithContentsOfURL:engineURL encoding:NSUTF8StringEncoding error:nil] : nil;
    NSString* rules = rulesURL ? [NSString stringWithContentsOfURL:rulesURL encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!engine.length || !rules.length) {
        pfbWebAdsNote(@"web-ads-engine.js or web-ads-page.json missing or unreadable");
        return;
    }
    NSString* source = [NSString stringWithFormat:@"(function () {\n%@\npfbWebAdsEngine(%@);\n})();", engine, rules];
    gPFBWebAdReports = [PFBWebAdReports new];
    gPFBWebAdScript = [[WKUserScript alloc] initWithSource:source
                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                          forMainFrameOnly:NO];
}

// The lists named in web-ads.json are looked up in iOS's store under their version and
// compiled only when missing; lists of other versions are removed once these are ready.
static void pfbWebAdsLoad(void) {
    if (gPFBWebAdLoading) {
        return;
    }
    gPFBWebAdLoading = YES;
    pfbWebAdsMakeScript();
    NSURL* indexURL = [[PFBBundle sharedBundle] pathForFile:@"web-ads.json"];
    NSData* indexData = indexURL ? [NSData dataWithContentsOfURL:indexURL] : nil;
    id index = indexData ? [NSJSONSerialization JSONObjectWithData:indexData options:0 error:nil] : nil;
    NSString* version = [index isKindOfClass:[NSDictionary class]] ? index[@"version"] : nil;
    NSArray* names = [index isKindOfClass:[NSDictionary class]] ? index[@"lists"] : nil;
    if (![version isKindOfClass:[NSString class]] || ![names isKindOfClass:[NSArray class]] || names.count == 0) {
        pfbWebAdsNote(@"web-ads.json missing or unreadable");
        return;
    }
    WKContentRuleListStore* store = [WKContentRuleListStore defaultStore];
    NSMutableArray<WKContentRuleList*>* ready = [NSMutableArray array];
    NSMutableSet<NSString*>* current = [NSMutableSet set];
    NSMutableSet<NSString*>* pending = [NSMutableSet set];
    dispatch_group_t group = dispatch_group_create();
    for (NSString* name in names) {
        if (![name isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString* identifier = [NSString stringWithFormat:@"PFBWebAds.%@.%@", version, name];
        [current addObject:identifier];
        [pending addObject:name];
        dispatch_group_enter(group);
        void (^keep)(WKContentRuleList*) = ^(WKContentRuleList* list) {
            @synchronized(ready) {
                [ready addObject:list];
            }
        };
        void (^leave)(void) = ^{
            @synchronized(pending) {
                [pending removeObject:name];
            }
            dispatch_group_leave(group);
        };
        [store lookUpContentRuleListForIdentifier:identifier
                                completionHandler:^(WKContentRuleList* found, __unused NSError* missing) {
                                    if (found) {
                                        keep(found);
                                        leave();
                                        return;
                                    }
                                    NSURL* url = [[PFBBundle sharedBundle] pathForFile:name];
                                    NSString* rules = url ? [NSString stringWithContentsOfURL:url
                                                                                     encoding:NSUTF8StringEncoding
                                                                                        error:nil]
                                                          : nil;
                                    if (!rules) {
                                        pfbWebAdsNote([name stringByAppendingString:@" missing"]);
                                        leave();
                                        return;
                                    }
                                    [store compileContentRuleListForIdentifier:identifier
                                                        encodedContentRuleList:rules
                                                             completionHandler:^(WKContentRuleList* list, NSError* error) {
                                                                 if (list) {
                                                                     keep(list);
                                                                 } else {
                                                                     pfbWebAdsNote([NSString stringWithFormat:@"%@ not compiled: %@",
                                                                                                              name, error.localizedDescription]);
                                                                 }
                                                                 leave();
                                                             }];
                                }];
    }
    // A list iOS has still not compiled a minute later holds back all of them, so it is reported.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      NSArray<NSString*>* late;
      @synchronized(pending) {
          late = [pending.allObjects sortedArrayUsingSelector:@selector(compare:)];
      }
      if (late.count) {
          pfbWebAdsNote([@"not compiled after 60 s: " stringByAppendingString:[late componentsJoinedByString:@", "]]);
      }
    });
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
      @synchronized(ready) {
          gPFBWebAdLists = [ready copy];
      }
      for (WKUserContentController* controller in gPFBWebAdWaiting) {
          pfbWebAdsAttach(controller);
      }
      [gPFBWebAdWaiting removeAllObjects];
      [store getAvailableContentRuleListIdentifiers:^(NSArray<NSString*>* identifiers) {
          for (NSString* identifier in identifiers) {
              if ([identifier hasPrefix:@"PFBWebAds."] && ![current containsObject:identifier]) {
                  [store removeContentRuleListForIdentifier:identifier completionHandler:^(__unused NSError* error){
                  }];
              }
          }
      }];
    });
}

// The loads the lists block on a page, kept on its web view until the engine reports the page.
static void pfbWebAdsBlocked(__unused id delegate, __unused SEL command, WKWebView* webView, NSString* identifier,
                             id action, NSURL* url) {
    if ([action respondsToSelector:NSSelectorFromString(@"blockedLoad")] && ![[action valueForKey:@"blockedLoad"] boolValue]) {
        return;
    }
    if (![webView isKindOfClass:[WKWebView class]] || ![identifier hasPrefix:@"PFBWebAds."]) {
        return;
    }
    NSMutableDictionary* page = objc_getAssociatedObject(webView, kPFBWebAdBlockedKey);
    if (!page) {
        page = [@{@"lists": [NSCountedSet set], @"urls": [NSMutableOrderedSet orderedSet]} mutableCopy];
        objc_setAssociatedObject(webView, kPFBWebAdBlockedKey, page, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString* list = [[identifier pathExtension] length] ? [identifier.stringByDeletingPathExtension pathExtension] : identifier;
    [page[@"lists"] addObject:list.length ? list : identifier];
    NSString* address = [(url.host ?: @"") stringByAppendingString:url.path ?: @""];
    NSMutableOrderedSet* urls = page[@"urls"];
    if (urls.count < 6 && address.length) {
        [urls addObject:[address substringToIndex:MIN(address.length, (NSUInteger)70)]];
    }
}

// WebKit asks a navigation delegate once, when it is set, whether it hears of blocked loads.
static void pfbWebAdsWatch(id delegate) {
    SEL heard = NSSelectorFromString(@"_webView:contentRuleListWithIdentifier:performedAction:forURL:");
    if ([delegate respondsToSelector:heard]) {
        return;
    }
    if (class_addMethod([delegate class], heard, (IMP)pfbWebAdsBlocked, "v@:@@@@")) {
        PFBCOMPAT_OBSERVE(PFBCompat_block_web_ads, @"blocked loads followed on %@", NSStringFromClass([delegate class]));
    }
}

static NSInteger pfbWebAdsNumber(NSDictionary* body, NSString* key) {
    return [body[key] isKindOfClass:[NSNumber class]] ? [body[key] integerValue] : 0;
}

static NSString* pfbWebAdsPageLine(NSString* host, NSDictionary* body, WKWebView* webView, BOOL listed) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    if (!listed) {
        [parts addObject:@"block lists not on this page"];
    }
    [parts addObject:[NSString stringWithFormat:@"%ld page rules", (long)pfbWebAdsNumber(body, @"rules")]];
    NSCountedSet* scripts = [NSCountedSet set];
    for (id name in [body[@"scripts"] isKindOfClass:[NSArray class]] ? body[@"scripts"] : @[]) {
        if ([name isKindOfClass:[NSString class]]) {
            [scripts addObject:name];
        }
    }
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (NSString* name in [scripts.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSUInteger count = [scripts countForObject:name];
        [names addObject:count > 1 ? [NSString stringWithFormat:@"%@ x%lu", name, (unsigned long)count] : name];
    }
    if (names.count) {
        [parts addObject:[@"scripts " stringByAppendingString:[names componentsJoinedByString:@", "]]];
    }
    for (NSString* key in @[@"hidden", @"removed", @"styled", @"csp"]) {
        NSInteger value = pfbWebAdsNumber(body, key);
        if (value) {
            [parts addObject:[NSString stringWithFormat:@"%@ %ld", key, (long)value]];
        }
    }
    NSDictionary* page = webView ? objc_getAssociatedObject(webView, kPFBWebAdBlockedKey) : nil;
    NSCountedSet* lists = page[@"lists"];
    if (lists.count) {
        NSUInteger total = 0;
        NSMutableArray<NSString*>* byList = [NSMutableArray array];
        for (NSString* list in [lists.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            total += [lists countForObject:list];
            [byList addObject:[NSString stringWithFormat:@"%@ x%lu", list, (unsigned long)[lists countForObject:list]]];
        }
        [parts addObject:[NSString stringWithFormat:@"blocked %lu (%@): %@", (unsigned long)total,
                                                    [byList componentsJoinedByString:@", "],
                                                    [[page[@"urls"] array] componentsJoinedByString:@", "]]];
        objc_setAssociatedObject(webView, kPFBWebAdBlockedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([body[@"locked"] isEqual:@YES]) {
        [parts addObject:@"scroll locked"];
    }
    return [NSString stringWithFormat:@"%@: %@", host, [parts componentsJoinedByString:@"; "]];
}

@implementation PFBWebAdReports

// A page's report, and a frame's only when it has errors; both come from the page's own world.
- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    NSDictionary* body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSString* host = [body[@"host"] isKindOfClass:[NSString class]] ? body[@"host"] : nil;
    if (!host.length) {
        return;
    }
    host = [host substringToIndex:MIN(host.length, (NSUInteger)60)];
    for (id error in [body[@"errors"] isKindOfClass:[NSArray class]] ? body[@"errors"] : @[]) {
        if ([error isKindOfClass:[NSString class]]) {
            NSString* text = [error substringToIndex:MIN([error length], (NSUInteger)170)];
            PFBCompatMeasure(@"web ads engine", [NSString stringWithFormat:@"%@: %@", host, text], 20);
        }
    }
    if (![body[@"t"] isEqual:@"page"]) {
        return;
    }
    // The option only counts as working on a page that has the lists.
    BOOL listed = ([objc_getAssociatedObject(controller, kPFBWebAdControllerKey) unsignedIntegerValue] & kPFBWebAdHasLists) != 0;
    if (listed) {
        PFBCOMPAT_ACTION(PFBCompat_block_web_ads, @"page engine on a web page");
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_block_web_ads, @"page engine ran, block lists not on the page");
    }
    PFBCompatMeasure(@"web pages", pfbWebAdsPageLine(host, body, message.webView, listed), 30);
}

@end

%hook WKWebView

// A web view made before the lists are ready gets them as soon as they are.
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration*)configuration {
    WKUserContentController* controller = configuration.userContentController;
    BOOL attached = NO;
    if (controller && pfbWebAdsWanted()) {
        pfbWebAdsLoad();
        pfbWebAdsAttach(controller);
        attached = gPFBWebAdLists.count > 0;
        if (!attached) {
            [gPFBWebAdWaiting addObject:controller];
        }
    }
    WKWebView* view = %orig;
    if (view) {
        objc_setAssociatedObject(view, kPFBWebAdViewKey, @(attached), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

- (void)setNavigationDelegate:(id<WKNavigationDelegate>)delegate {
    if (delegate && pfbWebAdsWanted()) {
        pfbWebAdsWatch(delegate);
    }
    %orig;
}

- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    NSURL* url = request.URL;
    if ([url.scheme hasPrefix:@"http"] && url.host.length && !PFBIsXDomain(url.host)) {
        if ([objc_getAssociatedObject(self, kPFBWebAdViewKey) boolValue]) {
            PFBCOMPAT_ACTION(PFBCompat_block_web_ads, @"block lists on a web page");
        } else {
            PFBCOMPAT_OBSERVE(PFBCompat_block_web_ads, @"web page opened");
        }
    }
    return %orig;
}

%end

%ctor {
    %init;
    gPFBWebAdWaiting = [NSHashTable weakObjectsHashTable];
    // Compiled a few seconds after launch, before a link is likely to be opened.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (pfbWebAdsWanted()) {
          pfbWebAdsLoad();
      }
    });
}
