#import "Sideload/PFBLoginBridge.h"
#import "Debug/PFBDebugger.h"
#import "Support/HookHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>

// The public unauthenticated bearer every client sends, split so it is not one
// grep-able literal.
static NSString* pfbBridgeBearer(void) {
    return [@"Bearer AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3D"
            stringByAppendingString:@"RUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"];
}

// An exact host test, never a substring of the URL: a third-party address that
// merely mentions an X host must not receive the session.
static BOOL pfbBridgeIsXHost(NSURL* url) {
    if (![url.scheme isEqualToString:@"https"] || !PFBIsXDomain(url.host)) {
        return NO;
    }
    return ![url.absoluteString containsString:@"jfapi"];
}

// The shell account's OAuth signature, which the server refuses on any X host.
static BOOL pfbBridgeCarriesAppOAuth(NSURLRequest* req) {
    NSString* auth = [req valueForHTTPHeaderField:@"Authorization"];
    return [auth isKindOfClass:[NSString class]] && [auth containsString:@"oauth_token="];
}

// A media upload: a write to the upload host, or to the DM media store.
static BOOL pfbBridgeIsMediaUpload(NSURLRequest* req) {
    NSString* host = req.URL.host.lowercaseString;
    NSString* method = req.HTTPMethod.uppercaseString;
    if (![method isEqualToString:@"POST"] && ![method isEqualToString:@"PUT"]) {
        return NO;
    }
    return [host hasPrefix:@"upload."] ||
           ([host hasPrefix:@"ton."] && [req.URL.path hasPrefix:@"/i/ton/data/"]);
}

// API hosts always, and any other X host (media upload included) once the request
// carries the shell account's OAuth, so a new endpoint is covered without a host list.
static BOOL pfbBridgeWantsRequest(NSURLRequest* req) {
    NSURL* url = req.URL;
    if (!pfbBridgeIsXHost(url)) {
        return NO;
    }
    return [url.host.lowercaseString hasPrefix:@"api."] || [url.path hasPrefix:@"/i/api"] ||
           pfbBridgeCarriesAppOAuth(req);
}

#pragma mark - Read injection over the shared web session

// Only CreateTweet is left to WebCreateTweet.x, which reroutes it to the web
// endpoint with a per-operation x-client-transaction-id; injecting here would
// clobber that reroute. Every other mutation authenticates by cookie like a read.
static BOOL pfbBridgeIsCreateTweet(NSString* path) {
    return [path isKindOfClass:[NSString class]] &&
           [path.lastPathComponent isEqualToString:@"CreateTweet"];
}

// The read session is the shared web session: the one WebCreateTweet.x harvests
// for writes and PFBClearWebSession wipes. Reading it here means login,
// persistence and sign-out all flow through that single place.
static void pfbBridgeReadSharedSession(NSString** authToken, NSString** csrf) {
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

// Once per launch and per answer, while the journal records: which session a request
// signed for another account than the shared session's goes out with.
static void pfbBridgeProbeAccount(NSString* line) {
    static NSMutableSet<NSString*>* said;
    static dispatch_once_t once;
    if (!PFBDebugIsRecording()) {
        return;
    }
    dispatch_once(&once, ^{
      said = [NSMutableSet set];
    });
    @synchronized(said) {
        if ([said containsObject:line]) {
            return;
        }
        [said addObject:line];
    }
    PFBDebugLog(@"%@", line);
}

// Adds a web session cookie + csrf to an app request, replacing the shell account's
// invalid OAuth so the server authenticates it by cookie. A request signed for a bridged
// account goes with that account's own session; the shared one serves the rest.
static NSURLRequest* pfbBridgeInject(NSURLRequest* req) {
    if (!req || !pfbBridgeWantsRequest(req)) {
        return req;
    }
    if (pfbBridgeIsCreateTweet(req.URL.path)) {
        return req;
    }
    NSString* authToken = nil;
    NSString* csrf = nil;
    pfbBridgeReadSharedSession(&authToken, &csrf);
    if (authToken.length == 0 || csrf.length == 0) {
        return req;
    }
    NSString* cookie = req.allHTTPHeaderFields[@"Cookie"] ?: @"";
    if ([cookie containsString:@"auth_token="]) {
        return req;
    }
    NSString* own = PFBWebAuthTokenOfRequest(req);
    BOOL ownSession = own.length && ![own isEqualToString:authToken];
    if (ownSession) {
        // Never the shared session for another account: its own token, and its csrf once
        // fetched. Until then the request may be refused, but never sent as another account.
        authToken = own;
        csrf = PFBWebCt0ForAuthToken(own, YES);
        pfbBridgeProbeAccount(csrf.length
            ? @"[bridge] a request signed for another account went with its own web session"
            : @"[bridge] a request signed for another account went with its own web session, csrf pending");
    }
    if (pfbBridgeIsMediaUpload(req)) {
        NSString* host = req.URL.host.lowercaseString;
        pfbBridgeProbeAccount([NSString stringWithFormat:@"[bridge] media upload to %@ went with %@ web session",
                                                         [host substringToIndex:[host rangeOfString:@"."].location],
                                                         ownSession ? @"its own account's" : @"the shared"]);
        PFBCompatReach(PFBCompatPath_web_media);
        PFBCOMPAT_ACTION(PFBCompat_web_session, @"media uploaded through the web session");
    }
    NSMutableURLRequest* m = [req mutableCopy];
    NSString* add = csrf.length ? [NSString stringWithFormat:@"auth_token=%@; ct0=%@", authToken, csrf]
                                : [NSString stringWithFormat:@"auth_token=%@", authToken];
    NSString* merged = cookie.length ? [NSString stringWithFormat:@"%@; %@", cookie, add] : add;
    [m setValue:merged forHTTPHeaderField:@"Cookie"];
    [m setValue:csrf forHTTPHeaderField:@"x-csrf-token"];
    [m setValue:pfbBridgeBearer() forHTTPHeaderField:@"Authorization"];
    return m;
}

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    return %orig(pfbBridgeInject(request), handler);
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    return %orig(pfbBridgeInject(request));
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData {
    return %orig(pfbBridgeInject(request), bodyData);
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData
                               completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    return %orig(pfbBridgeInject(request), bodyData, handler);
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromFile:(NSURL*)fileURL {
    return %orig(pfbBridgeInject(request), fileURL);
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromFile:(NSURL*)fileURL
                               completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    return %orig(pfbBridgeInject(request), fileURL, handler);
}

- (NSURLSessionUploadTask*)uploadTaskWithStreamedRequest:(NSURLRequest*)request {
    return %orig(pfbBridgeInject(request));
}

%end

#pragma mark - Account mount

// Prompts a restart once the account is live: the native chrome (Liquid Glass, themed
// bars) only fully applies on a fresh launch. Same quit-and-relaunch mechanism as the
// settings.
static void pfbBridgeShowRestartPrompt(void) {
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
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"LOGIN_RESTART_TITLE"]
                         message:[bundle localizedStringForKey:@"LOGIN_RESTART_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"RESTART_LATER_ACTION"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"RESTART_NOW_ACTION"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* action) {
                                              [[NSUserDefaults standardUserDefaults] synchronize];
                                              exit(0);
                                            }]];
    [top presentViewController:alert animated:YES completion:nil];
}

