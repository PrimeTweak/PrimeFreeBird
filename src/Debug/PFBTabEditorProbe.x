// Reads how Twitter's tab editor lays out its page when the tour opens it: its views with their
// frames, layout, texts and controls go to MEASUREMENTS, so the page can be laid out anew.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBEditorProbeTopic = @"tab editor";
static const NSUInteger kPFBEditorProbeLines = 60;
static BOOL gPFBEditorProbeRead;

BOOL PFBTabEditorProbeRead(void) {
    return gPFBEditorProbeRead;
}

static NSString* PFBEditorRect(CGRect rect) {
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", rect.origin.x, rect.origin.y, rect.size.width,
                                      rect.size.height];
}

// What a control does: each target's class with the actions it receives.
static NSString* PFBEditorActions(UIControl* control) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (id target in control.allTargets) {
        NSArray<NSString*>* actions = [control actionsForTarget:target forControlEvent:control.allControlEvents];
        [parts addObject:[NSString stringWithFormat:@"%@ %@", PFBReadableClassName(target),
                                                    actions.count ? [actions componentsJoinedByString:@"/"] : @"?"]];
    }
    return parts.count ? [parts componentsJoinedByString:@", "] : @"none";
}

static NSString* PFBEditorText(NSString* text) {
    NSString* flat = [[text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
        componentsJoinedByString:@" "];
    return flat.length > 70 ? [[flat substringToIndex:70] stringByAppendingString:@"…"] : flat;
}

// One line per view: depth, class, frame in the page, then what bears on laying it out again.
// Labels, images, buttons and effect views are read as a whole, without their insides.
static void PFBEditorDescribe(UIView* view, UIView* page, NSUInteger depth, NSMutableArray<NSString*>* lines) {
    if (lines.count >= kPFBEditorProbeLines || depth > 9) {
        return;
    }
    NSMutableString* line = [NSMutableString stringWithFormat:@"%lu %@ %@", (unsigned long)depth,
                                                              PFBReadableClassName(view),
                                                              PFBEditorRect([view convertRect:view.bounds toView:page])];
    if (view.hidden) {
        [line appendString:@" hidden"];
    }
    if (view.alpha < 0.999) {
        [line appendFormat:@" alpha %.2f", view.alpha];
    }
    if (!view.translatesAutoresizingMaskIntoConstraints) {
        [line appendString:@" autolayout"];
    }
    if (view.backgroundColor) {
        [line appendFormat:@" bg %@", PFBColorText(view.backgroundColor)];
    }
    if (view.layer.cornerRadius > 0.0) {
        [line appendFormat:@" radius %.0f", view.layer.cornerRadius];
    }
    if (view.accessibilityLabel.length) {
        [line appendFormat:@" label \"%@\"", PFBEditorText(view.accessibilityLabel)];
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel* label = (UILabel*)view;
        [line appendFormat:@" text \"%@\" %.1f pt %@ lines %ld", PFBEditorText(label.text), label.font.pointSize,
                           PFBColorText(label.textColor), (long)label.numberOfLines];
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton* button = (UIButton*)view;
        NSString* title = button.configuration.title ?: [button titleForState:UIControlStateNormal];
        [line appendFormat:@" title \"%@\"", PFBEditorText(title)];
    }
    if ([view isKindOfClass:[UIStackView class]]) {
        UIStackView* stack = (UIStackView*)view;
        [line appendFormat:@" stack %@ spacing %.0f alignment %ld distribution %ld",
                           stack.axis == UILayoutConstraintAxisVertical ? @"vertical" : @"horizontal", stack.spacing,
                           (long)stack.alignment, (long)stack.distribution];
    }
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView* scroll = (UIScrollView*)view;
        [line appendFormat:@" content %.0fx%.0f inset top %.0f bottom %.0f", scroll.contentSize.width,
                           scroll.contentSize.height, scroll.adjustedContentInset.top, scroll.adjustedContentInset.bottom];
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage* image = ((UIImageView*)view).image;
        [line appendFormat:@" image %@", image ? [NSString stringWithFormat:@"%.0fx%.0f", image.size.width, image.size.height]
                                               : @"none"];
    }
    if ([view isKindOfClass:[UIControl class]]) {
        [line appendFormat:@" actions %@", PFBEditorActions((UIControl*)view)];
    }
    if (view.gestureRecognizers.count) {
        NSMutableArray<NSString*>* kinds = [NSMutableArray array];
        for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
            [kinds addObject:PFBReadableClassName(recognizer)];
        }
        [line appendFormat:@" gestures [%@]", [kinds componentsJoinedByString:@", "]];
    }
    [lines addObject:line];
    if (view.hidden || [view isKindOfClass:[UILabel class]] || [view isKindOfClass:[UIImageView class]] ||
        [view isKindOfClass:[UIButton class]] || [view isKindOfClass:[UIVisualEffectView class]]) {
        return;
    }
    for (UIView* sub in view.subviews) {
        PFBEditorDescribe(sub, page, depth + 1, lines);
    }
}

static void PFBEditorChildren(UIViewController* controller, NSMutableArray<NSString*>* names, NSUInteger depth) {
    for (UIViewController* child in controller.childViewControllers) {
        [names addObject:PFBReadableClassName(child)];
        if (depth < 3) {
            PFBEditorChildren(child, names, depth + 1);
        }
    }
}

// NO when the page is no longer on screen, so its next appearance is read instead.
static BOOL PFBEditorProbeRead(UIViewController* editor) {
    UIView* page = editor.viewIfLoaded;
    if (!page.window) {
        return NO;
    }
    NSMutableArray<NSString*>* children = [NSMutableArray array];
    PFBEditorChildren(editor, children, 0);
    UINavigationItem* item = editor.navigationItem;
    NSMutableArray<NSString*>* right = [NSMutableArray array];
    for (UIBarButtonItem* button in item.rightBarButtonItems) {
        [right addObject:button.title.length ? button.title : PFBReadableClassName(button.customView ?: button)];
    }
    UIEdgeInsets safe = page.safeAreaInsets;
    NSMutableArray<NSString*>* lines = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"screen %@ · children [%@] · page %@ · safe area top %.0f bottom %.0f · "
                                   @"title view %@ · right [%@]",
                                   PFBReadableClassName(editor), [children componentsJoinedByString:@", "],
                                   PFBEditorRect([page convertRect:page.bounds toView:nil]), safe.top, safe.bottom,
                                   PFBReadableClassName(item.titleView), [right componentsJoinedByString:@", "]]];
    PFBEditorDescribe(page, page, 0, lines);
    for (NSString* line in lines) {
        PFBCompatMeasure(kPFBEditorProbeTopic, line, kPFBEditorProbeLines);
    }
    return YES;
}

%hook T1TabCustomizationViewController

// Read once per launch, after the page has settled.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gPFBEditorProbeRead) {
        return;
    }
    __weak UIViewController* editor = (UIViewController*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (gPFBEditorProbeRead) {
          return;
      }
      @try {
          gPFBEditorProbeRead = PFBEditorProbeRead(editor);
      } @catch (id exception) {
          gPFBEditorProbeRead = YES;
          PFBCompatMeasure(kPFBEditorProbeTopic, [NSString stringWithFormat:@"stopped (%@)", exception],
                           kPFBEditorProbeLines);
      }
    });
}

%end
