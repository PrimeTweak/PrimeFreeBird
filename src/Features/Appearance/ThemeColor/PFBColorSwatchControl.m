// A pill-style accent color option, or the new look's round one.

#import "Features/Appearance/ThemeColor/PFBColorSwatchControl.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"

static const CGFloat kPillHeight = 40.0;
static const CGFloat kRadioDiameter = 22.0;
static const CGFloat kRadioCheckSize = 12.0;
// The rainbow's band around the custom color.
static const CGFloat kRainbowBand = 5.0;
// A round option's color, whatever the control's size.
static const CGFloat kRoundDiameter = 28.0;

@interface PFBColorSwatchControl ()
@property (nonatomic, strong) UIView* pillView;
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UIView* radioView;
@property (nonatomic, strong) UIImageView* radioCheck;
@property (nonatomic, strong) UIColor* swatchTint;
@property (nonatomic, assign) BOOL round;
@property (nonatomic, strong) CAGradientLayer* rainbow;
@property (nonatomic, strong) UIView* wellView;
@end

@implementation PFBColorSwatchControl

// The color alone: the bar holding the options marks the chosen one.
- (instancetype)initRound {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _round = YES;
        self.pillView = [[UIView alloc] init];
        self.pillView.clipsToBounds = YES;
        self.pillView.userInteractionEnabled = NO;
        [self addSubview:self.pillView];
    }
    return self;
}

// A band of hues around a well that holds the custom color, empty until one is picked.
- (instancetype)initRainbow {
    self = [self initRound];
    if (self) {
        NSMutableArray* hues = [NSMutableArray array];
        for (NSNumber* hex in @[ @0xFF3B30, @0xFF9500, @0xFFCC00, @0x34C759, @0x00C7BE, @0x007AFF, @0xAF52DE,
                                 @0xFF2D55, @0xFF3B30 ]) {
            unsigned int rgb = hex.unsignedIntValue;
            [hues addObject:(id)[UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                                                green:((rgb >> 8) & 0xFF) / 255.0
                                                 blue:(rgb & 0xFF) / 255.0
                                                alpha:1.0]
                                 .CGColor];
        }
        self.rainbow = [CAGradientLayer layer];
        self.rainbow.type = kCAGradientLayerConic;
        self.rainbow.startPoint = CGPointMake(0.5, 0.5);
        self.rainbow.endPoint = CGPointMake(0.5, 0.0);
        self.rainbow.colors = hues;
        [self.pillView.layer addSublayer:self.rainbow];
        self.wellView = [[UIView alloc] init];
        self.wellView.userInteractionEnabled = NO;
        [self.pillView addSubview:self.wellView];
        [self setSwatchNeutral];
    }
    return self;
}

