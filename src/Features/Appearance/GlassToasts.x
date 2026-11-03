// Glass toasts: Twitter's toasts drawn as the tweak's capsule at the top, as wide as their words,
// the button on the right, on Liquid Glass or on the standard look's light capsule.

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

// The capsule's margin to the screen's sides, and the room around its content.
static const CGFloat kPFBGlassToastMargin = 16.0;
static const CGFloat kPFBGlassToastSideInset = 16.0;
static const CGFloat kPFBGlassToastTopInset = 8.0;
// Twitter's room around the content, as measured.
static const CGFloat kPFBGlassToastTwitterInset = 12.0;

static const void* kPFBGlassToastSurfaceKey = &kPFBGlassToastSurfaceKey;
static const void* kPFBGlassToastTwitterLookKey = &kPFBGlassToastTwitterLookKey;
static const void* kPFBGlassToastArrangedKey = &kPFBGlassToastArrangedKey;
static const void* kPFBGlassToastSideKey = &kPFBGlassToastSideKey;
static NSUInteger gPFBGlassToastsMeasured;

static BOOL PFBGlassToastsOn(void) {
    return [PFBSettings boolForKey:@"glass_toasts"];
}

// The content's column: the icon with the words, then the button.
static UIStackView* PFBGlassToastColumn(UIView* content) {
    for (UIView* view in content.subviews) {
        if ([view isKindOfClass:[UIStackView class]]) {
            UIStackView* column = (UIStackView*)view;
            return column.arrangedSubviews.count == 2 ? column : nil;
        }
    }
    return nil;
}

// The toast's content: the last one shown, as a new toast's content comes after the one it replaces.
static UIView* PFBGlassToastContentIn(UIView* container) {
    Class contentClass = NSClassFromString(@"XDSToastContentView");
    __block UIView* content = nil;
    PFBWalkAllSubviews(container, 4, ^(UIView* view) {
      if (contentClass && [view isKindOfClass:contentClass] && !view.hidden) {
          content = view;
      }
    });
    return content;
}

// The capsule's width: its content on one row with the room around it, within the margins.
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
    CGFloat inset = side ? side.doubleValue : kPFBGlassToastTwitterInset;
    CGFloat width = [column systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width + 2 * inset;
    return MIN(ceil(width), room);
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

// Twitter's chrome under the content: its dark blur and its shadow, nothing else.
static NSArray<UIView*>* PFBGlassToastChrome(UIView* container) {
    NSMutableArray<UIView*>* chrome = [NSMutableArray array];
    for (UIView* view in container.subviews) {
        if ([view respondsToSelector:@selector(setBlurHidden:)]) {
            [chrome addObject:view];
        }
    }
    return chrome;
}

// Twitter's look as it last set it: its color and corners. A solid color goes with its blur
// hidden, as on the error toast.
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
    UIColor* color = [look[@"color"] isKindOfClass:[UIColor class]] ? look[@"color"] : nil;
    CGFloat alpha = 0;
    [color getRed:NULL green:NULL blue:NULL alpha:&alpha];
    container.backgroundColor = color;
    container.layer.cornerRadius = [look[@"radius"] doubleValue];
    container.layer.cornerCurve = look[@"curve"] ?: kCACornerCurveCircular;
    for (UIView* chrome in PFBGlassToastChrome(container)) {
        chrome.hidden = NO;
        [(XDSToastContainerView*)chrome setBlurHidden:alpha >= 0.99];
    }
}

static NSString* PFBGlassToastColorText(UIColor* color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        return color ? @"pattern" : @"none";
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X/%.2f", (int)lround(r * 255), (int)lround(g * 255),
                                      (int)lround(b * 255), a];
}

static void PFBGlassToastDescribe(NSMutableString* text, UIView* view, NSInteger depth) {
    [text appendFormat:@"\n%@%@ %.0f,%.0f %.0fx%.0f", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
                       NSStringFromClass([view class]), CGRectGetMinX(view.frame), CGRectGetMinY(view.frame),
                       CGRectGetWidth(view.frame), CGRectGetHeight(view.frame)];
    if (view.hidden) {
        [text appendString:@" hidden"];
    }
    if (view.alpha < 1) {
        [text appendFormat:@" alpha %.2f", view.alpha];
    }
    if (view.layer.opacity < 1) {
        [text appendFormat:@" opacity %.2f", view.layer.opacity];
    }
    if (view.layer.cornerRadius > 0) {
        [text appendFormat:@" radius %.0f", view.layer.cornerRadius];
    }
    if (view.clipsToBounds || view.layer.masksToBounds) {
        [text appendString:@" clips"];
    }
    if (view.layer.mask || view.maskView) {
        [text appendString:@" mask"];
    }
    if (view.layer.filters.count || view.layer.compositingFilter) {
        [text appendString:@" filters"];
    }
    if (view.backgroundColor) {
        [text appendFormat:@" bg %@", PFBGlassToastColorText(view.backgroundColor)];
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        [text appendFormat:@" effect %@", NSStringFromClass([((UIVisualEffectView*)view).effect class])];
    }
    if ([view isKindOfClass:[UILabel class]]) {
        [text appendFormat:@" \"%@\"", ((UILabel*)view).text ?: @""];
    }
}

