#import <UIKit/UIKit.h>

@interface PFBModernSettingsCompactButtonCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UIImageView* chevronImageView;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle;
@end
