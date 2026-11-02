// A pill-style accent color option.

#import "Features/Appearance/ThemeColor/PFBColorSwatchControl.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"

static const CGFloat kPillHeight = 40.0;
static const CGFloat kRadioDiameter = 22.0;
static const CGFloat kRadioCheckSize = 12.0;
// The round option: its color, the ring drawn around it once chosen, and the check inside.
static const CGFloat kRoundDiameter = 44.0;
static const CGFloat kRoundRingDiameter = 54.0;
static const CGFloat kRoundCheckSize = 18.0;

@interface PFBColorSwatchControl ()
@property (nonatomic, strong) UIView* pillView;
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UIView* radioView;
@property (nonatomic, strong) UIImageView* radioCheck;
@property (nonatomic, strong) UIColor* swatchTint;
@property (nonatomic, assign) BOOL round;
@end

@implementation PFBColorSwatchControl

// The ring is the radio here: hidden until chosen, then in the text color around the color.
- (instancetype)initRound {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _round = YES;
        self.radioView = [[UIView alloc] init];
        self.radioView.userInteractionEnabled = NO;
        self.radioView.layer.cornerRadius = kRoundRingDiameter / 2.0;
        self.radioView.layer.borderWidth = 2.0;
        self.radioView.hidden = YES;
        self.pillView = [[UIView alloc] init];
        self.pillView.userInteractionEnabled = NO;
        self.pillView.layer.cornerRadius = kRoundDiameter / 2.0;
        self.radioCheck = [[UIImageView alloc] init];
        self.radioCheck.contentMode = UIViewContentModeScaleAspectFit;
        self.radioCheck.image = [PFBTwitterGlyphFor(@"checkmark", [UIImage systemImageNamed:@"checkmark"])
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.radioCheck.tintColor = [UIColor whiteColor];
        self.radioCheck.hidden = YES;
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.userInteractionEnabled = NO;
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
        self.nameLabel.textColor = [UIColor secondaryLabelColor];
        for (UIView* part in @[ self.radioView, self.pillView, self.nameLabel ]) {
            part.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:part];
        }
        self.radioCheck.translatesAutoresizingMaskIntoConstraints = NO;
        [self.pillView addSubview:self.radioCheck];
        [NSLayoutConstraint activateConstraints:@[
            [self.radioView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.radioView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.radioView.widthAnchor constraintEqualToConstant:kRoundRingDiameter],
            [self.radioView.heightAnchor constraintEqualToConstant:kRoundRingDiameter],
            [self.pillView.centerXAnchor constraintEqualToAnchor:self.radioView.centerXAnchor],
            [self.pillView.centerYAnchor constraintEqualToAnchor:self.radioView.centerYAnchor],
            [self.pillView.widthAnchor constraintEqualToConstant:kRoundDiameter],
            [self.pillView.heightAnchor constraintEqualToConstant:kRoundDiameter],
            [self.radioCheck.centerXAnchor constraintEqualToAnchor:self.pillView.centerXAnchor],
            [self.radioCheck.centerYAnchor constraintEqualToAnchor:self.pillView.centerYAnchor],
            [self.radioCheck.widthAnchor constraintEqualToConstant:kRoundCheckSize],
            [self.radioCheck.heightAnchor constraintEqualToConstant:kRoundCheckSize],
            [self.nameLabel.topAnchor constraintEqualToAnchor:self.radioView.bottomAnchor constant:4],
            [self.nameLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
            [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
            [self.nameLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        self.radioView.layer.borderColor = [UIColor labelColor].CGColor;
    }
    return self;
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
    self.pillView.backgroundColor = color;
    self.swatchTint = color;
    if (self.round) {
        return;
    }
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
    self.pillView.backgroundColor = [UIColor tertiarySystemFillColor];
    self.nameLabel.textColor = [UIColor secondaryLabelColor];
}

- (void)setSwatchName:(NSString*)name {
    self.nameLabel.text = name;
}

- (void)setSwatchSelected:(BOOL)selected {
    self.radioCheck.hidden = !selected;
    if (self.round) {
        self.radioView.hidden = !selected;
        self.nameLabel.textColor = selected ? [UIColor labelColor] : [UIColor secondaryLabelColor];
        return;
    }
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
        self.radioView.layer.borderColor =
            [[UIColor labelColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        return;
    }
    if (self.radioCheck.hidden) {
        self.radioView.layer.borderColor = [UIColor tertiaryLabelColor].CGColor;
    }
}

@end
