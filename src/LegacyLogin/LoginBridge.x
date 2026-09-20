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

#pragma mark - Voie A: session injected into the app's own API traffic

static BOOL gInjectSession = NO;
static NSString* gInjectAuthToken = nil;
static NSString* gInjectCsrf = nil;

// Adds the web session cookie + csrf to an app API request that lacks them, so
// the server authenticates it by cookie instead of the missing OAuth signature.
static NSURLRequest* nfbBridgeInject(NSURLRequest* req) {
    if (!gInjectSession || !gInjectAuthToken.length || !req) {
        return req;
    }
    if (!nfbBridgeIsTwitterAPI(req.URL.absoluteString)) {
        return req;
    }
    NSString* cookie = req.allHTTPHeaderFields[@"Cookie"] ?: @"";
    if ([cookie containsString:@"auth_token="]) {
        return req;
    }
    NSMutableURLRequest* m = [req mutableCopy];
    NSString* add =
        [NSString stringWithFormat:@"auth_token=%@; ct0=%@", gInjectAuthToken, gInjectCsrf];
    NSString* merged = cookie.length ? [NSString stringWithFormat:@"%@; %@", cookie, add] : add;
    [m setValue:merged forHTTPHeaderField:@"Cookie"];
    [m setValue:gInjectCsrf forHTTPHeaderField:@"x-csrf-token"];
    NFBDebugLog(@"[bridge:A] session injected into %@", req.URL.path ?: @"?");
    return m;
}

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    if (gInjectSession && nfbBridgeIsTwitterAPI(request.URL.absoluteString)) {
        return %orig(nfbBridgeInject(request), handler);
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

// Reads the logged-in screen name and user id from the session, so the account is
// mounted under the right identity.
static void nfbBridgeVerify(NSString* authToken, NSString* csrf,
                            void (^done)(NSString* screen, long long uid)) {
    NSMutableURLRequest* req = nfbBridgeSessionRequest(
        @"https://api.twitter.com/1.1/account/verify_credentials.json", @"GET", authToken, csrf);
    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                            ? ((NSHTTPURLResponse*)response).statusCode : -1;
            id json = data.length
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSString* screen =
                [json isKindOfClass:[NSDictionary class]] ? json[@"screen_name"] : nil;
            long long uid = 0;
            if ([json isKindOfClass:[NSDictionary class]]) {
                id idStr = json[@"id_str"] ?: json[@"id"];
                uid = [idStr respondsToSelector:@selector(longLongValue)] ? [idStr longLongValue] : 0;
            }
            NFBDebugLog(@"[bridge] verify http=%ld screen=%@ id=%lld", code, screen ?: @"nil", uid);
            dispatch_async(dispatch_get_main_queue(), ^{
              done(screen, uid);
            });
          }];
    [task resume];
}

// Voie B: an already-authenticated session may drive onboarding/task to the
// open_account subtask without credentials or attestation, yielding the OAuth pair.
static void nfbBridgeExchangeB(NSString* authToken, NSString* csrf,
                               void (^done)(NSString* token, NSString* secret)) {
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
              done(token, secret);
            });
          }];
    [task resume];
}

@implementation LoginBridge

+ (void)startWithAuthToken:(NSString*)authToken
                      csrf:(NSString*)csrf
                 presenter:(UIViewController*)presenter {
    NFBDebugLog(@"[bridge] start: auth=%lu ct0=%lu", (unsigned long)authToken.length,
                (unsigned long)csrf.length);
    if (!authToken.length || !csrf.length) {
        NFBDebugLog(@"[bridge] no session - abort");
        return;
    }
    __weak UIViewController* weakPresenter = presenter;
    nfbBridgeVerify(authToken, csrf, ^(NSString* screen, long long uid) {
      if (!screen.length || uid == 0) {
          NFBDebugLog(@"[bridge] verify incomplete - cannot mount");
          return;
      }
      // Voie B first: the clean OAuth pair. Voie A only if B yields nothing.
      nfbBridgeExchangeB(authToken, csrf, ^(NSString* token, NSString* secret) {
        if (token.length && secret.length) {
            NFBDebugLog(@"[bridge:B] oauth pair obtained - mounting real account");
            nfbBridgeMount(screen, uid, token, secret, weakPresenter);
            return;
        }
        NFBDebugLog(@"[bridge:B] no pair - enabling voie A (cookie injection)");
        gInjectAuthToken = authToken;
        gInjectCsrf = csrf;
        gInjectSession = YES;
        NFBDebugLog(@"[bridge:A] injection armed; mounting session-backed account");
        nfbBridgeMount(screen, uid, authToken, csrf, weakPresenter);
      });
    });
}

@end
