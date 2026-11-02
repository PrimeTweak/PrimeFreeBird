#import <UIKit/UIKit.h>

@interface PFBMutedAddCell : UITableViewCell
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) UIButton* addButton;
@property (nonatomic, strong) UILabel* hintLabel;
// The new look: the field in a filled capsule, and Add in a capsule of the text color, as Done.
- (void)applyNativeLook;
@end
