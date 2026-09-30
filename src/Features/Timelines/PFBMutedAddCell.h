#import <UIKit/UIKit.h>

@interface PFBMutedAddCell : UITableViewCell
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) UIButton* addButton;
@property (nonatomic, strong) UILabel* hintLabel;
// The popover closes this gap so the box sits under the segment exactly as
// the first language row does.
@property (nonatomic, strong) NSLayoutConstraint* boxTop;
@end
