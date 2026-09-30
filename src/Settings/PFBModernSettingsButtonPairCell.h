#import <UIKit/UIKit.h>

// Two actions that belong together, side by side rather than stacked as two
// look-alike rows.
@interface PFBModernSettingsButtonPairCell : UITableViewCell
- (void)configureWithFirst:(NSString*)first second:(NSString*)second;
- (void)addFirstTarget:(id)target action:(SEL)action;
- (void)addSecondTarget:(id)target action:(SEL)action;
@end
