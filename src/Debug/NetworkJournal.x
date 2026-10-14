// Network journal, while recording: failed API responses, account requests and media
// uploads, read through a forwarding proxy on each new session's delegate and on each
// account request's completion handler. Prefix [resp].

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

// Probe: counts of wrapped sessions and of identity questions the proxy answered
// differently from the real delegate (F-01). Written once at the end of the tour.
static atomic_uint_fast64_t gPFBF01Sessions = 0;
static atomic_uint_fast64_t gPFBF01Differ = 0;
static atomic_uint gPFBF01Lines = 0;

// Probe: counts one divergence; YES while it may still be looked at for a line: the first
// 256 of a launch, until 8 lines are noted (F-01).
static BOOL pfbProbeF01Count(void) {
    return atomic_fetch_add(&gPFBF01Differ, 1) < 256 && atomic_load(&gPFBF01Lines) < 8;
}

// Probe: notes once per identity selector + argument when the proxy's own answer
// differs from the real delegate's; the proxy keeps returning its own (unchanged).
static void pfbProbeF01Divergence(NSString* sel, NSString* arg, BOOL mine, BOOL real,
                                  id realDelegate) {
    NSString* key = [NSString stringWithFormat:@"10F#F-01 %@ %@", sel, arg.length ? arg : @"?"];
    if (!PFBProbeWants(key)) {
        return;
    }
    atomic_fetch_add(&gPFBF01Lines, 1);
    PFBProbeNote(key, @"10F#F-01 delegate proxy asked %@ %@: proxy says %d, real %@ says %d", sel,
                 arg.length ? arg : @"?", mine ? 1 : 0, PFBProbeClassName(realDelegate), real ? 1 : 0);
}

// Probe: at the end of the tour, how many sessions were wrapped and how many
// identity answers diverged.
static void pfbProbeF01ArmTourEnd(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:PFBProbeTourEndedNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification* note) {
            // After a full tour only: a cancelled or remaining-only tour leaves the summary open.
            if (![PFBCompatTourLastRun() hasPrefix:@"Full tour"] || !PFBProbeWants(@"10F#F-01 summary")) {
                return;
            }
            PFBProbeNote(@"10F#F-01 summary", @"10F#F-01 delegate proxy: %llu sessions wrapped, %llu differing answers",
                         (unsigned long long)atomic_load(&gPFBF01Sessions),
                         (unsigned long long)atomic_load(&gPFBF01Differ));
        }];
    });
}

// Probe: the tweet-creating operations, to see which ones reach the server without a
// transaction id and how it answers (F034).
static NSString* pfbProbeF034ErrorTag(NSData* body) {
    if (!body.length) {
        return @"none";
    }
    NSString* code = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    NSArray* errors = [parsed isKindOfClass:[NSDictionary class]] ? parsed[@"errors"] : nil;
    NSDictionary* first = [errors isKindOfClass:[NSArray class]] && errors.count &&
                                  [errors.firstObject isKindOfClass:[NSDictionary class]]
                              ? errors.firstObject
                              : nil;
    id codeValue = first[@"code"];
    if ([codeValue respondsToSelector:@selector(stringValue)]) {
        code = [codeValue stringValue];
    }
    // Only the numeric code and a category go in the line; the server message text does not.
    // A body without "errors" is no refusal, whatever words its data holds.
    NSString* text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding].lowercaseString ?: @"";
    if (!code.length && ![text containsString:@"\"errors\""]) {
        return @"none";
    }
    NSString* category = [text containsString:@"automat"] ? @"automation"
                         : ([text containsString:@"subscri"] || [text containsString:@"premium"] ||
                            [text containsString:@"verified"])
                             ? @"subscription"
                             : (code.length ? @"other" : @"none");
    return code.length ? [NSString stringWithFormat:@"%@ %@", code, category] : category;
}

static BOOL pfbRespIsTwitterAPI(NSString* url) {
    if (![url isKindOfClass:[NSString class]]) {
        return NO;
    }
    if ([url containsString:@"jfapi"]) {
        return NO;
    }
    return [url containsString:@"api.twitter.com"] || [url containsString:@"api.x.com"] ||
           [url containsString:@"twitter.com/i/api"] || [url containsString:@"x.com/i/api"];
}

// The hosts that take media uploads.
static BOOL pfbRespIsMediaHost(NSString* host) {
    for (NSString* name in @[ @"upload", @"ton", @"caps" ]) {
        for (NSString* root in @[ @"twitter.com", @"x.com" ]) {
            if ([host isEqualToString:[NSString stringWithFormat:@"%@.%@", name, root]]) {
                return YES;
            }
        }
    }
    return NO;
}

// Account requests, the ones a web session can carry to avoid App Attest.
static BOOL pfbRespIsAccountPath(NSString* path) {
    return [path containsString:@"/1.1/account"] || [path containsString:@"/1.1/users/"];
}

