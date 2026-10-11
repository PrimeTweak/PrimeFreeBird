#import <QuartzCore/QuartzCore.h>
#import "Support/PFBManager.h"
#import "Common/PFBSettings.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"
#import "Settings/PFBModernSettingsTabBarCell.h"
#import "Settings/PFBTabFlowView.h"

@interface PFBModernSettingsTabBarCell ()
@property (nonatomic, strong) UIView* box;
@property (nonatomic, strong) UILabel* captionLabel;
@property (nonatomic, strong) PFBTabFlowView* barContainer;
@property (nonatomic, strong) UIView* rule;
@property (nonatomic, strong) UILabel* hintLabel;
@property (nonatomic, strong) UILabel* countLabel;
@property (nonatomic, strong) NSMutableArray<UIButton*>* tabButtons;
@property (nonatomic, copy) NSString* hintText;
@end
@implementation PFBModernSettingsTabBarCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.preservesSuperviewLayoutMargins = NO;
        self.contentView.layoutMargins = UIEdgeInsetsZero;
        self.separatorInset = UIEdgeInsetsZero;
        self.backgroundColor = [PFBPalette currentBackgroundColor];
        self.tabButtons = [NSMutableArray array];

        self.box = [UIView new];
        self.box.translatesAutoresizingMaskIntoConstraints = NO;
        self.box.layer.cornerRadius = 16.0;
        self.box.layer.masksToBounds = YES;
        [self.contentView addSubview:self.box];

        self.captionLabel = [UILabel new];
        self.captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.captionLabel];

        self.barContainer = [PFBTabFlowView new];
        self.barContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.barContainer];

        self.rule = [UIView new];
        self.rule.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.rule];

        self.hintLabel = [UILabel new];
        self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.box addSubview:self.hintLabel];

        self.countLabel = [UILabel new];
        self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.countLabel.textAlignment = NSTextAlignmentCenter;
        self.countLabel.layer.cornerRadius = 11.0;
        self.countLabel.layer.masksToBounds = YES;
        [self.countLabel setContentHuggingPriority:UILayoutPriorityRequired
                                           forAxis:UILayoutConstraintAxisHorizontal];
        [self.countLabel
            setContentCompressionResistancePriority:UILayoutPriorityRequired
                                            forAxis:UILayoutConstraintAxisHorizontal];
        [self.box addSubview:self.countLabel];

        [NSLayoutConstraint activateConstraints:@[
            // Flush with the rows above: their title starts at 10 and their
            // switch ends at -10, so the box shares both edges.
            [self.box.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                   constant:10],
            [self.box.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                    constant:-10],
            [self.box.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [self.box.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                  constant:-18],

            [self.captionLabel.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                            constant:14],
            [self.captionLabel.topAnchor constraintEqualToAnchor:self.box.topAnchor constant:12],

            [self.barContainer.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                            constant:8],
            [self.barContainer.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                             constant:-8],
            [self.barContainer.topAnchor constraintEqualToAnchor:self.captionLabel.bottomAnchor
                                                        constant:6],

            // Inset like the text it separates, rather than edge to edge.
            [self.rule.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                    constant:14],
            [self.rule.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                     constant:-14],
            [self.rule.topAnchor constraintEqualToAnchor:self.barContainer.bottomAnchor
                                                constant:8],
            [self.rule.heightAnchor constraintEqualToConstant:1],

            [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.box.leadingAnchor
                                                         constant:14],
            [self.hintLabel.topAnchor constraintEqualToAnchor:self.rule.bottomAnchor constant:10],
            [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.box.bottomAnchor
                                                        constant:-12],

            [self.countLabel.trailingAnchor constraintEqualToAnchor:self.box.trailingAnchor
                                                           constant:-14],
            [self.countLabel.leadingAnchor
                constraintGreaterThanOrEqualToAnchor:self.hintLabel.trailingAnchor
                                            constant:8],
            [self.countLabel.centerYAnchor constraintEqualToAnchor:self.hintLabel.centerYAnchor],
            [self.countLabel.heightAnchor constraintEqualToConstant:22],
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)configureWithTabs:(NSArray<NSDictionary*>*)tabs
                  caption:(NSString*)caption
                     hint:(NSString*)hint {
    self.captionLabel.text = caption;
    self.hintLabel.text = hint;
    if (self.tabButtons.count != tabs.count) {
        for (UIButton* old in self.tabButtons) {
            [old removeFromSuperview];
        }
        [self.tabButtons removeAllObjects];
        for (NSUInteger i = 0; i < tabs.count; i++) {
            UIButton* tab = [UIButton buttonWithType:UIButtonTypeCustom];
            [self.barContainer addSubview:tab];
            [self.tabButtons addObject:tab];
        }
    }
    [tabs enumerateObjectsUsingBlock:^(NSDictionary* tab, NSUInteger i, BOOL* stop) {
      UIButton* button = self.tabButtons[i];
      objc_setAssociatedObject(button, @"tabKey", tab[@"key"],
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      objc_setAssociatedObject(button, @"tabName", tab[@"name"],
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)setCountText:(NSString*)text {
    self.countLabel.text = [NSString stringWithFormat:@"  %@  ", text];
}

// A cell can be recycled while a refusal is still on screen. Without this the
// next row it serves would open with the count invisible and a red line under
// tabs that were never touched.
- (void)prepareForReuse {
    [super prepareForReuse];
    if (self.hintText) {
        self.hintLabel.text = self.hintText;
        self.hintText = nil;
    }
    self.countLabel.alpha = 1.0;
    self.countLabel.transform = CGAffineTransformIdentity;
    [self applyTheme];
}

- (void)refuseTab:(UIButton*)tab withMessage:(NSString*)message {
    if (!self.hintText) {
        self.hintText = self.hintLabel.text;
    }
    self.hintLabel.text = message;
    // The count fades and shrinks while the message shows, and returns with the
    // hint. Its constraints stay active, so the message keeps the same width.
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.countLabel.alpha = 0.0;
                       self.countLabel.transform = CGAffineTransformMakeScale(0.85, 0.85);
                     }];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id colorPalette =
        [[[TAEColorSettingsCls sharedSettings] currentColorPalette] colorPalette];
    self.hintLabel.textColor =
        [colorPalette performSelector:@selector(alertColor)];

    CAKeyframeAnimation* nudge =
        [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    nudge.values = @[ @0, @(-4), @4, @(-2), @0 ];
    nudge.duration = 0.32;
    [tab.layer addAnimation:nudge forKey:@"pfbRefuse"];

    __weak __typeof(self) weakSelf = self;
    NSString* restore = self.hintText;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     __typeof(self) strongSelf = weakSelf;
                     if (!strongSelf ||
                         ![strongSelf.hintLabel.text isEqualToString:message]) {
                         return;
                     }
                     strongSelf.hintLabel.text = restore;
                     [strongSelf applyTheme];
                     [UIView animateWithDuration:0.2
                                      animations:^{
                                        strongSelf.countLabel.alpha = 1.0;
                                        strongSelf.countLabel.transform =
                                            CGAffineTransformIdentity;
                                      }];
                   });
}

- (void)addTabTarget:(id)target action:(SEL)action {
    for (UIButton* tab in self.tabButtons) {
        [tab removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [tab addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)applyTheme {
    id fontGroup = [PFBManager sharedFontGroup];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor* soft = [colorPalette performSelector:@selector(tabBarItemColor)];
    UIColor* faint = [colorPalette performSelector:@selector(faintBackgroundColor)];
    UIColor* divider = [colorPalette performSelector:@selector(dividerColor)];

    self.box.backgroundColor = faint;
    self.rule.backgroundColor = divider;
    self.captionLabel.font = [fontGroup performSelector:@selector(subtext3BoldFont)];
    self.captionLabel.textColor = soft;
    self.hintLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.hintLabel.textColor = soft;
    self.countLabel.font = [fontGroup performSelector:@selector(subtext2BoldFont)];
    self.countLabel.textColor = soft;
    self.countLabel.backgroundColor = [PFBPalette currentBackgroundColor];
    [self refreshTabs];
}

- (void)refreshTabs {
    id fontGroup = [PFBManager sharedFontGroup];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    UIColor* ink = [colorPalette performSelector:@selector(textColor)];
    UIColor* soft = [colorPalette performSelector:@selector(tabBarItemColor)];

    for (UIButton* tab in self.tabButtons) {
        NSString* name = objc_getAssociatedObject(tab, @"tabName") ?: @"";
        NSString* key = objc_getAssociatedObject(tab, @"tabKey");
        BOOL hidden = key ? [PFBSettings boolForKey:key] : NO;
        NSMutableAttributedString* label = [[NSMutableAttributedString alloc]
            initWithString:name
                attributes:@{
                  NSFontAttributeName :
                      [fontGroup performSelector:@selector(subtext1BoldFont)],
                  NSForegroundColorAttributeName : hidden ? soft : ink
                }];
        if (hidden) {
            [label addAttribute:NSStrikethroughStyleAttributeName
                          value:@(NSUnderlineStyleSingle)
                          range:NSMakeRange(0, name.length)];
            [label addAttribute:NSStrikethroughColorAttributeName
                          value:soft
                          range:NSMakeRange(0, name.length)];
        }
        [tab setAttributedTitle:label forState:UIControlStateNormal];
        tab.alpha = hidden ? 0.45 : 1.0;
        tab.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    }
    [self setNeedsLayout];
}

@end
