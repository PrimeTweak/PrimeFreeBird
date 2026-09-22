#import <UIKit/UIKit.h>

// Bridges a captured web session (auth_token + ct0) into a native account: a
// shell account is mounted over the shared session, and the app's API traffic
// authenticates by cookie. Receipts under [bridge].
@interface LoginBridge : NSObject
+ (void)startWithAuthToken:(NSString*)authToken
                      csrf:(NSString*)csrf
                    userID:(long long)userID
                screenName:(NSString*)screenName
                 presenter:(UIViewController*)presenter;
@end
