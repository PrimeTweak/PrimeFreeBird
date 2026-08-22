//
//  ModernSettingsCells.h
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>
#import "Core/TwitterChirpFont.h"

@interface ModernSettingsTableViewCell : UITableViewCell
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
// A tab that cannot be struck: the button nudges and the hint below says why,
// then the hint returns on its own.
- (void)refuseTab:(UIButton*)tab withMessage:(NSString*)message;
@end

// The state of the web session, with the two actions that change it. It replaces
// a sign-in row and a clear row that could say nothing about whether there was
// anything to sign out of.
@interface ModernSettingsSessionCardCell : UITableViewCell
- (void)configureWithHandle:(NSString*)handle
                   signedIn:(BOOL)signedIn
                     detail:(NSString*)detail
               primaryTitle:(NSString*)primaryTitle
           destructiveTitle:(NSString*)destructiveTitle;
- (void)addPrimaryTarget:(id)target action:(SEL)action;
- (void)addDestructiveTarget:(id)target action:(SEL)action;
@end

// Two actions that belong together, side by side rather than stacked as two
// look-alike rows.
@interface ModernSettingsButtonPairCell : UITableViewCell
- (void)configureWithFirst:(NSString*)first second:(NSString*)second;
- (void)addFirstTarget:(id)target action:(SEL)action;
- (void)addSecondTarget:(id)target action:(SEL)action;
@end

@interface ModernSettingsHeaderCell : UITableViewCell
@property (nonatomic, strong) UILabel* headerLabel;
- (void)configureWithTitle:(NSString*)title;
@end
