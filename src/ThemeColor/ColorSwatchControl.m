//
//  ColorSwatchControl.m
//  PrimeFreeBird
//

#import "ColorSwatchControl.h"

static const CGFloat kPillHeight = 40.0;
static const CGFloat kRadioDiameter = 22.0;
static const CGFloat kRadioCheckSize = 12.0;

@interface ColorSwatchControl ()
@property (nonatomic, strong) UIView* pillView;
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UIView* radioView;
@property (nonatomic, strong) UIImageView* radioCheck;
@property (nonatomic, strong) UIColor* swatchTint;
@end

@implementation ColorSwatchControl

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
        self.nameLabel.font = [UIFont boldSystemFontOfSize:15];
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
    // Restore the coloured look in case this control was neutral before.
    self.nameLabel.textColor = [UIColor whiteColor];
    // A small white check on a FILLED circle. The old checkmark.circle.fill
    // symbol carries its own artwork margins, which made the checked circle
    // render smaller than the empty ring on screen. Filling radioView
    // itself keeps the checked state at exactly the ring's 22pt.
    UIImage* check = [[UIImage systemImageNamed:@"checkmark"]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.radioCheck.image = check;
    self.radioCheck.tintColor = [UIColor whiteColor];
    if (!self.radioCheck.hidden) {
        self.radioView.backgroundColor = color;
    }
}

// The colourless state: the quiet grey of the reset button, with readable
// secondary text. Used by the Custom swatch until a custom colour is active.
- (void)setSwatchNeutral {
    self.pillView.backgroundColor = [UIColor tertiarySystemFillColor];
    self.nameLabel.textColor = [UIColor secondaryLabelColor];
}

- (void)setSwatchName:(NSString*)name {
    self.nameLabel.text = name;
}

- (void)setSwatchSelected:(BOOL)selected {
    self.radioCheck.hidden = !selected;
    if (selected) {
        self.radioView.backgroundColor = self.swatchTint ?: [UIColor secondaryLabelColor];
        self.radioView.layer.borderColor = [UIColor clearColor].CGColor;
    } else {
        self.radioView.backgroundColor = [UIColor clearColor];
        self.radioView.layer.borderColor = [UIColor tertiaryLabelColor].CGColor;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.radioCheck.hidden) {
        self.radioView.layer.borderColor = [UIColor tertiaryLabelColor].CGColor;
    }
}

@end
