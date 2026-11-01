// One group of a settings page in a sheet, as Twitter's new settings show theirs.

#import <UIKit/UIKit.h>

@class PFBModernSettingsPageViewController;

@interface PFBNativeSettingsSheetController : UIViewController

// The page shows a single group; screens its rows open go onto the presenter's stack.
+ (void)presentPage:(PFBModernSettingsPageViewController*)page
             titled:(NSString*)title
               from:(UIViewController*)presenter;

@end
