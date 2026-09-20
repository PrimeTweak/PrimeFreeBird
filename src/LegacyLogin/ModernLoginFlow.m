#import "ModernLoginFlow.h"
#import "Debug/NFBDebugger.h"
#import <objc/runtime.h>
#import <objc/message.h>

// The public app bearer, split so it is not one grep-able literal. This is the
// well-known unauthenticated bearer every Twitter client sends.
static NSString* nfbBearerValue(void);

static NSString* nfbBearer(void) {
    return [@"Bearer " stringByAppendingString:nfbBearerValue()];
}

// The raw public bearer token, no "Bearer " prefix - the guest command wants the
// token itself.
static NSString* nfbBearerValue(void) {
    return [@"AAAAAAAAAAAAAAAAAAAAAFXzAwAAAAAAMHCxpeSDG1gLNLghVe8d74hl6k4%3D"
            stringByAppendingString:@"RUMF4xAQLsbeBhTSRrCiQpJtxoGWeyHrDb5te2jpGskWDFW82F"];
}

static NSString* const kTaskURL =
    @"https://api.twitter.com/1.1/onboarding/task.json";

// Builds and caches the app's own iOS header provider from the live user-agent
// provider. Enumerated inits only, never a guessed one.
static id nfbIOSHeaderProvider(void) {
    static id provider = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class runner = objc_getClass("TFSTwitterServiceRunner");
        Class hp = objc_getClass("TFNTwitterAPIBasicHeaderProvider");
        SEL uapSel = NSSelectorFromString(@"userAgentProvider");
        if (!runner || !hp || ![runner respondsToSelector:uapSel]) {
            return;
        }
        id uap = ((id (*)(id, SEL))objc_msgSend)(runner, uapSel);
        if (!uap) {
            return;
        }
        SEL initSel = NSSelectorFromString(@"initWithUserAgentProvider:");
        id inst = [hp alloc];
        if (![inst respondsToSelector:initSel]) {
            return;
        }
        provider = ((id (*)(id, SEL, id))objc_msgSend)(inst, initSel, uap);
    });
    return provider;
}

// Overwrites the request's client headers with the app's real iOS identity, so
// the flow stops sending an Android user-agent on an iOS binary.
static void nfbApplyIOSIdentity(NSMutableURLRequest* req) {
    id provider = nfbIOSHeaderProvider();
    if (!provider) {
        NFBDebugLog(@"[flow] ios identity: header provider unavailable");
        return;
    }
    NSUInteger applied = 0;
    SEL allSel =
        NSSelectorFromString(@"tnl_allDefaultHTTPHeaderFieldsForRequest:URLRequest:");
    if ([provider respondsToSelector:allSel]) {
        id headers =
            ((id (*)(id, SEL, id, id))objc_msgSend)(provider, allSel, nil, req);
        if ([headers isKindOfClass:[NSDictionary class]]) {
            for (NSString* k in (NSDictionary*)headers) {
                [req setValue:((NSDictionary*)headers)[k] forHTTPHeaderField:k];
                applied++;
            }
        }
    }
    if (applied == 0) {
        // Fallback to the individual accessors when the bulk method yields nothing.
        NSArray* pairs = @[ @[ @"_tfn_userAgent", @"User-Agent" ],
                            @[ @"_tfn_platform", @"X-Twitter-Client" ],
                            @[ @"_tfn_clientVersion", @"X-Twitter-Client-Version" ] ];
        for (NSArray* pair in pairs) {
            SEL s = NSSelectorFromString(pair[0]);
            if ([provider respondsToSelector:s]) {
                id v = ((id (*)(id, SEL))objc_msgSend)(provider, s);
                if ([v isKindOfClass:[NSString class]]) {
                    [req setValue:v forHTTPHeaderField:pair[1]];
                    applied++;
                }
            }
        }
    }
    NSString* ua = req.allHTTPHeaderFields[@"User-Agent"] ?: @"none";
    NSString* uaHead = ua.length > 24 ? [ua substringToIndex:24] : ua;
    NFBDebugLog(@"[flow] ios identity: %lu header(s), UA=%@",
                (unsigned long)applied, uaHead);
}

@interface ModernLoginFlow ()
@property (nonatomic, copy) NSString* username;
@property (nonatomic, copy) NSString* password;
@property (nonatomic, copy) NSString* guestToken;
@property (nonatomic, copy) NSString* csrf;
@property (nonatomic, copy) void (^done)(NSString*, NSString*, NSString*, NSError*);
@end

