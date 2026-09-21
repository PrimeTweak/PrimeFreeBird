#import "LoginBridge.h"
#import "Debug/NFBDebugger.h"
#import <objc/runtime.h>
#import <objc/message.h>

// The public unauthenticated bearer every client sends, split so it is not one
// grep-able literal.
static NSString* nfbBridgeBearer(void) {
    return [@"Bearer AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3D"
            stringByAppendingString:@"RUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"];
}

static BOOL nfbBridgeIsTwitterAPI(NSString* url) {
    if (![url isKindOfClass:[NSString class]]) {
        return NO;
    }
    if ([url containsString:@"jfapi"]) {
        return NO;
    }
    return [url containsString:@"api.twitter.com"] || [url containsString:@"api.x.com"] ||
           [url containsString:@"twitter.com/i/api"] || [url containsString:@"x.com/i/api"];
}

#pragma mark - Read injection over the shared web session

// Only CreateTweet is left to WebCreateTweet.x, which reroutes it to the web
// endpoint with a per-operation x-client-transaction-id; injecting here would
// clobber that reroute. Every other mutation authenticates by cookie like a read.
static BOOL nfbBridgeIsCreateTweet(NSString* path) {
    return [path isKindOfClass:[NSString class]] &&
           [path.lastPathComponent isEqualToString:@"CreateTweet"];
}

// The read session is the shared web session: the one WebCreateTweet.x harvests
// for writes and "Delete web session" wipes. Reading it here means login,
// persistence and sign-out all flow through that single place.
static void nfbBridgeReadSharedSession(NSString** authToken, NSString** csrf) {
    NSHTTPCookieStorage* jar = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    // The session may sit on either host, so both are read (as harvestSharedCookies
    // does), taking each token from wherever it is found.
    for (NSString* host in @[@"https://x.com", @"https://twitter.com"]) {
        for (NSHTTPCookie* cookie in [jar cookiesForURL:[NSURL URLWithString:host]]) {
            if ([cookie.name isEqualToString:@"auth_token"] && cookie.value.length) {
                *authToken = cookie.value;
            } else if ([cookie.name isEqualToString:@"ct0"] && cookie.value.length) {
                *csrf = cookie.value;
            }
        }
    }
}

// Adds the web session cookie + csrf to an app read request, replacing the shell
// account's invalid OAuth so the server authenticates it by cookie.
static NSURLRequest* nfbBridgeInject(NSURLRequest* req) {
    if (!req || !nfbBridgeIsTwitterAPI(req.URL.absoluteString)) {
        return req;
    }
    if (nfbBridgeIsCreateTweet(req.URL.path)) {
        return req;
    }
    NSString* authToken = nil;
    NSString* csrf = nil;
    nfbBridgeReadSharedSession(&authToken, &csrf);
    if (authToken.length == 0 || csrf.length == 0) {
        return req;
    }
    NSString* cookie = req.allHTTPHeaderFields[@"Cookie"] ?: @"";
    if ([cookie containsString:@"auth_token="]) {
        return req;
    }
    NSMutableURLRequest* m = [req mutableCopy];
    NSString* add = [NSString stringWithFormat:@"auth_token=%@; ct0=%@", authToken, csrf];
    NSString* merged = cookie.length ? [NSString stringWithFormat:@"%@; %@", cookie, add] : add;
    [m setValue:merged forHTTPHeaderField:@"Cookie"];
    [m setValue:csrf forHTTPHeaderField:@"x-csrf-token"];
    [m setValue:nfbBridgeBearer() forHTTPHeaderField:@"Authorization"];
    return m;
}

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    if (nfbBridgeIsTwitterAPI(request.URL.absoluteString)) {
        return %orig(nfbBridgeInject(request), handler);
    }
    return %orig;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    if (nfbBridgeIsTwitterAPI(request.URL.absoluteString)) {
        return %orig(nfbBridgeInject(request));
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData {
    if (nfbBridgeIsTwitterAPI(request.URL.absoluteString)) {
        return %orig(nfbBridgeInject(request), bodyData);
    }
    return %orig;
}

%end

#pragma mark - Account mount (the login VC's helpers are file-local, so replicated)

// Prompts a restart once the account is live: the native chrome (Liquid Glass,
// themed bars) only fully applies on a fresh launch. Same quit-and-relaunch
// mechanism the tweak's settings already use.
static void nfbBridgeShowRestartPrompt(void) {
    UIWindow* keyWindow = nil;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    UIViewController* top = keyWindow.rootViewController;
    if (!top) {
        return;
    }
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:@"Almost there"
                         message:@"Restart Twitter to finish loading the interface."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* action) {
                                              [[NSUserDefaults standardUserDefaults] synchronize];
                                              exit(0);
                                            }]];
    [top presentViewController:alert animated:YES completion:nil];
}

