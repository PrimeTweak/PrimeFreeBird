// Glass toasts. On Twitter's own glass (12.44, Liquid Glass) the toast stays Twitter's: only its glass
// takes the tab bar's tint and its words the tab bar's gray. Otherwise the tweak's capsule at the top,
// as wide as its words, the button on the right.

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
// Twitter's tab bar glass since 12.44: the background color at 25 %, with no scrim.
static const CGFloat kPFBGlassToastBarTint = 0.25;

static const void* kPFBGlassToastSurfaceKey = &kPFBGlassToastSurfaceKey;
static const void* kPFBGlassToastTwitterLookKey = &kPFBGlassToastTwitterLookKey;
static const void* kPFBGlassToastArrangedKey = &kPFBGlassToastArrangedKey;
static const void* kPFBGlassToastSideKey = &kPFBGlassToastSideKey;
static const void* kPFBGlassToastTintedKey = &kPFBGlassToastTintedKey;
static const void* kPFBGlassToastLaidContentKey = &kPFBGlassToastLaidContentKey;
static const void* kPFBGlassToastWidthsKey = &kPFBGlassToastWidthsKey;
static const void* kPFBGlassToastMeasuredKey = &kPFBGlassToastMeasuredKey;

static BOOL PFBGlassToastsOn(void) {
    return [PFBSettings boolForKey:@"glass_toasts"];
}

// Twitter draws its toasts on its own glass, laid out its own way, while its Liquid Glass is on.
static BOOL PFBGlassToastNative(void) {
    return PFBNativeGlassAsked() && NSClassFromString(@"XDSToastContainerView") != nil;
}

