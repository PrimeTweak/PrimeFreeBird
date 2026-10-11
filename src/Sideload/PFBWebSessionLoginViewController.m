#import "Support/HookHelpers.h"
#import "Sideload/PFBWebSessionLoginViewController.h"

// Persist harvested cookies to the shared jar (survives relaunch) + the in-memory globals.
static void persistWebSessionCookies(NSArray<NSHTTPCookie*>* cookies) {
    NSHTTPCookieStorage* jar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie* cookie in cookies) {
        NSString* domain = cookie.domain ?: @"";
        if (!PFBIsXDomain(domain)) {
            continue;
        }
        [jar setCookie:cookie];
    }
    PFBStoreWebCookies(cookies);
}
@implementation PFBWebSessionLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [[PFBBundle sharedBundle] localizedStringForKey:@"WEB_SESSION_LOGIN_TITLE"];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancelTapped)];

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    self.loginWebView = [[WKWebView alloc] initWithFrame:self.view.bounds
                                           configuration:configuration];
    self.loginWebView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.loginWebView.navigationDelegate = self;
    self.loginWebView.customUserAgent = PFBMobileSafariUserAgent;
    [self.view addSubview:self.loginWebView];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask =
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.spinner.hidesWhenStopped = YES;
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];

    [self.loginWebView
        loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/login"]]];
}

- (void)cancelTapped {
    [self finishWithSuccess:NO];
}

- (void)finishWithSuccess:(BOOL)success {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    void (^completion)(BOOL) = self.completion;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (completion) {
                                     completion(success);
                                 }
                             }];
}

// After each navigation settles, check for a completed login: auth_token + ct0 both set.
- (void)webView:(WKWebView*)webView didFinishNavigation:(__unused WKNavigation*)navigation {
    [self.spinner stopAnimating];
    if (self.finished) {
        return;
    }
    [webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
            BOOL hasAuth = NO;
            BOOL hasCT0 = NO;
            for (NSHTTPCookie* cookie in cookies) {
                NSString* domain = cookie.domain ?: @"";
                if (!PFBIsXDomain(domain)) {
                    continue;
                }
                if (cookie.value.length == 0) {
                    continue;
                }
                if ([cookie.name isEqualToString:@"auth_token"]) {
                    hasAuth = YES;
                } else if ([cookie.name isEqualToString:@"ct0"]) {
                    hasCT0 = YES;
                }
            }
            if (!hasAuth || !hasCT0) {
                return;
            }
            persistWebSessionCookies(cookies);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishWithSuccess:YES];
            });
        }];
}

- (void)webView:(__unused WKWebView*)webView
    didFailProvisionalNavigation:(__unused WKNavigation*)navigation
                       withError:(__unused NSError*)error {
    [self.spinner stopAnimating];
}

@end
