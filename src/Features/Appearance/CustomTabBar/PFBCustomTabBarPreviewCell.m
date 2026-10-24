// The tab-bar preview cell of the tab editor.

#import "Features/Appearance/CustomTabBar/PFBCustomTabBarPreviewCell.h"
#import "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.h"
#import "Support/TFNHeaders.h"

@interface PFBCustomTabBarPreviewCell ()
@property (nonatomic, strong) UIImageView* iconView;
@end

@implementation PFBCustomTabBarPreviewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.iconView = [UIImageView new];
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:self.iconView];

        [NSLayoutConstraint activateConstraints:@[
            [self.iconView.centerXAnchor
                constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.iconView.centerYAnchor
                constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.iconView.widthAnchor constraintEqualToConstant:24],
            [self.iconView.heightAnchor constraintEqualToConstant:24]
        ]];
    }
    return self;
}

- (void)configureWithImageName:(NSString*)imageName {
    if (imageName.length && [UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        self.iconView.image =
            [UIImage tfn_vectorImageNamed:imageName
                                 fitsSize:CGSizeMake(24, 24)
                                fillColor:PFBCustomTabBarIconColor()];
    } else {
        self.iconView.image = nil;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
}

+ (NSString*)reuseIdentifier {
    return @"PFBCustomTabBarPreviewCell";
}

@end
