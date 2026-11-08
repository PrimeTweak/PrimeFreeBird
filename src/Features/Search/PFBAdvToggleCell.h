#import <UIKit/UIKit.h>

@class PFBAdvField;

@interface PFBAdvToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel2;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UISwitch* toggle;
@property (nonatomic, strong) PFBAdvField* model;
- (void)configureWith:(PFBAdvField*)model on:(BOOL)on;
@end
