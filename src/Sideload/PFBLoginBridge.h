#import <UIKit/UIKit.h>

// Bridges a captured web session (auth_token + ct0) into a native account: a
// shell account is mounted over the shared session, and the app's API traffic
// authenticates by cookie. failure runs at once with the reason when no account is mounted.
@interface PFBLoginBridge : NSObject
+ (void)startWithAuthToken:(NSString*)authToken
                      csrf:(NSString*)csrf
                    userID:(long long)userID
                screenName:(NSString*)screenName
                 presenter:(UIViewController*)presenter
                   failure:(void (^)(NSString* reason))failure;
@end
