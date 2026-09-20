#import <UIKit/UIKit.h>

// Modern onboarding/task login: replaces the dead xAuth endpoint. Runs the guest
// activate + login subtask chain, ending in an oauth_token pair the native
// account is built from. Probes every step under the [flow] prefix.
@interface ModernLoginFlow : NSObject
+ (void)startWithUsername:(NSString*)username
                 password:(NSString*)password
               completion:(void (^)(NSString* token, NSString* secret,
                                     NSString* screenName, NSError* error))completion;
@end
