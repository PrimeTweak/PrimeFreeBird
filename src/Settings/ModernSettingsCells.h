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
@end

@interface ModernSettingsHeaderCell : UITableViewCell
@property (nonatomic, strong) UILabel* headerLabel;
- (void)configureWithTitle:(NSString*)title;
@end
