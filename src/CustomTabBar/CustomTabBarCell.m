//
//  CustomTabBarCell.m
//  PrimeFreeBird
//
//  Styling mirrors the app's native TabCustomizationViewCell so the editor's
//  tiles match the stock tab-customization screen.
//

#import "CustomTabBarCell.h"
#import <QuartzCore/QuartzCore.h>
#import "Core/TwitterChirpFont.h"
#import "CustomTabBarNativeColors.h"

@interface UIImage (TFNAdditions)
+ (id)tfn_vectorImageNamed:(id)arg1
                  fitsSize:(struct CGSize)arg2
                 fillColor:(id)arg3;
@end

@interface CustomTabBarCell ()
@property (nonatomic, strong) UIView* container;
@property (nonatomic, strong) UIImageView* iconView;
@property (nonatomic, strong) UILabel* titleLabel;
@property (nonatomic, copy) NSString* imageName;
@property (nonatomic, assign) BOOL tabSelected;
@property (nonatomic, assign) BOOL fixed;
@property (nonatomic, strong) UIColor* accentColor;
@end

@implementation CustomTabBarCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.container = [UIView new];
        self.container.translatesAutoresizingMaskIntoConstraints = NO;
        self.container.layer.cornerRadius = 12;
        self.container.layer.cornerCurve = kCACornerCurveContinuous;
        self.container.layer.borderWidth = 2;
        [self.contentView addSubview:self.container];

        self.iconView = [UIImageView new];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.container addSubview:self.iconView];

        self.titleLabel = [UILabel new];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.5;
        [self.contentView addSubview:self.titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.container.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor],
            [self.container.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.container.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.container.heightAnchor
                constraintEqualToAnchor:self.container.widthAnchor],

            [self.iconView.centerXAnchor
                constraintEqualToAnchor:self.container.centerXAnchor],
            [self.iconView.centerYAnchor
                constraintEqualToAnchor:self.container.centerYAnchor],
            [self.iconView.widthAnchor constraintEqualToConstant:28],
            [self.iconView.heightAnchor constraintEqualToConstant:28],

            [self.titleLabel.topAnchor
                constraintEqualToAnchor:self.container.bottomAnchor
                               constant:8],
            [self.titleLabel.leadingAnchor
                constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.titleLabel.trailingAnchor
                constraintEqualToAnchor:self.contentView.trailingAnchor]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString*)title
                 imageName:(NSString*)imageName
                  selected:(BOOL)selected
                     fixed:(BOOL)fixed
               accentColor:(UIColor*)accentColor {
    self.titleLabel.text = title;
    self.imageName = imageName;
    self.tabSelected = selected;
    self.fixed = fixed;
    self.accentColor = accentColor;
    [self applyAppearance];
}

- (void)applyAppearance {
    UIColor* accent = self.accentColor ?: [UIColor systemBlueColor];
    BOOL on = self.tabSelected;

    UIColor* iconColor;
    if (self.fixed) {
        // Home can't be toggled, so it stays visually locked and neutral.
        self.container.backgroundColor = CustomTabBarInactiveCardBackgroundColor();
        self.container.layer.borderWidth = 0;
        iconColor = [UIColor tertiaryLabelColor];
        self.titleLabel.textColor = [UIColor secondaryLabelColor];
        self.titleLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    } else if (on) {
        self.container.backgroundColor = [accent colorWithAlphaComponent:0.15];
        self.container.layer.borderWidth = 2;
        self.container.layer.borderColor = accent.CGColor;
        iconColor = accent;
        self.titleLabel.textColor = [UIColor labelColor];
        self.titleLabel.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:13];
    } else {
        self.container.backgroundColor = CustomTabBarCardBackgroundColor();
        self.container.layer.borderWidth = 0;
        iconColor = [UIColor tertiaryLabelColor];
        self.titleLabel.textColor = [UIColor secondaryLabelColor];
        self.titleLabel.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    }

    // A soft floating-card shadow on the non-selected cards (and the locked Home
    // card) — the elevated look he liked. The selected card is already defined by
    // its accent border, so it stays flat.
    if (!self.fixed && on) {
        self.container.layer.shadowOpacity = 0.0;
    } else {
        self.container.layer.masksToBounds = NO;
        self.container.layer.shadowColor = [UIColor blackColor].CGColor;
        self.container.layer.shadowOpacity = 0.12;
        self.container.layer.shadowRadius = 6.0;
        self.container.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    }

    if (self.imageName.length) {
        self.iconView.image = [UIImage tfn_vectorImageNamed:self.imageName
                                                   fitsSize:CGSizeMake(28, 28)
                                                  fillColor:iconColor];
    } else {
        self.iconView.image = nil;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.titleLabel.text = nil;
    self.container.layer.borderColor = [UIColor clearColor].CGColor;
    self.container.layer.shadowOpacity = 0;
}

+ (NSString*)reuseIdentifier {
    return @"CustomTabBarCell";
}

@end
