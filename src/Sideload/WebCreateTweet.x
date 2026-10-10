// Signs CreateTweet with the web session (auth_token, ct0, a fresh transaction id) and
// rebuilds the Periscope token, mute list and Grok requests as the web client sends them.
// Reply in web view takes only replies off this path, before they are sent.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Sideload/PFBWebSessionLoginViewController.h"

// MARK: - Constants

static NSString* const WebBearer = @"Bearer "
                                   @"AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%"
                                   @"3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";

static NSString* const WebQueryIDDefaultsKey = @"pfb_createtweet_queryid";
static NSString* const PeriscopeWebPath = @"/i/api/1.1/oauth/authenticate_periscope.json";
static NSString* WebCreateTweetQueryID = @"vwzfnq1lLOa1Nfx7htM2mw";

// MARK: - Session state

// Latest cookies harvested from the app's web session (the account currently signed in
// on the web). auth_multi carries the auth_token of every other signed-in account.
static NSString* WebCT0 = nil;
static NSString* WebAuthToken = nil;
static NSString* WebTwid = nil;
static NSString* WebAuthMulti = nil;

// Per-account resolved credentials (userID -> @{auth_token, ct0, twid}).
static NSMutableDictionary<NSString*, NSDictionary*>* WebAccountCookies = nil;
static NSObject* WebAccountCookiesLock = nil;

// Per-session csrf tokens (auth_token -> ct0), and the tokens whose ct0 is being fetched.
static NSMutableDictionary<NSString*, NSString*>* WebCt0ByToken = nil;
static NSMutableSet<NSString*>* WebCt0Minting = nil;

// The authenticated helper webview is kept alive to mint a fresh
// x-client-transaction-id per send (x rate-limits requests without one).
static WKWebView* WebHelperWebView = nil;
static BOOL WebHelperReady = NO;
static BOOL WebHelperInFlight = NO;
// One transaction id per (method, path), minted ahead of the request that needs it.
// Written on the main thread and read from the request's thread, so every access
// takes the lock.
static NSMutableDictionary<NSString*, NSString*>* WebXTIDByKey = nil;
static NSMutableSet<NSString*>* WebXTIDMinting = nil;
static NSObject* WebXTIDLock = nil;

// Offscreen native webview that establishes and harvests a specific account's web session.
static UIWindow* WebHarvestWindow = nil;
static BOOL WebBootstrapInFlight = NO;

static const void* WebPostingUIDKey = &WebPostingUIDKey;
static const void* WebHarvestWebViewKey = &WebHarvestWebViewKey;
static const void* CreateTweetWatcherKey = &CreateTweetWatcherKey;

static void refreshXTID(void);
static void refreshXTIDFor(NSString* method, NSString* path);
static void refreshWebCookiesViaWebView(void);
static void teardownWebHarvestWindow(void);

// MARK: - Small helpers

// twid is stored as "u=<id>" (percent-encoded). Pull the numeric account id out of it.
static NSString* userIDFromTwid(NSString* twid) {
    if (twid.length == 0) {
        return nil;
    }
    NSString* decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString* digits =
        [[decoded componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

static NSString* userIDStringForAccount(id account) {
    if (!account || ![account respondsToSelector:@selector(userID)]) {
        return nil;
    }
    long long uid = ((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID));
    return uid ? [@(uid) stringValue] : nil;
}

static id accountForUserID(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }
    @try {
        Class twitterClass = %c(TFNTwitter);
        if (![twitterClass respondsToSelector:@selector(sharedTwitter)]) {
            return nil;
        }
        id twitter = ((id (*)(id, SEL))objc_msgSend)((id)twitterClass, @selector(sharedTwitter));
        if (![twitter respondsToSelector:@selector(accounts)]) {
            return nil;
        }
        NSArray* accounts = ((id (*)(id, SEL))objc_msgSend)(twitter, @selector(accounts));
        for (id account in accounts) {
            if ([userIDStringForAccount(account) isEqualToString:userID]) {
                return account;
            }
        }
    } @catch (__unused NSException* exception) {
    }
    return nil;
}

static UIWindowScene* activeWindowScene(void) {
    UIWindowScene* fallback = nil;
    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)scene;
        }
        if (!fallback) {
            fallback = (UIWindowScene*)scene;
        }
    }
    return fallback;
}

// Runs `ready` in a tight poll off the main thread, kicking `kick` every ~3s, until it
// passes or the deadline elapses. Never blocks the main thread.
static BOOL waitUntil(BOOL (^ready)(void), void (^kick)(void), NSTimeInterval maxSeconds) {
    if (ready()) {
        return YES;
    }
    if ([NSThread isMainThread]) {
        return NO;
    }

    NSUInteger maxTicks = (NSUInteger)(maxSeconds / 0.05);
    for (NSUInteger tick = 0; tick < maxTicks && !ready(); tick++) {
        if (kick && (tick % 60 == 0)) {
            dispatch_async(dispatch_get_main_queue(), kick);
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    return ready();
}

// MARK: - Cookie harvesting

static NSObject* accountCacheLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebAccountCookiesLock = [NSObject new];
        WebAccountCookies = [NSMutableDictionary dictionary];
        WebCt0ByToken = [NSMutableDictionary dictionary];
        WebCt0Minting = [NSMutableSet set];
    });
    return WebAccountCookiesLock;
}

static void cacheTokenCt0(NSString* authToken, NSString* ct0) {
    if (authToken.length == 0) {
        return;
    }
    @synchronized(accountCacheLock()) {
        if (ct0.length) {
            WebCt0ByToken[authToken] = ct0;
        } else {
            [WebCt0ByToken removeObjectForKey:authToken];
        }
    }
}

