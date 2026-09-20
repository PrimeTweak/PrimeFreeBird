// Measurement only: observes Twitter's home-grown attestation flow to see what
// blocks sign-in on a sideloaded build. Logs feature-switch reads whose key
// mentions attestation, and inspects the token provider and the onboarding
// subtask. Nothing is forced or altered. Prefix [attest].
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Debug/NFBDebugger.h"

// Every feature-switch read touching attestation, so we see the exact server
// keys and their values on this build - the ones a fix would force.
%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    BOOL value = %orig;
    if (NFBDebugIsRecording() && [key isKindOfClass:[NSString class]] &&
        [key.lowercaseString containsString:@"attestation"]) {
        NFBDebugLog(@"[attest] switch bool '%@' = %d", key, value ? 1 : 0);
    }
    return value;
}

%end

// The token provider is a Swift singleton; this reads whether it exists and
// whether it currently holds or yields a token, without triggering a real one.
static void nfbAttestInspectProvider(void) {
    Class provider = objc_getClass("_TtC15XAppAttestation24AttestationTokenProvider");
    if (!provider) {
        NFBDebugLog(@"[attest] token provider class absent");
        return;
    }
    NFBDebugLog(@"[attest] token provider present");
    Class constants = objc_getClass("_TtC15XAppAttestation20AttestationConstants");
    NFBDebugLog(@"[attest] constants class: %d", constants != nil);
}

// The onboarding subtask that carries the token: its presence in the flow is
// what turns a login into an attestation challenge.
static void nfbAttestInspectSubtask(void) {
    Class subtask = objc_getClass("OCFAttestationSubtask");
    Class state = objc_getClass("OCFAttestationSubtaskState");
    NFBDebugLog(@"[attest] subtask=%d state=%d", subtask != nil, state != nil);
    if (state) {
        SEL keySel = NSSelectorFromString(@"attestationTokenKey");
        if ([state respondsToSelector:keySel]) {
            id key = ((id (*)(id, SEL))objc_msgSend)(state, keySel);
            NFBDebugLog(@"[attest] token json key: %@", key);
        }
    }
}

%hook OCFAttestationSubtask

// Fires only when Twitter actually inserts an attestation step into the flow -
// the proof that this is what a sideloaded login hits.
- (id)initWithJSONDictionary:(id)dict
                   subtaskID:(id)subtaskID
                    typeName:(id)typeName
          backNavigationType:(id)backNavType
          backNavigationLink:(id)backNavLink
                       error:(id*)error {
    if (NFBDebugIsRecording()) {
        NFBDebugLog(@"[attest] SUBTASK HIT in flow: id=%@ type=%@", subtaskID, typeName);
    }
    return %orig;
}

%end

%hook OCFAttestationSubtaskState

// The token the app sends back. Length only, never the value.
- (void)setAttestationToken:(id)token {
    if (NFBDebugIsRecording()) {
        NSUInteger len = [token isKindOfClass:[NSString class]] ? [token length] : 0;
        NFBDebugLog(@"[attest] token set, length=%lu", (unsigned long)len);
    }
    %orig;
}

%end

// The native login skips onboarding/task, so all Twitter API traffic is watched:
// path, method, auth/attestation fields, and reply. Web login (jfapi) is left out.
static BOOL nfbIsTwitterAPI(NSString* url) {
    if (![url isKindOfClass:[NSString class]]) {
        return NO;
    }
    if ([url containsString:@"jfapi"]) {
        return NO;
    }
    return [url containsString:@"api.twitter.com"] ||
           [url containsString:@"api.x.com"] ||
           [url containsString:@"/1.1/"] ||
           [url containsString:@"/onboarding/"] ||
           [url containsString:@"/auth/"] ||
           [url containsString:@"/oauth"];
}

static void nfbReportRequest(NSURLRequest* request, NSString* tag) {
    NSString* url = request.URL.absoluteString;
    NSString* path = request.URL.path ?: url;
    NSData* body = request.HTTPBody;
    NSString* bodyText = body.length
        ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : @"";
    NSDictionary* headers = request.allHTTPHeaderFields;
    BOOL hasAuthHeader = headers[@"Authorization"] != nil ||
                         headers[@"authorization"] != nil;
    BOOL hasCsrf = headers[@"x-csrf-token"] != nil;
    BOOL bodyAttest = [bodyText containsString:@"attestation"];
    BOOL bodyPassword = [bodyText containsString:@"password"];
    NFBDebugLog(@"[net:%@] %@ %@", tag, request.HTTPMethod ?: @"GET", path);
    NFBDebugLog(@"[net:%@] auth_header=%d csrf=%d body_len=%lu attestation=%d password=%d",
                tag, hasAuthHeader, hasCsrf, (unsigned long)body.length,
                bodyAttest, bodyPassword);
    if (bodyText.length && bodyText.length <= 300) {
        NFBDebugLog(@"[net:%@] body: %@", tag, bodyText);
    } else if (bodyText.length) {
        NFBDebugLog(@"[net:%@] body head: %@", tag, [bodyText substringToIndex:300]);
    }
}

