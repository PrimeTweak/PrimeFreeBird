// Probe for Twitter 12.45, removed once read: everything Chat's empty inbox holds, with each text's fonts,
// colors, paragraph styles, insets and place on the screen, once per appearance and text size.

#import "Support/HookHelpers.h"

static NSString* const kPFBChatEmptyProbeTopic = @"probe chat empty";
static const NSUInteger kPFBChatEmptyProbeCap = 400;
static NSUInteger gPFBChatEmptyProbeSeq;
static NSMutableSet<NSString*>* gPFBChatEmptyProbeSeen;

static void PFBChatEmptyProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBChatEmptyProbeTopic, [NSString stringWithFormat:@"%03lu %@", (unsigned long)++gPFBChatEmptyProbeSeq, line],
                     kPFBChatEmptyProbeCap);
}

static NSString* PFBChatEmptyProbeRect(CGRect rect) {
    return [NSString stringWithFormat:@"%.2f,%.2f %.2fx%.2f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

static NSString* PFBChatEmptyProbeColor(UIColor* color) {
    if (![color isKindOfClass:[UIColor class]]) {
        return @"none";
    }
    UIColor* light = [color resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]];
    UIColor* dark = [color resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
    CGFloat r = 0, g = 0, b = 0, a = 0, R = 0, G = 0, B = 0, A = 0;
    if (![light getRed:&r green:&g blue:&b alpha:&a] || ![dark getRed:&R green:&G blue:&B alpha:&A]) {
        return color.description;
    }
    return [NSString stringWithFormat:@"light %.0f,%.0f,%.0f,%.2f dark %.0f,%.0f,%.0f,%.2f", r * 255.0, g * 255.0, b * 255.0, a, R * 255.0,
                                      G * 255.0, B * 255.0, A];
}

static NSString* PFBChatEmptyProbeFont(UIFont* font) {
    if (![font isKindOfClass:[UIFont class]]) {
        return @"none";
    }
    NSDictionary* attributes = font.fontDescriptor.fontAttributes;
    NSNumber* weight = attributes[UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
    NSString* style = attributes[UIFontDescriptorTextStyleAttribute];
    return [NSString stringWithFormat:@"%@ %.2f weight %.2f%@ ascender %.2f descender %.2f line %.2f", font.fontName, font.pointSize,
                                      weight.doubleValue, style ? [@" style " stringByAppendingString:style] : @"", font.ascender,
                                      font.descender, font.lineHeight];
}

static NSString* PFBChatEmptyProbeText(NSString* text) {
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return text.length > 70 ? [[text substringToIndex:70] stringByAppendingString:@"..."] : text;
}

// Each run of an attributed text: its font, color, kern, baseline offset and paragraph style.
static void PFBChatEmptyProbeRuns(NSAttributedString* text, NSString* indent) {
    if (![text isKindOfClass:[NSAttributedString class]] || !text.length) {
        return;
    }
    __block NSUInteger runs = 0;
    [text enumerateAttributesInRange:NSMakeRange(0, text.length)
                             options:0
                          usingBlock:^(NSDictionary* attributes, NSRange range, BOOL* stop) {
                            if (++runs > 6) {
                                *stop = YES;
                                return;
                            }
                            NSParagraphStyle* para = attributes[NSParagraphStyleAttributeName];
                            NSString* paragraph =
                                [para isKindOfClass:[NSParagraphStyle class]]
                                    ? [NSString stringWithFormat:@" paragraph multiple %.2f min %.2f max %.2f spacing %.2f before %.2f after %.2f align %ld",
                                                                 para.lineHeightMultiple, para.minimumLineHeight, para.maximumLineHeight,
                                                                 para.lineSpacing, para.paragraphSpacingBefore, para.paragraphSpacing,
                                                                 (long)para.alignment]
                                    : @"";
                            PFBChatEmptyProbeLine([NSString stringWithFormat:@"%@  run %lu+%lu font %@ color %@ kern %@ offset %@%@", indent,
                                                                             (unsigned long)range.location, (unsigned long)range.length,
                                                                             PFBChatEmptyProbeFont(attributes[NSFontAttributeName]),
                                                                             PFBChatEmptyProbeColor(attributes[NSForegroundColorAttributeName]),
                                                                             attributes[NSKernAttributeName] ?: @"-",
                                                                             attributes[NSBaselineOffsetAttributeName] ?: @"-", paragraph]);
                          }];
}

// One line per view, then its texts' runs, text layers and accessibility elements, then its subviews.
static void PFBChatEmptyProbeView(UIView* view, NSUInteger depth) {
    if (depth > 9) {
        return;
    }
    NSString* indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSMutableString* line = [NSMutableString stringWithFormat:@"%@%@ (%@) %@%@%@%@", indent, NSStringFromClass(view.class),
                                                              NSStringFromClass(view.superclass),
                                                              PFBChatEmptyProbeRect([view convertRect:view.bounds toView:nil]),
                                                              view.hidden ? @" hidden" : @"",
                                                              view.alpha < 1.0 ? [NSString stringWithFormat:@" alpha %.2f", view.alpha] : @"",
                                                              view.clipsToBounds ? @" clips" : @""];
    NSAttributedString* runs = nil;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel* label = (UILabel*)view;
        CGRect text = [label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines];
        [line appendFormat:@" label '%@' font %@ color %@ lines %ld align %ld text %@", PFBChatEmptyProbeText(label.text),
                           PFBChatEmptyProbeFont(label.font), PFBChatEmptyProbeColor(label.textColor), (long)label.numberOfLines,
                           (long)label.textAlignment, PFBChatEmptyProbeRect(text)];
        runs = label.attributedText;
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView* field = (UITextView*)view;
        UIEdgeInsets inset = field.textContainerInset;
        [line appendFormat:@" textview '%@' font %@ color %@ inset %.2f,%.2f,%.2f,%.2f padding %.2f scroll %d edit %d select %d content %@",
                           PFBChatEmptyProbeText(field.text), PFBChatEmptyProbeFont(field.font), PFBChatEmptyProbeColor(field.textColor), inset.top,
                           inset.left, inset.bottom, inset.right, field.textContainer.lineFragmentPadding, field.scrollEnabled, field.editable,
                           field.selectable, PFBChatEmptyProbeRect((CGRect){CGPointZero, field.contentSize})];
        runs = field.attributedText;
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView* image = (UIImageView*)view;
        [line appendFormat:@" image %.2fx%.2f@%.0f mode %ld rendering %ld tint %@ symbol %d", image.image.size.width, image.image.size.height,
                           image.image.scale, (long)image.contentMode, (long)image.image.renderingMode, PFBChatEmptyProbeColor(image.tintColor),
                           image.image.symbolImage];
    } else if ([view isKindOfClass:[UIStackView class]]) {
        UIStackView* stack = (UIStackView*)view;
        [line appendFormat:@" stack axis %ld spacing %.2f alignment %ld distribution %ld arranged %lu", (long)stack.axis, stack.spacing,
                           (long)stack.alignment, (long)stack.distribution, (unsigned long)stack.arrangedSubviews.count];
        for (UIView* arranged in stack.arrangedSubviews) {
            CGFloat after = [stack customSpacingAfterView:arranged];
            if (after != UIStackViewSpacingUseDefault && after != UIStackViewSpacingUseSystem) {
                [line appendFormat:@" after %@ %.2f", NSStringFromClass(arranged.class), after];
            }
        }
    } else if ([view respondsToSelector:@selector(attributedText)]) {
        id text = [(id)view attributedText];
        if ([text isKindOfClass:[NSAttributedString class]]) {
            [line appendFormat:@" text '%@'", PFBChatEmptyProbeText([text string])];
            runs = text;
        }
    }
    if (view.accessibilityLabel.length) {
        [line appendFormat:@" ax '%@' at %@", PFBChatEmptyProbeText(view.accessibilityLabel), PFBChatEmptyProbeRect(view.accessibilityFrame)];
    }
    PFBChatEmptyProbeLine(line);
    PFBChatEmptyProbeRuns(runs, indent);
    for (CALayer* layer in view.layer.sublayers) {
        if ([layer isKindOfClass:[CATextLayer class]]) {
            CATextLayer* text = (CATextLayer*)layer;
            id string = text.string;
            NSString* words = [string isKindOfClass:[NSAttributedString class]] ? [string string] : [string description];
            PFBChatEmptyProbeLine([NSString stringWithFormat:@"%@  text layer '%@' size %.2f at %@", indent, PFBChatEmptyProbeText(words), text.fontSize,
                                                             PFBChatEmptyProbeRect([view.layer convertRect:layer.bounds fromLayer:layer])]);
        }
    }
    NSUInteger shown = 0;
    for (id element in view.accessibilityElements) {
        if ([element isKindOfClass:[UIView class]] || ++shown > 8) {
            continue;
        }
        PFBChatEmptyProbeLine([NSString stringWithFormat:@"%@  ax element %@ '%@' at %@", indent, NSStringFromClass([element class]),
                                                         PFBChatEmptyProbeText([element accessibilityLabel]),
                                                         PFBChatEmptyProbeRect([element accessibilityFrame])]);
    }
    for (UIView* subview in view.subviews) {
        PFBChatEmptyProbeView(subview, depth + 1);
    }
}

// The inbox at rest, its list unmoved: read 0.6 s after a layout, so a tab switch has settled.
static BOOL PFBChatEmptyProbeAtRest(UIView* empty) {
    UIView* list = empty.superview;
    while (list && ![list isKindOfClass:[UIScrollView class]]) {
        list = list.superview;
    }
    UIScrollView* scroll = (UIScrollView*)list;
    return empty.window && CGRectGetHeight(empty.bounds) >= 1.0 && !scroll.tracking && !scroll.dragging && !scroll.decelerating &&
           (!scroll || fabs(scroll.contentOffset.y + scroll.adjustedContentInset.top) <= 0.5);
}

%hook _TtC6ChatUI18ChatEmptyStateView

- (void)layoutSubviews {
    %orig;
    static BOOL pending;
    UIView* empty = (UIView*)self;
    if (pending || !empty.window) {
        return;
    }
    pending = YES;
    __weak UIView* weakEmpty = empty;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      pending = NO;
      UIView* view = weakEmpty;
      UITraitCollection* traits = view.traitCollection;
      NSString* key = [NSString stringWithFormat:@"style %ld, size %@", (long)traits.userInterfaceStyle, traits.preferredContentSizeCategory];
      gPFBChatEmptyProbeSeen = gPFBChatEmptyProbeSeen ?: [NSMutableSet set];
      if (!view || !PFBChatEmptyProbeAtRest(view) || [gPFBChatEmptyProbeSeen containsObject:key]) {
          return;
      }
      [gPFBChatEmptyProbeSeen addObject:key];
      PFBChatEmptyProbeLine([NSString stringWithFormat:@"dump: %@, window %@, superview %@", key, PFBChatEmptyProbeRect(view.window.bounds),
                                                       NSStringFromClass(view.superview.class)]);
      PFBChatEmptyProbeView(view, 0);
    });
}

%end
