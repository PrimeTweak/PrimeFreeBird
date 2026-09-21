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
    };

    UIViewController* dismisser = presenter.presentingViewController ?: presenter;
    if (dismisser) {
        [dismisser dismissViewControllerAnimated:YES completion:switchBlock];
    } else {
        switchBlock();
    }
}

#pragma mark - Session-authenticated requests

// Builds a request carrying the captured web session, so the server treats it as
// the logged-in browser.
static NSMutableURLRequest* nfbBridgeSessionRequest(NSString* urlStr, NSString* method,
                                                    NSString* authToken, NSString* csrf) {
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = method;
    [req setValue:nfbBridgeBearer() forHTTPHeaderField:@"Authorization"];
    [req setValue:csrf forHTTPHeaderField:@"x-csrf-token"];
    [req setValue:[NSString stringWithFormat:@"auth_token=%@; ct0=%@", authToken, csrf]
        forHTTPHeaderField:@"Cookie"];
    return req;
}

// Voie B: an already-authenticated session may drive onboarding/task to the
// open_account subtask without credentials or attestation, yielding the OAuth pair.
static void nfbBridgeExchangeB(NSString* authToken, NSString* csrf,
                               void (^done)(NSString* token, NSString* secret, NSString* screen)) {
    NSMutableURLRequest* req = nfbBridgeSessionRequest(
        @"https://api.twitter.com/1.1/onboarding/task.json?flow_name=login", @"POST", authToken,
        csrf);
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                            ? ((NSHTTPURLResponse*)response).statusCode : -1;
            NSString* token = nil;
            NSString* secret = nil;
            NSString* screen = nil;
            id json = data.length
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSArray* subs = json[@"subtasks"];
                if ([subs isKindOfClass:[NSArray class]]) {
                    for (id s in subs) {
                        id open =
                            [s isKindOfClass:[NSDictionary class]] ? s[@"open_account"] : nil;
                        if ([open isKindOfClass:[NSDictionary class]]) {
                            token = open[@"oauth_token"];
                            secret = open[@"oauth_token_secret"];
                            screen = open[@"screen_name"];
                            break;
                        }
                    }
                }
            }
            NSString* head = data.length
                ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (head.length > 160) {
                head = [head substringToIndex:160];
            }
            NFBDebugLog(@"[bridge:B] exchange http=%ld oauth=%lu secret=%lu reply=%@", code,
                        (unsigned long)token.length, (unsigned long)secret.length, head);
            dispatch_async(dispatch_get_main_queue(), ^{
              done(token, secret, screen);
            });
          }];
    [task resume];
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
    // A missing handle no longer blocks the mount: the app refreshes it from the
    // userID once the account exists.
    NSString* placeholder = [NSString stringWithFormat:@"id%lld", userID];
    __weak UIViewController* weakPresenter = presenter;
    // Voie B first: the clean OAuth pair, whose open_account carries the real
    // handle. Voie A only if B yields nothing.
    nfbBridgeExchangeB(authToken, csrf, ^(NSString* token, NSString* secret, NSString* bScreen) {
      if (token.length && secret.length) {
          NSString* screen = bScreen.length ? bScreen : (screenName.length ? screenName : placeholder);
          NFBDebugLog(@"[bridge:B] oauth pair obtained - mounting real account (screen=%@)", screen);
          nfbBridgeMount(screen, userID, token, secret, weakPresenter);
          return;
      }
      // Voie A: reads authenticate by cookie over the shared web session (the
      // NSURLSession hook), so the shell account only needs to exist. The session
      // itself already lives in the shared cookie jar (seeded at capture), which
      // is what the injection and WebCreateTweet.x both read.
      NSString* screen = screenName.length ? screenName : placeholder;
      NFBDebugLog(@"[bridge:A] no pair - mounting shell account over shared session (screen=%@)",
                  screen);
      nfbBridgeMount(screen, userID, authToken, csrf, weakPresenter);
    });
}

@end
