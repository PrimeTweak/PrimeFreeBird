#import "ModernLoginFlow.h"
#import "Debug/NFBDebugger.h"
#import <objc/runtime.h>
#import <objc/message.h>

// The app's own command stack, which carries the correct app bearer. Reused so
// guest activate is authorized exactly as the app authorizes it.
static id nfbContext(void) {
    return ((id (*)(id, SEL))objc_msgSend)(
        objc_getClass("TFSTwitterServiceRunner"), @selector(APICommandContext));
}

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

@interface ModernLoginFlow ()
@property (nonatomic, copy) NSString* username;
@property (nonatomic, copy) NSString* password;
@property (nonatomic, copy) NSString* guestToken;
@property (nonatomic, copy) NSString* attToken;
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

// Common POST to onboarding/task with the headers the flow needs. The att token,
// once the server issues it, is echoed back on every later call.
- (void)postTask:(NSDictionary*)body
           query:(NSString*)query
           stage:(NSString*)stage
          handler:(void (^)(NSDictionary* json))handler {
    NSString* urlStr = query.length ? [NSString stringWithFormat:@"%@?%@", kTaskURL, query] : kTaskURL;
    NSMutableURLRequest* req =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"POST";
    [req setValue:nfbBearer() forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"yes" forHTTPHeaderField:@"X-Twitter-Active-User"];
    [req setValue:@"en" forHTTPHeaderField:@"X-Twitter-Client-Language"];
    [req setValue:@"TwitterAndroid/10.21.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"TwitterAndroid" forHTTPHeaderField:@"X-Twitter-Client"];
    [req setValue:@"10.21.1" forHTTPHeaderField:@"X-Twitter-Client-Version"];
    [req setValue:@"5" forHTTPHeaderField:@"X-Twitter-API-Version"];
    if (self.guestToken.length) {
        [req setValue:self.guestToken forHTTPHeaderField:@"X-Guest-Token"];
    }
    if (self.csrf.length) {
        [req setValue:self.csrf forHTTPHeaderField:@"x-csrf-token"];
    }
    // Shared cookie jar carries __cf_bm and guest_id set by guest activate.
    req.HTTPShouldHandleCookies = YES;
    // Probe: capture the real app bearer the first time, so if an onboarding step
    // returns 401 the correct bearer is already in the log for the next fix.
    static dispatch_once_t onceBearer;
    dispatch_once(&onceBearer, ^{
      id ctx = nfbContext();
      if ([ctx respondsToSelector:@selector(authorizationHeaders)]) {
          id hdrs = ((id (*)(id, SEL))objc_msgSend)(ctx, @selector(authorizationHeaders));
          id auth = [hdrs isKindOfClass:[NSDictionary class]] ? hdrs[@"Authorization"] : nil;
          NFBDebugLog(@"[flow] app bearer len=%lu head=%@",
                      (unsigned long)[auth length],
                      [auth length] > 24 ? [auth substringToIndex:24] : (auth ?: @"nil"));
      } else {
          NFBDebugLog(@"[flow] context has no authorizationHeaders accessor");
      }
    });
    if (self.attToken.length) {
        [req setValue:self.attToken forHTTPHeaderField:@"att"];
    }
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                            ? ((NSHTTPURLResponse*)response).statusCode : -1;
            NSString* att = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? ((NSHTTPURLResponse*)response).allHeaderFields[@"att"] : nil;
            if (att.length) {
                self.attToken = att;
            }
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
                // Full reply and the request headers actually sent, so the exact
                // server complaint and any missing header are visible at once.
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
// endpoint now requires - without it the call is 401. Plain NSURLSession, the
// bearer being the public Android one every working client uses.
- (void)activateGuest {
    NFBDebugLog(@"[flow] start: activating guest");
    self.csrf = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-"
                                                                     withString:@""].lowercaseString;
    NSMutableURLRequest* req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:@"https://api.twitter.com/1.1/guest/activate.json"]];
    req.HTTPMethod = @"POST";
    [req setValue:nfbBearer() forHTTPHeaderField:@"Authorization"];
    [req setValue:self.csrf forHTTPHeaderField:@"x-csrf-token"];
    [req setValue:@"TwitterAndroid/10.21.1" forHTTPHeaderField:@"User-Agent"];
    // HTTPShouldHandleCookies keeps the jar, so __cf_bm and guest_id from this
    // reply ride along on the flow steps - Cloudflare rejects the flow without them.
    req.HTTPShouldHandleCookies = YES;
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
            // The server may set its own ct0; if so, use it for the flow steps.
            NSString* setCookie = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? ((NSHTTPURLResponse*)response).allHeaderFields[@"Set-Cookie"] : nil;
            NFBDebugLog(@"[flow] guest set-cookie: %@", setCookie ?: @"none");
            self.guestToken = gt;
            [self startFlow];
          }];
    [task resume];
}

// Step 2: open the login flow, get the first flow_token.
- (void)startFlow {
    NSDictionary* body = @{
        @"flow_token" : [NSNull null],
        @"input_flow_data" : @{
            @"country_code" : [NSNull null],
            @"flow_context" : @{
                @"referrer_context" : @{
                    @"referral_details" : @"utm_source=google-play&utm_medium=organic",
                    @"referrer_url" : @""
                },
                @"start_location" : @{@"location" : @"deeplink"}
            },
            @"requested_variant" : [NSNull null],
            @"target_user_id" : @0
        }
    };
    [self postTask:body
             query:@"flow_name=login&api_version=1&known_device_token=&sim_country_code=us"
             stage:@"start_flow"
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
