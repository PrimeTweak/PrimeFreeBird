// The parts of the new look's showcase pages, laid out by hand as Twitter's settings rows are.

#import "Settings/Native/PFBShowcase.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/PFBManager.h"
#import "Support/HookHelpers.h"

// iOS draws the design it launched with, so Visual style counts as it stood at launch.
static BOOL gPFBShowcaseGlassAtLaunch;

__attribute__((constructor)) static void PFBShowcaseReadLaunchDesign(void) {
    id glass = [[NSUserDefaults standardUserDefaults] objectForKey:@"enable_liquid_glass"];
    gPFBShowcaseGlassAtLaunch = glass ? [glass boolValue] : YES;
}

BOOL PFBShowcaseUsesGlass(void) {
    if (@available(iOS 26.0, *)) {
        return gPFBShowcaseGlassAtLaunch && NSClassFromString(@"UIGlassEffect") != nil;
    }
    return NO;
}

UILabel* PFBShowcaseIntroLabel(void) {
    UILabel* label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentNatural;
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
    label.textColor = PFBSettingsSubtitleColor();
    return label;
}

void PFBShowcaseSetTitle(UIViewController* controller, NSString* title) {
    controller.title = title;
    UILabel* label = [[UILabel alloc] init];
    label.text = title;
    label.font = [TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:18];
    label.textColor = UIColor.labelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    [label sizeToFit];
    controller.navigationItem.titleView = label;
}

UIView* PFBShowcaseCard(void) {
    UIView* card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 28.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    return card;
}

// Whether a view shows: neither it nor a view above it hidden or clear.
static BOOL PFBShowcaseShows(UIView* view) {
    for (UIView* level = view; level; level = level.superview) {
        if (level.hidden || level.alpha <= 0.01) {
            return NO;
        }
    }
    return YES;
}

// The showing view of a class nearest the window, looked for level by level with no depth limit.
static UIView* PFBShowcaseShallowest(UIWindow* window, Class cls) {
    NSArray<UIView*>* level = @[ window ];
    while (level.count) {
        NSMutableArray<UIView*>* next = [NSMutableArray array];
        for (UIView* view in level) {
            if (view.hidden || view.alpha <= 0.01) {
                continue;
            }
            if ([view isKindOfClass:cls]) {
                return view;
            }
            [next addObjectsFromArray:view.subviews];
        }
        level = next;
    }
    return nil;
}

// The tab bar found last, looked for again only once it left the window or stopped showing.
static __weak UIView* gPFBShowcaseTabBar;

CGFloat PFBShowcaseBottomLimit(UIView* view) {
    CGFloat limit = CGRectGetMaxY(view.bounds) - view.safeAreaInsets.bottom;
    static Class barClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      barClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
    });
    if (!barClass || !view.window) {
        return limit;
    }
    UIView* bar = gPFBShowcaseTabBar;
    if (!bar || bar.window != view.window || !PFBShowcaseShows(bar)) {
        bar = PFBShowcaseShallowest(view.window, barClass);
        gPFBShowcaseTabBar = bar;
    }
    if (bar) {
        CGRect frame = [bar convertRect:bar.bounds toView:view];
        if (CGRectGetMinY(frame) < limit && CGRectGetMaxY(frame) > CGRectGetMinY(view.bounds)) {
            limit = CGRectGetMinY(frame);
        }
    }
    return limit;
}

// A color of Twitter's palette reached by name, or the fallback.
static UIColor* PFBShowcasePaletteColor(NSString* getter, UIColor* fallback) {
    return [PFBPalette colorFor:NSSelectorFromString(getter) fallback:fallback];
}

// Turns a left-to-right frame into the view's direction.
static CGRect PFBShowcaseMirrored(CGRect frame, CGFloat width, BOOL rtl) {
    if (rtl) {
        frame.origin.x = width - CGRectGetMaxX(frame);
    }
    return frame;
}

#pragma mark - Surface

@implementation PFBShowcaseSurface {
    CGFloat _radius;
    UIVisualEffectView* _glass;
}

