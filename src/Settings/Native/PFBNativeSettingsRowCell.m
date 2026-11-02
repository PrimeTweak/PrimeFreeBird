// A row of Twitter's new settings: icon, title, the current choice when it has one, and a chevron
// or a three-dot glyph.

#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/PFBManager.h"

// Under a description, the room left below it, as above the title.
static const CGFloat kPFBRowDetailBottom = 16;

@implementation PFBNativeSettingsRowStyle

+ (PFBNativeSettingsRowStyle*)shared {
    static PFBNativeSettingsRowStyle* style;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        style = [[PFBNativeSettingsRowStyle alloc] init];
        style.rowHeight = 56;
        style.iconFrame = CGRectMake(24, 12, 24, 24);
        style.titleFrame = CGRectMake(64, 14, 0, 20);
        style.chevronFrame = CGRectMake(48, 18, 16, 16);
    });
    return style;
}

@end

// Turns a left-to-right frame into the row's direction; the flip is the same both ways.
static CGRect PFBRowMirrored(CGRect frame, CGFloat width, BOOL rtl) {
    if (rtl) {
        frame.origin.x = width - CGRectGetMaxX(frame);
    }
    return frame;
}

// The chevron's or the three dots' frame, left to right, on a row whose content is shifted down by shift.
static CGRect PFBRowTrailingFrame(CGFloat width, CGFloat shift, PFBNativeSettingsRowAccessory accessory) {
    CGRect trailing = [PFBNativeSettingsRowStyle shared].chevronFrame;
    trailing.origin.x = width - trailing.origin.x;
    trailing.origin.y += shift;
    if (accessory == PFBNativeSettingsRowAccessoryMore) {
        trailing = CGRectInset(trailing, (trailing.size.width - 20) / 2, (trailing.size.height - 20) / 2);
    }
    return trailing;
}

@interface PFBNativeSettingsRowCell ()
@property (nonatomic, strong) UIImageView* icon;
@property (nonatomic, strong) UILabel* title;
@property (nonatomic, strong) UILabel* value;
@property (nonatomic, strong) UILabel* detailLine;
@property (nonatomic, strong) UIImageView* trailing;
@property (nonatomic, copy) NSString* iconName;
@property (nonatomic) PFBNativeSettingsRowAccessory accessory;
@end

@implementation PFBNativeSettingsRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _icon = [[UIImageView alloc] init];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _title = [[UILabel alloc] init];
        _value = [[UILabel alloc] init];
        _detailLine = [[UILabel alloc] init];
        _detailLine.numberOfLines = 0;
        _trailing = [[UIImageView alloc] init];
        _trailing.contentMode = UIViewContentModeCenter;
        for (UIView* part in @[ _icon, _title, _value, _detailLine, _trailing ]) {
            [self.contentView addSubview:part];
        }
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self applyTheme];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _destructive = NO;
    _iconColor = nil;
}

- (void)configureWithTitle:(NSString*)title
                  iconName:(NSString*)iconName
                     value:(NSString*)value
                 accessory:(PFBNativeSettingsRowAccessory)accessory {
    [self configureWithTitle:title detail:nil iconName:iconName value:value accessory:accessory];
}

- (void)configureWithTitle:(NSString*)title
                    detail:(NSString*)detail
                  iconName:(NSString*)iconName
                     value:(NSString*)value
                 accessory:(PFBNativeSettingsRowAccessory)accessory {
    self.title.text = title;
    self.value.text = value;
    self.detailLine.text = detail;
    self.accessibilityLabel = title;
    self.accessibilityValue = value;
    self.accessibilityHint = detail;
    self.iconName = iconName;
    self.accessory = accessory;
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)setDestructive:(BOOL)destructive {
    _destructive = destructive;
    [self applyTheme];
}

- (void)setIconColor:(UIColor*)iconColor {
    _iconColor = iconColor;
    [self applyTheme];
}

