// Measurement only: journals failed API responses of the delegate-based requests
// the completion-handler logger cannot see, by wrapping each session delegate in
// a forwarding proxy. Prefix [resp].

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Debug/NFBDebugger.h"

static BOOL nfbRespIsTwitterAPI(NSString* url) {
    if (![url isKindOfClass:[NSString class]]) {
        return NO;
    }
    if ([url containsString:@"jfapi"]) {
        return NO;
    }
    return [url containsString:@"api.twitter.com"] || [url containsString:@"api.x.com"] ||
           [url containsString:@"twitter.com/i/api"] || [url containsString:@"x.com/i/api"];
}

// Per-task accumulated body, so a delegate-based reply can be read on completion.
static char kNFBRespBodyKey;

// Forwards every delegate callback to the real delegate, intercepting only the
// two response callbacks to log them. Transparent for everything else.
@interface NFBURLDelegateProxy : NSObject
@property (nonatomic, strong) id nfbReal;
@end

@implementation NFBURLDelegateProxy

- (BOOL)respondsToSelector:(SEL)sel {
    if (sel == @selector(URLSession:dataTask:didReceiveData:) ||
        sel == @selector(URLSession:task:didCompleteWithError:)) {
        return YES;
    }
    return [self.nfbReal respondsToSelector:sel];
}

- (id)forwardingTargetForSelector:(SEL)sel {
    return self.nfbReal;
}

- (void)URLSession:(NSURLSession*)session
          dataTask:(NSURLSessionDataTask*)dataTask
    didReceiveData:(NSData*)data {
    if (NFBDebugIsRecording() && data.length &&
        nfbRespIsTwitterAPI(dataTask.originalRequest.URL.absoluteString)) {
        NSMutableData* acc = objc_getAssociatedObject(dataTask, &kNFBRespBodyKey);
        if (!acc) {
            acc = [NSMutableData data];
            objc_setAssociatedObject(dataTask, &kNFBRespBodyKey, acc,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (acc.length < 400) {
            [acc appendData:data];
        }
    }
    if ([self.nfbReal respondsToSelector:_cmd]) {
        [self.nfbReal URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession*)session
                task:(NSURLSessionTask*)task
    didCompleteWithError:(NSError*)error {
    if (NFBDebugIsRecording() &&
        nfbRespIsTwitterAPI(task.originalRequest.URL.absoluteString)) {
        long code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
                        ? ((NSHTTPURLResponse*)task.response).statusCode : -1;
        NSData* acc = objc_getAssociatedObject(task, &kNFBRespBodyKey);
        NSString* body = acc.length
            ? [[NSString alloc] initWithData:acc encoding:NSUTF8StringEncoding] : @"";
        if (body.length > 200) {
            body = [body substringToIndex:200];
        }
        // Only failures are journaled: a healthy session answers 200 dozens of
        // times per minute and would drown the rest of the log.
        if (code != 200 || error || [body containsString:@"\"errors\""]) {
            NFBDebugLog(@"[resp] %@ http=%ld err=%ld body=%@", task.originalRequest.URL.path ?: @"?",
                        code, (long)error.code, body);
        }
        NSString* path = task.originalRequest.URL.path ?: @"";
        BOOL isWrite = [path containsString:@"Create"] || [path containsString:@"Favorite"] ||
                       [path containsString:@"Retweet"] || [path containsString:@"Delete"] ||
                       [path containsString:@"note_tweet"] || [path containsString:@"Unfavorite"];
        if (isWrite) {
            NSMutableString* hdr = [NSMutableString string];
            NSDictionary* fields = task.originalRequest.allHTTPHeaderFields;
            for (NSString* k in fields) {
                [hdr appendFormat:@"%@=%lu ", k, (unsigned long)[fields[k] length]];
            }
            NFBDebugLog(@"[resp] write headers %@: %@", path, hdr);
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
            NFBDebugLog(@"[resp] auth headers %@ (http=%ld): %@", path, code, hdr);
        }
    }
    if ([self.nfbReal respondsToSelector:_cmd]) {
        [self.nfbReal URLSession:session task:task didCompleteWithError:error];
    }
}

@end

%hook NSURLSession

+ (NSURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration*)configuration
                                 delegate:(id)delegate
                            delegateQueue:(NSOperationQueue*)queue {
    if (delegate && ![delegate isKindOfClass:[NFBURLDelegateProxy class]]) {
        NFBURLDelegateProxy* proxy = [NFBURLDelegateProxy new];
        proxy.nfbReal = delegate;
        // The session retains its delegate, which keeps the proxy (and the real
        // delegate it holds) alive for the session's lifetime.
        return %orig(configuration, proxy, queue);
    }
    return %orig;
}

%end
