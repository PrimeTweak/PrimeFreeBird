#import "WebLoginProbeViewController.h"
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Debug/NFBDebugger.h"
#import "LoginBridge.h"

// The cookies that prove a real session: the auth token and the CSRF token the
// API calls need. Their arrival after login is what this screen measures.
static NSString* const kNFBAuthCookie = @"auth_token";
static NSString* const kNFBCsrfCookie = @"ct0";

@interface WebLoginProbeViewController () <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, assign) BOOL sawAuth;
@property (nonatomic, assign) BOOL asRoot;
@end

@implementation WebLoginProbeViewController

+ (void)presentFrom:(UIViewController*)presenter {
    WebLoginProbeViewController* login = [WebLoginProbeViewController new];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:login];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}

+ (UINavigationController*)rootNavigationController {
    WebLoginProbeViewController* login = [WebLoginProbeViewController new];
    login.asRoot = YES;
    return [[UINavigationController alloc] initWithRootViewController:login];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Web login";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    if (!self.asRoot) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                          target:self
                                                          action:@selector(dismissSelf)];
    }
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(reload)];

    // Shown behind the web view, so a blank or failed page still tells the user
    // what happened without needing the log.
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 24, 0)];
    self.statusLabel.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.text = @"Loading twitter.com/login...";
    [self.view addSubview:self.statusLabel];

    // A desktop user agent and a standing data store: the mobile login page
    // leans on flows the tweak's forced design disturbs, the desktop one does not.
    WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
    cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    [cfg.userContentController addScriptMessageHandler:self name:@"nfbExchange"];
    // Installed at document start, all frames: the page wraps its own fetch as it
    // loads, so a late evaluateJavaScript wraps nothing, and the login may run in
    // a subframe.
    WKUserScript* wrap =
        [[WKUserScript alloc] initWithSource:kNFBExchangeScript
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [cfg.userContentController addUserScript:wrap];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds
                                      configuration:cfg];
    self.webView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.customUserAgent =
        @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        @"(KHTML, like Gecko) Version/17.0 Safari/605.1.15";
    self.webView.opaque = NO;
    [self.view addSubview:self.webView];

    [self reload];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Measures every place a session could live and whether the web view's cookies
