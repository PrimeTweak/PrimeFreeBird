#import "Common/PFBCompatibility.h"
#import "Support/PFBManager.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Support/TwitterChirpFont.h"
#import "Debug/PFBDebugger.h"
#import "Settings/PFBModernSettingsSessionCardCell.h"

@interface PFBModernSettingsSessionCardCell ()
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* avatarLabel;
@property (nonatomic, strong) UIImageView* avatarImage;
@property (nonatomic, strong) NSURL* avatarURL;
@property (nonatomic, strong) UILabel* handleLabel;
@property (nonatomic, strong) UILabel* detailLabel;
@property (nonatomic, strong) UIView* stateDot;
@property (nonatomic, strong) UIButton* primaryButton;
@property (nonatomic, strong) UIButton* destructiveButton;
@property (nonatomic, assign) BOOL signedIn;
@end
@implementation PFBModernSettingsSessionCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;
        self.backgroundColor = [PFBPalette currentBackgroundColor];

        self.box = [UIView new];
        self.box.translatesAutoresizingMaskIntoConstraints = NO;
        self.box.layer.cornerRadius = 16.0;
        self.box.layer.masksToBounds = YES;
        [self.contentView addSubview:self.box];

        self.avatarLabel = [UILabel new];
        self.avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarLabel.textAlignment = NSTextAlignmentCenter;
        self.avatarLabel.layer.cornerRadius = 20.0;
        self.avatarLabel.layer.masksToBounds = YES;
        [self.box addSubview:self.avatarLabel];

        // The account's photo sits over the initial, which shows until it loads.
        self.avatarImage = [UIImageView new];
        self.avatarImage.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarImage.contentMode = UIViewContentModeScaleAspectFill;
        self.avatarImage.layer.cornerRadius = 20.0;
        self.avatarImage.layer.masksToBounds = YES;
        self.avatarImage.alpha = 0.0;
        [self.box addSubview:self.avatarImage];

        self.handleLabel = [UILabel new];
        self.handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.handleLabel];

        self.detailLabel = [UILabel new];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.numberOfLines = 0;
        [self.box addSubview:self.detailLabel];

        self.stateDot = [UIView new];
        self.stateDot.translatesAutoresizingMaskIntoConstraints = NO;
        self.stateDot.layer.cornerRadius = 4.5;
        [self.box addSubview:self.stateDot];

        self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.primaryButton.layer.cornerRadius = 11.0;
        self.primaryButton.layer.masksToBounds = YES;
        [self.box addSubview:self.primaryButton];

        self.destructiveButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.destructiveButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.destructiveButton.layer.cornerRadius = 11.0;
        self.destructiveButton.layer.masksToBounds = YES;
        [self.box addSubview:self.destructiveButton];

        [NSLayoutConstraint activateConstraints:@[
            [self.box.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                   constant:10],
            [self.box.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                    constant:-10],
            [self.box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [self.box.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                  constant:-6],

            [self.avatarLabel.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                           constant:14],
            [self.avatarLabel.topAnchor constraintEqualToAnchor:self.box.topAnchor constant:13],
            [self.avatarLabel.widthAnchor constraintEqualToConstant:40],
            [self.avatarLabel.heightAnchor constraintEqualToConstant:40],
            [self.avatarImage.leadingAnchor constraintEqualToAnchor:self.avatarLabel.leadingAnchor],
            [self.avatarImage.trailingAnchor constraintEqualToAnchor:self.avatarLabel.trailingAnchor],
            [self.avatarImage.topAnchor constraintEqualToAnchor:self.avatarLabel.topAnchor],
            [self.avatarImage.bottomAnchor constraintEqualToAnchor:self.avatarLabel.bottomAnchor],

            [self.handleLabel.leadingAnchor constraintEqualToAnchor:self.avatarLabel.trailingAnchor
                                                           constant:11],
            [self.handleLabel.topAnchor constraintEqualToAnchor:self.avatarLabel.topAnchor
                                                       constant:0],
            [self.handleLabel.trailingAnchor constraintEqualToAnchor:self.stateDot.leadingAnchor
                                                            constant:-10],

            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.handleLabel.leadingAnchor],
            [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.stateDot.leadingAnchor
                                                            constant:-10],
            [self.detailLabel.topAnchor constraintEqualToAnchor:self.handleLabel.bottomAnchor
                                                       constant:2],

            [self.stateDot.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                         constant:-14],
            [self.stateDot.centerYAnchor constraintEqualToAnchor:self.avatarLabel.centerYAnchor],
            [self.stateDot.widthAnchor constraintEqualToConstant:9],
            [self.stateDot.heightAnchor constraintEqualToConstant:9],

            [self.primaryButton.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                             constant:14],
            [self.primaryButton.topAnchor
                constraintGreaterThanOrEqualToAnchor:self.detailLabel.bottomAnchor
                                            constant:12],
            [self.primaryButton.topAnchor
                constraintGreaterThanOrEqualToAnchor:self.avatarLabel.bottomAnchor
                                            constant:12],
            [self.primaryButton.bottomAnchor constraintEqualToAnchor:self.box.bottomAnchor
                                                            constant:-13],
            [self.primaryButton.heightAnchor constraintEqualToConstant:38],

            [self.destructiveButton.leadingAnchor
                constraintEqualToAnchor:self.primaryButton.trailingAnchor
                               constant:8],
            [self.destructiveButton.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                                  constant:-14],
            [self.destructiveButton.topAnchor constraintEqualToAnchor:self.primaryButton.topAnchor],
            [self.destructiveButton.heightAnchor constraintEqualToConstant:38],
            [self.destructiveButton.widthAnchor
                constraintEqualToAnchor:self.primaryButton.widthAnchor],
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)configureWithHandle:(NSString*)handle
                   signedIn:(BOOL)signedIn
                     detail:(NSString*)detail
               primaryTitle:(NSString*)primaryTitle
           destructiveTitle:(NSString*)destructiveTitle {
    self.signedIn = signedIn;
    self.handleLabel.text = handle;
    self.detailLabel.text = detail;
    self.avatarLabel.text =
        handle.length > 1 ? [[handle substringWithRange:NSMakeRange(1, 1)] uppercaseString] : @"?";
    [self.primaryButton setTitle:primaryTitle forState:UIControlStateNormal];
    [self.destructiveButton setTitle:destructiveTitle forState:UIControlStateNormal];
    self.destructiveButton.enabled = signedIn;
    [self applyTheme];
}

// Kept for the session: the card is redrawn every time the page reloads.
static NSCache* PFBAvatarCache(void) {
    static NSCache* cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      cache = [NSCache new];
    });
    return cache;
}

