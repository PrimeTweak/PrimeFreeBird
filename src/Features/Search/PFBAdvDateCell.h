#import <UIKit/UIKit.h>

@class PFBAdvField;

@interface PFBAdvDateCell : UITableViewCell
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIDatePicker* picker;
@property (nonatomic, strong) UIButton* clearButton;
@property (nonatomic, strong) PFBAdvField* model;
- (void)configureWith:(PFBAdvField*)model;
@end
