#import <UIKit/UIKit.h>

@class PFBAdvField;

@interface PFBAdvMenuCell : UITableViewCell
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIButton* valueButton;
- (void)configureWith:(PFBAdvField*)model
                 menu:(UIMenu*)menu
         currentTitle:(NSString*)currentTitle;
@end