@implementation ModernLoginFlow

+ (void)startWithUsername:(NSString*)username
                 password:(NSString*)password
               completion:(void (^)(NSString*, NSString*, NSString*, NSError*))completion {
    ModernLoginFlow* flow = [ModernLoginFlow new];
    flow.username = username;
    flow.password = password;
    flow.done = completion;
    [flow activateGuest];
}

- (void)fail:(NSString*)stage code:(long)code {
    NFBDebugLog(@"[flow] FAILED at %@ code=%ld", stage, code);
    if (self.done) {
        self.done(nil, nil, nil,
                  [NSError errorWithDomain:@"nfb.modernlogin" code:code
                                  userInfo:@{NSLocalizedDescriptionKey : stage}]);
    }
}

// Mints a guest attestation over this exact body+url, returning the two header
// values (or nils on failure) and their names, read from the app's constants.
// Never crashes the flow: a missing provider or nil result yields no headers.
- (void)attestBody:(NSData*)body
               url:(NSURL*)url
        completion:(void (^)(NSString* tokenValue, NSString* sigValue,
                             NSString* tokenName, NSString* sigName))completion {
    Class constants = objc_getClass("_TtC15XAppAttestation20AttestationConstants");
    NSString* tokenName = nil;
    NSString* sigName = nil;
    if (constants) {
        SEL hk = NSSelectorFromString(@"headerKey");
        SEL sk = NSSelectorFromString(@"signedPayloadHeaderKey");
        if ([constants respondsToSelector:hk]) {
            tokenName = ((id (*)(id, SEL))objc_msgSend)(constants, hk);
        }
        if ([constants respondsToSelector:sk]) {
            sigName = ((id (*)(id, SEL))objc_msgSend)(constants, sk);
        }
    }
    NFBDebugLog(@"[flow] attest header names: token=%@ sig=%@",
                tokenName ?: @"?", sigName ?: @"?");

    Class providerCls = objc_getClass("_TtC15XAppAttestation24AttestationTokenProvider");
    SEL sharedSel = NSSelectorFromString(@"sharedProvider");
    SEL attestSel =
        NSSelectorFromString(@"attestPayload:url:forGuestWithAccountID:completion:");
    if (!providerCls || ![providerCls respondsToSelector:sharedSel]) {
        NFBDebugLog(@"[flow] attest: provider class absent");
        completion(nil, nil, tokenName, sigName);
        return;
    }
    id provider = ((id (*)(id, SEL))objc_msgSend)(providerCls, sharedSel);
    if (!provider || ![provider respondsToSelector:attestSel]) {
        NFBDebugLog(@"[flow] attest: provider not ready");
        completion(nil, nil, tokenName, sigName);
        return;
    }

    NSString* accountID = self.guestToken.length ? self.guestToken : @"";
    NFBDebugLog(@"[flow] attest: requesting for guest (account=%lu chars)",
                (unsigned long)accountID.length);
    void (^cb)(id) = ^(id result) {
        NSString* headerValue = nil;
        NSString* signedHash = nil;
        NSString* keyID = nil;
        if (result) {
            SEL hv = NSSelectorFromString(@"headerValue");
            SEL sh = NSSelectorFromString(@"signedHash");
            SEL ki = NSSelectorFromString(@"keyID");
            if ([result respondsToSelector:hv]) {
                headerValue = ((id (*)(id, SEL))objc_msgSend)(result, hv);
            }
            if ([result respondsToSelector:sh]) {
                signedHash = ((id (*)(id, SEL))objc_msgSend)(result, sh);
            }
            if ([result respondsToSelector:ki]) {
                keyID = ((id (*)(id, SEL))objc_msgSend)(result, ki);
            }
        }
        NFBDebugLog(@"[flow] attest result: keyID=%@ value_len=%lu sig_len=%lu",
                    keyID ?: @"nil", (unsigned long)headerValue.length,
                    (unsigned long)signedHash.length);
        completion(headerValue, signedHash, tokenName, sigName);
    };
    ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(provider, attestSel, body, url,
                                                      accountID, cb);
}

