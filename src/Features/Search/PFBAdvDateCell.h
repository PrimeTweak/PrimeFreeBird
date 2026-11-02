#import <UIKit/UIKit.h>

@class PFBAdvField;

// A date of the form: its title, the capsule with iOS's date control and a clear button, then
// the example.
@interface PFBAdvDateCell : UITableViewCell
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIDatePicker* picker;
@property (nonatomic, strong) UIButton* clearButton;
@property (nonatomic, strong) PFBAdvField* model;
- (void)configureWith:(PFBAdvField*)model;
@end