static void cacheAccountPair(NSString* userID, NSDictionary* pair) {
    if (userID.length == 0) {
        return;
    }
    @synchronized(accountCacheLock()) {
        NSString* oldToken = WebAccountCookies[userID][@"auth_token"];
        if (oldToken.length) {
            [WebCt0ByToken removeObjectForKey:oldToken];
        }
        if (pair) {
            WebAccountCookies[userID] = pair;
            NSString* token = pair[@"auth_token"];
            NSString* ct0 = pair[@"ct0"];
            if (token.length && ct0.length) {
                WebCt0ByToken[token] = ct0;
            }
        } else {
            [WebAccountCookies removeObjectForKey:userID];
        }
    }
}

static NSDictionary* cachedAccountPair(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }
    @synchronized(accountCacheLock()) {
        return WebAccountCookies[userID];
    }
}

void PFBStoreWebCookies(NSArray<NSHTTPCookie*>* cookies) {
    if (![cookies isKindOfClass:[NSArray class]]) {
        return;
    }

    for (NSHTTPCookie* cookie in cookies) {
        NSString* domain = cookie.domain ?: @"";
        if (!PFBIsXDomain(domain)) {
            continue;
        }
        if (cookie.value.length == 0) {
            continue;
        }

        if ([cookie.name isEqualToString:@"ct0"]) {
            WebCT0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"auth_token"]) {
            WebAuthToken = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"]) {
            WebTwid = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"auth_multi"]) {
            WebAuthMulti = [cookie.value copy];
        }
    }

    if (WebAuthToken.length && WebCT0.length) {
        cacheTokenCt0(WebAuthToken, WebCT0);
    }
    NSString* userID = userIDFromTwid(WebTwid);
    if (userID.length && WebAuthToken.length && WebCT0.length) {
        cacheAccountPair(userID, @{
            @"auth_token": WebAuthToken,
            @"ct0": WebCT0,
            @"twid": WebTwid,
        });
    }
}

static void harvestSharedCookies(void) {
    NSMutableArray<NSHTTPCookie*>* all = [NSMutableArray array];
    for (NSString* domain in
         @[@"https://api.twitter.com", @"https://twitter.com", @"https://x.com"]) {
        NSArray* cookies =
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:domain]];
        if (cookies) {
            [all addObjectsFromArray:cookies];
        }
    }
    PFBStoreWebCookies(all);
}

// MARK: - Helper webview (x-client-transaction-id)

static void onHelperWebViewLoaded(WKWebView* webView);

@interface PFBWebHelperDelegate : NSObject <WKNavigationDelegate>
@end
@implementation PFBWebHelperDelegate
- (void)webView:(WKWebView*)webView didFinishNavigation:(__unused WKNavigation*)navigation {
    onHelperWebViewLoaded(webView);
}
- (void)webView:(__unused WKWebView*)webView
    didFailProvisionalNavigation:(__unused WKNavigation*)navigation
                       withError:(__unused NSError*)error {
    WebHelperWebView = nil;
    WebHelperReady = NO;
    WebHelperInFlight = NO;
}
@end

static PFBWebHelperDelegate* WebHelperDelegateInstance = nil;

// Seed the helper webview's cookie store with the harvested session cookies so it loads
// authenticated.
static void seedSessionCookies(WKHTTPCookieStore* store, void (^done)(void)) {
    NSDictionary* pairs =
        @{@"auth_token": WebAuthToken ?: @"", @"ct0": WebCT0 ?: @"", @"twid": WebTwid ?: @""};

    NSMutableArray<NSHTTPCookie*>* cookies = [NSMutableArray array];
    for (NSString* name in pairs) {
        NSString* value = pairs[name];
        if (value.length == 0) {
            continue;
        }
        NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:@{
            NSHTTPCookieName: name,
            NSHTTPCookieValue: value,
            NSHTTPCookieDomain: @".x.com",
            NSHTTPCookiePath: @"/",
        }];
        if (cookie) {
            [cookies addObject:cookie];
        }
    }

    if (cookies.count == 0) {
        done();
        return;
    }

    __block NSUInteger remaining = cookies.count;
    for (NSHTTPCookie* cookie in cookies) {
        [store setCookie:cookie
            completionHandler:^{
                if (--remaining == 0) {
                    done();
                }
            }];
    }
}

static void seedHelperCookies(WKWebView* webView, void (^done)(void)) {
    seedSessionCookies(webView.configuration.websiteDataStore.httpCookieStore, done);
}

static void refreshWebCookiesViaWebView(void) {
    if (WebHelperWebView) {
        refreshXTID();
        return;
    }
    if (WebHelperInFlight) {
        return;
    }
    WebHelperInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        harvestSharedCookies();

        WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;

        WKWebView* webView = [[WKWebView alloc] initWithFrame:CGRectMake(-3000, -3000, 390, 844)
                                                configuration:configuration];
        WebHelperDelegateInstance = [[PFBWebHelperDelegate alloc] init];
        webView.navigationDelegate = WebHelperDelegateInstance;
        webView.customUserAgent =
            @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like "
            @"Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
        webView.userInteractionEnabled = NO;
        webView.alpha = 0.01;
        WebHelperWebView = webView;
        WebHelperReady = NO;

        UIWindow* keyWindow = nil;
        for (UIWindow* w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) {
                keyWindow = w;
                break;
            }
        }
        keyWindow = keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        [keyWindow addSubview:webView];

        seedHelperCookies(webView, ^{
            [webView
                loadRequest:[NSURLRequest
                                requestWithURL:[NSURL URLWithString:@"https://x.com/settings/account"]]];
        });
    });
}

