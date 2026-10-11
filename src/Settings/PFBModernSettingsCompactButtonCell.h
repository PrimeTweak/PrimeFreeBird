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
@end

// The subtitle color of the settings cells: the tab bar item color of Twitter's
// current palette.
UIColor* PFBSettingsSubtitleColor(void);
