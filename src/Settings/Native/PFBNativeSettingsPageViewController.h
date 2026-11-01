// A settings page in Twitter's new look: a row per group of the page, each opening its group
// in a sheet.

#import <UIKit/UIKit.h>

@class PFBModernSettingsPageViewController;

@interface PFBNativeSettingsPageViewController : UIViewController

// Shows the groups of the page the classic look would show; its class keeps the rows' behavior.
- (instancetype)initWithPage:(PFBModernSettingsPageViewController*)page;

// A whole settings page in the new look, any other screen as it is.
+ (UIViewController*)controllerShowing:(UIViewController*)controller;

@end