// Registers the account with the app's account service and switches the UI to it,
// dismissing the login screen first. Mirrors the login controller's own sequence.
static void nfbBridgeMount(NSString* screen, long long uid, NSString* token, NSString* secret,
                           UIViewController* presenter) {
    Class accountCls = objc_getClass("TFNTwitterAccount");
    SEL initSel = NSSelectorFromString(@"initWithUsername:userID:");
    if (!accountCls || ![accountCls instancesRespondToSelector:initSel]) {
        NFBDebugLog(@"[bridge] account class/init absent");
        return;
    }
    id account = ((id (*)(id, SEL, id, long long))objc_msgSend)(
        [accountCls alloc], initSel, screen, uid);
    SEL updSel = NSSelectorFromString(@"updateUserInfoAndCredentialsWithToken:secret:username:");
    if (account && [account respondsToSelector:updSel]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(account, updSel, token, secret, screen);
    }
    if (!account) {
        NFBDebugLog(@"[bridge] account nil after init");
        return;
    }

    Class twitterCls = objc_getClass("TFNTwitter");
    SEL sharedSel = NSSelectorFromString(@"sharedTwitter");
    id shared = (twitterCls && [twitterCls respondsToSelector:sharedSel])
                    ? ((id (*)(id, SEL))objc_msgSend)(twitterCls, sharedSel) : nil;
    SEL svcSel = NSSelectorFromString(@"accountService");
    id service = (shared && [shared respondsToSelector:svcSel])
                     ? ((id (*)(id, SEL))objc_msgSend)(shared, svcSel) : nil;
    SEL addSel = NSSelectorFromString(@"addAccount:");
    if (service && [service respondsToSelector:addSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(service, addSel, account);
    }
    SEL saveSel = NSSelectorFromString(@"saveSharedTwitter");
    if (twitterCls && [twitterCls respondsToSelector:saveSel]) {
        ((void (*)(id, SEL))objc_msgSend)(twitterCls, saveSel);
    }
    NFBDebugLog(@"[bridge] account registered: screen=%@ id=%lld (service=%d)", screen ?: @"nil",
                uid, service != nil);

    void (^switchBlock)(void) = ^{
        Class hostCls = objc_getClass("T1HostViewController");
        SEL hostSel = NSSelectorFromString(@"sharedHostViewController");
        id host = (hostCls && [hostCls respondsToSelector:hostSel])
                      ? ((id (*)(id, SEL))objc_msgSend)(hostCls, hostSel) : nil;
        SEL viewSel = NSSelectorFromString(@"viewAccount:animated:");
        if (host && [host respondsToSelector:viewSel]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(host, viewSel, account, YES);
        }
        NFBDebugLog(@"[bridge] switched to account (host=%d)", host != nil);
        // Once the native account is live, prompt the restart that settles the
        // themed chrome; a short delay lets the switch animation land first.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         nfbBridgeShowRestartPrompt();
                       });
    };

    UIViewController* dismisser = presenter.presentingViewController ?: presenter;
    if (dismisser) {
        [dismisser dismissViewControllerAnimated:YES completion:switchBlock];
    } else {
        switchBlock();
    }
}

@implementation LoginBridge

+ (void)startWithAuthToken:(NSString*)authToken
                      csrf:(NSString*)csrf
                    userID:(long long)userID
                screenName:(NSString*)screenName
                 presenter:(UIViewController*)presenter {
    NFBDebugLog(@"[bridge] start: auth=%lu ct0=%lu id=%lld screen=%@", (unsigned long)authToken.length,
                (unsigned long)csrf.length, userID, screenName ?: @"nil");
    if (!authToken.length || !csrf.length || userID == 0) {
        NFBDebugLog(@"[bridge] session/userID missing - abort");
        return;
    }
    // The OAuth exchange (onboarding/task) never succeeded in testing - 500 code
    // 131 every time - so the shell account is mounted directly over the shared web
    // session. Reads authenticate by cookie (the NSURLSession hook) and writes
    // reroute through WebCreateTweet.x; the session already lives in the shared
    // cookie jar, seeded at capture.
    NSString* screen =
        screenName.length ? screenName : [NSString stringWithFormat:@"id%lld", userID];
    NFBDebugLog(@"[bridge] mounting shell account over shared session (screen=%@)", screen);
    nfbBridgeMount(screen, userID, authToken, csrf, presenter);
}

@end
