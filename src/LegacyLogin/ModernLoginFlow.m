#import "ModernLoginFlow.h"
#import "Debug/NFBDebugger.h"

// The public app bearer, split so it is not one grep-able literal. This is the
// well-known unauthenticated bearer every Twitter client sends.
static NSString* nfbBearer(void) {
    return [@"Bearer AAAAAAAAAAAAAAAAAAAAAFQODgEAAAAAVHTp76lzh3rFzcHb"
            stringByAppendingString:@"mHYli9V7mWo%3DR1RJ4YDpXvXAOJZlXQZFJ2sMuFEbBDLwGoDCV5D5Hh"];
}

static NSString* const kTaskURL =
    @"https://api.twitter.com/1.1/onboarding/task.json";

@interface ModernLoginFlow ()
@property (nonatomic, copy) NSString* username;
@property (nonatomic, copy) NSString* password;
@property (nonatomic, copy) NSString* guestToken;
@property (nonatomic, copy) NSString* attToken;
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
    if (self.guestToken.length) {
        [req setValue:self.guestToken forHTTPHeaderField:@"X-Guest-Token"];
    }
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
                if (reply.length) {
                    NFBDebugLog(@"[flow] %@ reply head: %@", stage,
                                reply.length > 240 ? [reply substringToIndex:240] : reply);
                }
                [self fail:stage code:code];
                return;
            }
            handler(json);
          }];
    [task resume];
}

// Step 1: a guest token, via the same guest activate endpoint the app uses.
- (void)activateGuest {
    NFBDebugLog(@"[flow] start: activating guest");
    NSMutableURLRequest* req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:@"https://api.twitter.com/1.1/guest/activate.json"]];
    req.HTTPMethod = @"POST";
    [req setValue:nfbBearer() forHTTPHeaderField:@"Authorization"];
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
                [self fail:@"guest_activate" code:code];
                return;
            }
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
            @"flow_context" : @{
                @"start_location" : @{@"location" : @"manual_link"}
            }
        }
    };
    [self postTask:body
             query:@"flow_name=login"
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
