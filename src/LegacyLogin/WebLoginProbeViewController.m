#import "WebLoginProbeViewController.h"
#import <WebKit/WebKit.h>
#import "Debug/NFBDebugger.h"

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

// Installed at the start of every page so the login flow's own onboarding calls
// are wrapped before they run, not only after a session cookie appears.
- (void)webView:(WKWebView*)webView didCommitNavigation:(WKNavigation*)navigation {
    [self probeTokenExchangeWithAuth:nil csrf:nil];
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
      for (NSHTTPCookie* cookie in cookies) {
          if ([cookie.name isEqualToString:kNFBAuthCookie]) {
              auth = YES;
              NFBDebugLog(@"[weblogin] %@ present, length %lu, domain %@",
                          kNFBAuthCookie, (unsigned long)cookie.value.length,
                          cookie.domain);
          } else if ([cookie.name isEqualToString:kNFBCsrfCookie]) {
              csrf = YES;
              NFBDebugLog(@"[weblogin] %@ present, length %lu", kNFBCsrfCookie,
                          (unsigned long)cookie.value.length);
          }
      }
      NFBDebugLog(@"[weblogin] cookie sweep: auth=%d csrf=%d total=%lu", auth ? 1 : 0,
                  csrf ? 1 : 0, (unsigned long)cookies.count);
      if (auth && !self.sawAuth) {
          self.sawAuth = YES;
          NFBDebugLog(@"[weblogin] AUTH TOKEN OBTAINED - web login reaches a session");
          NSString* authValue = nil;
          NSString* csrfValue = nil;
          for (NSHTTPCookie* cookie in cookies) {
              if ([cookie.name isEqualToString:kNFBAuthCookie]) {
                  authValue = cookie.value;
              } else if ([cookie.name isEqualToString:kNFBCsrfCookie]) {
                  csrfValue = cookie.value;
              }
          }
          [self probeTokenExchangeWithAuth:authValue csrf:csrfValue];
      }
    }];
}

// The task body cannot be guessed, so the page's own fetch is wrapped and each
// onboarding/task call it makes is reported: URL, body, and reply shape.
static NSString* const kNFBExchangeScript =
    @"(function(){"
    @"  if(window.__nfbWrapped){return;}window.__nfbWrapped=1;"
    @"  var out=function(m){window.webkit.messageHandlers.nfbExchange.postMessage(m);};"
    @"  var of=window.fetch;"
    @"  window.fetch=function(){"
    @"    var a=arguments;var u=(a[0]&&a[0].url)||a[0]||'';"
    @"    var opt=(a[0]&&a[0].method)?a[0]:(a[1]||{});"
    @"    if(String(u).indexOf('onboarding/task')>=0){"
    @"      var b=opt&&opt.body?String(opt.body):'(no body)';"
    @"      out('REQ '+String(u).slice(0,90)+' body='+b.slice(0,400));"
    @"    }"
    @"    return of.apply(this,a).then(function(r){"
    @"      if(String(u).indexOf('onboarding/task')>=0){"
    @"        r.clone().text().then(function(t){"
    @"          out('RESP status '+r.status+' oauth='+(t.indexOf('oauth_token')>=0?1:0)"
    @"              +' secret='+(t.indexOf('oauth_token_secret')>=0?1:0)"
    @"              +' flow='+(t.indexOf('flow_token')>=0?1:0)"
    @"              +' subtask='+(t.indexOf('subtask_id')>=0?1:0));"
    @"        });"
    @"      }"
    @"      return r;"
    @"    });"
    @"  };"
    @"})();";

// Wraps the page's fetch as early as possible, so the onboarding calls the login
// page makes on its own are captured. No request is sent by us here.
- (void)probeTokenExchangeWithAuth:(NSString*)authToken csrf:(NSString*)csrf {
    NFBDebugLog(@"[exchange] fetch wrap installed - watching onboarding/task");
    [self.webView evaluateJavaScript:kNFBExchangeScript completionHandler:nil];
}

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