static void onHelperWebViewLoaded(WKWebView* webView) {
    WebHelperInFlight = NO;

    [webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
            PFBStoreWebCookies(cookies);
        }];

    NSString* script = nil;
    NSURL* scriptURL = [[PFBBundle sharedBundle] pathForFile:@"WebXTID.js"];
    if (scriptURL) {
        script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    }
    if (script.length == 0) {
        return;
    }

    [webView evaluateJavaScript:script
              completionHandler:^(__unused id result, __unused NSError* error) {
                  WebHelperReady = YES;
                  refreshXTID();
                  refreshXTIDFor(@"GET", PeriscopeWebPath);
              }];
}

static void xtidPrepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      WebXTIDByKey = [NSMutableDictionary dictionary];
      WebXTIDMinting = [NSMutableSet set];
      WebXTIDLock = [NSObject new];
    });
}

static NSString* xtidKey(NSString* method, NSString* path) {
    return [NSString stringWithFormat:@"%@ %@", method.uppercaseString ?: @"POST", path ?: @""];
}

static NSString* cachedXTID(NSString* key) {
    xtidPrepare();
    @synchronized(WebXTIDLock) {
        return WebXTIDByKey[key];
    }
}

static NSString* createTweetPath(void) {
    return [NSString stringWithFormat:@"/graphql/%@/CreateTweet", WebCreateTweetQueryID];
}

// Mints in the page, where X's own generator runs; one request per key at a time.
static void refreshXTIDFor(NSString* method, NSString* path) {
    xtidPrepare();
    WKWebView* webView = WebHelperWebView;
    if (![webView isKindOfClass:[WKWebView class]] || path.length == 0) {
        return;
    }
    NSString* verb = method.uppercaseString ?: @"POST";
    NSString* key = xtidKey(verb, path);
    @synchronized(WebXTIDLock) {
        if ([WebXTIDMinting containsObject:key]) {
            return;
        }
        [WebXTIDMinting addObject:key];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [webView callAsyncJavaScript:@"return await window.__pfbTransactionId(path, method);"
                           arguments:@{@"method": verb, @"path": path}
                             inFrame:nil
                      inContentWorld:WKContentWorld.pageWorld
                   completionHandler:^(id result, __unused NSError* error) {
                       BOOL ok = [result isKindOfClass:[NSString class]] &&
                                 [(NSString*)result length] > 10 &&
                                 ![(NSString*)result hasPrefix:@"ERR:"];
                       @synchronized(WebXTIDLock) {
                           [WebXTIDMinting removeObject:key];
                           if (ok) {
                               WebXTIDByKey[key] = [result copy];
                           }
                       }
                   }];
    });
}

// Keeps the CreateTweet id warm.
static void refreshXTID(void) {
    refreshXTIDFor(@"POST", createTweetPath());
}

// MARK: - Native bootstrap webview (per-account web session)

// Only the native authenticated webview can perform the OAuth->cookie exchange, so
// accounts with no web cookies yet get one loaded offscreen and harvested.
static void bootstrapAccount(id account, NSString* userID) {
    if (!account || userID.length == 0 || WebBootstrapInFlight) {
        return;
    }
    WebBootstrapInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (WebHarvestWindow) {
            WebHarvestWindow.hidden = YES;
            WebHarvestWindow.rootViewController = nil;
            WebHarvestWindow = nil;
        }

        Class webViewControllerClass = %c(T1WebViewController);
        SEL initSel = @selector(initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:
                                sourceStatus:scribeComponent:scribeParameters:);
        UIWindowScene* scene = activeWindowScene();
        if (!webViewControllerClass || !scene ||
            ![webViewControllerClass instancesRespondToSelector:initSel]) {
            WebBootstrapInFlight = NO;
            return;
        }

        NSURL* url = [NSURL URLWithString:@"https://x.com/settings/account"];
        T1WebViewController* webViewController = [[webViewControllerClass alloc] initWithRootURL:url
                                                                                         account:account
                                                                              shouldAuthenticate:YES
                                                                       shouldPresentAsNativePage:NO
                                                                                    sourceStatus:nil
                                                                                 scribeComponent:nil
                                                                                scribeParameters:nil];
        if (!webViewController) {
            WebBootstrapInFlight = NO;
            return;
        }

        objc_setAssociatedObject(webViewController, WebHarvestWebViewKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIWindow* window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = CGRectMake(-3000, -3000, 390, 844);
        window.windowLevel = UIWindowLevelNormal - 1000;
        window.userInteractionEnabled = NO;
        window.rootViewController = webViewController;
        window.hidden = NO;
        WebHarvestWindow = window;

        // Safety teardown in case the load never resolves.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           teardownWebHarvestWindow();
                       });
    });
}

static void teardownWebHarvestWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (WebHarvestWindow) {
            WebHarvestWindow.hidden = YES;
            WebHarvestWindow.rootViewController = nil;
            WebHarvestWindow = nil;
        }
        WebBootstrapInFlight = NO;
    });
}

// Called from WebReply.x's T1WebViewController -didFinishLoadingWithError: hook. Harvests
// cookies out of a finished bootstrap webview, then tears its window down.
void PFBMaybeHandleHarvestWebView(__unsafe_unretained id webViewController) {
    if (!webViewController || !objc_getAssociatedObject(webViewController, WebHarvestWebViewKey)) {
        return;
    }

    WKWebView* webView = nil;
    @try {
        if ([webViewController respondsToSelector:@selector(webView)]) {
            webView = ((WKWebView * (*)(id, SEL)) objc_msgSend)(webViewController, @selector(webView));
        }
    } @catch (__unused NSException* exception) {
    }

    void (^finish)(void) = ^{
        harvestSharedCookies();
        refreshWebCookiesViaWebView();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           teardownWebHarvestWindow();
                       });
    };

    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView.configuration.websiteDataStore.httpCookieStore
            getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
                PFBStoreWebCookies(cookies);
                finish();
            }];
    } else {
        finish();
    }
}

