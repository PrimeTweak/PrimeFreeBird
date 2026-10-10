#import <UIKit/UIKit.h>

@interface PFBMutedAddCell : UITableViewCell
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) UIButton* addButton;
@property (nonatomic, strong) UILabel* hintLabel;
// The box's top inset: the list sets it so the box lines up with the first
// language row.
@property (nonatomic, strong) NSLayoutConstraint* boxTop;
@end
