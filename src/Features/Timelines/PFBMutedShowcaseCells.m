// The heads of the new look's Filters lists, laid out by hand.

#import "Features/Timelines/PFBMutedShowcaseCells.h"
#import "Settings/PFBSettingsCellStyle.h"

static const CGFloat kPFBHeroSide = 20.0;
// The card's own margins, and the height of the field and of the button beside it.
static const CGFloat kPFBHeroInset = 16.0;
static const CGFloat kPFBHeroControl = 50.0;
static const CGFloat kPFBHeroChip = 36.0;

// Turns a left-to-right frame into the cell's direction.
static CGRect PFBHeroMirrored(UIView* view, CGRect frame, CGFloat width) {
    if (view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) {
        frame.origin.x = width - CGRectGetMaxX(frame);
    }
    return frame;
}

#pragma mark - Line and card

@interface PFBMutedHeroCell ()
@property (nonatomic, strong, readwrite) UILabel* intro;
@property (nonatomic, strong, readwrite) UIView* card;
@end

@implementation PFBMutedHeroCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _intro = PFBShowcaseIntroLabel();
        _card = PFBShowcaseCard();
        [self.contentView addSubview:_intro];
        [self.contentView addSubview:_card];
    }
    return self;
}

// The card's content at the card's width, its frames set only when applied; returns its height.
- (CGFloat)layoutCardWidth:(CGFloat)width apply:(BOOL)apply {
    return 0;
}

- (CGFloat)layoutWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat inner = MAX(0, width - 2 * kPFBHeroSide);
    CGFloat introHeight = ceil([self.intro sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    CGFloat cardY = 12.0 + introHeight + 20.0;
    CGFloat cardHeight = [self layoutCardWidth:inner apply:apply];
    if (apply) {
        self.intro.frame = CGRectMake(kPFBHeroSide, 12.0, inner, introHeight);
        self.card.frame = CGRectMake(kPFBHeroSide, cardY, inner, cardHeight);
    }
    return cardY + cardHeight + 12.0;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, ceil([self layoutWidth:size.width apply:NO]));
}

// A table that sizes its rows asks through Auto Layout; the head measures itself instead.
- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize
        withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority
              verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    return [self sizeThatFits:CGSizeMake(targetSize.width, CGFLOAT_MAX)];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutWidth:CGRectGetWidth(self.contentView.bounds) apply:YES];
}

- (void)applyTheme {
    self.intro.textColor = PFBSettingsSubtitleColor();
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end

#pragma mark - Words

@implementation PFBMutedWordsHeroCell {
    UILabel* _count;
    UILabel* _caption;
    PFBShowcaseSurface* _fieldSurface;
    UIImageView* _kindIcon;
    UILabel* _kindName;
    BOOL _showsKind;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _count = [[UILabel alloc] init];
        _count.textAlignment = NSTextAlignmentCenter;
        _count.font = PFBTabularDigitsFont(PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:34]));
        _caption = [[UILabel alloc] init];
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.numberOfLines = 0;
        _caption.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
        _fieldSurface = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        _field = [[UITextField alloc] init];
        _field.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.returnKeyType = UIReturnKeyDone;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        [_fieldSurface.contentView addSubview:_field];
        _addButton = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
        _addButton.symbolName = @"plus";
        _kindIcon = [[UIImageView alloc] init];
        _kindIcon.contentMode = UIViewContentModeCenter;
        _kindName = [[UILabel alloc] init];
        _kindName.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:14]);
        _durationButton = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
        _durationButton.trailingSymbolName = @"chevron.up.chevron.down";
        _durationButton.labelFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:14]);
        _durationButton.showsMenuAsPrimaryAction = YES;
        for (UIView* part in @[ _count, _caption, _fieldSurface, _addButton, _kindIcon, _kindName, _durationButton ]) {
            [self.card addSubview:part];
        }
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    [super applyTheme];
    _count.textColor = PFBSettingsTextColor();
    _caption.textColor = PFBSettingsSubtitleColor();
    _field.textColor = PFBSettingsTextColor();
    if (_field.placeholder.length) {
        _field.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:_field.placeholder
                attributes:@{NSForegroundColorAttributeName: PFBSettingsSubtitleColor()}];
    }
    _kindIcon.tintColor = PFBSettingsSubtitleColor();
    _kindName.textColor = PFBSettingsSubtitleColor();
}

