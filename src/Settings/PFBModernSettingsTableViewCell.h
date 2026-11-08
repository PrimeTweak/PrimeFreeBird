#import <UIKit/UIKit.h>

@interface PFBModernSettingsTableViewCell : UITableViewCell
// A row that states something rather than leading somewhere: the chevron would
// promise a screen that does not exist.
- (void)setShowsChevron:(BOOL)showsChevron;
@property (nonatomic, strong) UIImageView* iconImageView;
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UIImageView* chevronImageView;
- (void)configureWithTitle:(NSString*)title
                  subtitle:(NSString*)subtitle
                  iconName:(NSString*)iconName;
@end
