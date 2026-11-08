#import <UIKit/UIKit.h>

@interface PFBMutedTermCell : UITableViewCell
@property (nonatomic, strong) UILabel* kindLabel;
@property (nonatomic, strong) UILabel* termLabel;
@property (nonatomic, strong) UIButton* durationButton;
@property (nonatomic, strong) UIButton* removeButton;
// The two shapes this row takes. A hidden view keeps its slot in Auto Layout,
// so the constraints move with the accessories, not just their visibility, or
// the text would stop at the hidden buttons.
- (void)applyTermRow;
// A hidden conversation: no accessories, the badge only when its author is
// known, and the text running the full width at the list's own margin — the
// geometry of a language row, so both lists read as one.
- (void)applyThreadRowWithMargin:(CGFloat)margin showBadge:(BOOL)showBadge;
@end
