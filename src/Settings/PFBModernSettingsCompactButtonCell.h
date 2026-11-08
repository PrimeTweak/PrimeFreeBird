#import <UIKit/UIKit.h>

@interface PFBModernSettingsCompactButtonCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UIImageView* chevronImageView;
@property (nonatomic, strong) UILabel* detailLabel;
// The title with a description under it, and the value on the right.
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle detail:(NSString*)detail;
// A row that only shows its value has no chevron.
- (void)setShowsChevron:(BOOL)showsChevron;
// A row that opens a menu in place shows the up-down chevron instead of the right one.
- (void)setOpensMenu:(BOOL)opensMenu;
@end
