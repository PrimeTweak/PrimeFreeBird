// Glass toasts. On Twitter's own glass (12.44, Liquid Glass) the toast stays Twitter's: its glass takes
// 65 % of the background color, its button a light pill and its words the tab bar's gray. Otherwise the
// tweak's capsule at the top, as wide as its words, the button on the right.

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
// The toast's glass tint, with no scrim: 65 % of the background color, chosen on renders so its words
// read over any page. The bar's own tint, 25 %, lets a dark page show through a toast.
static const CGFloat kPFBGlassToastTint = 0.65;
// The button's pill: the background color at 85 %, in the shape Twitter gives its gray one.
static const CGFloat kPFBGlassToastButtonFill = 0.85;

static const void* kPFBGlassToastSurfaceKey = &kPFBGlassToastSurfaceKey;
static const void* kPFBGlassToastTwitterLookKey = &kPFBGlassToastTwitterLookKey;
static const void* kPFBGlassToastArrangedKey = &kPFBGlassToastArrangedKey;
static const void* kPFBGlassToastSideKey = &kPFBGlassToastSideKey;
static const void* kPFBGlassToastTintedKey = &kPFBGlassToastTintedKey;
static const void* kPFBGlassToastLaidContentKey = &kPFBGlassToastLaidContentKey;
static const void* kPFBGlassToastButtonColorKey = &kPFBGlassToastButtonColorKey;

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

// Twitter's toast button: a UIButton whose pill is its own background color and corners (read in the
// binary). nil when the toast has none.
static UIButton* PFBGlassToastButton(UIView* container) {
    Class contentClass = NSClassFromString(@"XDSToastContentView");
    Ivar ivar = contentClass ? class_getInstanceVariable(contentClass, "alternateActionButton") : NULL;
    if (!ivar) {
        PFBCompatNoteFailure(PFBCompat_glass_toasts, @"Twitter's toast button not found");
        return nil;
    }
    __block UIButton* button = nil;
    PFBWalkAllSubviews(container, kPFBGlassToastWordsDepth, ^(UIView* view) {
      id part = !button && [view isKindOfClass:contentClass] ? object_getIvar(view, ivar) : nil;
      if ([part isKindOfClass:[UIButton class]]) {
          button = part;
      }
    });
    return button;
}