// MARK: - Prewarm

// The CreateTweet rewrite needs the web session ready before the first Tweet is sent.
void PFBPrewarmWebCookiesIfNeeded(void) {
    NSString* savedQueryID =
        [[NSUserDefaults standardUserDefaults] stringForKey:WebQueryIDDefaultsKey];
    if (savedQueryID.length) {
        WebCreateTweetQueryID = [savedQueryID copy];
    }

    refreshWebCookiesViaWebView();
    harvestSharedCookies();

    id current = PFBAccountForAuthenticatedWebView();
    NSString* currentUserID = userIDStringForAccount(current);
    if (current && currentUserID.length && !cachedAccountPair(currentUserID)) {
        bootstrapAccount(current, currentUserID);
    }
}

// MARK: - Credential resolution

// Resolve the auth_token for an arbitrary account: the primary (web-session) account
// uses the harvested token directly; others come out of the auth_multi cookie.
static NSString* authTokenForUserID(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }

    NSString* primaryUID = userIDFromTwid(WebTwid);
    if ([primaryUID isEqualToString:userID] && WebAuthToken.length) {
        return WebAuthToken;
    }

    if (WebAuthMulti.length == 0) {
        return nil;
    }
    NSString* decoded = [WebAuthMulti stringByRemovingPercentEncoding] ?: WebAuthMulti;
    decoded = [decoded
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    NSCharacterSet* separators = [NSCharacterSet characterSetWithCharactersInString:@"|,"];
    for (NSString* entry in [decoded componentsSeparatedByCharactersInSet:separators]) {
        NSRange colon = [entry rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString* uid = [entry substringToIndex:colon.location];
        NSString* token = [entry substringFromIndex:NSMaxRange(colon)];
        if ([uid isEqualToString:userID] && token.length) {
            return token;
        }
    }
    return nil;
}

@interface PFBCt0Fetcher : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy) NSString* ct0;
@property (nonatomic, copy) NSString* twid;
@property (nonatomic, assign) BOOL loggedOut;
- (void)captureFromResponse:(NSURLResponse*)response;
@end

@implementation PFBCt0Fetcher
- (void)captureFromResponse:(NSURLResponse*)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return;
    }
    NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
    NSArray<NSHTTPCookie*>* cookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:http.allHeaderFields
                                               forURL:http.URL ?: response.URL];
    for (NSHTTPCookie* cookie in cookies) {
        if ([cookie.name isEqualToString:@"ct0"] && cookie.value.length) {
            self.ct0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"] && cookie.value.length) {
            self.twid = [cookie.value copy];
        }
    }
}
- (void)URLSession:(__unused NSURLSession*)session
                          task:(__unused NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest*))completionHandler {
    [self captureFromResponse:response];

    NSString* target = request.URL.absoluteString.lowercaseString ?: @"";
    if ([target containsString:@"login"] || [target containsString:@"logout"] ||
        [target containsString:@"/i/flow/"] || [target containsString:@"account/access"]) {
        self.loggedOut = YES;
    }
    completionHandler(request);
}
@end

// Mint a fresh ct0 for a bare auth_token by hitting x.com once and reading the Set-Cookie.
static NSString* fetchCt0Sync(NSString* authToken, NSString* expectedUserID) {
    if (authToken.length == 0 || [NSThread isMainThread]) {
        return nil;
    }

    PFBCt0Fetcher* fetcher = [PFBCt0Fetcher new];
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:fetcher
                                                     delegateQueue:nil];

    NSMutableURLRequest* request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/"]];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:[NSString stringWithFormat:@"auth_token=%@", authToken]
        forHTTPHeaderField:@"Cookie"];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                      @"(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request
                completionHandler:^(__unused NSData* data, NSURLResponse* response,
                                    __unused NSError* error) {
                    [fetcher captureFromResponse:response];
                    dispatch_semaphore_signal(done);
                }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];

    if (fetcher.loggedOut) {
        return nil;
    }

    NSString* responseUserID = userIDFromTwid(fetcher.twid);
    if (expectedUserID.length && responseUserID.length &&
        ![responseUserID isEqualToString:expectedUserID]) {
        return nil;
    }
    return fetcher.ct0;
}

NSString* PFBWebAuthTokenOfRequest(NSURLRequest* request) {
    NSString* auth = [request valueForHTTPHeaderField:@"Authorization"];
    if (![auth isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange marker = [auth rangeOfString:@"oauth_token=\""];
    if (marker.location == NSNotFound) {
        return nil;
    }
    NSString* rest = [auth substringFromIndex:NSMaxRange(marker)];
    NSRange endQuote = [rest rangeOfString:@"\""];
    NSString* token = endQuote.location == NSNotFound ? nil : [rest substringToIndex:endQuote.location];
    if (token.length == 0 || [token containsString:@"-"]) {
        return nil;
    }
    return token;
}

NSString* PFBWebCt0ForAuthToken(NSString* authToken, BOOL mint) {
    if (authToken.length == 0) {
        return nil;
    }
    harvestSharedCookies();
    NSString* known = nil;
    BOOL start = NO;
    @synchronized(accountCacheLock()) {
        known = WebCt0ByToken[authToken];
        if (!known.length && mint && ![WebCt0Minting containsObject:authToken]) {
            [WebCt0Minting addObject:authToken];
            start = YES;
        }
    }
    if (start) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString* fresh = fetchCt0Sync(authToken, nil);
            cacheTokenCt0(authToken, fresh);
            @synchronized(accountCacheLock()) {
                [WebCt0Minting removeObject:authToken];
            }
            PFBDebugLog(@"[bridge] csrf token fetched for a session: %@", fresh.length ? @"yes" : @"no");
        });
    }
    return known.length ? known : nil;
}

