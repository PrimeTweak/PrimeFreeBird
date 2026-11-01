// One group of a settings page in a sheet, as Twitter's new settings show theirs.

#import <UIKit/UIKit.h>

@class PFBModernSettingsPageViewController;

@interface PFBNativeSettingsSheetController : UIViewController

// The page shows a single group; closed runs once the sheet has gone, however it was closed.
+ (void)presentPage:(PFBModernSettingsPageViewController*)page
             titled:(NSString*)title
               from:(UIViewController*)presenter
             closed:(void (^)(void))closed;

@end
