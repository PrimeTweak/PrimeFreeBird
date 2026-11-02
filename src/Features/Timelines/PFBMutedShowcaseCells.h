// The new look's head of each Filters list: its line, then a card. Words holds the day's count and
// the field that adds a term, Languages the languages to keep, Conversations how many are hidden.

#import <UIKit/UIKit.h>
#import "Settings/Native/PFBShowcase.h"

NS_ASSUME_NONNULL_BEGIN

// The line and the card; each list lays its own content out on the card.
@interface PFBMutedHeroCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel* intro;
@property (nonatomic, strong, readonly) UIView* card;
@end

@interface PFBMutedWordsHeroCell : PFBMutedHeroCell
@property (nonatomic, strong, readonly) UITextField* field;
@property (nonatomic, strong, readonly) PFBShowcaseButton* addButton;
// The duration the next term gets; its menu is set by the list.
@property (nonatomic, strong, readonly) PFBShowcaseButton* durationButton;
- (void)setCount:(NSInteger)count caption:(NSString*)caption;
// What the typed text will be, shown with the duration under the field; nil hides the line.
- (void)setKindSymbol:(nullable NSString*)symbol name:(nullable NSString*)name;
@end

@interface PFBMutedLanguagesHeroCell : PFBMutedHeroCell
// One chip per language, filled while it is kept; a tap sends the action with the chip's index as tag.
- (void)setLanguages:(NSArray<NSString*>*)names kept:(NSIndexSet*)kept target:(id)target action:(SEL)action;
@end

@interface PFBMutedThreadsHeroCell : PFBMutedHeroCell
// How many conversations are hidden, or, with none, how to hide one.
- (void)setTitle:(NSString*)title hint:(nullable NSString*)hint;
@end

NS_ASSUME_NONNULL_END