- (instancetype)initWithCornerRadius:(CGFloat)radius {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _radius = radius;
        if (PFBShowcaseUsesGlass()) {
            _glass = [[UIVisualEffectView alloc] initWithEffect:[[NSClassFromString(@"UIGlassEffect") alloc] init]];
            _glass.layer.cornerCurve = kCACornerCurveContinuous;
            [self addSubview:_glass];
        } else {
            self.layer.cornerCurve = kCACornerCurveContinuous;
            self.layer.borderWidth = 0.5;
            self.layer.shadowColor = [UIColor blackColor].CGColor;
            self.layer.shadowOpacity = 0.08f;
            self.layer.shadowRadius = 8.0;
            self.layer.shadowOffset = CGSizeMake(0, 2);
            [self applyTheme];
        }
    }
    return self;
}

- (UIView*)contentView {
    return _glass ? _glass.contentView : self;
}

- (void)applyTheme {
    if (_glass) {
        return;
    }
    self.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    self.layer.borderColor = [[UIColor separatorColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = _radius < 0 ? CGRectGetHeight(self.bounds) / 2.0 : _radius;
    if (_glass) {
        _glass.frame = self.bounds;
        _glass.layer.cornerRadius = radius;
    } else {
        self.layer.cornerRadius = radius;
    }
}

@end

#pragma mark - Button

static const CGFloat kPFBShowcaseButtonHeight = 36.0;
static const CGFloat kPFBShowcaseButtonPadding = 16.0;

@implementation PFBShowcaseButton {
    PFBShowcaseSurface* _surface;
    UIImageView* _icon;
    UILabel* _text;
    UIImageView* _trailingIcon;
}

// Made directly rather than through buttonWithType:, which UIKit documents as not returning a subclass.
+ (instancetype)buttonWithStyle:(PFBShowcaseButtonStyle)style {
    PFBShowcaseButton* button = [[self alloc] initWithFrame:CGRectZero];
    button.style = style;
    return button;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _labelFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
        _icon = [[UIImageView alloc] init];
        _icon.contentMode = UIViewContentModeCenter;
        _text = [[UILabel alloc] init];
        _trailingIcon = [[UIImageView alloc] init];
        _trailingIcon.contentMode = UIViewContentModeCenter;
        for (UIView* part in @[ _icon, _text, _trailingIcon ]) {
            part.userInteractionEnabled = NO;
            [self addSubview:part];
        }
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self applyStyle];
    }
    return self;
}

- (void)setStyle:(PFBShowcaseButtonStyle)style {
    _style = style;
    [self applyStyle];
}

- (void)setLabel:(NSString*)label {
    _label = [label copy];
    _text.text = label;
    self.accessibilityLabel = label;
    [self setNeedsLayout];
}

- (void)setSymbolName:(NSString*)symbolName {
    _symbolName = [symbolName copy];
    [self applyStyle];
}

- (void)setTrailingSymbolName:(NSString*)trailingSymbolName {
    _trailingSymbolName = [trailingSymbolName copy];
    [self applyStyle];
}

- (void)setLabelFont:(UIFont*)labelFont {
    _labelFont = labelFont;
    [self applyStyle];
}

- (void)setGroundColor:(UIColor*)groundColor {
    _groundColor = groundColor;
    [self applyStyle];
}

// A frame set while a press scales the capsule would be scaled with it, so its size and its
// center are set apart.
- (void)setFrame:(CGRect)frame {
    if (CGAffineTransformIsIdentity(self.transform)) {
        [super setFrame:frame];
        return;
    }
    self.bounds = (CGRect){self.bounds.origin, frame.size};
    self.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
}

