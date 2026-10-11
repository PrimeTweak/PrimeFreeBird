// Network journal, while recording: failed API responses, account requests and media
// uploads, read through a forwarding proxy on each new session's delegate and on each
// account request's completion handler. Prefix [resp].

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Debug/PFBDebugger.h"

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
        // The session retains its delegate, which keeps the proxy (and the real
        // delegate it holds) alive for the session's lifetime.
        return %orig(configuration, proxy, queue);
    }
    return %orig;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler {
    NSString* path = request.URL.path ?: @"";
    if (!PFBDebugIsRecording() || !completionHandler || !pfbRespIsAccountPath(path) ||
        !pfbRespIsTwitterAPI(request.URL.absoluteString)) {
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
