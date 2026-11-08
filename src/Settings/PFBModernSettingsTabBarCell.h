#import <UIKit/UIKit.h>

// A replica of the Explore bar, laid out the way the app lays it out. Tapping a tab
// strikes it through rather than removing it, and the tabs flow onto a second line
// when they no longer fit.
@interface PFBModernSettingsTabBarCell : UITableViewCell
// Each entry: @{@"key": <pref key>, @"name": <tab name>}.
- (void)configureWithTabs:(NSArray<NSDictionary*>*)tabs
                  caption:(NSString*)caption
                     hint:(NSString*)hint;
- (void)setCountText:(NSString*)text;
- (void)addTabTarget:(id)target action:(SEL)action;
// Repaints the tabs from the stored state: struck through when hidden, plain
// when shown. Called after a tap so the bar answers without the row reloading.
- (void)refreshTabs;
// A tab that cannot be struck: the button nudges and the hint below says why,
// then the hint returns on its own.
- (void)refuseTab:(UIButton*)tab withMessage:(NSString*)message;
@end
