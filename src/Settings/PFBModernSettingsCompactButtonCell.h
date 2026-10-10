#import <UIKit/UIKit.h>

@interface PFBModernSettingsCompactButtonCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UIImageView* chevronImageView;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle;
@end

// The subtitle color of the settings cells: the tab bar item color of Twitter's
// current palette.
UIColor* PFBSettingsSubtitleColor(void);
