// A row of Twitter's new settings: icon, title, the current choice when it has one, and a chevron
// or a three-dot glyph.

#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Settings/PFBSettingsCellStyle.h"
#import "Support/PFBManager.h"

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

@interface PFBNativeSettingsRowCell ()
@property (nonatomic, strong) UIImageView* icon;
@property (nonatomic, strong) UILabel* title;
@property (nonatomic, strong) UILabel* value;
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
        _trailing = [[UIImageView alloc] init];
        _trailing.contentMode = UIViewContentModeCenter;
        for (UIView* part in @[ _icon, _title, _value, _trailing ]) {
            [self.contentView addSubview:part];
        }
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self applyTheme];
    }
    return self;
}

- (void)configureWithTitle:(NSString*)title
                  iconName:(NSString*)iconName
                     value:(NSString*)value
                 accessory:(PFBNativeSettingsRowAccessory)accessory {
    self.title.text = title;
    self.value.text = value;
    self.accessibilityLabel = title;
    self.accessibilityValue = value;
    self.iconName = iconName;
    self.accessory = accessory;
    [self applyTheme];
    [self setNeedsLayout];
}

// Vector images bake in their fill color, so they are drawn again on every appearance change.
- (void)applyTheme {
    PFBNativeSettingsRowStyle* style = [PFBNativeSettingsRowStyle shared];
    UIColor* ink = PFBSettingsTextColor();
    self.backgroundColor = [PFBPalette currentBackgroundColor];
    pfbApplySelectedBackground(self);
    self.title.font = style.titleFont ?: [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16];
    self.title.textColor = ink;
    self.value.font = self.title.font;
    self.value.textColor = PFBSettingsSubtitleColor();
    if (![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return;
    }
    self.icon.image = self.iconName ? [UIImage tfn_vectorImageNamed:self.iconName
                                                           fitsSize:style.iconFrame.size
                                                          fillColor:ink]
                                    : nil;
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

// Twitter's frames hold for a row of its height; a taller row keeps them centered.
- (void)layoutSubviews {
    [super layoutSubviews];
    PFBNativeSettingsRowStyle* style = [PFBNativeSettingsRowStyle shared];
    CGRect bounds = self.contentView.bounds;
    CGFloat width = bounds.size.width;
    CGFloat shift = MAX(0, (bounds.size.height - style.rowHeight) / 2);
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect trailing = style.chevronFrame;
    trailing.origin.x = width - trailing.origin.x;
    trailing.origin.y += shift;
    if (self.accessory == PFBNativeSettingsRowAccessoryMore) {
        trailing = CGRectInset(trailing, (trailing.size.width - 20) / 2, (trailing.size.height - 20) / 2);
    }
    CGRect title = style.titleFrame;
    CGFloat titleHeight = MAX(title.size.height, ceil(self.title.font.lineHeight));
    CGFloat titleY = CGRectGetMidY(title) + shift - titleHeight / 2;
    // The value takes what the title leaves, and half the room when both are long.
    CGFloat end = CGRectGetMinX(trailing) - 8;
    CGRect value = CGRectZero;
    if (self.value.text.length) {
        CGFloat room = MAX(0, end - title.origin.x);
        CGFloat needed = ceil([self.title sizeThatFits:CGSizeMake(CGFLOAT_MAX, titleHeight)].width);
        CGFloat fitted = MIN(ceil([self.value sizeThatFits:CGSizeMake(CGFLOAT_MAX, titleHeight)].width),
                             MAX(room - needed - 8, room / 2));
        value = CGRectMake(end - fitted, titleY, fitted, titleHeight);
        end = CGRectGetMinX(value) - 8;
    }
    title = CGRectMake(title.origin.x, titleY, MAX(0, end - title.origin.x), titleHeight);
    self.trailing.frame = PFBRowMirrored(trailing, width, rtl);
    self.icon.frame = PFBRowMirrored(CGRectOffset(style.iconFrame, 0, shift), width, rtl);
    self.title.frame = PFBRowMirrored(title, width, rtl);
    self.value.frame = PFBRowMirrored(value, width, rtl);
}

@end
