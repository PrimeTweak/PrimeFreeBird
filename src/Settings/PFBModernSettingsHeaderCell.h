#import <UIKit/UIKit.h>

@interface PFBModernSettingsHeaderCell : UITableViewCell
@property (nonatomic, strong) UILabel* headerLabel;
- (void)configureWithTitle:(NSString*)title;
@end