// The token and csrf a request goes out with: its own account's session when it was
// signed with one, else the shared session. NO when no ct0 can be had in time.
static BOOL resolveCredsForRequest(NSURLRequest* request, NSString** outAuthToken, NSString** outCt0,
                                   BOOL freshCsrf) {
    // Nothing goes through the web without a signed-in session, as before.
    if (WebAuthToken.length == 0) {
        return NO;
    }
    NSString* own = PFBWebAuthTokenOfRequest(request);
    if ([own isEqualToString:WebAuthToken]) {
        own = nil;
    }
    NSString* authToken = own ?: WebAuthToken;
    NSString* ct0 = freshCsrf ? fetchCt0Sync(authToken, own ? nil : userIDFromTwid(WebTwid)) : nil;
    if (ct0.length) {
        cacheTokenCt0(authToken, ct0);
    } else {
        ct0 = PFBWebCt0ForAuthToken(authToken, NO);
    }
    if (ct0.length == 0) {
        ct0 = fetchCt0Sync(authToken, own ? nil : userIDFromTwid(WebTwid));
        cacheTokenCt0(authToken, ct0);
    }
    if (ct0.length == 0) {
        return NO;
    }
    *outAuthToken = authToken;
    *outCt0 = ct0;
    return YES;
}

// Resolve credentials for the posting account, bootstrapping and minting as needed.
// Returns NO if the account can't be authenticated for web posting.
static BOOL resolveWebCreds(NSString* userID, NSString** outAuthToken, NSString** outCt0) {
    NSDictionary* cached = cachedAccountPair(userID);
    if (cached[@"auth_token"] && cached[@"ct0"]) {
        if (outAuthToken) *outAuthToken = cached[@"auth_token"];
        if (outCt0) *outCt0 = cached[@"ct0"];
        return YES;
    }

    NSString *authToken = nil, *ct0 = nil;
    NSString* token = authTokenForUserID(userID);

    for (int attempt = 0; attempt < 2 && ct0.length == 0; attempt++) {
        if (token.length == 0) {
            id account = accountForUserID(userID);
            if (!account) {
                break;
            }
            // Bootstrap a web session for this account, then read its token back out.
            waitUntil(
                ^BOOL {
                    harvestSharedCookies();
                    return authTokenForUserID(userID).length > 0;
                },
                ^{
                    bootstrapAccount(account, userID);
                },
                30.0);
            token = authTokenForUserID(userID);
            if (token.length == 0) {
                break;
            }
        }

        NSString* fresh = fetchCt0Sync(token, userID);
        if (fresh.length) {
            authToken = token;
            ct0 = fresh;
            cacheAccountPair(userID, @{
                @"auth_token": token,
                @"ct0": fresh,
                @"twid": [NSString stringWithFormat:@"u=%@", userID],
            });
        } else {
            cacheAccountPair(userID, nil);
            token = nil;
        }
    }

    if (authToken.length == 0 || ct0.length == 0) {
        return NO;
    }
    if (outAuthToken) *outAuthToken = authToken;
    if (outCt0) *outCt0 = ct0;
    return YES;
}

// MARK: - Request transform

// The session is attached only for an HTTPS request to X itself: the path alone
// could match a third-party URL.
static BOOL isCreateTweetURL(NSURL* url) {
    return [url.scheme isEqualToString:@"https"] && PFBIsXDomain(url.host) &&
           [url.path hasSuffix:@"/CreateTweet"];
}

// The queryId sits in the request path: .../graphql/<queryId>/CreateTweet
static NSString* queryIDFromCreateTweetURL(NSURL* url) {
    NSArray<NSString*>* components = url.path.pathComponents;
    if (components.count >= 2 && [components.lastObject isEqualToString:@"CreateTweet"]) {
        return components[components.count - 2];
    }
    return nil;
}

