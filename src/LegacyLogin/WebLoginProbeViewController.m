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
@property (nonatomic, strong) UIView* headerView;
@property (nonatomic, strong) UIActivityIndicatorView* spinner;
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) UIButton* retryButton;
@property (nonatomic, assign) BOOL sawAuth;
@property (nonatomic, assign) BOOL asRoot;
@property (nonatomic, assign) BOOL didStartInitialLoad;
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
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self setupHeader];

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
    self.webView.navigationDelegate = self;
    self.webView.customUserAgent =
        @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        @"(KHTML, like Gecko) Version/17.0 Safari/605.1.15";
    // Opaque over a matching background so the web area never flashes white before
    // x.com paints - that flash read as a glitch on the way in.
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor systemBackgroundColor];
    self.webView.scrollView.backgroundColor = [UIColor systemBackgroundColor];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    // Kept hidden until the page finishes, so the redirect chain and the X splash
    // never flash; the header and spinner cover the wait, then it fades in.
    self.webView.alpha = 0.0;
    [self.view addSubview:self.webView];

    // Loading spinner and error text, in front of the web area.
    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [UIColor secondaryLabelColor];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.hidden = YES;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.retryButton setTitle:@"Retry" forState:UIControlStateNormal];
    self.retryButton.hidden = YES;
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.retryButton addTarget:self
                         action:@selector(reload)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.webView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.webView.centerYAnchor],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.webView.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.webView.leadingAnchor
                                                        constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.webView.trailingAnchor
                                                         constant:-24],
        [self.retryButton.centerXAnchor constraintEqualToAnchor:self.webView.centerXAnchor],
        [self.retryButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor
                                                    constant:16],
    ]];
    // The page load itself is deferred to viewDidAppear so it never runs during
    // the presentation animation.
}