// The glass style stands on a glass surface; the others draw their own ground and border.
- (void)applyStyle {
    BOOL glass = self.style == PFBShowcaseButtonStyleGlass;
    if (glass && !_surface) {
        _surface = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        _surface.userInteractionEnabled = NO;
        [self insertSubview:_surface atIndex:0];
    } else if (!glass && _surface) {
        [_surface removeFromSuperview];
        _surface = nil;
    }
    UIColor* ink = PFBSettingsTextColor();
    UIColor* ground = self.groundColor ?: [UIColor clearColor];
    UIColor* border = nil;
    if (self.style == PFBShowcaseButtonStyleOutline) {
        border = PFBShowcasePaletteColor(@"primaryOutlinedButtonBorderColor", [UIColor separatorColor]);
    } else if (self.style == PFBShowcaseButtonStyleDestructive) {
        ink = PFBSettingsAlertColor();
        border = PFBShowcasePaletteColor(@"destructiveOutlinedButtonBorderColor", [UIColor separatorColor]);
    } else if (self.style == PFBShowcaseButtonStyleFilled) {
        ground = PFBShowcasePaletteColor(@"primaryButtonBackgroundColor", [UIColor labelColor]);
        ink = PFBShowcasePaletteColor(@"primaryButtonTextColor", [UIColor systemBackgroundColor]);
    }
    self.backgroundColor = ground;
    self.layer.borderWidth = border ? 1.0 : 0.0;
    self.layer.borderColor = [border resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    _text.font = self.labelFont;
    _text.textColor = ink;
    UIImageSymbolConfiguration* lead = [UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                      weight:UIImageSymbolWeightMedium];
    UIImageSymbolConfiguration* trail = [UIImageSymbolConfiguration configurationWithPointSize:11
                                                                                       weight:UIImageSymbolWeightSemibold];
    _icon.image = self.symbolName ? [UIImage systemImageNamed:self.symbolName withConfiguration:lead] : nil;
    _icon.tintColor = ink;
    _trailingIcon.image =
        self.trailingSymbolName ? [UIImage systemImageNamed:self.trailingSymbolName withConfiguration:trail] : nil;
    _trailingIcon.tintColor = PFBSettingsSubtitleColor();
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyStyle];
}

