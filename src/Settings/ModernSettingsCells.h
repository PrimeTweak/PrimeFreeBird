//
//  ModernSettingsCells.h
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>
#import "Core/TwitterChirpFont.h"

@interface ModernSettingsTableViewCell : UITableViewCell
@property (nonatomic, strong) UIImageView* iconImageView;
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UIImageView* chevronImageView;
- (void)configureWithTitle:(NSString*)title
                  subtitle:(NSString*)subtitle
                  iconName:(NSString*)iconName;
@end

@interface ModernSettingsCompactButtonCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UIImageView* chevronImageView;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle;
@end

@interface ModernSettingsToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, strong) UILabel* subtitleLabel;
@property (nonatomic, strong) UISwitch* toggleSwitch;
@property (nonatomic, strong) NSLayoutConstraint* titleLeading;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle;
- (void)setIndented:(BOOL)indented;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
@property (nonatomic, strong) UIImageView* iconImageView;
- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle iconName:(NSString*)iconName;
// A row another option has taken over: the switch stops responding and the
// text recedes, so the reason reads as state rather than failure.
- (void)setRowEnabled:(BOOL)enabled;
// A second control on the same row, carrying a value in words rather than a
// state to guess. Hidden unless a row asks for one, so every other row is
// laid out exactly as before.
@property (nonatomic, strong) UIButton* pillButton;
@property (nonatomic, strong) NSLayoutConstraint* titleTrailingToSwitch;
@property (nonatomic, strong) NSLayoutConstraint* titleTrailingToPill;
- (void)setPillTitle:(NSString*)title;
- (void)setPillVisible:(BOOL)visible animated:(BOOL)animated;
- (void)addPillTarget:(id)target action:(SEL)action;
@end

// A replica of the Explore bar, laid out the way the app lays it out. Tapping a
// tab strikes it through instead of removing it, so the bar keeps its shape and
// nothing is lost from view.
//
// The tabs flow: they sit on one line while they fit and take a second line the
// moment they do not, so a longer name, a translation or a larger text size
// cannot push one off the edge.
@interface ModernSettingsTabBarCell : UITableViewCell
// Each entry: @{@"key": <pref key>, @"name": <tab name>}.
- (void)configureWithTabs:(NSArray<NSDictionary*>*)tabs
                  caption:(NSString*)caption
                     hint:(NSString*)hint;
- (void)setCountText:(NSString*)text;
- (void)addTabTarget:(id)target action:(SEL)action;
// Repaints the tabs from the stored state: struck through when hidden, plain
// when shown. Called after a tap so the bar answers without the row reloading.
- (void)refreshTabs;
@end

@interface ModernSettingsHeaderCell : UITableViewCell
@property (nonatomic, strong) UILabel* headerLabel;
- (void)configureWithTitle:(NSString*)title;
@end
