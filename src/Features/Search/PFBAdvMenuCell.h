#import <UIKit/UIKit.h>

@class PFBAdvField;

@interface PFBAdvMenuCell : UITableViewCell
@property (nonatomic, strong) UILabel* floatLabel;
@property (nonatomic, strong) UILabel* exampleLabel;
@property (nonatomic, strong) UIButton* valueButton;
@property (nonatomic, strong) PFBAdvField* model;
- (void)configureWith:(PFBAdvField*)model
                 menu:(UIMenu*)menu
         currentTitle:(NSString*)currentTitle
             hasValue:(BOOL)hasValue;
@end
