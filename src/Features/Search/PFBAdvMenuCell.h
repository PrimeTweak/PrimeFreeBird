#import <UIKit/UIKit.h>

@class PFBAdvField;

// A field of the form that opens its choices: its title, then the capsule with the current
// choice and a chevron.
@interface PFBAdvMenuCell : UITableViewCell
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIControl* valueField;
@property (nonatomic, strong) UILabel* valueLabel;
@property (nonatomic, copy) void (^open)(void);
- (void)configureWith:(PFBAdvField*)model currentTitle:(NSString*)currentTitle open:(void (^)(void))open;
@end