// A press shrinks the capsule a little, as Twitter's buttons do; glass keeps its full opacity.
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.15
                     animations:^{
                       self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
                     }];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = 2 * kPFBShowcaseButtonPadding;
    CGFloat parts = 0;
    if (_icon.image) {
        width += _icon.image.size.width;
        parts++;
    }
    if (self.label.length) {
        width += ceil([_text sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
        parts++;
    }
    if (_trailingIcon.image) {
        width += _trailingIcon.image.size.width;
        parts++;
    }
    width += MAX(0, parts - 1) * 6.0;
    CGFloat height = MAX(kPFBShowcaseButtonHeight, ceil(self.labelFont.lineHeight) + 14.0);
    // A symbol alone makes a circle.
    return CGSizeMake(self.label.length ? width : height, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat height = CGRectGetHeight(bounds);
    _surface.frame = bounds;
    self.layer.cornerRadius = height / 2.0;
    CGSize iconSize = _icon.image ? _icon.image.size : CGSizeZero;
    CGSize trailSize = _trailingIcon.image ? _trailingIcon.image.size : CGSizeZero;
    CGFloat textWidth = self.label.length ? ceil([_text sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)].width) : 0;
    CGFloat room = CGRectGetWidth(bounds) - 2 * kPFBShowcaseButtonPadding;
    CGFloat gaps = ((iconSize.width > 0) + (textWidth > 0) + (trailSize.width > 0) - 1) * 6.0;
    textWidth = MIN(textWidth, MAX(0, room - iconSize.width - trailSize.width - MAX(0, gaps)));
    CGFloat total = iconSize.width + textWidth + trailSize.width + MAX(0, gaps);
    CGFloat x = (CGRectGetWidth(bounds) - total) / 2.0;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat width = CGRectGetWidth(bounds);
    _icon.frame = PFBShowcaseMirrored(CGRectMake(x, 0, iconSize.width, height), width, rtl);
    x += iconSize.width + (iconSize.width > 0 && (textWidth > 0 || trailSize.width > 0) ? 6.0 : 0);
    _text.frame = PFBShowcaseMirrored(CGRectMake(x, 0, textWidth, height), width, rtl);
    x += textWidth + (textWidth > 0 && trailSize.width > 0 ? 6.0 : 0);
    _trailingIcon.frame = PFBShowcaseMirrored(CGRectMake(x, 0, trailSize.width, height), width, rtl);
}

@end

#pragma mark - Row

static const CGFloat kPFBShowcaseRowTrailing = 20.0;
static const CGFloat kPFBShowcaseCircle = 32.0;
static const CGFloat kPFBShowcaseRowGap = 12.0;
static const CGFloat kPFBShowcaseRowMinHeight = 52.0;
static const CGFloat kPFBShowcaseRowPadding = 13.0;

@implementation PFBShowcaseRowCell {
    UIView* _circle;
    UIImageView* _symbol;
    UILabel* _title;
    UILabel* _subtitle;
    UILabel* _value;
    UIImageView* _glyph;
    NSString* _symbolName;
    PFBShowcaseAccessory _accessory;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _circle = [[UIView alloc] init];
        _circle.layer.cornerRadius = kPFBShowcaseCircle / 2.0;
        _symbol = [[UIImageView alloc] init];
        _symbol.contentMode = UIViewContentModeCenter;
        [_circle addSubview:_symbol];
        _title = [[UILabel alloc] init];
        _subtitle = [[UILabel alloc] init];
        _subtitle.numberOfLines = 2;
        _value = [[UILabel alloc] init];
        _value.textAlignment = NSTextAlignmentRight;
        _glyph = [[UIImageView alloc] init];
        _glyph.contentMode = UIViewContentModeCenter;
        for (UIView* part in @[ _circle, _title, _subtitle, _value, _glyph ]) {
            [self.contentView addSubview:part];
        }
        _titleLines = 1;
        [self applyTheme];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _symbolColor = nil;
    _twitterGlyphName = nil;
    self.trailingView = nil;
    self.titleLines = 1;
}

- (void)configureWithSymbol:(NSString*)symbol
                      title:(NSString*)title
                   subtitle:(NSString*)subtitle
                      value:(NSString*)value
                  accessory:(PFBShowcaseAccessory)accessory {
    _symbolName = [symbol copy];
    _accessory = accessory;
    _title.text = title;
    _subtitle.text = subtitle;
    _value.text = value;
    self.accessibilityLabel = title;
    self.accessibilityValue = value ?: subtitle;
    self.accessibilityTraits = accessory == PFBShowcaseAccessoryNone ? UIAccessibilityTraitNone : UIAccessibilityTraitButton;
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)setSymbolColor:(UIColor*)symbolColor {
    _symbolColor = symbolColor;
    [self applyTheme];
}

- (void)setTwitterGlyphName:(NSString*)twitterGlyphName {
    _twitterGlyphName = [twitterGlyphName copy];
    [self applyTheme];
}

- (void)setTitleLines:(NSInteger)titleLines {
    _titleLines = MAX(1, titleLines);
    _title.numberOfLines = _titleLines;
    [self setNeedsLayout];
}

- (void)setTrailingView:(UIView*)trailingView {
    if (_trailingView == trailingView) {
        return;
    }
    [_trailingView removeFromSuperview];
    _trailingView = trailingView;
    if (trailingView) {
        if (CGRectIsEmpty(trailingView.bounds)) {
            [trailingView sizeToFit];
        }
        [self.contentView addSubview:trailingView];
    }
    // A row with a control of its own is read as that control, which carries the row's words.
    self.isAccessibilityElement = trailingView == nil;
    self.accessibilityElements = trailingView ? @[ trailingView ] : nil;
    [self setNeedsLayout];
}

// The palette's colors are read again on every appearance change, and the vector glyphs baked
// again in them.
- (void)applyTheme {
    self.backgroundColor = PFBSettingsRowGround(self);
    pfbApplySelectedBackground(self);
    UIColor* ink = PFBSettingsTextColor();
    _title.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16]);
    _title.textColor = ink;
    _subtitle.font = PFBSettingsDetailFont();
    _subtitle.textColor = PFBSettingsSubtitleColor();
    _value.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    _value.textColor = PFBSettingsSubtitleColor();
    _circle.backgroundColor = [UIColor tertiarySystemFillColor];
    _circle.hidden = _symbolName == nil;
    UIImageSymbolConfiguration* config = [UIImageSymbolConfiguration configurationWithPointSize:15
                                                                                        weight:UIImageSymbolWeightMedium];
    UIImage* symbol = _symbolName ? [UIImage systemImageNamed:_symbolName withConfiguration:config] : nil;
    // A Twitter glyph takes the box of the system circle at the same size.
    UIImage* box = _twitterGlyphName ? [UIImage systemImageNamed:@"circle" withConfiguration:config] : nil;
    UIImage* twitterGlyph = box ? PFBTwitterGlyphFor(_twitterGlyphName, box) : nil;
    _symbol.image = twitterGlyph && twitterGlyph != box ? twitterGlyph : symbol;
    _symbol.tintColor = self.symbolColor ?: ink;
    _glyph.image = nil;
    if (_accessory == PFBShowcaseAccessoryMenu) {
        UIImageSymbolConfiguration* small = [UIImageSymbolConfiguration configurationWithPointSize:12
                                                                                           weight:UIImageSymbolWeightSemibold];
        _glyph.image = [UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:small];
        _glyph.tintColor = [UIColor tertiaryLabelColor];
    } else if (_accessory != PFBShowcaseAccessoryNone &&
               [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        BOOL more = _accessory == PFBShowcaseAccessoryMore;
        UIImage* glyph = [UIImage tfn_vectorImageNamed:more ? @"more_vertical" : @"chevron_right"
                                              fitsSize:more ? CGSizeMake(20, 20) : CGSizeMake(16, 16)
                                             fillColor:more ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor]];
        _glyph.image = [glyph imageFlippedForRightToLeftLayoutDirection];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

- (CGFloat)textStart {
    return _symbolName ? kPFBShowcaseRowLeading + kPFBShowcaseCircle + kPFBShowcaseRowGap : kPFBShowcaseRowLeading;
}

// Where the text ends: before the control, the glyph and the value that follow it.
- (CGFloat)textEndForWidth:(CGFloat)width valueWidth:(CGFloat*)valueWidth {
    CGFloat end = width - kPFBShowcaseRowTrailing;
    if (self.trailingView) {
        end -= CGRectGetWidth(self.trailingView.bounds) + kPFBShowcaseRowGap;
    }
    if (_glyph.image) {
        end -= 20.0 + 8.0;
    }
    CGFloat fitted = 0;
    if (_value.text.length) {
        fitted = MIN(ceil([_value sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width),
                     MAX(0, (end - [self textStart]) / 2.0));
        end -= fitted + 8.0;
    }
    if (valueWidth) {
        *valueWidth = fitted;
    }
    return end;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat room = MAX(0, [self textEndForWidth:size.width valueWidth:NULL] - [self textStart]);
    CGFloat height = ceil([_title sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
    if (_subtitle.text.length) {
        height += 2.0 + ceil([_subtitle sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
    }
    return CGSizeMake(size.width, MAX(kPFBShowcaseRowMinHeight, height + 2 * kPFBShowcaseRowPadding));
}

// A table that sizes its rows asks through Auto Layout; the row measures itself instead.
- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize
        withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority
              verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    return [self sizeThatFits:CGSizeMake(targetSize.width, CGFLOAT_MAX)];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat midY = CGRectGetMidY(bounds);
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat valueWidth = 0;
    CGFloat start = [self textStart];
    CGFloat end = [self textEndForWidth:width valueWidth:&valueWidth];
    CGFloat room = MAX(0, end - start);
    CGFloat titleHeight = ceil([_title sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
    CGFloat subtitleHeight =
        _subtitle.text.length ? ceil([_subtitle sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height) : 0;
    CGFloat block = titleHeight + (subtitleHeight > 0 ? 2.0 + subtitleHeight : 0);
    CGFloat top = midY - block / 2.0;
    _circle.frame = PFBShowcaseMirrored(
        CGRectMake(kPFBShowcaseRowLeading, midY - kPFBShowcaseCircle / 2.0, kPFBShowcaseCircle, kPFBShowcaseCircle), width,
        rtl);
    _symbol.frame = _circle.bounds;
    _title.frame = PFBShowcaseMirrored(CGRectMake(start, top, room, titleHeight), width, rtl);
    _subtitle.frame = PFBShowcaseMirrored(CGRectMake(start, top + titleHeight + 2.0, room, subtitleHeight), width, rtl);
    CGFloat x = width - kPFBShowcaseRowTrailing;
    if (self.trailingView) {
        CGSize control = self.trailingView.bounds.size;
        x -= control.width;
        self.trailingView.frame =
            PFBShowcaseMirrored(CGRectMake(x, midY - control.height / 2.0, control.width, control.height), width, rtl);
        x -= kPFBShowcaseRowGap;
    }
    if (_glyph.image) {
        x -= 20.0;
        _glyph.frame = PFBShowcaseMirrored(CGRectMake(x, midY - 10.0, 20.0, 20.0), width, rtl);
        x -= 8.0;
    } else {
        _glyph.frame = CGRectZero;
    }
    _value.textAlignment = rtl ? NSTextAlignmentLeft : NSTextAlignmentRight;
    _value.frame = PFBShowcaseMirrored(CGRectMake(x - valueWidth, midY - titleHeight / 2.0, valueWidth, titleHeight),
                                       width, rtl);
}

@end