- (void)setCount:(NSInteger)count caption:(NSString*)caption {
    _count.text = [NSNumberFormatter localizedStringFromNumber:@(count) numberStyle:NSNumberFormatterDecimalStyle];
    _caption.text = caption;
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)setKindSymbol:(NSString*)symbol name:(NSString*)name {
    _showsKind = symbol != nil;
    UIImageSymbolConfiguration* size = [UIImageSymbolConfiguration configurationWithPointSize:13
                                                                                      weight:UIImageSymbolWeightMedium];
    _kindIcon.image = symbol ? [UIImage systemImageNamed:symbol withConfiguration:size] : nil;
    _kindName.text = name;
    [self setNeedsLayout];
}

// The count and its caption, the field with the add button beside it, then, while a term is typed,
// what it will be and the duration it gets.
- (CGFloat)layoutCardWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat inner = MAX(0, width - 2 * kPFBHeroInset);
    CGFloat y = 18.0;
    CGFloat countHeight = ceil(_count.font.lineHeight);
    CGFloat captionHeight = ceil([_caption sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    if (apply) {
        _count.frame = CGRectMake(kPFBHeroInset, y, inner, countHeight);
        _caption.frame = CGRectMake(kPFBHeroInset, y + countHeight, inner, captionHeight);
    }
    y += countHeight + captionHeight + 16.0;
    if (apply) {
        CGFloat fieldWidth = MAX(0, width - 24.0 - kPFBHeroControl - 10.0);
        _fieldSurface.frame = PFBHeroMirrored(self, CGRectMake(12.0, y, fieldWidth, kPFBHeroControl), width);
        _field.frame = PFBHeroMirrored(self, CGRectMake(18.0, 0, MAX(0, fieldWidth - 26.0), kPFBHeroControl), fieldWidth);
        _addButton.frame =
            PFBHeroMirrored(self, CGRectMake(width - 12.0 - kPFBHeroControl, y, kPFBHeroControl, kPFBHeroControl), width);
    }
    y += kPFBHeroControl;
    _kindIcon.hidden = !_showsKind;
    _kindName.hidden = !_showsKind;
    _durationButton.hidden = !_showsKind;
    if (_showsKind) {
        y += 10.0;
        CGFloat line = 32.0;
        if (apply) {
            CGFloat chip = MIN([_durationButton sizeThatFits:CGSizeMake(width, line)].width, width / 2.0);
            _durationButton.frame = PFBHeroMirrored(self, CGRectMake(width - 12.0 - chip, y, chip, line), width);
            _kindIcon.frame = PFBHeroMirrored(self, CGRectMake(18.0, y, 18.0, line), width);
            _kindName.frame =
                PFBHeroMirrored(self, CGRectMake(42.0, y, MAX(0, width - 12.0 - chip - 8.0 - 42.0), line), width);
        }
        y += line;
    }
    return y + 16.0;
}

@end

#pragma mark - Languages

@implementation PFBMutedLanguagesHeroCell {
    NSArray<PFBShowcaseButton*>* _chips;
}

- (void)setLanguages:(NSArray<NSString*>*)names kept:(NSIndexSet*)kept target:(id)target action:(SEL)action {
    if (_chips.count != names.count) {
        for (UIView* chip in _chips) {
            [chip removeFromSuperview];
        }
        NSMutableArray<PFBShowcaseButton*>* chips = [NSMutableArray array];
        for (NSUInteger i = 0; i < names.count; i++) {
            PFBShowcaseButton* chip = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleGlass];
            chip.tag = (NSInteger)i;
            chip.labelFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
            [chip addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
            [self.card addSubview:chip];
            [chips addObject:chip];
        }
        _chips = chips;
    }
    for (NSUInteger i = 0; i < _chips.count; i++) {
        BOOL on = [kept containsIndex:i];
        PFBShowcaseButton* chip = _chips[i];
        chip.label = names[i];
        chip.style = on ? PFBShowcaseButtonStyleFilled : PFBShowcaseButtonStyleGlass;
        chip.symbolName = on ? @"checkmark" : nil;
        chip.accessibilityTraits = UIAccessibilityTraitButton | (on ? UIAccessibilityTraitSelected : 0);
    }
    [self setNeedsLayout];
}

// The chips in centered lines, as many to a line as fit.
- (CGFloat)layoutCardWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat room = MAX(0, width - 2 * kPFBHeroInset);
    CGFloat gap = 8.0;
    NSMutableArray<NSMutableArray<NSNumber*>*>* lines = [NSMutableArray array];
    NSMutableArray<NSNumber*>* widths = [NSMutableArray array];
    CGFloat used = 0;
    for (PFBShowcaseButton* chip in _chips) {
        CGFloat chipWidth = MIN([chip sizeThatFits:CGSizeMake(room, kPFBHeroChip)].width, room);
        [widths addObject:@(chipWidth)];
        if (!lines.count || used + gap + chipWidth > room) {
            [lines addObject:[NSMutableArray array]];
            used = chipWidth;
        } else {
            used += gap + chipWidth;
        }
        [lines.lastObject addObject:@(widths.count - 1)];
    }
    CGFloat y = 18.0;
    for (NSArray<NSNumber*>* line in lines) {
        CGFloat total = gap * (CGFloat)(line.count - 1);
        for (NSNumber* index in line) {
            total += widths[index.unsignedIntegerValue].doubleValue;
        }
        CGFloat x = kPFBHeroInset + (room - total) / 2.0;
        for (NSNumber* index in line) {
            CGFloat chipWidth = widths[index.unsignedIntegerValue].doubleValue;
            if (apply) {
                _chips[index.unsignedIntegerValue].frame =
                    PFBHeroMirrored(self, CGRectMake(x, y, chipWidth, kPFBHeroChip), width);
            }
            x += chipWidth + gap;
        }
        y += kPFBHeroChip + gap;
    }
    return (lines.count ? y - gap : y) + 18.0;
}