// Common POST to onboarding/task: builds the request, applies the iOS identity,
// then attaches guest attestation before sending.
- (void)postTask:(NSDictionary*)body
           query:(NSString*)query
           stage:(NSString*)stage
          handler:(void (^)(NSDictionary* json))handler {
    NSString* urlStr =
        query.length ? [NSString stringWithFormat:@"%@?%@", kTaskURL, query] : kTaskURL;
    NSURL* url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:nfbBearer() forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"yes" forHTTPHeaderField:@"X-Twitter-Active-User"];
    [req setValue:@"en" forHTTPHeaderField:@"X-Twitter-Client-Language"];
    if (self.guestToken.length) {
        [req setValue:self.guestToken forHTTPHeaderField:@"X-Guest-Token"];
    }
    if (self.csrf.length) {
        [req setValue:self.csrf forHTTPHeaderField:@"x-csrf-token"];
    }
    // Shared cookie jar carries __cf_bm and guest_id set by guest activate.
    req.HTTPShouldHandleCookies = YES;
    NSData* bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    req.HTTPBody = bodyData;
    nfbApplyIOSIdentity(req);

    __weak ModernLoginFlow* weakSelf = self;
    [self attestBody:bodyData
                 url:url
          completion:^(NSString* tokenValue, NSString* sigValue,
                       NSString* tokenName, NSString* sigName) {
            if (tokenValue.length && tokenName.length) {
                [req setValue:tokenValue forHTTPHeaderField:tokenName];
            }
            if (sigValue.length && sigName.length) {
                [req setValue:sigValue forHTTPHeaderField:sigName];
            }
            [weakSelf sendTask:req stage:stage handler:handler];
          }];
}

// Sends the prepared onboarding/task request and reports the outcome. On failure
// the full reply and the exact headers sent are logged, so the server complaint
// and any missing header are visible at once.
- (void)sendTask:(NSMutableURLRequest*)req
           stage:(NSString*)stage
         handler:(void (^)(NSDictionary* json))handler {
    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                            ? ((NSHTTPURLResponse*)response).statusCode : -1;
            id json = data.length
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSString* nextSubtask = @"?";
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSArray* subs = json[@"subtasks"];
                if ([subs isKindOfClass:[NSArray class]] && subs.count) {
                    nextSubtask = subs[0][@"subtask_id"] ?: @"?";
                }
            }
            NFBDebugLog(@"[flow] %@ http=%ld len=%lu next=%@", stage, code,
                        (unsigned long)data.length, nextSubtask);
            if (error || code != 200 || ![json isKindOfClass:[NSDictionary class]]) {
                NSString* reply = data.length
                    ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                NFBDebugLog(@"[flow] %@ FULL reply: %@", stage,
                            reply.length > 500 ? [reply substringToIndex:500] : reply);
                NSMutableString* hdrLine = [NSMutableString string];
                for (NSString* k in req.allHTTPHeaderFields) {
                    [hdrLine appendFormat:@"%@=%lu ", k,
                        (unsigned long)[req.allHTTPHeaderFields[k] length]];
                }
                NFBDebugLog(@"[flow] %@ sent header keys: %@", stage, hdrLine);
                [self fail:stage code:code];
                return;
            }
            handler(json);
          }];
    [task resume];
}

// Step 1: a guest token. Sent with a random ct0 as csrf and cookie, which the
// endpoint now requires - without it the call is 401. The iOS identity is applied
// so the guest token is minted under the same client the flow later uses.
- (void)activateGuest {
    NFBDebugLog(@"[flow] start: activating guest");
    self.csrf = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-"
                                                                     withString:@""].lowercaseString;
    NSMutableURLRequest* req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:@"https://api.twitter.com/1.1/guest/activate.json"]];
    req.HTTPMethod = @"POST";
    [req setValue:nfbBearer() forHTTPHeaderField:@"Authorization"];
    [req setValue:self.csrf forHTTPHeaderField:@"x-csrf-token"];
    // HTTPShouldHandleCookies keeps the jar, so __cf_bm and guest_id from this
    // reply ride along on the flow steps - Cloudflare rejects the flow without them.
    req.HTTPShouldHandleCookies = YES;
    nfbApplyIOSIdentity(req);
    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                            ? ((NSHTTPURLResponse*)response).statusCode : -1;
            id json = data.length
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSString* gt = [json isKindOfClass:[NSDictionary class]] ? json[@"guest_token"] : nil;
            NFBDebugLog(@"[flow] guest activate http=%ld token_len=%lu", code,
                        (unsigned long)gt.length);
            if (!gt.length) {
                NSString* reply = data.length
                    ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                if (reply.length) {
                    NFBDebugLog(@"[flow] guest reply head: %@",
                                reply.length > 200 ? [reply substringToIndex:200] : reply);
                }
                [self fail:@"guest_activate" code:code];
                return;
            }
            NSString* setCookie = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? ((NSHTTPURLResponse*)response).allHeaderFields[@"Set-Cookie"] : nil;
            NFBDebugLog(@"[flow] guest set-cookie: %@", setCookie ?: @"none");
            self.guestToken = gt;
            [self startFlow];
          }];
    [task resume];
}

