// A row of Twitter's new settings: icon, title, and a chevron or a three-dot glyph.

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
        _trailing = [[UIImageView alloc] init];
        _trailing.contentMode = UIViewContentModeCenter;
        for (UIView* part in @[ _icon, _title, _trailing ]) {
            [self.contentView addSubview:part];
        }
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self applyTheme];
    }
    return self;
}

- (void)configureWithTitle:(NSString*)title
                  iconName:(NSString*)iconName
                 accessory:(PFBNativeSettingsRowAccessory)accessory {
    self.title.text = title;
    self.accessibilityLabel = title;
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
    title = CGRectMake(title.origin.x, CGRectGetMidY(title) + shift - titleHeight / 2,
                       MAX(0, CGRectGetMinX(trailing) - 8 - title.origin.x), titleHeight);
    self.trailing.frame = PFBRowMirrored(trailing, width, rtl);
    self.icon.frame = PFBRowMirrored(CGRectOffset(style.iconFrame, 0, shift), width, rtl);
    self.title.frame = PFBRowMirrored(title, width, rtl);
}

@end
