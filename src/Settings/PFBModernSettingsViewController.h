// The settings root: the list of pages.

#import <UIKit/UIKit.h>
#import "Support/TWHeaders.h"

NS_ASSUME_NONNULL_BEGIN

@interface PFBModernSettingsViewController : UIViewController

// native gives the pages the look of Twitter's new settings; the classic look otherwise.
- (instancetype)initWithAccount:(TFNTwitterAccount*)account native:(BOOL)native;

@end

NS_ASSUME_NONNULL_END
