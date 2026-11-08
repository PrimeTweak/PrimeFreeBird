#import <UIKit/UIKit.h>

@class PFBAdvField;

// A field of the form to type in: its title, the capsule, the example under it.
@interface PFBAdvBoxCell : UITableViewCell <UITextFieldDelegate>
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) PFBAdvField* model;
- (void)configureWith:(PFBAdvField*)model;
@end
