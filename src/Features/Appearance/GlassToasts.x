// Glass toasts: Twitter's toasts drawn as the tweak's bar at the top, across the width, the words
// beside the icon and the button on the right, on glass or on the standard look's light capsule.

#import "Support/HookHelpers.h"
#import "Support/TFNHeaders.h"
#import "Settings/Native/PFBShowcase.h"
#import "Common/PFBSettings.h"
#import "Common/PFBCompatibility.h"

// The hooked Twitter views, declared for the compiler.
@interface XDSToastContentView : UIView
@end

@interface T1ToastContainerView (PFBGlassToasts)
- (void)prepareForToastWithUpdatedStyle:(BOOL)updated;
@end

// The bar's margin to the screen's sides, and its widest on a large screen.
static const CGFloat kPFBGlassToastMargin = 16.0;
static const CGFloat kPFBGlassToastMaxWidth = 560.0;

static const void* kPFBGlassToastSurfaceKey = &kPFBGlassToastSurfaceKey;
static const void* kPFBGlassToastVeilKey = &kPFBGlassToastVeilKey;
static const void* kPFBGlassToastTwitterLookKey = &kPFBGlassToastTwitterLookKey;
static const void* kPFBGlassToastArrangedKey = &kPFBGlassToastArrangedKey;

static BOOL PFBGlassToastsOn(void) {
    return [PFBSettings boolForKey:@"glass_toasts"];
}

// The bar's width in the room Twitter places its toasts in: never narrower than Twitter's own,
// never past the margins.
static CGFloat PFBGlassToastWidth(CGRect placement, CGFloat twitterWidth) {
    CGFloat room = CGRectGetWidth(placement) - 2 * kPFBGlassToastMargin;
    if (room <= 0) {
        return twitterWidth;
    }
    return MIN(MAX(MIN(room, kPFBGlassToastMaxWidth), twitterWidth), room);
}