// The drawn capsule in the report, for the first toasts of a launch: the views above it up to the
// window, then each of its layers, recorded at once.
static void PFBGlassToastMeasure(UIView* container, CGFloat twitterWidth) {
    if (gPFBGlassToastsMeasured >= 3 || !container.window) {
        return;
    }
    gPFBGlassToastsMeasured++;
    UIView* content = PFBGlassToastContentIn(container);
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"Liquid Glass %@ · capsule %.0fx%.0f at %.0f,%.0f · Twitter's width %.0f · side room %@",
                         PFBShowcaseUsesGlass() ? @"on" : @"off", CGRectGetWidth(container.frame),
                         CGRectGetHeight(container.frame), CGRectGetMinX(container.frame),
                         CGRectGetMinY(container.frame), twitterWidth,
                         objc_getAssociatedObject(content, kPFBGlassToastSideKey) ?: @"not set"];
    [text appendString:@"\nabove:"];
    for (UIView* view = container.superview; view; view = view.superview) {
        PFBGlassToastDescribe(text, view, 1);
    }
    [text appendString:@"\ncapsule:"];
    NSMutableArray<NSArray*>* stack = [NSMutableArray arrayWithObject:@[ container, @1 ]];
    while (stack.count) {
        UIView* view = stack.lastObject[0];
        NSInteger depth = [stack.lastObject[1] integerValue];
        [stack removeLastObject];
        PFBGlassToastDescribe(text, view, depth);
        if (depth < 9 && ![view isKindOfClass:[UILabel class]] && ![view isKindOfClass:[UIButton class]]) {
            for (UIView* child in view.subviews.reverseObjectEnumerator) {
                [stack addObject:@[ child, @(depth + 1) ]];
            }
        }
    }
    PFBCompatMeasure([NSString stringWithFormat:@"glass toast %lu", (unsigned long)gPFBGlassToastsMeasured], text, 2);
}

// The container drawn as the capsule: the glass behind everything, Twitter's chrome put away,
// the corners round. With the option off, Twitter's look comes back.
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
        surface = glass;
        objc_setAssociatedObject(container, kPFBGlassToastSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (styled) {
        PFBGlassToastNoteTwitterLook(container, NO);
    }
    for (UIView* chrome in PFBGlassToastChrome(container)) {
        if (!chrome.hidden) {
            chrome.hidden = YES;
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
    TFNToastViewController* shower = [container respondsToSelector:@selector(toastViewController)]
                                         ? [(T1ToastContainerView*)container toastViewController]
                                         : nil;
    id toast = [shower respondsToSelector:@selector(currentToast)] ? [shower currentToast] : nil;
    PFBGlassToastColor(container, toast);
    if (styled) {
        // Twitter may size the toast before its new content is in: the width is set again from it.
        CGFloat twitterWidth = CGRectGetWidth(container.frame);
        if ([shower respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
            CGRect placement = [shower _tfn_toastHorizontalPlacementBounds];
            CGFloat width = PFBGlassToastWidth(container, placement, twitterWidth);
            if (fabs(width - twitterWidth) > 0.5) {
                CGRect frame = container.frame;
                frame.origin.x = CGRectGetMidX(placement) - width / 2.0;
                frame.size.width = width;
                container.frame = frame;
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          PFBGlassToastMeasure(container, twitterWidth);
        });
    }
    PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"toast drawn as the glass capsule");
}

%hook TFNToastViewController

- (double)_tfn_toastWidth {
    double width = %orig;
    if (!PFBGlassToastsOn() || ![self respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
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
    if (!PFBGlassToastsOn()) {
        return frame;
    }
    CGRect placement = [self _tfn_toastHorizontalPlacementBounds];
    CGFloat width = PFBGlassToastWidth([self toastContainerView], placement, CGRectGetWidth(frame));
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

// Twitter sets each toast's blur and color here, then lays it out: the capsule is drawn after both.
- (void)prepareForToastWithUpdatedStyle:(BOOL)updated {
    %orig;
    PFBGlassToastDress(self, YES);
}

- (void)layoutSubviews {
    %orig;
    PFBGlassToastDress(self, NO);
}

%end
