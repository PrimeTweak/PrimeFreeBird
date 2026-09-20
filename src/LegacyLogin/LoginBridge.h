#import <UIKit/UIKit.h>

// Bridges a captured web session (auth_token + ct0) into a native account.
// Voie B exchanges the session for an OAuth pair; Voie A injects the session
// cookies into the app's API traffic when B yields nothing. Probes under [bridge].
@interface LoginBridge : NSObject
+ (void)startWithAuthToken:(NSString*)authToken
                      csrf:(NSString*)csrf
                 presenter:(UIViewController*)presenter;
@end