// The content's column of two: the icon with the words, then the button.
static UIStackView* PFBGlassToastColumn(UIView* content) {
    for (UIView* view in content.subviews) {
        if ([view isKindOfClass:[UIStackView class]]) {
            UIStackView* column = (UIStackView*)view;
            return column.arrangedSubviews.count == 2 ? column : nil;
        }
    }
    return nil;
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
    if (column.spacing != 12.0) {
        column.spacing = 12.0;
    }
    PFBWalkAllSubviews(column.arrangedSubviews[0], 8, ^(UIView* view) {
      if ([view isKindOfClass:[UILabel class]]) {
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

// The words in the text colors, the button as a plain one in the accent, the icon in its color;
// each set only when it differs, as this runs on every layout.
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

static NSArray<UIView*>* PFBGlassToastChrome(UIView* container) {
    NSMutableArray<UIView*>* chrome = [NSMutableArray array];
    for (UIView* view in container.subviews) {
        if ([view respondsToSelector:@selector(setBlurHidden:)]) {
            [chrome addObject:view];
        }
    }
    return chrome;
}

// Twitter's look as it last set it: its color, corners and shadow. A solid color goes with its
// blur hidden, as on the error toast.
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
        look[@"shadow"] = @(PFBGlassToastChrome(container).firstObject.layer.shadowOpacity);
    }
}

static void PFBGlassToastRestore(UIView* container, UIView* surface) {
    [surface removeFromSuperview];
    objc_setAssociatedObject(container, kPFBGlassToastSurfaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(container, kPFBGlassToastVeilKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary* look = objc_getAssociatedObject(container, kPFBGlassToastTwitterLookKey);
    UIColor* color = [look[@"color"] isKindOfClass:[UIColor class]] ? look[@"color"] : nil;
    CGFloat alpha = 0;
    [color getRed:NULL green:NULL blue:NULL alpha:&alpha];
    container.backgroundColor = color;
    container.layer.cornerRadius = [look[@"radius"] doubleValue];
    container.layer.cornerCurve = look[@"curve"] ?: kCACornerCurveCircular;
    for (UIView* chrome in PFBGlassToastChrome(container)) {
        chrome.layer.shadowOpacity = [look[@"shadow"] floatValue];
        [(XDSToastContainerView*)chrome setBlurHidden:alpha >= 0.99];
    }
}

// The container drawn as the bar: the glass behind everything, Twitter's blur, shadow and error
// red put away, the corners round. With the option off, Twitter's look comes back.
static void PFBGlassToastDress(UIView* container, BOOL styled) {
    UIView* surface = objc_getAssociatedObject(container, kPFBGlassToastSurfaceKey);
    if (!PFBGlassToastsOn()) {
        if (surface) {
            // Twitter has just set this toast's color and blur: they are the ones given back.
            if (styled) {
                PFBGlassToastNoteTwitterLook(container, NO);
            }
            PFBGlassToastRestore(container, surface);
        }
        PFBCOMPAT_OBSERVE(PFBCompat_glass_toasts, @"Twitter's toast found");
        return;
    }
    if (!surface) {
        PFBGlassToastNoteTwitterLook(container, YES);
        PFBShowcaseSurface* glass = [[PFBShowcaseSurface alloc] initWithCornerRadius:-1];
        glass.userInteractionEnabled = NO;
        // Under glass, a veil keeps the words readable over a busy picture.
        if (PFBShowcaseUsesGlass()) {
            UIView* veil = [[UIView alloc] initWithFrame:glass.contentView.bounds];
            veil.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            veil.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.55];
            veil.userInteractionEnabled = NO;
            veil.layer.cornerCurve = kCACornerCurveContinuous;
            [glass.contentView addSubview:veil];
            objc_setAssociatedObject(container, kPFBGlassToastVeilKey, veil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        surface = glass;
        objc_setAssociatedObject(container, kPFBGlassToastSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        styled = YES;
    } else if (styled) {
        PFBGlassToastNoteTwitterLook(container, NO);
    }
    if (styled) {
        for (UIView* chrome in PFBGlassToastChrome(container)) {
            chrome.layer.shadowOpacity = 0;
            [(XDSToastContainerView*)chrome setBlurHidden:YES];
        }
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
    UIView* veil = objc_getAssociatedObject(container, kPFBGlassToastVeilKey);
    if (veil.layer.cornerRadius != radius) {
        veil.layer.cornerRadius = radius;
    }
    TFNToastViewController* shower = [container respondsToSelector:@selector(toastViewController)]
                                         ? [(T1ToastContainerView*)container toastViewController]
                                         : nil;
    id toast = [shower respondsToSelector:@selector(currentToast)] ? [shower currentToast] : nil;
    PFBGlassToastColor(container, toast);
    PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"toast drawn as the glass bar");
}

%hook TFNToastViewController

- (double)_tfn_toastWidth {
    double width = %orig;
    if (!PFBGlassToastsOn() || ![self respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        return width;
    }
    return PFBGlassToastWidth([self _tfn_toastHorizontalPlacementBounds], width);
}

- (CGRect)_tfn_toastContainerFrame {
    CGRect frame = %orig;
    if (![self respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        return frame;
    }
    PFBCompatReach(PFBCompatPath_glass_toast_width);
    if (!PFBGlassToastsOn()) {
        return frame;
    }
    CGRect placement = [self _tfn_toastHorizontalPlacementBounds];
    CGFloat width = PFBGlassToastWidth(placement, CGRectGetWidth(frame));
    frame.origin.x = CGRectGetMidX(placement) - width / 2.0;
    frame.size.width = width;
    return frame;
}

%end

%hook XDSToastContentView

- (id)initWithFrame:(CGRect)frame configuration:(id)configuration {
    XDSToastContentView* content = %orig;
    if (content && PFBGlassToastColumn(content)) {
        PFBCompatReach(PFBCompatPath_glass_toast_row);
        if (PFBGlassToastsOn()) {
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

%end

%hook T1ToastContainerView

// Twitter sets each toast's blur and color here, then lays it out: the bar is drawn after both.
- (void)prepareForToastWithUpdatedStyle:(BOOL)updated {
    %orig;
    PFBGlassToastDress(self, YES);
}

- (void)layoutSubviews {
    %orig;
    PFBGlassToastDress(self, NO);
}

%end