@end

#pragma mark - Conversations

@implementation PFBMutedThreadsHeroCell {
    PFBShowcaseSurface* _disc;
    UIImageView* _eye;
    UILabel* _title;
    UILabel* _hint;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _disc = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        _eye = [[UIImageView alloc] init];
        _eye.contentMode = UIViewContentModeCenter;
        UIImageSymbolConfiguration* size = [UIImageSymbolConfiguration configurationWithPointSize:21
                                                                                          weight:UIImageSymbolWeightMedium];
        _eye.image = [UIImage systemImageNamed:@"eye.slash" withConfiguration:size];
        [_disc.contentView addSubview:_eye];
        _title = [[UILabel alloc] init];
        _title.numberOfLines = 0;
        _title.textAlignment = NSTextAlignmentCenter;
        _title.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:17]);
        _hint = [[UILabel alloc] init];
        _hint.numberOfLines = 0;
        _hint.textAlignment = NSTextAlignmentCenter;
        _hint.font = PFBSettingsDetailFont();
        for (UIView* part in @[ _disc, _title, _hint ]) {
            [self.card addSubview:part];
        }
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    [super applyTheme];
    _eye.tintColor = PFBSettingsTextColor();
    _title.textColor = PFBSettingsTextColor();
    _hint.textColor = PFBSettingsSubtitleColor();
}

- (void)setTitle:(NSString*)title hint:(NSString*)hint {
    _title.text = title;
    _hint.text = hint;
    [self applyTheme];
    [self setNeedsLayout];
}

// The glass disc, then what is hidden, and how to hide one when nothing is.
- (CGFloat)layoutCardWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat inner = MAX(0, width - 2 * kPFBHeroInset);
    CGFloat y = 20.0;
    if (apply) {
        _disc.frame = CGRectMake(width / 2.0 - 26.0, y, 52.0, 52.0);
        _eye.frame = _disc.bounds;
    }
    y += 52.0 + 12.0;
    CGFloat titleHeight = ceil([_title sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
    if (apply) {
        _title.frame = CGRectMake(kPFBHeroInset, y, inner, titleHeight);
    }
    y += titleHeight;
    _hint.hidden = _hint.text.length == 0;
    if (!_hint.hidden) {
        CGFloat hintHeight = ceil([_hint sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height);
        if (apply) {
            _hint.frame = CGRectMake(kPFBHeroInset, y + 4.0, inner, hintHeight);
        }
        y += 4.0 + hintHeight;
    }
    return y + 18.0;
}

@end
