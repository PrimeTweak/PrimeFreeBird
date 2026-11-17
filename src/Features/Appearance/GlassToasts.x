// Glass toasts. On Twitter's own glass (12.44, Liquid Glass) the toast stays Twitter's: only its glass
// takes half the background color and its words the tab bar's gray. Otherwise the tweak's capsule at
// the top, as wide as its words, the button on the right.

#import "Support/HookHelpers.h"
#import "Support/TFNHeaders.h"
#import "Settings/Native/PFBShowcase.h"
#import "Common/PFBSettings.h"
#import "Common/PFBCompatibility.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"

// The hooked Twitter views, declared for the compiler.
@interface XDSToastContentView : UIView
@end

@interface T1ToastContainerView (PFBGlassToasts)
- (void)prepareForToastWithUpdatedStyle:(BOOL)updated;
- (void)setSurfaceColor:(UIColor*)color;
@end

@interface XDSToastContainerView (PFBGlassToasts)
- (UIView*)contentView;
@end

// Twitter's Liquid Glass view: its clear tint and its scrim are colors.
@interface XDSGlass : UIView
- (void)setClearTint:(UIColor*)tint scrimColor:(UIColor*)scrim;
@end

// The capsule's margin to the screen's sides, and the room around its content.
static const CGFloat kPFBGlassToastMargin = 16.0;
static const CGFloat kPFBGlassToastSideInset = 16.0;
static const CGFloat kPFBGlassToastTopInset = 8.0;
// Every capsule's height: two lines of words with the room above and below.
static const CGFloat kPFBGlassToastHeight = 52.0;
// Twitter's room on each side of a label in its words view, as measured.
static const CGFloat kPFBGlassToastLabelInset = 4.0;
// Twitter's room around the content, as measured.
static const CGFloat kPFBGlassToastTwitterInset = 12.0;
// The toast's glass tint: half the background color, the white the tab bar's glass shows over a light
// page (measured), with no scrim. The bar's own tint, 25 %, lets a dark page show through a toast.
static const CGFloat kPFBGlassToastTint = 0.5;

static const void* kPFBGlassToastSurfaceKey = &kPFBGlassToastSurfaceKey;
static const void* kPFBGlassToastTwitterLookKey = &kPFBGlassToastTwitterLookKey;
static const void* kPFBGlassToastArrangedKey = &kPFBGlassToastArrangedKey;
static const void* kPFBGlassToastSideKey = &kPFBGlassToastSideKey;
static const void* kPFBGlassToastTintedKey = &kPFBGlassToastTintedKey;
static const void* kPFBGlassToastLaidContentKey = &kPFBGlassToastLaidContentKey;

static BOOL PFBGlassToastsOn(void) {
    return [PFBSettings boolForKey:@"glass_toasts"];
}

// Twitter draws its toasts on its own glass, laid out its own way, while its Liquid Glass is on.
static BOOL PFBGlassToastNative(void) {
    return PFBNativeGlassAsked() && NSClassFromString(@"XDSToastContainerView") != nil;
}

static UIStackView* PFBGlassToastColumn(UIView* content) {
    for (UIView* view in content.subviews) {
        if ([view isKindOfClass:[UIStackView class]]) {
            UIStackView* column = (UIStackView*)view;
            return column.arrangedSubviews.count == 2 ? column : nil;
        }
    }
    return nil;
}

// The content as found from the container: the last one shown, as a new toast's content comes after
// the one it replaces.
static UIView* PFBGlassToastSearchContent(UIView* container) {
    Class contentClass = NSClassFromString(@"XDSToastContentView");
    __block UIView* content = nil;
    PFBWalkAllSubviews(container, 4, ^(UIView* view) {
      if (contentClass && [view isKindOfClass:contentClass] && !view.hidden) {
          content = view;
      }
    });
    return content;
}

// The toast's content: as found from the container, or else the one that last laid itself out
// inside it.
static UIView* PFBGlassToastContentIn(UIView* container) {
    UIView* content = PFBGlassToastSearchContent(container);
    UIView* laid = objc_getAssociatedObject(container, kPFBGlassToastLaidContentKey);
    if (!content && !laid.hidden && [laid isDescendantOfView:container]) {
        content = laid;
    }
    return content;
}

