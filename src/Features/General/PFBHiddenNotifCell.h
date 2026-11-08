#import <UIKit/UIKit.h>

@interface PFBHiddenNotifCell : UITableViewCell
@property (nonatomic, strong) UILabel* snippet;
@property (nonatomic, strong) UILabel* expiry;
@property (nonatomic, strong) NSLayoutConstraint* snippetTop;
@property (nonatomic, strong) NSLayoutConstraint* expiryBottom;
@property (nonatomic, strong) NSLayoutConstraint* snippetBottom;
- (void)applyEmptyLayout:(BOOL)empty;
@end
