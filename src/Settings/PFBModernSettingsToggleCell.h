#import <UIKit/UIKit.h>

@interface PFBModernSettingsToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UISwitch* toggleSwitch;
@property (nonatomic, strong) NSLayoutConstraint* titleLeading;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
@property (nonatomic, strong) UIImageView* iconImageView;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle iconName:(NSString*)iconName;
// A row another option has taken over: the switch stops responding and the
// text recedes, so the reason reads as state rather than failure.
- (void)setRowEnabled:(BOOL)enabled;
// A second control on the same row, carrying a value in words rather than a
// state to guess. Hidden unless a row asks for one, so every other row keeps
// its standard layout.
@property (nonatomic, strong) UIButton* pillButton;
@property (nonatomic, strong) NSLayoutConstraint* titleTrailingToSwitch;
@property (nonatomic, strong) NSLayoutConstraint* titleTrailingToPill;
- (void)setPillTitle:(NSString*)title;
- (void)setPillVisible:(BOOL)visible animated:(BOOL)animated;
- (void)addPillTarget:(id)target action:(SEL)action;
@end