static void pfbRespLogAccount(NSString* method, NSString* path, NSURLResponse* response,
                              NSError* error, NSString* body) {
    long code = [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? ((NSHTTPURLResponse*)response).statusCode : -1;
    NSString* shown = (code == 200 || !body.length) ? @"" : [@" body=" stringByAppendingString:body];
    PFBDebugLog(@"[resp] account %@ %@ http=%ld err=%ld%@", method ?: @"GET", path ?: @"?", code,
                (long)error.code, shown);
}

// Per-task accumulated body, so a delegate-based reply can be read on completion.
static char kPFBRespBodyKey;

// Forwards every delegate callback to the real delegate, intercepting only the
// two response callbacks to log them. Transparent for everything else.
@interface PFBURLDelegateProxy : NSObject
@property (nonatomic, strong) id pfbReal;
@end

@implementation PFBURLDelegateProxy

- (BOOL)respondsToSelector:(SEL)sel {
    if (sel == @selector(URLSession:dataTask:didReceiveData:) ||
        sel == @selector(URLSession:task:didCompleteWithError:)) {
        return YES;
    }
    return [self.pfbReal respondsToSelector:sel];
}

- (id)forwardingTargetForSelector:(SEL)sel {
    return self.pfbReal;
}

// Probe: identity questions are answered by NSObject (the proxy), not forwarded, so the
// proxy's own answer is returned unchanged and only a divergence from the real delegate is
// noted (F-01); the tweak's own wrap test and a comparison with itself are left out.
- (BOOL)isKindOfClass:(Class)aClass {
    BOOL mine = [super isKindOfClass:aClass];
    if (PFBDebugIsRecording() && self.pfbReal && aClass != [PFBURLDelegateProxy class]) {
        BOOL real = [self.pfbReal isKindOfClass:aClass];
        if (mine != real && pfbProbeF01Count()) {
            pfbProbeF01Divergence(@"isKindOfClass:", NSStringFromClass(aClass), mine, real, self.pfbReal);
        }
    }
    return mine;
}

- (BOOL)isMemberOfClass:(Class)aClass {
    BOOL mine = [super isMemberOfClass:aClass];
    if (PFBDebugIsRecording() && self.pfbReal && aClass != [PFBURLDelegateProxy class]) {
        BOOL real = [self.pfbReal isMemberOfClass:aClass];
        if (mine != real && pfbProbeF01Count()) {
            pfbProbeF01Divergence(@"isMemberOfClass:", NSStringFromClass(aClass), mine, real, self.pfbReal);
        }
    }
    return mine;
}

- (BOOL)conformsToProtocol:(Protocol*)aProtocol {
    BOOL mine = [super conformsToProtocol:aProtocol];
    if (PFBDebugIsRecording() && self.pfbReal) {
        BOOL real = [self.pfbReal conformsToProtocol:aProtocol];
        if (mine != real && pfbProbeF01Count()) {
            pfbProbeF01Divergence(@"conformsToProtocol:",
                                  aProtocol ? NSStringFromProtocol(aProtocol) : @"?", mine, real, self.pfbReal);
        }
    }
    return mine;
}

- (BOOL)isEqual:(id)object {
    BOOL mine = [super isEqual:object];
    if (PFBDebugIsRecording() && self.pfbReal && object != self) {
        BOOL real = [self.pfbReal isEqual:object];
        if (mine != real && pfbProbeF01Count()) {
            pfbProbeF01Divergence(@"isEqual:", PFBProbeClassName(object), mine, real, self.pfbReal);
        }
    }
    return mine;
}

- (void)URLSession:(NSURLSession*)session
          dataTask:(NSURLSessionDataTask*)dataTask
    didReceiveData:(NSData*)data {
    if (PFBDebugIsRecording() && data.length &&
        pfbRespIsTwitterAPI(dataTask.originalRequest.URL.absoluteString)) {
        NSMutableData* acc = objc_getAssociatedObject(dataTask, &kPFBRespBodyKey);
        if (!acc) {
            acc = [NSMutableData data];
            objc_setAssociatedObject(dataTask, &kPFBRespBodyKey, acc,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (acc.length < 400) {
            [acc appendData:data];
        }
    }
    if ([self.pfbReal respondsToSelector:_cmd]) {
        [self.pfbReal URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession*)session
                task:(NSURLSessionTask*)task
    didCompleteWithError:(NSError*)error {
    // Media uploads: every failure, and the first success of each host.
    NSString* host = task.originalRequest.URL.host.lowercaseString;
    if (PFBDebugIsRecording() && pfbRespIsMediaHost(host)) {
        long code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
                        ? ((NSHTTPURLResponse*)task.response).statusCode : -1;
        static NSMutableSet<NSString*>* succeeded;
        BOOL failed = code < 200 || code >= 300 || error;
        BOOL first = NO;
        @synchronized([PFBURLDelegateProxy class]) {
            succeeded = succeeded ?: [NSMutableSet set];
            first = !failed && ![succeeded containsObject:host];
            if (first) {
                [succeeded addObject:host];
            }
        }
        if (failed || first) {
            PFBDebugLog(@"[resp] media %@%@ http=%ld err=%ld", host, task.originalRequest.URL.path ?: @"",
                        code, (long)error.code);
        }
    }
    if (PFBDebugIsRecording() &&
        pfbRespIsTwitterAPI(task.originalRequest.URL.absoluteString)) {
        long code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
                        ? ((NSHTTPURLResponse*)task.response).statusCode : -1;
        NSData* acc = objc_getAssociatedObject(task, &kPFBRespBodyKey);
        NSString* body = acc.length
            ? [[NSString alloc] initWithData:acc encoding:NSUTF8StringEncoding] : @"";
        if (body.length > 200) {
            body = [body substringToIndex:200];
        }
        // Failures are journaled, and account requests whatever their outcome. A healthy session
        // answers 200, or 304 for an unchanged resource, dozens of times per minute.
        NSString* path = task.originalRequest.URL.path ?: @"";
        if (pfbRespIsAccountPath(path)) {
            pfbRespLogAccount(task.originalRequest.HTTPMethod, path, task.response, error, body);
        } else if ((code != 200 && code != 304) || error || [body containsString:@"\"errors\""]) {
            PFBDebugLog(@"[resp] %@ http=%ld err=%ld body=%@", path.length ? path : @"?", code,
                        (long)error.code, body);
        }
        BOOL isWrite = [path containsString:@"Create"] || [path containsString:@"Favorite"] ||
                       [path containsString:@"Retweet"] || [path containsString:@"Delete"] ||
                       [path containsString:@"note_tweet"] || [path containsString:@"Unfavorite"];
        if (isWrite) {
            NSMutableString* hdr = [NSMutableString string];
            NSDictionary* fields = task.originalRequest.allHTTPHeaderFields;
            for (NSString* k in fields) {
                [hdr appendFormat:@"%@=%lu ", k, (unsigned long)[fields[k] length]];
            }
            PFBDebugLog(@"[resp] write headers %@: %@", path, hdr);
        }
        // Probe: only the exact CreateTweet is rerouted with a transaction id; the other
        // tweet-creating operations are watched here to see whether the server refuses
        // them without one (F034).
        if (isWrite) {
            NSString* op = path.lastPathComponent;
            static NSSet<NSString*>* createOps;
            static dispatch_once_t createOnce;
            dispatch_once(&createOnce, ^{
                createOps = [NSSet setWithObjects:@"CreateTweet", @"CreateNoteTweet",
                                                  @"CreateScheduledTweet", @"CreateDraftTweet",
                                                  @"CreateTweetWithUndo", nil];
            });
            if ([createOps containsObject:op]) {
                NSString* key = [NSString stringWithFormat:@"04#F034 %@", op];
                if (PFBProbeWants(key)) {
                    BOOL hasXtid = [task.originalRequest valueForHTTPHeaderField:@"x-client-transaction-id"] != nil;
                    PFBProbeNote(key, @"04#F034 %@: transaction id %@, http %ld, error %@", op,
                                 hasXtid ? @"present" : @"absent", code, pfbProbeF034ErrorTag(acc));
                }
            }
        }
        // Spaces asks for a Periscope token before it loads; logging the auth this
        // request carries (lengths only) shows whether the web session reached it.
        BOOL isAuth = [path containsString:@"periscope"] || [path containsString:@"/oauth/"];
        if (isAuth && code != 200) {
            NSMutableString* hdr = [NSMutableString string];
            NSDictionary* fields = task.originalRequest.allHTTPHeaderFields;
            for (NSString* k in fields) {
                [hdr appendFormat:@"%@=%lu ", k, (unsigned long)[fields[k] length]];
            }
            PFBDebugLog(@"[resp] auth headers %@ (http=%ld): %@", path, code, hdr);
        }
    }
    if ([self.pfbReal respondsToSelector:_cmd]) {
        [self.pfbReal URLSession:session task:task didCompleteWithError:error];
    }
}

@end

%hook NSURLSession

+ (NSURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration*)configuration
                                 delegate:(id)delegate
                            delegateQueue:(NSOperationQueue*)queue {
    if (PFBDebugIsRecording() && delegate && ![delegate isKindOfClass:[PFBURLDelegateProxy class]]) {
        PFBURLDelegateProxy* proxy = [PFBURLDelegateProxy new];
        proxy.pfbReal = delegate;
        // Probe: count wrapped sessions and arm the end-of-tour summary (F-01).
        atomic_fetch_add(&gPFBF01Sessions, 1);
        pfbProbeF01ArmTourEnd();
        // The session retains its delegate, which keeps the proxy (and the real
        // delegate it holds) alive for the session's lifetime.
        return %orig(configuration, proxy, queue);
    }
    return %orig;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler {
    if (!PFBDebugIsRecording() || !completionHandler) {
        return %orig;
    }
    NSString* path = request.URL.path ?: @"";
    if (!pfbRespIsAccountPath(path) || !pfbRespIsTwitterAPI(request.URL.absoluteString)) {
        return %orig;
    }
    NSString* method = request.HTTPMethod;
    void (^handler)(NSData*, NSURLResponse*, NSError*) = completionHandler;
    return %orig(request, ^(NSData* data, NSURLResponse* response, NSError* error) {
      NSData* head = [data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)200))];
      NSString* body = head.length ? [[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding] : nil;
      pfbRespLogAccount(method, path, response, error, body);
      handler(data, response, error);
    });
}

%end
