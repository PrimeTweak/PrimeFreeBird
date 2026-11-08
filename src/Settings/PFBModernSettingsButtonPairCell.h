#import <UIKit/UIKit.h>

// Two actions that belong together, side by side rather than stacked as two
// look-alike rows.
@interface PFBModernSettingsButtonPairCell : UITableViewCell
- (void)configureWithFirst:(NSString*)first second:(NSString*)second;
- (void)addFirstTarget:(id)target action:(SEL)action;
- (void)addSecondTarget:(id)target action:(SEL)action;
// A second action that deletes something reads in red; disabled, it reads in gray.
- (void)setSecondDestructive:(BOOL)destructive;
- (void)setSecondEnabled:(BOOL)enabled;
@end