// The button on its light pill; off, Twitter's own color comes back.
static void PFBGlassToastButtonPill(UIView* container, BOOL light) {
    UIButton* button = PFBGlassToastButton(container);
    if (!button) {
        return;
    }
    PFBCompatReach(PFBCompatPath_glass_toast_button);
    id twitterColor = objc_getAssociatedObject(button, kPFBGlassToastButtonColorKey);
    if (!light) {
        if (twitterColor) {
            button.backgroundColor = [twitterColor isKindOfClass:[UIColor class]] ? twitterColor : nil;
            objc_setAssociatedObject(button, kPFBGlassToastButtonColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!twitterColor) {
        objc_setAssociatedObject(button, kPFBGlassToastButtonColorKey, button.backgroundColor ?: [NSNull null],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor* fill = [[PFBPalette currentBackgroundColor] colorWithAlphaComponent:kPFBGlassToastButtonFill];
    if (![button.backgroundColor isEqual:fill]) {
        button.backgroundColor = fill;
    }
}

// [toastprobe] Set while the tweak tints the glass, so the calls Twitter makes are told apart.
static BOOL gPFBToastProbeOurs;
// [toastprobe] The scrim tried on the toast: the background color at 60 %.
static const CGFloat kPFBToastProbeScrim = 0.6;

// Twitter's glass given the toast's tint, once per toast style unless forced.
static void PFBGlassToastTint(UIView* glass, BOOL force) {
    if (!force && objc_getAssociatedObject(glass, kPFBGlassToastTintedKey)) {
        return;
    }
    UIColor* tint = [[PFBPalette currentBackgroundColor] colorWithAlphaComponent:kPFBGlassToastTint];
    UIColor* scrim = [[PFBPalette currentBackgroundColor] colorWithAlphaComponent:kPFBToastProbeScrim];
    gPFBToastProbeOurs = YES;
    [(XDSGlass*)glass setClearTint:tint scrimColor:scrim];
    gPFBToastProbeOurs = NO;
    objc_setAssociatedObject(glass, kPFBGlassToastTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// [toastprobe] A color as red, green, blue on 255 and its alpha, resolved for the screen's look.
static NSString* PFBToastProbeColor(id color) {
    if (![color isKindOfClass:[UIColor class]]) {
        return color ? NSStringFromClass([color class]) : @"none";
    }
    UIColor* resolved = [(UIColor*)color resolvedColorWithTraitCollection:UITraitCollection.currentTraitCollection];
    CGFloat r = 0, g = 0, b = 0, a = 0, w = 0;
    if ([resolved getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"%.0f,%.0f,%.0f/%.2f", r * 255, g * 255, b * 255, a];
    }
    if ([resolved getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"%.0f/%.2f", w * 255, a];
    }
    return resolved.description;
}

// [toastprobe] A layer's filters and blend, by name.
static NSString* PFBToastProbeFilters(CALayer* layer) {
    NSMutableArray* names = [NSMutableArray array];
    for (id filter in layer.filters ?: @[]) {
        id name = [filter respondsToSelector:@selector(name)] ? [filter performSelector:@selector(name)] : nil;
        [names addObject:[name description] ?: NSStringFromClass([filter class])];
    }
    NSString* blend = layer.compositingFilter ? [layer.compositingFilter description] : @"-";
    return [NSString stringWithFormat:@"filters=%@ blend=%@", names.count ? [names componentsJoinedByString:@","] : @"-",
                                      [blend substringToIndex:MIN(blend.length, (NSUInteger)40)]];
}

static NSString* PFBToastProbeLayerLine(CALayer* layer) {
    return [NSString stringWithFormat:@"%@ op=%.2f bg=%@ r=%.1f %@ clip=%d mask=%@ %@", NSStringFromCGRect(layer.frame),
                                      layer.opacity,
                                      layer.backgroundColor ? PFBToastProbeColor([UIColor colorWithCGColor:layer.backgroundColor]) : @"-",
                                      layer.cornerRadius, layer.cornerCurve, layer.masksToBounds,
                                      layer.mask ? NSStringFromClass([layer.mask class]) : @"-", PFBToastProbeFilters(layer)];
}

// [toastprobe] One view of the glass, then its own extra layers, then its subviews.
static void PFBToastProbeWalk(UIView* view, NSUInteger depth, NSString* topic, NSUInteger* index) {
    NSString* extra = @"";
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        NSString* effect = [((UIVisualEffectView*)view).effect description] ?: @"none";
        extra = [@" effect=" stringByAppendingString:[effect substringToIndex:MIN(effect.length, (NSUInteger)160)]];
    }
    PFBCompatMeasure(topic, [NSString stringWithFormat:@"%02lu d%lu %@ a=%.2f hid=%d bg=%@ %@%@", (unsigned long)(*index)++,
                                                       (unsigned long)depth, NSStringFromClass([view class]), view.alpha,
                                                       view.hidden, PFBToastProbeColor(view.backgroundColor),
                                                       PFBToastProbeLayerLine(view.layer), extra],
                     70);
    NSMutableSet* viewLayers = [NSMutableSet set];
    for (UIView* sub in view.subviews) {
        [viewLayers addObject:[NSValue valueWithNonretainedObject:sub.layer]];
    }
    for (CALayer* sub in view.layer.sublayers) {
        if (![viewLayers containsObject:[NSValue valueWithNonretainedObject:sub]]) {
            PFBCompatMeasure(topic, [NSString stringWithFormat:@"%02lu d%lu layer %@ %@", (unsigned long)(*index)++,
                                                               (unsigned long)depth + 1, NSStringFromClass([sub class]),
                                                               PFBToastProbeLayerLine(sub)],
                             70);
        }
    }
    if (depth < 8) {
        for (UIView* sub in view.subviews) {
            PFBToastProbeWalk(sub, depth + 1, topic, index);
        }
    }
}

// [toastprobe] Twitter's glass around a toast, once per toast height, three heights at most.
static void PFBToastProbeTree(UIView* glass) {
    static NSMutableSet* heights;
    NSNumber* height = @(round(CGRectGetHeight(glass.bounds)));
    if (!glass.window || height.doubleValue <= 0 || [heights containsObject:height] || heights.count >= 3) {
        return;
    }
    heights = heights ?: [NSMutableSet set];
    [heights addObject:height];
    NSUInteger index = 0;
    PFBToastProbeWalk(glass, 0, [NSString stringWithFormat:@"toast glass %@ pt", height], &index);
}

// [toastprobe] The first toast's glass as Twitter sets it, before the tweak's tint.
static void PFBToastProbeTwitterTree(UIView* glass) {
    static BOOL done;
    if (done || objc_getAssociatedObject(glass, kPFBGlassToastTintedKey)) {
        return;
    }
    done = YES;
    NSUInteger index = 0;
    PFBToastProbeWalk(glass, 0, @"toast glass before the tweak", &index);
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

// On Twitter's glass, Twitter's toast as it is: its glass tinted, its button on a light pill, its words gray.
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
            PFBGlassToastButtonPill(container, NO);
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
        PFBToastProbeTwitterTree(twitterGlass);
        PFBGlassToastTint(twitterGlass, styled);
        PFBGlassToastGrayText(container);
        PFBGlassToastButtonPill(container, YES);
        // [toastprobe] The glass is read once the toast is laid out on screen.
        __weak UIView* probed = twitterGlass;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          if (probed) {
              PFBToastProbeTree(probed);
          }
        });
        PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"Twitter's toast tinted, button on a light pill, words in the bar's gray");
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

// [toastprobe] Every tint and scrim Twitter's glass is given, and by whom.
%hook XDSGlass

- (id)initCapsuleWithClearTint:(UIColor*)tint scrimColor:(UIColor*)scrim interactive:(BOOL)interactive {
    PFBCompatMeasure(@"toast glass calls", [NSString stringWithFormat:@"init by Twitter: tint %@ scrim %@ interactive %d",
                                                                      PFBToastProbeColor(tint), PFBToastProbeColor(scrim), interactive],
                     24);
    return %orig;
}

- (void)setClearTint:(UIColor*)tint scrimColor:(UIColor*)scrim {
    PFBCompatMeasure(@"toast glass calls", [NSString stringWithFormat:@"set by %@: tint %@ scrim %@ in %@",
                                                                      gPFBToastProbeOurs ? @"the tweak" : @"Twitter",
                                                                      PFBToastProbeColor(tint), PFBToastProbeColor(scrim),
                                                                      NSStringFromClass([self.superview class])],
                     24);
    %orig;
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
    // [toastprobe] The color Twitter gives its toast.
    PFBCompatMeasure(@"toast glass calls", [@"surface " stringByAppendingString:PFBToastProbeColor(color)], 24);
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