// Vector images bake in their fill color, so they are drawn again on every appearance change.
- (void)applyTheme {
    PFBNativeSettingsRowStyle* style = [PFBNativeSettingsRowStyle shared];
    UIColor* ink = self.destructive ? PFBSettingsAlertColor() : PFBSettingsTextColor();
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    pfbApplySelectedBackground(self);
    self.title.font = style.titleFont ?: [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16];
    self.title.textColor = ink;
    self.value.font = self.title.font;
    self.value.textColor = PFBSettingsSubtitleColor();
    self.detailLine.font = PFBSettingsDetailFont();
    self.detailLine.textColor = PFBSettingsSubtitleColor();
    if (![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return;
    }
    self.icon.image = self.iconName ? [UIImage tfn_vectorImageNamed:self.iconName
                                                           fitsSize:style.iconFrame.size
                                                          fillColor:self.iconColor ?: ink]
                                    : nil;
    if (self.accessory == PFBNativeSettingsRowAccessoryNone) {
        self.trailing.image = nil;
        return;
    }
    // A menu shows the up-down chevron of UIKit's pop-up buttons, as the sheets' menu rows do.
    if (self.accessory == PFBNativeSettingsRowAccessoryMenu) {
        UIImageSymbolConfiguration* config =
            [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
        self.trailing.tintColor = [UIColor tertiaryLabelColor];
        self.trailing.image = [UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:config];
        return;
    }
    BOOL more = self.accessory == PFBNativeSettingsRowAccessoryMore;
    UIImage* glyph = [UIImage tfn_vectorImageNamed:more ? @"more_vertical" : @"chevron_right"
                                          fitsSize:more ? CGSizeMake(20, 20) : style.chevronFrame.size
                                         fillColor:more ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor]];
    self.trailing.image = [glyph imageFlippedForRightToLeftLayoutDirection];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

// Where the title starts: after the icon, or where the icon would stand on a row without one.
- (CGFloat)titleStart {
    PFBNativeSettingsRowStyle* style = [PFBNativeSettingsRowStyle shared];
    return self.iconName ? style.titleFrame.origin.x : style.iconFrame.origin.x;
}

// Where the title's line and the description end: before the glyph, or at the row's margin.
- (CGFloat)textEndForWidth:(CGFloat)width {
    if (self.accessory == PFBNativeSettingsRowAccessoryNone) {
        return width - [PFBNativeSettingsRowStyle shared].iconFrame.origin.x;
    }
    return CGRectGetMinX(PFBRowTrailingFrame(width, 0, self.accessory)) - 8;
}

- (CGFloat)detailHeightForWidth:(CGFloat)width {
    CGFloat room = MAX(0, [self textEndForWidth:width] - [self titleStart]);
    return ceil([self.detailLine sizeThatFits:CGSizeMake(room, CGFLOAT_MAX)].height);
}

// Twitter's height for a row; a description adds its own lines under the title.
- (CGSize)sizeThatFits:(CGSize)size {
    PFBNativeSettingsRowStyle* style = [PFBNativeSettingsRowStyle shared];
    if (!self.detailLine.text.length) {
        return CGSizeMake(size.width, style.rowHeight);
    }
    CGFloat titleHeight = MAX(style.titleFrame.size.height, ceil(self.title.font.lineHeight));
    CGFloat height = style.titleFrame.origin.y + titleHeight + 2 + [self detailHeightForWidth:size.width] +
                     kPFBRowDetailBottom;
    return CGSizeMake(size.width, MAX(style.rowHeight, ceil(height)));
}

// A table that sizes its rows asks through Auto Layout; the row measures itself instead.
- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize
        withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority
              verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    return [self sizeThatFits:CGSizeMake(targetSize.width, CGFLOAT_MAX)];
}

// Twitter's frames hold for a row of its height; a taller row keeps them centered, and puts the
// title at its top when a description follows it.
- (void)layoutSubviews {
    [super layoutSubviews];
    PFBNativeSettingsRowStyle* style = [PFBNativeSettingsRowStyle shared];
    CGRect bounds = self.contentView.bounds;
    CGFloat width = bounds.size.width;
    CGFloat shift = MAX(0, (bounds.size.height - style.rowHeight) / 2);
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL described = self.detailLine.text.length > 0;
    CGRect trailing = PFBRowTrailingFrame(width, shift, self.accessory);
    CGRect title = style.titleFrame;
    CGFloat titleHeight = MAX(title.size.height, ceil(self.title.font.lineHeight));
    CGFloat titleY = described ? title.origin.y : CGRectGetMidY(title) + shift - titleHeight / 2;
    CGFloat start = [self titleStart];
    // The value takes what the title leaves, and half the room when both are long.
    CGFloat end = [self textEndForWidth:width];
    CGRect value = CGRectZero;
    if (self.value.text.length) {
        CGFloat room = MAX(0, end - start);
        CGFloat needed = ceil([self.title sizeThatFits:CGSizeMake(CGFLOAT_MAX, titleHeight)].width);
        CGFloat fitted = MIN(ceil([self.value sizeThatFits:CGSizeMake(CGFLOAT_MAX, titleHeight)].width),
                             MAX(room - needed - 8, room / 2));
        value = CGRectMake(end - fitted, titleY, fitted, titleHeight);
        end = CGRectGetMinX(value) - 8;
    }
    title = CGRectMake(start, titleY, MAX(0, end - start), titleHeight);
    CGRect detail = CGRectZero;
    if (described) {
        detail = CGRectMake(start, CGRectGetMaxY(title) + 2, MAX(0, [self textEndForWidth:width] - start),
                            [self detailHeightForWidth:width]);
    }
    self.trailing.frame = PFBRowMirrored(trailing, width, rtl);
    self.icon.frame = PFBRowMirrored(CGRectOffset(style.iconFrame, 0, shift), width, rtl);
    self.title.frame = PFBRowMirrored(title, width, rtl);
    self.value.frame = PFBRowMirrored(value, width, rtl);
    self.detailLine.frame = PFBRowMirrored(detail, width, rtl);
}

@end