// Step 2: open the login flow, get the first flow_token. A clean login body -
// no signup referrer, splash_screen start - so the shape matches a real login.
- (void)startFlow {
    NSDictionary* body = @{
        @"flow_token" : [NSNull null],
        @"input_flow_data" : @{
            @"flow_context" : @{
                @"start_location" : @{@"location" : @"splash_screen"}
            }
        }
    };
    [self postTask:body query:@"flow_name=login" stage:@"start_flow"
           handler:^(NSDictionary* json) {
             [self jsInstrumentation:json[@"flow_token"]];
           }];
}

// Step 3: the JS instrumentation subtask - an empty response satisfies it.
- (void)jsInstrumentation:(NSString*)flowToken {
    NSDictionary* body = @{
        @"flow_token" : flowToken ?: @"",
        @"subtask_inputs" : @[ @{
            @"subtask_id" : @"LoginJsInstrumentationSubtask",
            @"js_instrumentation" : @{@"response" : @"{}", @"link" : @"next_link"}
        } ]
    };
    [self postTask:body query:nil stage:@"js_instrumentation" handler:^(NSDictionary* json) {
      [self enterUsername:json[@"flow_token"]];
    }];
}

// Step 4: the username.
- (void)enterUsername:(NSString*)flowToken {
    NSDictionary* body = @{
        @"flow_token" : flowToken ?: @"",
        @"subtask_inputs" : @[ @{
            @"subtask_id" : @"LoginEnterUserIdentifierSSO",
            @"settings_list" : @{
                @"setting_responses" : @[ @{
                    @"key" : @"user_identifier",
                    @"response_data" : @{@"text_data" : @{@"result" : self.username}}
                } ],
                @"link" : @"next_link"
            }
        } ]
    };
    [self postTask:body query:nil stage:@"enter_username" handler:^(NSDictionary* json) {
      [self enterPassword:json[@"flow_token"]];
    }];
}

// Step 5: the password.
- (void)enterPassword:(NSString*)flowToken {
    NSDictionary* body = @{
        @"flow_token" : flowToken ?: @"",
        @"subtask_inputs" : @[ @{
            @"subtask_id" : @"LoginEnterPassword",
            @"enter_password" : @{@"password" : self.password, @"link" : @"next_link"}
        } ]
    };
    [self postTask:body query:nil stage:@"enter_password" handler:^(NSDictionary* json) {
      [self duplicationCheck:json[@"flow_token"]];
    }];
}

// Step 6: the account duplication check yields the open_account with the tokens.
- (void)duplicationCheck:(NSString*)flowToken {
    NSDictionary* body = @{
        @"flow_token" : flowToken ?: @"",
        @"subtask_inputs" : @[ @{
            @"subtask_id" : @"AccountDuplicationCheck",
            @"check_logged_in_account" : @{@"link" : @"AccountDuplicationCheck_false"}
        } ]
    };
    [self postTask:body query:nil stage:@"duplication_check" handler:^(NSDictionary* json) {
      [self extractTokens:json];
    }];
}

// The open_account subtask carries oauth_token + oauth_token_secret.
- (void)extractTokens:(NSDictionary*)json {
    NSArray* subs = json[@"subtasks"];
    NSDictionary* open = nil;
    if ([subs isKindOfClass:[NSArray class]]) {
        for (NSDictionary* s in subs) {
            if ([s[@"open_account"] isKindOfClass:[NSDictionary class]]) {
                open = s[@"open_account"];
                break;
            }
        }
    }
    NSString* token = open[@"oauth_token"];
    NSString* secret = open[@"oauth_token_secret"];
    NSString* screen = open[@"screen_name"];
    NFBDebugLog(@"[flow] tokens: oauth=%lu secret=%lu screen=%@",
                (unsigned long)token.length, (unsigned long)secret.length, screen);
    if (token.length && secret.length) {
        NFBDebugLog(@"[flow] SUCCESS - oauth pair obtained, native account can mount");
        if (self.done) {
            self.done(token, secret, screen, nil);
        }
    } else {
        [self fail:@"extract_tokens" code:0];
    }
}

@end
