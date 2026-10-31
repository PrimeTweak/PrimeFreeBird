#import "Support/HookHelpers.h"
#import "Sideload/PFBWebLoginViewController.h"
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

@interface PFBWebSessionLoginViewController ()
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) UIButton* retryButton;
@end

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
    self.loginWebView.customUserAgent = PFBDesktopSafariUserAgent;
    [self.view addSubview:self.loginWebView];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask =
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    // Error text and Retry, as on the account login.
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.hidden = YES;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.retryButton setTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"WEB_LOGIN_RETRY_ACTION"]
                      forState:UIControlStateNormal];
    self.retryButton.hidden = YES;
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.retryButton addTarget:self
                         action:@selector(loadLoginPage)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.loginWebView.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.loginWebView.leadingAnchor
                                                        constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.loginWebView.trailingAnchor
                                                         constant:-24],
        [self.retryButton.centerXAnchor constraintEqualToAnchor:self.loginWebView.centerXAnchor],
        [self.retryButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor
                                                    constant:16],
    ]];

    [self loadLoginPage];
}

- (void)loadLoginPage {
    [self.spinner startAnimating];
    self.statusLabel.hidden = YES;
    self.retryButton.hidden = YES;
    [self.loginWebView
        loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:PFBWebLoginFlowURL]]];
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
                       withError:(NSError*)error {
    // A redirect supersedes the previous load and cancels it; that is not a real
    // failure, so leave the spinner running.
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    [self.spinner stopAnimating];
    self.statusLabel.text =
        [NSString stringWithFormat:[[PFBBundle sharedBundle] localizedStringForKey:@"WEB_LOGIN_LOAD_FAILED"],
                                   error.localizedDescription];
    self.statusLabel.hidden = NO;
    self.retryButton.hidden = NO;
}

@end