// The native request signs with OAuth: oauth_token="<userID>-<secret>".
static NSString* postingUserIDFromRequest(NSURLRequest* request) {
    NSString* auth = [request valueForHTTPHeaderField:@"Authorization"];
    if (![auth isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange marker = [auth rangeOfString:@"oauth_token=\""];
    if (marker.location == NSNotFound) {
        return nil;
    }
    NSString* rest = [auth substringFromIndex:NSMaxRange(marker)];
    NSRange endQuote = [rest rangeOfString:@"\""];
    if (endQuote.location == NSNotFound) {
        return nil;
    }
    NSString* token = [rest substringToIndex:endQuote.location];
    NSRange dash = [token rangeOfString:@"-"];
    return dash.location != NSNotFound ? [token substringToIndex:dash.location] : nil;
}

// Strip the native OAuth headers and re-authenticate the request against the web session.
static void applyWebAuth(NSMutableURLRequest* request, NSString* authToken, NSString* ct0,
                         NSString* userID) {
    request.HTTPShouldHandleCookies = NO;

    for (NSString* header in @[
             @"Authorization", @"X-Twitter-Client-DeviceID", @"X-Twitter-Client-Version",
             @"X-Twitter-Client", @"X-Twitter-API-Version", @"X-Twitter-Client-Limit-Ad-Tracking",
             @"X-B3-TraceId", @"Timezone", @"kdt", @"X-Client-UUID"
         ]) {
        [request setValue:nil forHTTPHeaderField:header];
    }

    [request setValue:WebBearer forHTTPHeaderField:@"authorization"];
    [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
    if (ct0.length) {
        [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    }

    NSMutableArray<NSString*>* cookiePairs = [NSMutableArray array];
    if (authToken.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"auth_token=%@", authToken]];
    }
    if (ct0.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"ct0=%@", ct0]];
    }
    if (userID.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"twid=u%%3D%@", userID]];
    }
    [request setValue:[cookiePairs componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
}

// Spaces asks for a Periscope token over this OAuth endpoint; the native path is
// refused, so it is rebuilt as the web client would send it.
static BOOL isPeriscopeAuthURL(NSURL* url) {
    return [url.scheme isEqualToString:@"https"] && PFBIsXDomain(url.host) &&
           [url.path containsString:@"authenticate_periscope"];
}

// Mute lists and Grok's translation are refused on the native path as well.
static BOOL isMuteURL(NSURL* url) {
    return [url.path containsString:@"/1.1/mutes/"] && [url.scheme isEqualToString:@"https"] &&
           PFBIsXDomain(url.host);
}

static BOOL isGrokURL(NSURL* url) {
    return [url.path containsString:@"/2/grok/"] && [url.scheme isEqualToString:@"https"] &&
           PFBIsXDomain(url.host);
}

// A request the native path refuses, rebuilt as the web client sends it: web bearer,
// the session's cookies and a transaction id for its own path, native identity
// headers stripped. A fresh csrf token costs one request to x.com.
static NSMutableURLRequest* webPathRequest(NSURLRequest* request, NSString* host, NSString* path,
                                           NSString* what, BOOL freshCsrf) {
    harvestSharedCookies();
    NSString *authToken = nil, *ct0 = nil;
    if (!resolveCredsForRequest(request, &authToken, &ct0, freshCsrf)) {
        return nil;
    }
    BOOL own = ![authToken isEqualToString:WebAuthToken];
    NSString* method = (request.HTTPMethod ?: @"GET").uppercaseString;
    NSString* key = xtidKey(method, path);
    void (^mint)(void) = ^{
        if (!WebHelperWebView) {
            refreshWebCookiesViaWebView();
        } else if (WebHelperReady) {
            refreshXTIDFor(method, path);
        }
    };
    if (cachedXTID(key).length == 0 && !waitUntil(
                                            ^BOOL {
                                                return cachedXTID(key).length > 0;
                                            },
                                            mint, 10.0)) {
        // Nothing waits on the main thread: the id is minted for the next request.
        dispatch_async(dispatch_get_main_queue(), mint);
    }
    NSURLComponents* web = [NSURLComponents new];
    web.scheme = @"https";
    web.host = host;
    web.path = path;
    web.percentEncodedQuery =
        [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO].percentEncodedQuery;
    NSMutableURLRequest* outgoing = [request mutableCopy];
    outgoing.URL = web.URL;
    applyWebAuth(outgoing, authToken, ct0, own ? nil : userIDFromTwid(WebTwid));
    NSString* xtid = cachedXTID(key);
    if (xtid.length) {
        [outgoing setValue:xtid forHTTPHeaderField:@"x-client-transaction-id"];
    }
    PFBDebugLog(@"[webtweet] rewrote %@ -> web with %@ session (auth=%lu ct0=%lu xtid=%lu)", what,
                own ? @"its own account's" : @"the shared", (unsigned long)authToken.length,
                (unsigned long)ct0.length, (unsigned long)xtid.length);
    return outgoing;
}

// A web-authenticated copy of a request the native path refuses (CreateTweet, the
// Periscope token, mute lists, Grok), or nil for any other request.
static NSMutableURLRequest* webRequestFromNativeSend(NSURLRequest* request) {
    // A request already rebuilt carries the web auth type: it is not rebuilt twice.
    if ([[request valueForHTTPHeaderField:@"x-twitter-auth-type"] isEqualToString:@"OAuth2Session"]) {
        return nil;
    }
    if (isPeriscopeAuthURL(request.URL)) {
        NSMutableURLRequest* outgoing = webPathRequest(request, @"x.com", PeriscopeWebPath, @"periscope token", YES);
        if (outgoing) {
            PFBCOMPAT_ACTION(PFBCompat_web_session, @"Spaces signed in with the web session");
        }
        return outgoing;
    }
    if (isMuteURL(request.URL)) {
        NSString* path = request.URL.path;
        NSString* webPath =
            [@"/i/api" stringByAppendingString:[path substringFromIndex:[path rangeOfString:@"/1.1/mutes/"].location]];
        NSMutableURLRequest* outgoing = webPathRequest(request, @"x.com", webPath, @"mute list", NO);
        if (outgoing) {
            PFBCompatReach(PFBCompatPath_web_mutes);
            PFBCOMPAT_ACTION(PFBCompat_web_session, @"mute list sent through the web session");
        }
        return outgoing;
    }
    if (isGrokURL(request.URL)) {
        NSString* host = [request.URL.host isEqualToString:@"api.twitter.com"] ? @"api.x.com" : request.URL.host;
        NSMutableURLRequest* outgoing = webPathRequest(request, host, request.URL.path, @"Grok request", NO);
        if (outgoing) {
            PFBCompatReach(PFBCompatPath_web_grok);
            PFBCOMPAT_ACTION(PFBCompat_web_session, @"Grok request sent through the web session");
        }
        return outgoing;
    }
    if (!isCreateTweetURL(request.URL)) {
        return nil;
    }

    NSString* queryID = queryIDFromCreateTweetURL(request.URL);
    if (queryID.length && ![queryID isEqualToString:WebCreateTweetQueryID]) {
        WebCreateTweetQueryID = [queryID copy];
        [[NSUserDefaults standardUserDefaults] setObject:queryID forKey:WebQueryIDDefaultsKey];
    }

    NSString* xtidForSend = xtidKey(@"POST", createTweetPath());
    if (cachedXTID(xtidForSend).length == 0) {
        waitUntil(
            ^BOOL {
                return cachedXTID(xtidForSend).length > 0;
            },
            ^{
                if (!WebHelperWebView) {
                    refreshWebCookiesViaWebView();
                } else if (WebHelperReady) {
                    refreshXTID();
                }
            },
            20.0);
        if (cachedXTID(xtidForSend).length == 0) {
            PFBDebugLog(@"[webtweet] no reroute: x-client-transaction-id unavailable");
            return nil;
        }
    }

    harvestSharedCookies();

    NSString* postingUserID = postingUserIDFromRequest(request);
    NSString *authToken = nil, *ct0 = nil;
    if (postingUserID.length) {
        if (!resolveWebCreds(postingUserID, &authToken, &ct0)) {
            PFBDebugLog(@"[webtweet] no reroute: web creds unresolved for %@", postingUserID);
            return nil;
        }
    } else {
        // A bridged account signs with its own session's auth_token: the Tweet goes out
        // with that session, and with the shared one only for an unreadable signature.
        if (!resolveCredsForRequest(request, &authToken, &ct0, YES)) {
            PFBDebugLog(@"[webtweet] no reroute: no session or no ct0 for the poster");
            return nil;
        }
        BOOL own = ![authToken isEqualToString:WebAuthToken];
        postingUserID = own ? nil : userIDFromTwid(WebTwid);
        PFBDebugLog(@"[webtweet] reroute via %@ session", own ? @"its own account's" : @"the shared");
    }

    NSMutableURLRequest* outgoing = [request mutableCopy];
    applyWebAuth(outgoing, authToken, ct0, postingUserID);
    NSString* xtid = cachedXTID(xtidForSend);
    [outgoing setValue:xtid forHTTPHeaderField:@"x-client-transaction-id"];
    refreshXTID();

    // Tag the request so the task watcher can drop this account's ct0 on a 4xx.
    if (postingUserID.length) {
        objc_setAssociatedObject(outgoing, WebPostingUIDKey, postingUserID,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    PFBDebugLog(@"[webtweet] rewrote CreateTweet -> web (auth=%lu ct0=%lu xtid=%lu)",
                (unsigned long)authToken.length, (unsigned long)ct0.length,
                (unsigned long)xtid.length);
    return outgoing;
}

// MARK: - Task watcher

// Watches a rewritten CreateTweet task; on a 4xx it invalidates the cached ct0 so the
// next send re-mints.
@interface PFBCreateTweetWatcher : NSObject
@property (nonatomic, copy) NSString* userID;
@end

@implementation PFBCreateTweetWatcher
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(__unused NSDictionary*)change
                       context:(__unused void*)context {
    NSURLSessionTask* task = object;
    if (![keyPath isEqualToString:@"state"] || task.state != NSURLSessionTaskStateCompleted) {
        return;
    }

    PFBCreateTweetWatcher* keepAlive = self; // stays alive while its retainer is detached below
    @try {
        [task removeObserver:self forKeyPath:@"state"];
    } @catch (__unused NSException* exception) {
    }
    objc_setAssociatedObject(task, CreateTweetWatcherKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSInteger code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
                         ? [(NSHTTPURLResponse*)task.response statusCode]
                         : 0;
    if (code >= 400 && code < 500 && keepAlive.userID.length) {
        cacheAccountPair(keepAlive.userID, nil);
    }
}
@end

static void watchCreateTweetTask(id task, NSString* userID) {
    if (![task isKindOfClass:[NSURLSessionTask class]] || userID.length == 0) {
        return;
    }
    PFBCreateTweetWatcher* watcher = [PFBCreateTweetWatcher new];
    watcher.userID = userID;
    objc_setAssociatedObject(task, CreateTweetWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [task addObserver:watcher
               forKeyPath:@"state"
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
    } @catch (__unused NSException* exception) {
    }
}

// MARK: - Shared account accessor

id PFBAccountForAuthenticatedWebView(void) {
    Class hostClass = %c(T1HostViewController);
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            id account = [host currentAccount];
            if (account) {
                return account;
            }
        }
    }
    return nil;
}

// MARK: - Interactive web-session login

// The web session cannot be minted silently on a sideloaded build, since the
// token-exchange path hits native attestation. The cookies from one real web login
// are harvested into the shared jar, so every read path sees the session.

// Harvests the shared cookie jar first, so a session opened elsewhere counts.
BOOL PFBHasUsableWebCredentials(void) {
    harvestSharedCookies();
    return WebAuthToken.length > 0 && WebCT0.length > 0;
}

NSMutableURLRequest* PFBWebSessionGETRequest(NSURL* url) {
    if (![url.scheme isEqualToString:@"https"] || !PFBIsXDomain(url.host) ||
        !PFBHasUsableWebCredentials()) {
        return nil;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10.0;
    applyWebAuth(request, WebAuthToken, WebCT0, nil);
    return request;
}

static UIViewController* webSessionTopController(void) {
    UIWindowScene* scene = activeWindowScene();
    UIWindow* keyWindow = nil;
    if (scene) {
        for (UIWindow* w in scene.windows) {
            if (w.isKeyWindow) {
                keyWindow = w;
                break;
            }
        }
        keyWindow = keyWindow ?: scene.windows.firstObject;
    }
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }
    UIViewController* top = keyWindow.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

void PFBPresentWebSessionLogin(void (^completion)(BOOL success)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* presenter = webSessionTopController();
        if (!presenter) {
            if (completion) {
                completion(NO);
            }
            return;
        }
        PFBWebSessionLoginViewController* login =
            [[PFBWebSessionLoginViewController alloc] init];
        login.completion = completion;
        UINavigationController* nav =
            [[UINavigationController alloc] initWithRootViewController:login];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [presenter presentViewController:nav animated:YES completion:nil];
    });
}

void PFBClearWebSession(void) {
    WebCT0 = nil;
    WebAuthToken = nil;
    WebTwid = nil;
    WebAuthMulti = nil;

    if (WebAccountCookiesLock) {
        @synchronized(WebAccountCookiesLock) {
            [WebAccountCookies removeAllObjects];
        }
    }

    NSHTTPCookieStorage* jar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie* cookie in [jar.cookies copy]) {
        NSString* domain = cookie.domain ?: @"";
        if (PFBIsXDomain(domain)) {
            [jar deleteCookie:cookie];
        }
    }

    // Only X's and Twitter's web data goes; the other sites opened in the app keep theirs.
    NSSet* types = [NSSet setWithArray:@[
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeSessionStorage,
    ]];
    WKWebsiteDataStore* store = [WKWebsiteDataStore defaultDataStore];
    [store fetchDataRecordsOfTypes:types
                 completionHandler:^(NSArray<WKWebsiteDataRecord*>* records) {
                     NSMutableArray<WKWebsiteDataRecord*>* ours = [NSMutableArray array];
                     for (WKWebsiteDataRecord* record in records) {
                         if (PFBIsXDomain(record.displayName)) {
                             [ours addObject:record];
                         }
                     }
                     [store removeDataOfTypes:types
                               forDataRecords:ours
                            completionHandler:^{
                            }];
                 }];
}

// Seeds the reply web view's cookie store, the shared default data store, with the current
// web session, then runs done: the reply page signs in from those cookies rather than
// through T1WebViewController's shouldAuthenticate path.
void PFBSeedReplyWebViewCookies(WKWebView* webView, void (^done)(void)) {
    harvestSharedCookies();
    seedHelperCookies(webView, done ?: ^{
                              });
}

// MARK: - Hooks

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask* task = %orig(outgoing);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(id)completionHandler {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask* task = %orig(outgoing, completionHandler);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromData:(NSData*)bodyData {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask* task = %orig(outgoing, bodyData);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromFile:(NSURL*)fileURL {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask* task = %orig(outgoing, fileURL);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

%end

// Grok's translation task is created by a call none of the hooks above sees, so
// it is rebuilt as it starts.
%hook NSURLSessionTask

- (void)resume {
    NSURLRequest* request = self.currentRequest ?: self.originalRequest;
    if (self.state == NSURLSessionTaskStateSuspended && isGrokURL(request.URL)) {
        NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
        if (outgoing) {
            @try {
                [self setValue:outgoing forKey:@"originalRequest"];
                [self setValue:outgoing forKey:@"currentRequest"];
            } @catch (__unused NSException* exception) {
            }
            PFBDebugLog(@"[webtweet] Grok task %@", self.currentRequest == outgoing ? @"rebuilt" : @"left as it was");
        }
    }
    %orig;
}

%end

// MARK: - Twitter's own web pages

// Twitter signs its web pages in through an OAuth address a web session cannot
// answer. Their web view gets a store that already holds the session's cookies,
// and the page is loaded directly. Other sites keep the web view's own store.
static const void* WebPageStoreKey = &WebPageStoreKey;
static const void* WebPagePendingKey = &WebPagePendingKey;

%hook T1WebViewController

- (id)updateConfiguration:(id)configuration {
    id result = %orig;
    WKWebViewConfiguration* config = [result isKindOfClass:[WKWebViewConfiguration class]] ? result : configuration;
    NSURL* root = [self respondsToSelector:@selector(rootURL)] ? [(id)self rootURL] : nil;
    harvestSharedCookies();
    if (WebAuthToken.length == 0 || !PFBIsXDomain(root.host) || ![config isKindOfClass:[WKWebViewConfiguration class]] ||
        objc_getAssociatedObject(self, WebHarvestWebViewKey)) {
        return result;
    }

    WKWebsiteDataStore* store = [WKWebsiteDataStore nonPersistentDataStore];
    config.websiteDataStore = store;
    objc_setAssociatedObject(store, WebPageStoreKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(store, WebPagePendingKey, [NSMutableArray array], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    seedSessionCookies(store.httpCookieStore, ^{
        // A load asked for while the cookies were being set runs now.
        NSArray* pending = objc_getAssociatedObject(store, WebPagePendingKey);
        objc_setAssociatedObject(store, WebPagePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        void (^load)(void) = pending.lastObject;
        if (load) {
            load();
        }
    });
    return result;
}

%end

// The page behind the OAuth address, taken from its redirect_url parameter.
static NSURLRequest* webPageRequest(NSURLRequest* request) {
    if (![request.URL.path containsString:@"/account/authenticate_web_view"]) {
        return request;
    }
    NSURLComponents* components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem* item in components.queryItems) {
        NSURL* target = [item.name isEqualToString:@"redirect_url"] && item.value.length ? [NSURL URLWithString:item.value] : nil;
        if (target) {
            NSMutableURLRequest* page = [request mutableCopy];
            page.URL = target;
            [page setValue:nil forHTTPHeaderField:@"Authorization"];
            PFBCompatReach(PFBCompatPath_web_pages);
            PFBCOMPAT_ACTION(PFBCompat_web_session, @"Twitter web page opened with the web session");
            PFBDebugLog(@"[webtweet] web page loaded directly: %@%@", target.host, target.path);
            return page;
        }
    }
    return request;
}

%hook WKWebView

- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    WKWebsiteDataStore* store = self.configuration.websiteDataStore;
    if (!objc_getAssociatedObject(store, WebPageStoreKey)) {
        return %orig;
    }

    NSURLRequest* page = webPageRequest(request);
    NSMutableArray* pending = objc_getAssociatedObject(store, WebPagePendingKey);
    if (!pending) {
        return %orig(page);
    }

    __weak WKWebView* weakSelf = self;
    [pending removeAllObjects];
    [pending addObject:[^{
                 [weakSelf loadRequest:page];
             } copy]];
    return nil;
}

%end