// Native brand header that stands in for the navigation bar: instant to draw, so
// the screen has content the moment it animates in.
- (void)setupHeader {
    UIView* header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:header];
    self.headerView = header;

    UIImageView* bird =
        [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bird.fill"]];
    bird.tintColor = [UIColor colorWithRed:0.114 green:0.631 blue:0.949 alpha:1.0];
    bird.contentMode = UIViewContentModeScaleAspectFit;
    bird.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel* name = [[UILabel alloc] init];
    name.text = @"PrimeFreeBird";
    name.font = [UIFont systemFontOfSize:21 weight:UIFontWeightHeavy];
    name.textColor = [UIColor labelColor];

    UILabel* tagline = [[UILabel alloc] init];
    tagline.text = @"The feed, without the noise.";
    tagline.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    tagline.textColor = [UIColor secondaryLabelColor];

    UIStackView* stack =
        [[UIStackView alloc] initWithArrangedSubviews:@[ bird, name, tagline ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;
    [stack setCustomSpacing:9 afterView:bird];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];

    UIView* hair = [[UIView alloc] init];
    hair.backgroundColor = [UIColor separatorColor];
    hair.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:hair];

    NSMutableArray<NSLayoutConstraint*>* c = [NSMutableArray arrayWithArray:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bird.widthAnchor constraintEqualToConstant:40],
        [bird.heightAnchor constraintEqualToConstant:40],
        [stack.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16],
        [hair.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [hair.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [hair.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
        [hair.heightAnchor constraintEqualToConstant:0.5]
    ]];

    if (!self.asRoot) {
        UIButton* close = [UIButton buttonWithType:UIButtonTypeSystem];
        [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        close.tintColor = [UIColor secondaryLabelColor];
        close.translatesAutoresizingMaskIntoConstraints = NO;
        [close addTarget:self
                    action:@selector(dismissSelf)
          forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:close];
        [c addObjectsFromArray:@[
            [close.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:12],
            [close.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
            [close.widthAnchor constraintEqualToConstant:36],
            [close.heightAnchor constraintEqualToConstant:36]
        ]];
    }
    [NSLayoutConstraint activateConstraints:c];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The brand header replaces the navigation bar, so the screen is one clean
    // surface instead of two stacked strips.
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // x.com is heavy; loading it during the present animation is what stuttered.
    // Start once the transition has settled.
    if (!self.didStartInitialLoad) {
        self.didStartInitialLoad = YES;
        [self reload];
    }
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

// The REST identity endpoints are gone (404); the handle is read from the
// account switcher of the logged-in page, retried a few times while it renders.
- (void)resolveScreenNameThenBridgeWithAuthToken:(NSString*)authToken
                                            csrf:(NSString*)csrf
                                          userID:(long long)userID
                                         attempt:(int)attempt {
    NSString* js =
        @"(function(){"
        @"var p=document.querySelector('[data-testid=\"AppTabBar_Profile_Link\"]');"
        @"if(p){var m=(p.getAttribute('href')||'').match(/^\\/([A-Za-z0-9_]{1,15})$/);"
        @"if(m)return m[1];}"
        @"var b=document.querySelector('[data-testid=\"SideNav_AccountSwitcher_Button\"]');"
        @"if(b){var mm=(b.innerText||'').match(/@([A-Za-z0-9_]{1,15})/);if(mm)return mm[1];}"
        @"var body=document.body?document.body.innerText:'';var at=body.match(/@([A-Za-z0-9_]{1,15})/);"
        @"return 'diag:path='+location.pathname+' links='"
        @"+document.querySelectorAll('a[href^=\"/\"]').length+' at='+(at?at[1]:'-');})();";
    [self.webView evaluateJavaScript:js
                   completionHandler:^(id result, NSError* error) {
                     NSString* raw = [result isKindOfClass:[NSString class]] ? result : nil;
                     NSString* screen = [raw hasPrefix:@"diag:"] ? nil : raw;
                     NFBDebugLog(@"[weblogin] handle probe attempt=%d -> %@", attempt,
                                 raw.length ? raw : @"(none)");
                     if (screen.length || attempt >= 8) {
                         [LoginBridge startWithAuthToken:authToken
                                                    csrf:csrf
                                                  userID:userID
                                              screenName:screen
                                               presenter:self];
                         return;
                     }
                     dispatch_after(
                         dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                         dispatch_get_main_queue(), ^{
                           [self resolveScreenNameThenBridgeWithAuthToken:authToken
                                                                     csrf:csrf
                                                                   userID:userID
                                                                  attempt:attempt + 1];
                         });
                   }];
}

- (void)reload {
    [self.spinner startAnimating];
    self.statusLabel.hidden = YES;
    self.retryButton.hidden = YES;
    self.webView.alpha = 0.0;
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
    [self.spinner stopAnimating];
    self.statusLabel.hidden = YES;
    if (self.webView.alpha < 1.0) {
        [UIView animateWithDuration:0.22
                         animations:^{
                           self.webView.alpha = 1.0;
                         }];
    }
    NFBDebugLog(@"[weblogin] settled at %@", webView.URL.absoluteString);
    WKHTTPCookieStore* store = webView.configuration.websiteDataStore.httpCookieStore;
    [store getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
      BOOL auth = NO;
      BOOL csrf = NO;
      NSString* authVal = nil;
      NSString* csrfVal = nil;
      long long uid = 0;
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
          } else if ([cookie.name isEqualToString:@"twid"]) {
              // twid is u=<userID>, url-encoded as u%3D<userID>.
              NSString* dec = [cookie.value stringByRemovingPercentEncoding] ?: cookie.value;
              uid = [[[dec componentsSeparatedByString:@"="] lastObject] longLongValue];
              NFBDebugLog(@"[weblogin] twid present, userID=%lld", uid);
          }
      }
      NFBDebugLog(@"[weblogin] cookie sweep: auth=%d csrf=%d total=%lu", auth ? 1 : 0,
                  csrf ? 1 : 0, (unsigned long)cookies.count);
      if (auth && !self.sawAuth) {
          self.sawAuth = YES;
          NFBDebugLog(@"[weblogin] AUTH TOKEN OBTAINED - web login reaches a session");
          // Seed the shared cookie jar with this session so the read injection and
          // WebCreateTweet.x (writes) both draw on the one session, and it survives
          // relaunch. "Delete web session" wipes this same jar.
          NSHTTPCookieStorage* jar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
          for (NSHTTPCookie* c in cookies) {
              NSString* domain = c.domain ?: @"";
              if ([domain containsString:@"x.com"] || [domain containsString:@"twitter.com"]) {
                  [jar setCookie:c];
              }
          }
          [self probeSessionStores:store];
          // REST account endpoints are gone (404); read the handle from the page
          // itself, then bridge the session into a native account (Voie B then A).
          [self resolveScreenNameThenBridgeWithAuthToken:authVal csrf:csrfVal userID:uid attempt:0];
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
    [self.spinner stopAnimating];
    self.statusLabel.hidden = NO;
    self.retryButton.hidden = NO;
    self.statusLabel.text =
        [NSString stringWithFormat:@"Could not load the login page.\n\n%@",
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