static void nfbReportReply(NSData* data, NSURLResponse* response, NSString* tag) {
    long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? ((NSHTTPURLResponse*)response).statusCode : -1;
    NSString* reply = data.length
        ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    BOOL attest = [reply containsString:@"ttestation"];
    BOOL denied = [reply containsString:@"AttestationDenied"];
    NFBDebugLog(@"[net:%@] reply http=%ld len=%lu attestation=%d denied=%d",
                tag, code, (unsigned long)data.length, attest, denied);
    if (reply.length && code != 200) {
        NFBDebugLog(@"[net:%@] reply head: %@", tag,
                    reply.length > 280 ? [reply substringToIndex:280] : reply);
    }
}

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    if (!NFBDebugIsRecording() || !nfbIsTwitterAPI(request.URL.absoluteString)) {
        return %orig;
    }
    nfbReportRequest(request, @"session");
    void (^wrapped)(NSData*, NSURLResponse*, NSError*) =
        ^(NSData* data, NSURLResponse* response, NSError* error) {
          nfbReportReply(data, response, @"session");
          if (handler) {
              handler(data, response, error);
          }
        };
    return %orig(request, wrapped);
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData
                               completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    if (!NFBDebugIsRecording() || !nfbIsTwitterAPI(request.URL.absoluteString)) {
        return %orig;
    }
    nfbReportRequest(request, @"upload");
    void (^wrapped)(NSData*, NSURLResponse*, NSError*) =
        ^(NSData* data, NSURLResponse* response, NSError* error) {
          nfbReportReply(data, response, @"upload");
          if (handler) {
              handler(data, response, error);
          }
        };
    return %orig(request, bodyData, wrapped);
}

%end

// Lists the real init methods of a class from the runtime, which sees Swift and
// category methods the static parser misses. Filters to selectors of interest.
static void nfbDumpMethods(const char* className, NSString* filter) {
    Class cls = objc_getClass(className);
    if (!cls) {
        NFBDebugLog(@"[rt] %s absent", className);
        return;
    }
    unsigned int n = 0;
    Method* list = class_copyMethodList(cls, &n);
    NFBDebugLog(@"[rt] %s: %u instance methods", className, n);
    for (unsigned int i = 0; i < n; i++) {
        NSString* sel = NSStringFromSelector(method_getName(list[i]));
        if (filter.length == 0 || [sel containsString:filter]) {
            NFBDebugLog(@"[rt]   -%@", sel);
        }
    }
    if (list) {
        free(list);
    }
    // Class methods too, for +sharedInstance style accessors.
    Class meta = object_getClass((id)cls);
    n = 0;
    Method* clist = class_copyMethodList(meta, &n);
    for (unsigned int i = 0; i < n; i++) {
        NSString* sel = NSStringFromSelector(method_getName(clist[i]));
        if (filter.length == 0 || [sel containsString:filter]) {
            NFBDebugLog(@"[rt]   +%@", sel);
        }
    }
    if (clist) {
        free(clist);
    }
}

// Finds which live class answers a bearer/auth accessor, and captures the value
// so the modern login can send the exact bearer the app uses. Value length and
// head only, never the whole secret.
static void nfbFindBearer(void) {
    for (NSString* name in @[@"TFSTwitterServiceRunner", @"TFNTwitterApiClient",
                             @"TFSTwitterAPICommandContext", @"TFNTwitterAccount"]) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) {
            continue;
        }
        for (NSString* accessor in @[@"APICommandContext", @"bearerToken",
                                     @"authorizationHeaders"]) {
            SEL sel = NSSelectorFromString(accessor);
            id target = cls;
            BOOL isClassSel = [cls respondsToSelector:sel];
            if (!isClassSel) {
                continue;
            }
            id val = ((id (*)(id, SEL))objc_msgSend)(target, sel);
            if ([val isKindOfClass:[NSString class]]) {
                NFBDebugLog(@"[rt] %@ +%@ = str len=%lu head=%@", name, accessor,
                            (unsigned long)[val length],
                            [val length] > 20 ? [val substringToIndex:20] : val);
            } else if ([val isKindOfClass:[NSDictionary class]]) {
                id a = val[@"Authorization"] ?: val[@"authorization"];
                NFBDebugLog(@"[rt] %@ +%@ = dict, Authorization len=%lu head=%@", name,
                            accessor, (unsigned long)[a length],
                            [a length] > 20 ? [a substringToIndex:20] : (a ?: @"nil"));
            } else if (val) {
                // an object - probe it for the accessors in turn
                for (NSString* sub in @[@"bearerToken", @"authorizationHeaders"]) {
                    SEL s2 = NSSelectorFromString(sub);
                    if ([val respondsToSelector:s2]) {
                        id v2 = ((id (*)(id, SEL))objc_msgSend)(val, s2);
                        id a = [v2 isKindOfClass:[NSDictionary class]]
                                   ? (v2[@"Authorization"] ?: v2[@"authorization"]) : v2;
                        NFBDebugLog(@"[rt] %@.%@.%@ len=%lu head=%@", name, accessor, sub,
                                    (unsigned long)[a length],
                                    [a length] > 20 ? [a substringToIndex:20] : (a ?: @"nil"));
                    }
                }
            }
        }
    }
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      if (!NFBDebugIsRecording()) {
          return;
      }
      nfbAttestInspectProvider();
      nfbAttestInspectSubtask();
      // The pieces the modern login still needs, read from the live runtime.
      nfbDumpMethods("TFSTwitterAPIGuestActivateCommand", @"init");
      nfbDumpMethods("TFSTwitterAPIOnboardingGetTaskCommand", @"init");
      nfbDumpMethods("TFSTwitterServiceRunner", @"");
      nfbFindBearer();
    });
}