// No address, or a failed download, leaves the initial in place.
- (void)loadAvatarFromURL:(NSURL*)url {
    self.avatarURL = url;
    UIImage* cached = url ? [PFBAvatarCache() objectForKey:url] : nil;
    self.avatarImage.image = cached;
    self.avatarImage.alpha = cached ? 1.0 : 0.0;
    if (!url || cached) {
        return;
    }
    __weak PFBModernSettingsSessionCardCell* weakSelf = self;
    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
          dataTaskWithURL:url
        completionHandler:^(NSData* data, __unused NSURLResponse* response,
                            __unused NSError* error) {
          UIImage* image = data.length ? [UIImage imageWithData:data] : nil;
          dispatch_async(dispatch_get_main_queue(), ^{
            if (!image) {
                PFBDebugLog(@"[session] avatar download failed");
                return;
            }
            [PFBAvatarCache() setObject:image forKey:url];
            PFBModernSettingsSessionCardCell* cell = weakSelf;
            // A reused cell may belong to another account by now.
            if (![cell.avatarURL isEqual:url]) {
                return;
            }
            cell.avatarImage.image = image;
            [UIView animateWithDuration:0.2
                             animations:^{
                               cell.avatarImage.alpha = 1.0;
                             }];
          });
        }];
    [task resume];
}

- (void)addPrimaryTarget:(id)target action:(SEL)action {
    [self.primaryButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self.primaryButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

- (void)addDestructiveTarget:(id)target action:(SEL)action {
    [self.destructiveButton removeTarget:nil
                                  action:NULL
                        forControlEvents:UIControlEventTouchUpInside];
    [self.destructiveButton addTarget:target
                               action:action
                     forControlEvents:UIControlEventTouchUpInside];
}

- (void)applyTheme {
    id fontGroup = [PFBManager sharedFontGroup];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id colorPalette =
        [[[TAEColorSettingsCls sharedSettings] currentColorPalette] colorPalette];
    UIColor* ink = [colorPalette performSelector:@selector(textColor)];
    UIColor* soft = [colorPalette performSelector:@selector(tabBarItemColor)];
    UIColor* faint = [colorPalette performSelector:@selector(faintBackgroundColor)];
    UIColor* alert = [colorPalette performSelector:@selector(alertColor)];
    UIColor* accent = [colorPalette performSelector:@selector(primaryColor)];

    self.backgroundColor = [PFBPalette currentBackgroundColor];
    self.box.backgroundColor = faint;
    self.avatarLabel.backgroundColor = accent;
    self.avatarLabel.textColor = [UIColor whiteColor];
    // Drawn with a system font: a single letter needs no type ramp or font-group lookup.
    self.avatarLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy];
    self.handleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.handleLabel.textColor = ink;
    self.detailLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.detailLabel.textColor = soft;
    self.stateDot.backgroundColor =
        self.signedIn ? [UIColor systemGreenColor] : [colorPalette performSelector:@selector(dividerColor)];

    UIFont* actionFont = [fontGroup performSelector:@selector(subtext1BoldFont)];
    for (UIButton* button in @[ self.primaryButton, self.destructiveButton ]) {
        button.titleLabel.font = actionFont;
        button.backgroundColor = [PFBPalette currentBackgroundColor];
    }
    [self.primaryButton setTitleColor:ink forState:UIControlStateNormal];
    [self.destructiveButton setTitleColor:alert forState:UIControlStateNormal];
    [self.destructiveButton setTitleColor:soft forState:UIControlStateDisabled];
}

@end
