// The padlock screen: the biometric or passcode gate shown at launch.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthViewController : UIViewController

// Called on the main queue with the authentication result; on success the
// controller has already dismissed itself when this fires.
@property (nonatomic, copy, nullable) void (^completion)(BOOL authenticated);

@end

NS_ASSUME_NONNULL_END
