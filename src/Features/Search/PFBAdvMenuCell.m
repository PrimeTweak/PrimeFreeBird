#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Features/Search/PFBAdvMenuCell.h"
#import "Features/Search/PFBAdvField.h"

@implementation PFBAdvMenuCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _valueButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _valueButton.titleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        [_valueButton setTitleColor:[UIColor labelColor]
                           forState:UIControlStateNormal];
        _valueButton.contentHorizontalAlignment =
            UIControlContentHorizontalAlignmentLeft;
        [_valueButton setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"]
                      forState:UIControlStateNormal];
        _valueButton.tintColor = [UIColor secondaryLabelColor];
        _valueButton.semanticContentAttribute =
            UISemanticContentAttributeForceRightToLeft;
        _valueButton.showsMenuAsPrimaryAction = YES;
        UILabel* example = nil;
        _floatLabel = PFBAdvInstallBox(self, _valueButton, &example);
        _exampleLabel = example;
    }
    return self;
}

- (void)configureWith:(PFBAdvField*)model
                 menu:(UIMenu*)menu
         currentTitle:(NSString*)currentTitle {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.floatLabel.text = [bundle localizedStringForKey:model.labelKey];
    [self.valueButton setTitle:currentTitle forState:UIControlStateNormal];
    self.valueButton.menu = menu;
    self.exampleLabel.text =
        model.exampleKey ? [bundle localizedStringForKey:model.exampleKey] : @"";
}

@end