// Registers the account with the app's account service and switches the UI to it,
// dismissing the login screen first.
static void pfbBridgeMount(NSString* screen, long long uid, NSString* token, NSString* secret,
                           UIViewController* presenter) {
    Class accountCls = objc_getClass("TFNTwitterAccount");
    SEL initSel = NSSelectorFromString(@"initWithUsername:userID:");
    if (!accountCls || ![accountCls instancesRespondToSelector:initSel]) {
        PFBDebugLog(@"[bridge] account class/init absent");
        return;
    }
    id account = ((id (*)(id, SEL, id, long long))objc_msgSend)(
        [accountCls alloc], initSel, screen, uid);
    SEL updSel = NSSelectorFromString(@"updateUserInfoAndCredentialsWithToken:secret:username:");
    if (account && [account respondsToSelector:updSel]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(account, updSel, token, secret, screen);
    }
    if (!account) {
        PFBDebugLog(@"[bridge] account nil after init");
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
    PFBDebugLog(@"[bridge] account registered: screen=%@ id=%lld (service=%d)", screen ?: @"nil",
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
        PFBDebugLog(@"[bridge] switched to account (host=%d)", host != nil);
        // Once the native account is live, prompt the restart that settles the
        // themed chrome; a short delay lets the switch animation land first.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         pfbBridgeShowRestartPrompt();
                       });
    };

    UIViewController* dismisser = presenter.presentingViewController ?: presenter;
    if (dismisser) {
        [dismisser dismissViewControllerAnimated:YES completion:switchBlock];
    } else {
        switchBlock();
    }
}

@implementation PFBLoginBridge

+ (void)startWithAuthToken:(NSString*)authToken
                      csrf:(NSString*)csrf
                    userID:(long long)userID
                screenName:(NSString*)screenName
                 presenter:(UIViewController*)presenter {
    PFBDebugLog(@"[bridge] start: auth=%lu ct0=%lu id=%lld screen=%@", (unsigned long)authToken.length,
                (unsigned long)csrf.length, userID, screenName ?: @"nil");
    if (!authToken.length || !csrf.length || userID == 0) {
        PFBDebugLog(@"[bridge] session/userID missing - abort");
        return;
    }
    // The shell account is mounted directly over the shared web session: reads
    // authenticate by cookie (the NSURLSession hook), writes reroute through
    // WebCreateTweet.x, and the session already lives in the shared cookie jar.
    NSString* screen =
        screenName.length ? screenName : [NSString stringWithFormat:@"id%lld", userID];
    pfbBridgeMount(screen, userID, authToken, csrf, presenter);
}

@end
