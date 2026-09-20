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

// The native login posts to onboarding/task through NSURLSession. This reads
// that request's body and reply, and whether an attestation_token rides along -
// the one path never measured. Web login (jfapi) is ignored here.
%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
    NSString* url = request.URL.absoluteString;
    if (!NFBDebugIsRecording() || ![url containsString:@"onboarding/task"] ||
        [url containsString:@"jfapi"]) {
        return %orig;
    }
    NSData* body = request.HTTPBody;
    NSString* bodyText = body.length
        ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding]
        : @"(no body)";
    BOOL hasAttest = [bodyText containsString:@"attestation"];
    NFBDebugLog(@"[native] onboarding/task POST attestation_in_body=%d len=%lu",
                hasAttest, (unsigned long)body.length);
    NFBDebugLog(@"[native] body head: %@",
                bodyText.length > 220 ? [bodyText substringToIndex:220] : bodyText);
    void (^wrapped)(NSData*, NSURLResponse*, NSError*) =
        ^(NSData* data, NSURLResponse* response, NSError* error) {
          long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                          ? ((NSHTTPURLResponse*)response).statusCode : -1;
          NSString* reply = data.length
              ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
          BOOL denied = [reply containsString:@"Attestation"] ||
                        [reply containsString:@"attestation"];
          BOOL subtaskInReply = [reply containsString:@"AttestationSubtask"] ||
                                [reply containsString:@"LoginAttestation"];
          NFBDebugLog(@"[native] reply http=%ld len=%lu attestation_mentioned=%d subtask=%d",
                      code, (unsigned long)data.length, denied, subtaskInReply);
          if (reply.length && code != 200) {
              NFBDebugLog(@"[native] reply head: %@",
                          reply.length > 240 ? [reply substringToIndex:240] : reply);
          }
          if (handler) {
              handler(data, response, error);
          }
        };
    return %orig(request, wrapped);
}

%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      if (NFBDebugIsRecording()) {
          nfbAttestInspectProvider();
          nfbAttestInspectSubtask();
      }
    });
}