// A color for the report, resolved for the view's appearance.
static NSString* PFBGlassToastRGBA(UIColor* color, UIView* view) {
    if (!color) {
        return @"none";
    }
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [[color resolvedColorWithTraitCollection:view.traitCollection] getRed:&red green:&green blue:&blue alpha:&alpha];
    return [NSString stringWithFormat:@"rgba(%.0f, %.0f, %.0f, %.2f)", red * 255.0, green * 255.0, blue * 255.0, alpha];
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
// Returns how many words and buttons the toast holds.
static NSUInteger PFBGlassToastGrayText(UIView* container) {
    UIColor* gray = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    __block NSUInteger words = 0;
    PFBWalkAllSubviews(container, kPFBGlassToastWordsDepth, ^(UIView* view) {
      if ([view isKindOfClass:[UIButton class]]) {
          words++;
          UIButton* button = (UIButton*)view;
          if (![[button titleColorForState:UIControlStateNormal] isEqual:gray]) {
              [button setTitleColor:gray forState:UIControlStateNormal];
          }
      } else if ([view isKindOfClass:[UILabel class]]) {
          UILabel* label = (UILabel*)view;
          words++;
          if (![label.textColor isEqual:gray]) {
              label.textColor = gray;
          }
      } else if ([view isKindOfClass:[UIImageView class]] && CGRectGetWidth(view.bounds) <= 28.0 &&
                 ![view.tintColor isEqual:gray]) {
          view.tintColor = gray;
      }
    });
    return words;
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

// Twitter's glass given its tab bar's tint, once per toast style unless forced.
static void PFBGlassToastTintLikeBar(UIView* glass, BOOL force) {
    if (!force && objc_getAssociatedObject(glass, kPFBGlassToastTintedKey)) {
        return;
    }
    UIColor* tint = [[PFBPalette currentBackgroundColor] colorWithAlphaComponent:kPFBGlassToastBarTint];
    [(XDSGlass*)glass setClearTint:tint scrimColor:[UIColor clearColor]];
    objc_setAssociatedObject(glass, kPFBGlassToastTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A glass for the report: its effect, the color the effect is tinted with, and its material's bytes.
static NSString* PFBGlassToastDescribeGlass(UIView* glass) {
    Ivar effectIvar = class_getInstanceVariable([glass class], "visualEffectView");
    id effectView = effectIvar ? object_getIvar(glass, effectIvar) : nil;
    UIVisualEffect* effect = [effectView isKindOfClass:[UIVisualEffectView class]] ? [(UIVisualEffectView*)effectView effect] : nil;
    UIColor* tint = [effect respondsToSelector:@selector(tintColor)] ? ((UIColor * (*)(id, SEL)) objc_msgSend)(effect, @selector(tintColor)) : nil;
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [tint getRed:&red green:&green blue:&blue alpha:&alpha];
    Ivar materialIvar = class_getInstanceVariable([glass class], "material");
    NSMutableString* material = [NSMutableString string];
    for (NSUInteger i = 0; materialIvar && i < 9; i++) {
        [material appendFormat:@"%02x", ((const uint8_t*)(__bridge void*)glass + ivar_getOffset(materialIvar))[i]];
    }
    return [NSString stringWithFormat:@"effect %@ tint %@, material %@", NSStringFromClass([effect class]) ?: @"none",
                                      tint ? [NSString stringWithFormat:@"rgba(%.0f, %.0f, %.0f, %.2f)", red * 255.0,
                                                                        green * 255.0, blue * 255.0, alpha]
                                           : @"none",
                                      material.length ? material : @"not read"];
}

// The tab bar's glass, once, for the report, so the toast's can be compared with it.
static void PFBGlassToastMeasureBarGlass(void) {
    static BOOL measured;
    if (measured) {
        return;
    }
    Class barClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
    Class glassClass = NSClassFromString(@"XDSGlass");
    __block UIView* found = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        for (UIWindow* window in [scene isKindOfClass:[UIWindowScene class]] ? ((UIWindowScene*)scene).windows : @[]) {
            PFBWalkAllSubviews(window, 40, ^(UIView* view) {
              if (!found && barClass && glassClass && [view isKindOfClass:barClass]) {
                  PFBWalkAllSubviews(view, 3, ^(UIView* inner) {
                    if (!found && [inner isKindOfClass:glassClass]) {
                        found = inner;
                    }
                  });
              }
            });
        }
    }
    if (!found) {
        return;
    }
    measured = YES;
    PFBCompatMeasure(@"glass toasts", [@"tab bar glass: " stringByAppendingString:PFBGlassToastDescribeGlass(found)], 10);
}

// The content's class and its depth under the toast, searched as deep as the words; nil when there is none.
static NSString* PFBGlassToastDescribeContent(UIView* view, NSUInteger depth, UIView** content) {
    Class contentClass = NSClassFromString(@"XDSToastContentView");
    if (contentClass && [view isKindOfClass:contentClass]) {
        *content = view;
        return [NSString stringWithFormat:@"%@ at depth %lu%@", NSStringFromClass([view class]), (unsigned long)depth,
                                          view.hidden ? @" hidden" : @""];
    }
    for (UIView* subview in depth < kPFBGlassToastWordsDepth ? view.subviews : @[]) {
        NSString* found = PFBGlassToastDescribeContent(subview, depth + 1, content);
        if (found) {
            return found;
        }
    }
    return nil;
}

// A toast, a second after it first had a size, for the report: what it is, where its content sits,
// each label's words, room, state and color, each button's shape and colors, the frame, and on
// Twitter's glass that glass against the tab bar's.
static void PFBGlassToastMeasure(UIView* container, UIView* glass, id toast, BOOL tinted) {
    UIView* content = nil;
    NSString* where = PFBGlassToastDescribeContent(container, 0, &content);
    if (!where) {
        NSMutableOrderedSet<NSString*>* classes = [NSMutableOrderedSet orderedSet];
        PFBWalkAllSubviews(container, 10, ^(UIView* view) {
          if (classes.count < 16) {
              [classes addObject:NSStringFromClass([view class])];
          }
        });
        where = [NSString stringWithFormat:@"none, under the toast %@", [classes.array componentsJoinedByString:@" "]];
    }
    UIStackView* column = nil;
    for (UIView* view in content.subviews) {
        if (!column && [view isKindOfClass:[UIStackView class]]) {
            column = (UIStackView*)view;
        }
    }
    NSMutableArray<NSString*>* labels = [NSMutableArray array];
    NSMutableArray<NSString*>* buttons = [NSMutableArray array];
    PFBWalkAllSubviews(content ?: container, kPFBGlassToastWordsDepth, ^(UIView* view) {
      if ([view isKindOfClass:[UIControl class]] && ![view isKindOfClass:[UILabel class]] && buttons.count < 3) {
          UIButton* button = [view isKindOfClass:[UIButton class]] ? (UIButton*)view : nil;
          [buttons addObject:[NSString stringWithFormat:@"%@ \"%@\" %@ background %@ corners %.0f, title %@",
                                                        NSStringFromClass([view class]), button.currentTitle ?: @"",
                                                        NSStringFromCGSize(view.bounds.size),
                                                        PFBGlassToastRGBA(view.backgroundColor, view), view.layer.cornerRadius,
                                                        PFBGlassToastRGBA([button titleColorForState:UIControlStateNormal], view)]];
      } else if ([view isKindOfClass:[UILabel class]]) {
          UILabel* label = (UILabel*)view;
          NSString* text = label.text ?: @"";
          NSDictionary* font = @{NSFontAttributeName : label.font ?: [UIFont systemFontOfSize:16]};
          [labels addObject:[NSString stringWithFormat:@"\"%@\" needs %.0f laid %.0f%@%@ color %@%@",
                                                       text.length > 40 ? [text substringToIndex:40] : text,
                                                       ceil([text sizeWithAttributes:font].width), CGRectGetWidth(label.bounds),
                                                       label.hidden ? @" hidden" : @"", label.alpha < 0.01 ? @" clear" : @"",
                                                       PFBGlassToastRGBA(label.textColor, label),
                                                       [view.superview isKindOfClass:[UIControl class]] ? @" in a button" : @""]];
      } else if ([view isKindOfClass:[UIImageView class]] && CGRectGetWidth(view.bounds) <= 28.0 && labels.count < 6) {
          [labels addObject:[NSString stringWithFormat:@"icon %@ tint %@", NSStringFromCGSize(view.bounds.size),
                                                       PFBGlassToastRGBA(view.tintColor, view)]];
      }
    });
    NSDictionary* widths = objc_getAssociatedObject(container, kPFBGlassToastWidthsKey);
    NSString* icon = [toast respondsToSelector:@selector(iconName)] ? [toast iconName] : nil;
    PFBCompatMeasure(
        @"glass toasts",
        [NSString stringWithFormat:@"%@ %@: content %@, %@; column %@; labels %@; buttons %@; width Twitter %@ tweak %@, "
                                   @"frame %@; glass %@",
                                   NSStringFromClass([toast class]) ?: @"no toast", [icon isKindOfClass:[NSString class]] ? icon : @"no icon",
                                   where, PFBGlassToastSearchContent(container) ? @"found by the toast search" : @"not found by the toast search",
                                   column ? [NSString stringWithFormat:@"%lu views %@", (unsigned long)column.arrangedSubviews.count,
                                                                       column.axis == UILayoutConstraintAxisHorizontal ? @"in a row" : @"stacked"]
                                          : @"none",
                                   labels.count ? [labels componentsJoinedByString:@", "] : @"none",
                                   buttons.count ? [buttons componentsJoinedByString:@", "] : @"none",
                                   widths[@"twitter"] ?: @"not asked", widths[@"tweak"] ?: @"not asked",
                                   NSStringFromCGRect(CGRectIntegral([container convertRect:container.bounds toView:nil])),
                                   glass ? [NSString stringWithFormat:@"%@ %@, %@",
                                                                      NSStringFromCGRect(CGRectIntegral([glass convertRect:glass.bounds toView:container])),
                                                                      tinted ? @"tinted like the tab bar" : @"Twitter's",
                                                                      PFBGlassToastDescribeGlass(glass)]
                                         : @"none, the tweak's capsule"],
        10);
    if (glass) {
        PFBGlassToastMeasureBarGlass();
    }
}

// Each toast is measured once, a second after it is first seen with its size, for its words to
// settle; up to 8 toasts a launch.
static void PFBGlassToastScheduleMeasure(UIView* container, UIView* glass, id toast) {
    static NSUInteger scheduled;
    if (scheduled >= 8 || CGRectIsEmpty(container.bounds) || (glass && CGRectIsEmpty(glass.bounds)) ||
        objc_getAssociatedObject(container, kPFBGlassToastMeasuredKey)) {
        return;
    }
    scheduled++;
    objc_setAssociatedObject(container, kPFBGlassToastMeasuredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView* weakContainer = container;
    __weak UIView* weakGlass = glass;
    __weak id weakToast = toast;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      UIView* laterContainer = weakContainer;
      UIView* laterGlass = weakGlass;
      if (laterContainer) {
          PFBGlassToastMeasure(laterContainer, laterGlass, weakToast,
                               laterGlass && objc_getAssociatedObject(laterGlass, kPFBGlassToastTintedKey) != nil);
      }
    });
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

// On Twitter's glass, Twitter's toast as it is, its glass tinted like the tab bar and its words gray.
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
            PFBGlassToastScheduleMeasure(container, nil, toast);
            PFBCOMPAT_OBSERVE(PFBCompat_glass_toasts, @"Twitter's toast without its glass");
            return;
        }
        PFBGlassToastTintLikeBar(twitterGlass, styled);
        // Measured once its words are in it.
        if (PFBGlassToastGrayText(container) > 0) {
            PFBGlassToastScheduleMeasure(container, twitterGlass, toast);
        }
        PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"Twitter's toast tinted like the tab bar, words in its gray");
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
    PFBGlassToastScheduleMeasure(container, nil, toast);
    PFBCOMPAT_ACTION(PFBCompat_glass_toasts, @"toast drawn as the glass capsule");
}

%hook TFNToastViewController

- (double)_tfn_toastWidth {
    double width = %orig;
    if (!PFBGlassToastsOn() || ![self respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        return width;
    }
    UIView* container = [self toastContainerView];
    BOOL native = PFBGlassToastNative();
    CGFloat own = native ? width : PFBGlassToastWidth(container, [self _tfn_toastHorizontalPlacementBounds], width);
    if (container) {
        objc_setAssociatedObject(container, kPFBGlassToastWidthsKey,
                                 @{@"twitter" : @(round(width)), @"tweak" : native ? @"kept" : @(own)},
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return own;
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

// Twitter tints its glass with the toast's color: the tab bar's tint is set again after it.
- (void)setSurfaceColor:(UIColor*)color {
    %orig;
    UIView* glass = PFBGlassToastsOn() ? PFBGlassToastTwitterGlass(self) : nil;
    if (glass) {
        PFBGlassToastTintLikeBar(glass, YES);
    }
}

- (void)layoutSubviews {
    %orig;
    PFBGlassToastDress(self, NO);
}

%end
