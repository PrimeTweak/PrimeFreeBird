// Block web ads: EasyList, EasyPrivacy and Fanboy's Annoyance list, made into WebKit content
// blockers by tools/easylist-webkit.py, are compiled once by iOS and put on Twitter's web views.
// The lists leave X's own pages alone, the tweak's web views included.

#import <WebKit/WebKit.h>
#import "Support/HookHelpers.h"

static NSArray<WKContentRuleList*>* gPFBWebAdLists;
static NSHashTable<WKUserContentController*>* gPFBWebAdWaiting;
static BOOL gPFBWebAdLoading;
static const void* kPFBWebAdViewKey = &kPFBWebAdViewKey;

// Links that open in the browser of the phone never reach a web view of Twitter.
static BOOL pfbWebAdsWanted(void) {
    return [PFBSettings boolForKey:@"block_web_ads"] && ![PFBSettings boolForKey:@"always_open_safari"];
}

static void pfbWebAdsAttach(WKUserContentController* controller) {
    for (WKContentRuleList* list in gPFBWebAdLists) {
        [controller addContentRuleList:list];
    }
}

static void pfbWebAdsNote(NSString* text) {
    PFBCompatMeasure(@"web ads", text, 8);
}

// The lists named in web-ads.json are looked up in iOS's store under their version and
// compiled only when missing; lists of other versions are removed once these are ready.
static void pfbWebAdsLoad(void) {
    if (gPFBWebAdLoading) {
        return;
    }
    gPFBWebAdLoading = YES;
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
    dispatch_group_t group = dispatch_group_create();
    for (NSString* name in names) {
        if (![name isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString* identifier = [NSString stringWithFormat:@"PFBWebAds.%@.%@", version, name];
        [current addObject:identifier];
        dispatch_group_enter(group);
        void (^keep)(WKContentRuleList*) = ^(WKContentRuleList* list) {
            @synchronized(ready) {
                [ready addObject:list];
            }
        };
        [store lookUpContentRuleListForIdentifier:identifier
                                completionHandler:^(WKContentRuleList* found, __unused NSError* missing) {
                                    if (found) {
                                        keep(found);
                                        dispatch_group_leave(group);
                                        return;
                                    }
                                    NSURL* url = [[PFBBundle sharedBundle] pathForFile:name];
                                    NSString* rules = url ? [NSString stringWithContentsOfURL:url
                                                                                     encoding:NSUTF8StringEncoding
                                                                                        error:nil]
                                                          : nil;
                                    if (!rules) {
                                        pfbWebAdsNote([name stringByAppendingString:@" missing"]);
                                        dispatch_group_leave(group);
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
                                                                 dispatch_group_leave(group);
                                                             }];
                                }];
    }
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

%hook WKWebView

// A web view made before the lists are ready gets them as soon as they are.
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration*)configuration {
    WKUserContentController* controller = configuration.userContentController;
    BOOL attached = NO;
    if (controller && pfbWebAdsWanted()) {
        pfbWebAdsLoad();
        if (gPFBWebAdLists.count) {
            pfbWebAdsAttach(controller);
            attached = YES;
        } else {
            [gPFBWebAdWaiting addObject:controller];
        }
    }
    WKWebView* view = %orig;
    if (view) {
        objc_setAssociatedObject(view, kPFBWebAdViewKey, @(attached), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
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