// reach the native side: the shared native cookie jar, the web view's own jar,
// and the keychain the account reads. Presence and length only, never values.
- (void)probeSessionStores:(WKHTTPCookieStore*)webStore {
    NSHTTPCookieStorage* shared = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSUInteger nativeAuth = 0, nativeCsrf = 0, nativeTotal = 0;
    for (NSHTTPCookie* c in shared.cookies) {
        if ([c.domain containsString:@"x.com"] || [c.domain containsString:@"twitter.com"]) {
            nativeTotal++;
            if ([c.name isEqualToString:@"auth_token"]) {
                nativeAuth = c.value.length;
            } else if ([c.name isEqualToString:@"ct0"]) {
                nativeCsrf = c.value.length;
            }
        }
    }
    NFBDebugLog(@"[store] native jar: auth=%lu ct0=%lu total=%lu",
                (unsigned long)nativeAuth, (unsigned long)nativeCsrf,
                (unsigned long)nativeTotal);

    // Are the two jars the same object, or separate?
    BOOL sameJar = (webStore ==
        [WKWebsiteDataStore defaultDataStore].httpCookieStore);
    NFBDebugLog(@"[store] web jar is default store: %d", sameJar ? 1 : 0);

    // The keychain the account uses: does an OAuth token already live there?
    for (NSString* service in @[@"com.twitter.", @"com.atebits.",
                                @"com.atebits.Tweetie2"]) {
        NSDictionary* q = @{
            (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService : service,
            (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes : @YES
        };
        CFTypeRef out = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
        NSUInteger count = 0;
        if (st == errSecSuccess && out) {
            count = [(__bridge NSArray*)out count];
            CFRelease(out);
        }
        NFBDebugLog(@"[store] keychain '%@': status=%d items=%lu", service,
                    (int)st, (unsigned long)count);
    }

    // Does the app expose an accounts store we could add to?
    Class accountCls = objc_getClass("TFNTwitterAccount");
    Class storeCls = objc_getClass("TFNTwitterAccountsManager")
                     ?: objc_getClass("TFNTwitterAccountStore");
    NFBDebugLog(@"[store] TFNTwitterAccount=%d accountsManager=%d",
                accountCls != nil, storeCls != nil);
    [self probeAccountState];
}

// Cookies are present, so the block is higher up: no account is mounted from
// them. Reads the store's account count, the active one, and its credential
// fields - shapes only, no values.
- (void)probeAccountState {
    // The store is not a singleton; it is created and asked to loadAccounts,
    // which reads the keychain entry. This mirrors what the app does at launch
    // and shows what the keychain actually yields.
    Class storeCls = objc_getClass("TFNTwitterAccountStore");
    if (!storeCls) {
        NFBDebugLog(@"[account] store class absent");
        return;
    }
    id store = [[storeCls alloc] init];
    if (![store respondsToSelector:NSSelectorFromString(@"loadAccounts")]) {
        NFBDebugLog(@"[account] store has no loadAccounts");
        return;
    }
    id accounts =
        ((id (*)(id, SEL))objc_msgSend)(store, NSSelectorFromString(@"loadAccounts"));
    if (![accounts isKindOfClass:[NSArray class]]) {
        NFBDebugLog(@"[account] loadAccounts returned %@",
                    accounts ? NSStringFromClass([accounts class]) : @"nil");
        return;
    }
    NFBDebugLog(@"[account] loadAccounts count=%lu", (unsigned long)[accounts count]);
    for (id acct in accounts) {
        NSString* screen =
            [acct respondsToSelector:NSSelectorFromString(@"screenName")]
                ? @"screenName" : @"-";
        BOOL hasAuth =
            [acct respondsToSelector:NSSelectorFromString(@"authToken")];
        BOOL hasSecret =
            [acct respondsToSelector:NSSelectorFromString(@"authTokenSecret")];
        id tok = hasAuth ? ((id (*)(id, SEL))objc_msgSend)(
                              acct, NSSelectorFromString(@"authToken")) : nil;
        id sec = hasSecret ? ((id (*)(id, SEL))objc_msgSend)(
                               acct, NSSelectorFromString(@"authTokenSecret")) : nil;
        NFBDebugLog(@"[account] entry: %@ authToken=%lu secret=%lu", screen,
                    (unsigned long)[tok length], (unsigned long)[sec length]);
    }
}

- (void)userContentController:(WKUserContentController*)controller
      didReceiveScriptMessage:(WKScriptMessage*)message {
    if (![message.name isEqualToString:@"nfbExchange"]) {
        return;
    }
    NSString* body = [message.body description];
    NFBDebugLog(@"[exchange] page result: %@", body);
    if ([body containsString:@"oauth=1"] && [body containsString:@"secret=1"]) {
        NFBDebugLog(@"[exchange] OAUTH PAIR RETURNED - native account is reachable");
    } else if ([body containsString:@"flow=1"] || [body containsString:@"subtask=1"]) {
        NFBDebugLog(@"[exchange] flow continues - a subtask step is needed");
    }
}

- (void)reload {
    self.statusLabel.text = @"Loading twitter.com/login...";
    NSURL* url = [NSURL URLWithString:@"https://twitter.com/login"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    NFBDebugLog(@"[weblogin] loading %@", url.absoluteString);
}

// After every page settles, the cookie jar is read and the two session cookies
// are reported. The token value is not logged, only whether it is present and
// how long it is, so nothing sensitive lands in the log.
- (void)webView:(WKWebView*)webView
    didStartProvisionalNavigation:(WKNavigation*)navigation {
    NFBDebugLog(@"[weblogin] navigating to %@", webView.URL.absoluteString);
}

- (void)webView:(WKWebView*)webView
    didReceiveServerRedirectForProvisionalNavigation:(WKNavigation*)navigation {
    NFBDebugLog(@"[weblogin] redirected to %@", webView.URL.absoluteString);
}

// The server can answer a page with an HTTP error and no navigation failure, so
// the status code is read here to tell an empty 404 page from a real login form.
- (void)webView:(WKWebView*)webView
    decidePolicyForNavigationResponse:(WKNavigationResponse*)response
                    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([response.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NFBDebugLog(@"[weblogin] http %ld for %@",
                    (long)((NSHTTPURLResponse*)response.response).statusCode,
                    response.response.URL.absoluteString);
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    self.statusLabel.hidden = YES;
    NFBDebugLog(@"[weblogin] settled at %@", webView.URL.absoluteString);
    WKHTTPCookieStore* store = webView.configuration.websiteDataStore.httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
      BOOL auth = NO;
      BOOL csrf = NO;
      NSString* authVal = nil;
      NSString* csrfVal = nil;
      for (NSHTTPCookie* cookie in cookies) {
          if ([cookie.name isEqualToString:kNFBAuthCookie]) {
              auth = YES;
              authVal = cookie.value;
              NFBDebugLog(@"[weblogin] %@ present, length %lu, domain %@",
                          kNFBAuthCookie, (unsigned long)cookie.value.length,
                          cookie.domain);
          } else if ([cookie.name isEqualToString:kNFBCsrfCookie]) {
              csrf = YES;
              csrfVal = cookie.value;
              NFBDebugLog(@"[weblogin] %@ present, length %lu", kNFBCsrfCookie,
                          (unsigned long)cookie.value.length);
          }
      }
      NFBDebugLog(@"[weblogin] cookie sweep: auth=%d csrf=%d total=%lu", auth ? 1 : 0,
                  csrf ? 1 : 0, (unsigned long)cookies.count);
      if (auth && !self.sawAuth) {
          self.sawAuth = YES;
          NFBDebugLog(@"[weblogin] AUTH TOKEN OBTAINED - web login reaches a session");
          [self probeSessionStores:store];
          // Bridge the captured session into a native account: Voie B then A.
          [LoginBridge startWithAuthToken:authVal csrf:csrfVal presenter:self];
      }
    }];
}

// The task body cannot be guessed, so the page's own fetch is wrapped and each
// onboarding/task call it makes is reported: URL, body, and reply shape.
static NSString* const kNFBExchangeScript =
    @"(function(){"
    @"  if(window.__nfbWrapped){return;}window.__nfbWrapped=1;"
    @"  var out=function(m){window.webkit.messageHandlers.nfbExchange.postMessage(m);};"
    @"  var pick=function(u){return String(u).indexOf('/onboarding/')>=0"
    @"      ||String(u).indexOf('/oauth')>=0||String(u).indexOf('/auth/')>=0;};"
    @"  var shape=function(t){return ' oauth='+(t.indexOf('oauth_token')>=0?1:0)"
    @"      +' secret='+(t.indexOf('oauth_token_secret')>=0?1:0)"
    @"      +' flow='+(t.indexOf('flow_token')>=0?1:0)"
    @"      +' subtask='+(t.indexOf('subtask_id')>=0?1:0);};"
    @"  var of=window.fetch;"
    @"  if(of){window.fetch=function(){"
    @"    var a=arguments;var u=(a[0]&&a[0].url)||a[0]||'';"
    @"    var opt=(a[0]&&a[0].method)?a[0]:(a[1]||{});"
    @"    if(pick(u)){var b=opt&&opt.body?String(opt.body):'';"
    @"      out('FETCH '+String(u).slice(0,80)+' body='+b.slice(0,300));}"
    @"    return of.apply(this,a).then(function(r){"
    @"      if(pick(u)){r.clone().text().then(function(t){"
    @"        out('FRESP '+r.status+shape(t));});}"
    @"      return r;});"
    @"  };}"
    @"  var oo=XMLHttpRequest.prototype.open;"
    @"  var os=XMLHttpRequest.prototype.send;"
    @"  XMLHttpRequest.prototype.open=function(m,u){this.__u=u;return oo.apply(this,arguments);};"
    @"  XMLHttpRequest.prototype.send=function(body){"
    @"    var x=this;"
    @"    if(pick(x.__u)){out('XHR '+String(x.__u).slice(0,80)"
    @"        +' body='+(body?String(body).slice(0,300):''));"
    @"      x.addEventListener('load',function(){"
    @"        out('XRESP '+x.status+shape(x.responseText||''));});}"
    @"    return os.apply(this,arguments);"
    @"  };"
    @"})();";

- (void)webView:(WKWebView*)webView
    didFailProvisionalNavigation:(WKNavigation*)navigation
                       withError:(NSError*)error {
    self.statusLabel.hidden = NO;
    self.statusLabel.text =
        [NSString stringWithFormat:@"Could not load the login page.\n\n%@\n\nTap refresh to retry.",
                                   error.localizedDescription];
    NFBDebugLog(@"[weblogin] provisional navigation failed (%ld): %@",
                (long)error.code, error.localizedDescription);
}

- (void)webView:(WKWebView*)webView
    didFailNavigation:(WKNavigation*)navigation
            withError:(NSError*)error {
    NFBDebugLog(@"[weblogin] navigation failed after start (%ld): %@",
                (long)error.code, error.localizedDescription);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView*)webView {
    NFBDebugLog(@"[weblogin] web content process terminated");
}

@end