// The width the content takes on one row: each label's words on a single line, the icon, then
// the button. Labels are measured by their text, as Twitter may have wrapped them already.
static CGFloat PFBGlassToastContentWidth(UIStackView* column) {
    UIView* words = column.arrangedSubviews[0];
    UIView* holder = column.arrangedSubviews[1];
    __block CGFloat text = 0;
    PFBWalkAllSubviews(words, 8, ^(UIView* view) {
      if ([view isKindOfClass:[UILabel class]] && !view.hidden && ((UILabel*)view).text.length) {
          UILabel* label = (UILabel*)view;
          NSDictionary* font = @{NSFontAttributeName : label.font ?: [UIFont systemFontOfSize:16]};
          text = MAX(text, ceil([label.text sizeWithAttributes:font].width));
      }
    });
    CGFloat width = text + 2 * kPFBGlassToastLabelInset;
    if ([words isKindOfClass:[UIStackView class]]) {
        UIStackView* row = (UIStackView*)words;
        UIView* icon = row.arrangedSubviews.firstObject;
        if (row.arrangedSubviews.count == 2 && !icon.hidden) {
            width += [icon systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width + row.spacing;
        }
    }
    if (!holder.hidden) {
        __block CGFloat button = 0;
        PFBWalkAllSubviews(holder, 4, ^(UIView* view) {
          if (button == 0 && [view isKindOfClass:[UIButton class]]) {
              button = view.intrinsicContentSize.width;
          }
        });
        width += MAX(button, CGRectGetWidth(holder.bounds)) + column.spacing;
    }
    return width;
}

// The toast's width: its content on one row with the room around it, within the margins. The room
// is read from the last layout, as Twitter's glass adds its own since 12.44; the tweak's before any.
static CGFloat PFBGlassToastWidth(UIView* container, CGRect placement, CGFloat twitterWidth) {
    CGFloat room = CGRectGetWidth(placement) - 2 * kPFBGlassToastMargin;
    if (room <= 0) {
        return twitterWidth;
    }
    UIView* content = PFBGlassToastContentIn(container);
    UIStackView* column = PFBGlassToastColumn(content);
    if (!column) {
        return MIN(twitterWidth, room);
    }
    NSNumber* side = objc_getAssociatedObject(content, kPFBGlassToastSideKey);
    CGFloat around = 2 * (side ? side.doubleValue : kPFBGlassToastTwitterInset);
    CGFloat laid = CGRectGetWidth(column.bounds);
    if (laid > 0 && CGRectGetWidth(container.bounds) > laid) {
        around = CGRectGetWidth(container.bounds) - laid;
    }
    return MIN(ceil(PFBGlassToastContentWidth(column) + around), room);
}

// The words no longer fit the row the last layout gave them.
static BOOL PFBGlassToastCramped(UIView* container) {
    UIStackView* column = PFBGlassToastColumn(PFBGlassToastContentIn(container));
    CGFloat laid = CGRectGetWidth(column.bounds);
    return column && laid > 0 && PFBGlassToastContentWidth(column) > laid + 0.5;
}

// The capsule's height: the same for every toast, taller only for a larger text size or a picture
// that would not fit; 0 for a toast laid out otherwise, which keeps Twitter's height.
static CGFloat PFBGlassToastHeight(UIView* container) {
    UIStackView* column = PFBGlassToastColumn(PFBGlassToastContentIn(container));
    if (!column) {
        return 0;
    }
    UIView* words = column.arrangedSubviews.firstObject;
    __block CGFloat lines = 0;
    PFBWalkAllSubviews(words, 8, ^(UIView* view) {
      if ([view isKindOfClass:[UILabel class]] && !view.hidden && ((UILabel*)view).text.length) {
          lines += ((UILabel*)view).font.lineHeight;
      }
    });
    UIView* icon = [words isKindOfClass:[UIStackView class]] ? ((UIStackView*)words).arrangedSubviews.firstObject : nil;
    CGFloat picture = icon && !icon.hidden ? [icon systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height : 0;
    return MAX(kPFBGlassToastHeight, ceil(MAX(lines, picture)) + 2 * kPFBGlassToastTopInset);
}

static void PFBGlassToastSetPriority(UIView* view, UILayoutPriority priority) {
    UILayoutConstraintAxis axis = UILayoutConstraintAxisHorizontal;
    if ([view contentHuggingPriorityForAxis:axis] != priority) {
        [view setContentHuggingPriority:priority forAxis:axis];
    }
    if ([view contentCompressionResistancePriorityForAxis:axis] != priority) {
        [view setContentCompressionResistancePriority:priority forAxis:axis];
    }
}

// Twitter's room around the column becomes the capsule's: wider at the round ends, lower above
// and below. The side room in use is kept for the width.
static void PFBGlassToastInsets(UIView* content, UIStackView* column) {
    NSUInteger sides = 0;
    for (NSLayoutConstraint* constraint in content.constraints) {
        if (constraint.firstItem != column && constraint.secondItem != column) {
            continue;
        }
        NSLayoutAttribute attribute =
            constraint.firstItem == column ? constraint.firstAttribute : constraint.secondAttribute;
        CGFloat sign = constraint.constant < 0 ? -1.0 : 1.0;
        CGFloat inset = 0;
        if (attribute == NSLayoutAttributeLeading || attribute == NSLayoutAttributeTrailing ||
            attribute == NSLayoutAttributeLeft || attribute == NSLayoutAttributeRight) {
            inset = kPFBGlassToastSideInset;
        } else if (attribute == NSLayoutAttributeTop || attribute == NSLayoutAttributeBottom) {
            inset = kPFBGlassToastTopInset;
        }
        if (inset > 0 && fabs(constraint.constant) == kPFBGlassToastTwitterInset) {
            constraint.constant = sign * inset;
        }
        if (inset == kPFBGlassToastSideInset && fabs(constraint.constant) == kPFBGlassToastSideInset) {
            sides++;
        }
    }
    objc_setAssociatedObject(content, kPFBGlassToastSideKey,
                             @(sides == 2 ? kPFBGlassToastSideInset : kPFBGlassToastTwitterInset),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The column becomes a row: the words give way to the button, which keeps its whole title.
static void PFBGlassToastArrange(UIView* content) {
    UIStackView* column = PFBGlassToastColumn(content);
    if (!column) {
        return;
    }
    if (column.axis != UILayoutConstraintAxisHorizontal) {
        column.axis = UILayoutConstraintAxisHorizontal;
    }
    if (column.alignment != UIStackViewAlignmentCenter) {
        column.alignment = UIStackViewAlignmentCenter;
    }
    if (column.spacing != 16.0) {
        column.spacing = 16.0;
    }
    PFBGlassToastInsets(content, column);
    // One line each, so every capsule has the same height.
    PFBWalkAllSubviews(column.arrangedSubviews[0], 8, ^(UIView* view) {
      if ([view isKindOfClass:[UILabel class]]) {
          UILabel* label = (UILabel*)view;
          if (label.numberOfLines != 1) {
              label.numberOfLines = 1;
          }
          PFBGlassToastSetPriority(view, UILayoutPriorityDefaultLow);
      }
    });
    PFBGlassToastSetPriority(column.arrangedSubviews[1], UILayoutPriorityRequired);
    PFBWalkAllSubviews(column.arrangedSubviews[1], 8, ^(UIView* view) {
      if ([view isKindOfClass:[UIButton class]]) {
          PFBGlassToastSetPriority(view, UILayoutPriorityRequired);
      }
    });
    objc_setAssociatedObject(content, kPFBGlassToastArrangedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The icon's color: Twitter's green for a success, its red for an error, the text color otherwise.
static UIColor* PFBGlassToastIconColor(id toast) {
    NSString* icon = [toast respondsToSelector:@selector(iconName)] ? [toast iconName] : nil;
    if (![icon isKindOfClass:[NSString class]]) {
        return [UIColor labelColor];
    }
    if ([icon containsString:@"checkmark"]) {
        return [UIColor colorWithRed:0.0 green:186.0 / 255.0 blue:124.0 / 255.0 alpha:1.0];
    }
    if ([icon containsString:@"error"]) {
        return [UIColor colorWithRed:244.0 / 255.0 green:33.0 / 255.0 blue:46.0 / 255.0 alpha:1.0];
    }
    return [UIColor labelColor];
}

// On the capsule: the words in the text colors, the button as a plain one in the accent, the icon in
// its color. Each is set only when it differs, as this runs on every layout.
static void PFBGlassToastColor(UIView* container, id toast) {
    UIColor* iconColor = PFBGlassToastIconColor(toast);
    UIColor* accent = PFBCurrentAccentColor() ?: [UIColor systemBlueColor];
    PFBWalkAllSubviews(container, 12, ^(UIView* view) {
      if ([view isKindOfClass:[UIButton class]]) {
          UIButton* button = (UIButton*)view;
          if (![button.backgroundColor isEqual:[UIColor clearColor]]) {
              button.backgroundColor = [UIColor clearColor];
          }
          if (![[button titleColorForState:UIControlStateNormal] isEqual:accent]) {
              [button setTitleColor:accent forState:UIControlStateNormal];
          }
      } else if ([view isKindOfClass:[UILabel class]] && ![view.superview isKindOfClass:[UIButton class]]) {
          UILabel* label = (UILabel*)view;
          // Twitter sets the message larger than the line under it.
          UIColor* color = label.font.pointSize >= 15.5 ? [UIColor labelColor] : [UIColor secondaryLabelColor];
          if (![label.textColor isEqual:color]) {
              label.textColor = color;
          }
      } else if ([view isKindOfClass:[UIImageView class]] && CGRectGetWidth(view.bounds) <= 24.0 &&
                 ![view.tintColor isEqual:iconColor]) {
          view.tintColor = iconColor;
      }
    });
}

// How deep the toast's words are looked for: past Twitter's glass and the views that host its content.
static const NSInteger kPFBGlassToastWordsDepth = 16;

// On Twitter's glass, every word and icon in the gray its tab bar gives unselected tabs, the text
// color at 60 % (measured in the bar); the button keeps Twitter's shape. Set only when it differs.
static void PFBGlassToastGrayText(UIView* container) {
    UIColor* gray = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    PFBWalkAllSubviews(container, kPFBGlassToastWordsDepth, ^(UIView* view) {
      if ([view isKindOfClass:[UIButton class]]) {
          UIButton* button = (UIButton*)view;
          if (![[button titleColorForState:UIControlStateNormal] isEqual:gray]) {
              [button setTitleColor:gray forState:UIControlStateNormal];
          }
      } else if ([view isKindOfClass:[UILabel class]]) {
          UILabel* label = (UILabel*)view;
          if (![label.textColor isEqual:gray]) {
              label.textColor = gray;
          }
      } else if ([view isKindOfClass:[UIImageView class]] && CGRectGetWidth(view.bounds) <= 28.0 &&
                 ![view.tintColor isEqual:gray]) {
          view.tintColor = gray;
      }
    });
}

// Twitter's glass around the toast since 12.44: its chrome holds the content in a view inside the
// glass. nil when Twitter draws the toast otherwise.
static UIView* PFBGlassToastTwitterGlass(UIView* container) {
    Class chromeClass = NSClassFromString(@"XDSToastContainerView");
    Class glassClass = NSClassFromString(@"XDSGlass");
    for (UIView* chrome in container.subviews) {
        if (!chromeClass || !glassClass || ![chrome isKindOfClass:chromeClass] ||
            ![chrome respondsToSelector:@selector(contentView)]) {
            continue;
        }
        UIView* inside = [(XDSToastContainerView*)chrome contentView];
        UIView* glass = inside.superview;
        while (glass && glass != chrome && ![glass isKindOfClass:glassClass]) {
            glass = glass.superview;
        }
        if (glass && glass != chrome && [glass respondsToSelector:@selector(setClearTint:scrimColor:)]) {
            return glass;
        }
    }
    return nil;
}

// Twitter's glass given the toast's tint, once per toast style unless forced.
static void PFBGlassToastTint(UIView* glass, BOOL force) {
    if (!force && objc_getAssociatedObject(glass, kPFBGlassToastTintedKey)) {
        return;
    }
    UIColor* tint = [[PFBPalette currentBackgroundColor] colorWithAlphaComponent:kPFBGlassToastTint];
    [(XDSGlass*)glass setClearTint:tint scrimColor:[UIColor clearColor]];
    objc_setAssociatedObject(glass, kPFBGlassToastTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Twitter's look as it last set it: its color and corners.
static void PFBGlassToastNoteTwitterLook(UIView* container, BOOL corners) {
    NSMutableDictionary* look = objc_getAssociatedObject(container, kPFBGlassToastTwitterLookKey);
    if (!look) {
        look = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(container, kPFBGlassToastTwitterLookKey, look, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    look[@"color"] = container.backgroundColor ?: [NSNull null];
    if (corners) {
        look[@"radius"] = @(container.layer.cornerRadius);
        look[@"curve"] = container.layer.cornerCurve ?: kCACornerCurveCircular;
    }
}

static void PFBGlassToastRestore(UIView* container, UIView* surface) {
    [surface removeFromSuperview];
    objc_setAssociatedObject(container, kPFBGlassToastSurfaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary* look = objc_getAssociatedObject(container, kPFBGlassToastTwitterLookKey);
    container.backgroundColor = [look[@"color"] isKindOfClass:[UIColor class]] ? look[@"color"] : nil;
    container.layer.cornerRadius = [look[@"radius"] doubleValue];
    container.layer.cornerCurve = look[@"curve"] ?: kCACornerCurveCircular;
}

// The toaster showing this toast, which sizes and places it.
static TFNToastViewController* PFBGlassToastShower(UIView* container) {
    return [container respondsToSelector:@selector(toastViewController)] ? [(T1ToastContainerView*)container toastViewController]
                                                                         : nil;
}

// The toast sized again for its content, centered where Twitter places it.
static void PFBGlassToastFit(UIView* container) {
    TFNToastViewController* shower = PFBGlassToastShower(container);
    CGRect frame = container.frame;
    if (CGRectGetHeight(frame) <= 0 || ![shower respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        return;
    }
    CGRect placement = [shower _tfn_toastHorizontalPlacementBounds];
    CGFloat width = PFBGlassToastWidth(container, placement, CGRectGetWidth(frame));
    CGFloat height = PFBGlassToastHeight(container);
    height = height > 0 ? height : CGRectGetHeight(frame);
    if (fabs(width - CGRectGetWidth(frame)) > 0.5 || fabs(height - CGRectGetHeight(frame)) > 0.5) {
        frame.origin.x = CGRectGetMidX(placement) - width / 2.0;
        frame.size = CGSizeMake(width, height);
        container.frame = frame;
    }
}

// On Twitter's glass, Twitter's toast as it is, its glass tinted with half the background and its words gray.
// Without it, the container drawn as the capsule, the glass behind everything and the corners round.
// With the option off, Twitter's look comes back.
static void PFBGlassToastDress(UIView* container, BOOL styled) {
    UIView* surface = objc_getAssociatedObject(container, kPFBGlassToastSurfaceKey);
    UIView* twitterGlass = PFBGlassToastTwitterGlass(container);
    if (!PFBGlassToastsOn()) {
        if (surface) {
            // Twitter has just set this toast's color: it is the one given back.
            if (styled) {
                PFBGlassToastNoteTwitterLook(container, NO);
            }
            PFBGlassToastRestore(container, surface);
        }
        if (twitterGlass) {
            objc_setAssociatedObject(twitterGlass, kPFBGlassToastTintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        PFBCOMPAT_OBSERVE(PFBCompat_glass_toasts, @"Twitter's toast found");
        return;
    }
    TFNToastViewController* shower = PFBGlassToastShower(container);
    id toast = [shower respondsToSelector:@selector(currentToast)] ? [shower currentToast] : nil;
    if (twitterGlass || PFBGlassToastNative()) {
        // Twitter's toast is kept whole: its layout, size and place stay, the tweak's own glass goes.
        if (surface) {
            PFBGlassToastRestore(container, surface);
        }
        if (!twitterGlass) {
            PFBCOMPAT_OBSERVE(PFBCompat_glass_toasts, @"Twitter's toast without its glass");
            return;
        }
        PFBGlassToastTint(twitterGlass, styled);
        PFBGlassToastGrayText(container);
        PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"Twitter's toast tinted with half the background, words in the bar's gray");
        return;
    }
    if (!surface) {
        PFBGlassToastNoteTwitterLook(container, YES);
        PFBShowcaseSurface* glass = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        glass.userInteractionEnabled = NO;
        surface = glass;
        objc_setAssociatedObject(container, kPFBGlassToastSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (styled) {
        PFBGlassToastNoteTwitterLook(container, NO);
    }
    if (container.subviews.firstObject != surface) {
        [container insertSubview:surface atIndex:0];
    }
    if (!CGRectEqualToRect(surface.frame, container.bounds)) {
        surface.frame = container.bounds;
    }
    if (![container.backgroundColor isEqual:[UIColor clearColor]]) {
        container.backgroundColor = [UIColor clearColor];
    }
    CGFloat radius = CGRectGetHeight(container.bounds) / 2.0;
    if (container.layer.cornerRadius != radius) {
        container.layer.cornerRadius = radius;
        container.layer.cornerCurve = kCACornerCurveContinuous;
    }
    PFBGlassToastColor(container, toast);
    // A toast already placed may get new content, or words wider than its row: its size is set again.
    if (styled || PFBGlassToastCramped(container)) {
        PFBGlassToastFit(container);
    }
    PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"toast drawn as the glass capsule");
}

%hook TFNToastViewController

- (double)_tfn_toastWidth {
    double width = %orig;
    if (!PFBGlassToastsOn() || ![self respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        return width;
    }
    if (PFBGlassToastNative()) {
        return width;
    }
    return PFBGlassToastWidth([self toastContainerView], [self _tfn_toastHorizontalPlacementBounds], width);
}

- (CGRect)_tfn_toastContainerFrame {
    CGRect frame = %orig;
    if (![self respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        return frame;
    }
    PFBCompatReach(PFBCompatPath_glass_toast_width);
    if (!PFBGlassToastsOn() || PFBGlassToastNative()) {
        return frame;
    }
    CGRect placement = [self _tfn_toastHorizontalPlacementBounds];
    CGFloat width = PFBGlassToastWidth([self toastContainerView], placement, CGRectGetWidth(frame));
    frame.origin.x = CGRectGetMidX(placement) - width / 2.0;
    frame.size.width = width;
    CGFloat height = PFBGlassToastHeight([self toastContainerView]);
    if (height > 0) {
        frame.size.height = height;
    }
    return frame;
}

%end

%hook XDSToastContentView

- (id)initWithFrame:(CGRect)frame configuration:(id)configuration {
    XDSToastContentView* content = %orig;
    if (content && PFBGlassToastColumn(content)) {
        PFBCompatReach(PFBCompatPath_glass_toast_row);
        if (PFBGlassToastsOn() && !PFBGlassToastNative()) {
            PFBGlassToastArrange(content);
        }
    }
    return content;
}

// Twitter rebuilds part of its constraints here; the row is set again after it.
- (void)updateConstraints {
    %orig;
    if (objc_getAssociatedObject(self, kPFBGlassToastArrangedKey) && PFBGlassToastsOn()) {
        PFBGlassToastArrange(self);
    }
}

// On the capsule, words set after the toast was placed show here first: the content is noted on its
// toast, which is sized again when the words outgrow their row.
- (void)layoutSubviews {
    %orig;
    if (!PFBGlassToastsOn() || PFBGlassToastNative()) {
        return;
    }
    Class containerClass = NSClassFromString(@"T1ToastContainerView");
    UIView* container = self.superview;
    while (container && containerClass && ![container isKindOfClass:containerClass]) {
        container = container.superview;
    }
    if (!container || !containerClass) {
        return;
    }
    objc_setAssociatedObject(container, kPFBGlassToastLaidContentKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (PFBGlassToastCramped(container)) {
        PFBGlassToastFit(container);
    }
}

%end

%hook T1ToastContainerView

// Twitter sets each toast's look and color here, then lays it out: the toast is drawn after both.
- (void)prepareForToastWithUpdatedStyle:(BOOL)updated {
    %orig;
    PFBGlassToastDress(self, YES);
}

// Twitter tints its glass with the toast's color: the toast's tint is set again after it.
- (void)setSurfaceColor:(UIColor*)color {
    %orig;
    UIView* glass = PFBGlassToastsOn() ? PFBGlassToastTwitterGlass(self) : nil;
    if (glass) {
        PFBGlassToastTint(glass, YES);
    }
}

- (void)layoutSubviews {
    %orig;
    PFBGlassToastDress(self, NO);
}

%end