// The color centered in the control, with the rainbow's well inside it.
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.round) {
        return;
    }
    CGRect bounds = self.bounds;
    self.pillView.frame = CGRectMake(CGRectGetMidX(bounds) - kRoundDiameter / 2.0,
                                     CGRectGetMidY(bounds) - kRoundDiameter / 2.0, kRoundDiameter, kRoundDiameter);
    self.pillView.layer.cornerRadius = kRoundDiameter / 2.0;
    CGRect well = CGRectInset(self.pillView.bounds, kRainbowBand, kRainbowBand);
    self.wellView.frame = well;
    self.wellView.layer.cornerRadius = CGRectGetWidth(well) / 2.0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.rainbow.frame = self.pillView.bounds;
    [CATransaction commit];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // The colored pill with the name inside.
        self.pillView = [[UIView alloc] init];
        self.pillView.translatesAutoresizingMaskIntoConstraints = NO;
        self.pillView.userInteractionEnabled = NO;
        self.pillView.layer.cornerRadius = kPillHeight / 2.0;
        self.pillView.clipsToBounds = YES;
        [self addSubview:self.pillView];

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.userInteractionEnabled = NO;
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15]);
        self.nameLabel.textColor = [UIColor whiteColor];
        [self.pillView addSubview:self.nameLabel];

        // The radio circle below.
        self.radioView = [[UIView alloc] init];
        self.radioView.translatesAutoresizingMaskIntoConstraints = NO;
        self.radioView.userInteractionEnabled = NO;
        self.radioView.layer.cornerRadius = kRadioDiameter / 2.0;
        self.radioView.layer.borderWidth = 2.0;
        self.radioView.layer.borderColor = [UIColor tertiaryLabelColor].CGColor;
        [self addSubview:self.radioView];

        self.radioCheck = [[UIImageView alloc] init];
        self.radioCheck.translatesAutoresizingMaskIntoConstraints = NO;
        self.radioCheck.contentMode = UIViewContentModeScaleAspectFit;
        self.radioCheck.hidden = YES;
        [self.radioView addSubview:self.radioCheck];

        [NSLayoutConstraint activateConstraints:@[
            [self.pillView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.pillView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.pillView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.pillView.heightAnchor constraintEqualToConstant:kPillHeight],

            [self.nameLabel.centerXAnchor constraintEqualToAnchor:self.pillView.centerXAnchor],
            [self.nameLabel.centerYAnchor constraintEqualToAnchor:self.pillView.centerYAnchor],
            [self.nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.pillView.leadingAnchor constant:8],
            [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.pillView.trailingAnchor constant:-8],

            [self.radioView.topAnchor constraintEqualToAnchor:self.pillView.bottomAnchor constant:8],
            [self.radioView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.radioView.widthAnchor constraintEqualToConstant:kRadioDiameter],
            [self.radioView.heightAnchor constraintEqualToConstant:kRadioDiameter],
            [self.radioView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [self.radioCheck.centerXAnchor constraintEqualToAnchor:self.radioView.centerXAnchor],
            [self.radioCheck.centerYAnchor constraintEqualToAnchor:self.radioView.centerYAnchor],
            [self.radioCheck.widthAnchor constraintEqualToConstant:kRadioCheckSize],
            [self.radioCheck.heightAnchor constraintEqualToConstant:kRadioCheckSize]
        ]];
    }
    return self;
}

- (void)setSwatchColor:(UIColor*)color {
    if (self.round) {
        (self.wellView ?: self.pillView).backgroundColor = color;
        return;
    }
    self.pillView.backgroundColor = color;
    self.swatchTint = color;
    // Restore the colored look in case this control was neutral before.
    self.nameLabel.textColor = [UIColor whiteColor];
    // A white check on the filled ring keeps the checked state at the ring's 22 pt.
    UIImage* check = [PFBTwitterGlyphFor(@"checkmark", [UIImage systemImageNamed:@"checkmark"])
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.radioCheck.image = check;
    self.radioCheck.tintColor = [UIColor whiteColor];
    if (!self.radioCheck.hidden) {
        self.radioView.backgroundColor = color;
    }
}

// The colorless state: a quiet gray fill with readable secondary text. Used by
// the Custom swatch until a custom color is active.
- (void)setSwatchNeutral {
    if (self.round) {
        self.wellView.backgroundColor = [UIColor systemBackgroundColor];
        return;
    }
    self.pillView.backgroundColor = [UIColor tertiarySystemFillColor];
    self.nameLabel.textColor = [UIColor secondaryLabelColor];
}

- (void)setSwatchName:(NSString*)name {
    self.nameLabel.text = name;
}

// A round option shows nothing itself: the bar holding it marks the chosen one.
- (void)setSwatchSelected:(BOOL)selected {
    if (self.round) {
        return;
    }
    self.radioCheck.hidden = !selected;
    if (selected) {
        self.radioView.backgroundColor = self.swatchTint ?: [UIColor secondaryLabelColor];
        self.radioView.layer.borderColor = [UIColor clearColor].CGColor;
    } else {
        self.radioView.backgroundColor = [UIColor clearColor];
        self.radioView.layer.borderColor = [UIColor tertiaryLabelColor].CGColor;
    }
}

// A layer's border keeps the CGColor it was given, so it is resolved again for the new appearance.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.round) {
        return;
    }
    if (self.radioCheck.hidden) {
        self.radioView.layer.borderColor = [UIColor tertiaryLabelColor].CGColor;
    }
}

@end
