#import <UIKit/UIKit.h>

@class PFBAdvField;

@interface PFBAdvBoxCell : UITableViewCell <UITextFieldDelegate>
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* placeholderLabel;
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) PFBAdvField* model;
- (void)configureWith:(PFBAdvField*)model;
@end
