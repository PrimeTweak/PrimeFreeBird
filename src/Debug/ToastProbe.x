// Temporary probe ([toastprobe]): how Twitter builds and places its toasts, before they take the
// tweak's look. Logs each toast pushed, shown and dismissed with its views, shows test toasts after
// launch, and writes a step line into a toast on screen.

#import "Support/HookHelpers.h"
#import "Support/PFBTwitterPopups.h"
#import "Support/TFNHeaders.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

// The hooked methods are declared too: the compiler checks every selector the hooks name.
@interface TFNToaster (PFBToastProbe)
+ (NSUInteger)normalToastQueueMaxCount;
+ (double)normalToastThrottleCooldownDuration;
- (id)toastViewController;
- (void)toastViewController:(id)controller didPresentToast:(id)toast;
- (void)toastViewController:(id)controller didDismissToast:(id)toast withStyle:(NSUInteger)style byGesture:(BOOL)gesture;
@end

@interface TFNToastViewController : UIViewController
- (void)presentToast:(id)toast
               withStyle:(NSUInteger)style
     toastsUpdateEnabled:(BOOL)updated
                animated:(BOOL)animated
              completion:(id)completion;
@end

@interface T1ToastContainerView : UIView
- (void)prepareForToastWithUpdatedStyle:(BOOL)updated;
@end

@interface TFNInformationToast (PFBToastProbe)
- (instancetype)initWithMessageText:(NSString*)text
                         detailText:(NSString*)detail
                           iconName:(NSString*)iconName
                    displayDuration:(double)duration
                     thumbnailImage:(UIImage*)image;
@end

// What the probe reads from a toast, its action and its content configuration.
@protocol PFBProbedToast <NSObject>
@optional
- (id)messageText;
- (id)detailText;
- (NSString*)iconName;
- (UIImage*)thumbnailImage;
- (double)displayDuration;
- (id)alternateAction;
- (NSString*)title;
- (UIImage*)iconImage;
- (NSString*)alternateActionTitle;
- (BOOL)showsSocialDMIcon;
- (id)primaryActionHandler;
@end

// What the probe reads from the controller that shows the toasts.
@protocol PFBProbedToastController <NSObject>
@optional
- (UIView*)toastContainerView;
- (UIView*)currentXDSToastView;
- (UIView*)currentContentView;
- (double)_tfn_toastWidth;
- (CGRect)_tfn_toastContainerFrame;
- (CGRect)_tfn_toastHorizontalPlacementBounds;
- (double)currentTop;
- (double)baselineTop;
- (double)minimizedToastViewHeight;
- (double)contentFittingWidth;
- (BOOL)currentToastsUpdateEnabled;
@end

// The ring keeps 300 lines; the probe stays under that, and each toast's views take at most 20.
static const NSInteger kPFBToastProbeBudget = 250;
static const NSInteger kPFBToastProbeTreeLines = 20;
static NSInteger gPFBToastProbeLines;

// What the presentation said, printed with the toast once it shows.
static NSString* gPFBToastProbePresented;
static NSString* gPFBToastProbeContent;
static NSString* gPFBToastProbeContainer;

// The step line the live test last wrote.
static NSString* gPFBToastProbeStep;

static void PFBToastProbeLog(NSString* format, ...) NS_FORMAT_FUNCTION(1, 2);
static void PFBToastProbeLog(NSString* format, ...) {
    if (gPFBToastProbeLines > kPFBToastProbeBudget) {
        return;
    }
    gPFBToastProbeLines++;
    if (gPFBToastProbeLines > kPFBToastProbeBudget) {
        PFBDebugLog(@"[toastprobe] line budget used up");
        return;
    }
    va_list args;
    va_start(args, format);
    NSString* line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    PFBDebugLog(@"[toastprobe] %@", line);
}

static void PFBToastProbeAfter(double seconds, void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// MARK: - Describing

// "XDesignSystem.ToastPlacementHost" reads "ToastPlacementHost".
static NSString* PFBToastProbeName(id object) {
    if (!object) {
        return @"none";
    }
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

static NSString* PFBToastProbeRect(CGRect rect) {
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", CGRectGetMinX(rect), CGRectGetMinY(rect),
                                      CGRectGetWidth(rect), CGRectGetHeight(rect)];
}

static NSString* PFBToastProbeText(id value, NSUInteger limit) {
    NSString* text = [value isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString*)value string] : [value description];
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return text.length > limit ? [[text substringToIndex:limit] stringByAppendingString:@"…"] : text;
}

// A color as #RRGGBB, with its alpha when not opaque; nil for none or a clear one.
static NSString* PFBToastProbeColor(UIColor* color, UITraitCollection* traits) {
    if (!color) {
        return nil;
    }
    UIColor* resolved = [color resolvedColorWithTraitCollection:traits];
    CGFloat r = 0, g = 0, b = 0, a = 0, w = 0;
    if (![resolved getRed:&r green:&g blue:&b alpha:&a]) {
        if (![resolved getWhite:&w alpha:&a]) {
            return @"pattern";
        }
        r = g = b = w;
    }
    if (a < 0.005) {
        return nil;
    }
    NSString* hex = [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(MIN(MAX(r, 0), 1) * 255),
                                               (int)lround(MIN(MAX(g, 0), 1) * 255), (int)lround(MIN(MAX(b, 0), 1) * 255)];
    return a < 0.995 ? [hex stringByAppendingFormat:@"/%.2f", a] : hex;
}

// An image's size, or the class of what a toast holds in its place.
static NSString* PFBToastProbeImage(id image) {
    if (![image isKindOfClass:[UIImage class]]) {
        return PFBToastProbeName(image);
    }
    return [NSString stringWithFormat:@"%.0fx%.0f", ((UIImage*)image).size.width, ((UIImage*)image).size.height];
}

static NSString* PFBToastProbeFont(UIFont* font) {
    return font ? [NSString stringWithFormat:@"%@ %.1f", font.fontName, font.pointSize] : @"no font";
}

// One view on one line: its class and frame, its look, and what it holds.
static NSString* PFBToastProbeDescribe(UIView* view) {
    UITraitCollection* traits = view.traitCollection;
    NSMutableString* line = [NSMutableString stringWithFormat:@"%@ %@", PFBToastProbeName(view), PFBToastProbeRect(view.frame)];
    if (view.hidden) {
        [line appendString:@" hidden"];
    }
    if (view.alpha < 0.99) {
        [line appendFormat:@" alpha %.2f", view.alpha];
    }
    NSString* background = PFBToastProbeColor(view.backgroundColor, traits);
    if (background) {
        [line appendFormat:@" bg %@", background];
    }
    CALayer* layer = view.layer;
    if (layer.cornerRadius > 0.5) {
        [line appendFormat:@" radius %.1f%@", layer.cornerRadius,
                           [layer.cornerCurve isEqualToString:kCACornerCurveContinuous] ? @" smooth" : @""];
    }
    if (layer.masksToBounds) {
        [line appendString:@" clips"];
    }
    if (layer.borderWidth > 0) {
        [line appendFormat:@" border %.1f %@", layer.borderWidth,
                           PFBToastProbeColor([UIColor colorWithCGColor:layer.borderColor], traits) ?: @"clear"];
    }
    if (layer.shadowOpacity > 0) {
        [line appendFormat:@" shadow %.2f r%.0f y%.0f", layer.shadowOpacity, layer.shadowRadius, layer.shadowOffset.height];
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel* label = (UILabel*)view;
        [line appendFormat:@" \"%@\" %@ %@ lines %ld align %ld", PFBToastProbeText(label.text ?: @"", 32),
                           PFBToastProbeFont(label.font), PFBToastProbeColor(label.textColor, traits) ?: @"clear",
                           (long)label.numberOfLines, (long)label.textAlignment];
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton* button = (UIButton*)view;
        [line appendFormat:@" title \"%@\" %@ tint %@%@", PFBToastProbeText(button.currentTitle ?: @"", 24),
                           PFBToastProbeFont(button.titleLabel.font), PFBToastProbeColor(button.tintColor, traits) ?: @"clear",
                           button.configuration ? @" configured" : @""];
    } else if ([view isKindOfClass:[UIStackView class]]) {
        UIStackView* stack = (UIStackView*)view;
        [line appendFormat:@" %@ spacing %.1f align %ld fill %ld items %lu",
                           stack.axis == UILayoutConstraintAxisHorizontal ? @"row" : @"column", stack.spacing,
                           (long)stack.alignment, (long)stack.distribution, (unsigned long)stack.arrangedSubviews.count];
    } else if ([view isKindOfClass:[UIVisualEffectView class]]) {
        [line appendFormat:@" effect %@", PFBToastProbeName(((UIVisualEffectView*)view).effect)];
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImage* image = ((UIImageView*)view).image;
        [line appendFormat:@" image %@ tint %@", image ? PFBToastProbeRect((CGRect){CGPointZero, image.size}) : @"none",
                           PFBToastProbeColor(view.tintColor, traits) ?: @"clear"];
    }
    return line;
}

// The views under a toast, one per line: a hidden view or UIKit's own parts are not opened, and an
// effect view is opened at its content.
static void PFBToastProbeTree(UIView* view, NSInteger depth, NSInteger* budget) {
    if (*budget <= 0 || depth > 10) {
        return;
    }
    (*budget)--;
    PFBToastProbeLog(@"%@%@", [@"" stringByPaddingToLength:(NSUInteger)depth * 2 withString:@" " startingAtIndex:0],
                     PFBToastProbeDescribe(view));
    if (view.hidden) {
        return;
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        for (UIView* inner in ((UIVisualEffectView*)view).contentView.subviews) {
            PFBToastProbeTree(inner, depth + 1, budget);
        }
        return;
    }
    if ([NSStringFromClass([view class]) hasPrefix:@"_"]) {
        return;
    }
    for (UIView* inner in view.subviews) {
        PFBToastProbeTree(inner, depth + 1, budget);
    }
}

static NSString* PFBToastProbeSummary(id toast) {
    id<PFBProbedToast> item = toast;
    NSMutableString* line = [NSMutableString stringWithString:PFBToastProbeName(toast)];
    if ([item respondsToSelector:@selector(messageText)] && [item messageText]) {
        [line appendFormat:@" \"%@\"", PFBToastProbeText([item messageText], 40)];
    }
    if ([item respondsToSelector:@selector(detailText)] && [item detailText]) {
        [line appendFormat:@" · detail \"%@\"", PFBToastProbeText([item detailText], 40)];
    }
    if ([item respondsToSelector:@selector(iconName)] && [item iconName]) {
        [line appendFormat:@" · icon %@", [item iconName]];
    }
    if ([item respondsToSelector:@selector(thumbnailImage)] && [item thumbnailImage]) {
        [line appendFormat:@" · thumbnail %@", PFBToastProbeImage([item thumbnailImage])];
    }
    if ([item respondsToSelector:@selector(displayDuration)]) {
        [line appendFormat:@" · duration %.1f", [item displayDuration]];
    }
    id action = [item respondsToSelector:@selector(alternateAction)] ? [item alternateAction] : nil;
    if (action) {
        id<PFBProbedToast> button = action;
        [line appendFormat:@" · button \"%@\"",
                           [button respondsToSelector:@selector(title)] ? PFBToastProbeText([button title] ?: @"", 20) : @"?"];
    }
    return line;
}

static NSString* PFBToastProbeConfiguration(id configuration) {
    id<PFBProbedToast> item = configuration;
    NSMutableString* line = [NSMutableString stringWithString:PFBToastProbeName(configuration)];
    if ([item respondsToSelector:@selector(messageText)] && [item messageText]) {
        [line appendFormat:@" \"%@\"", PFBToastProbeText([item messageText], 32)];
    }
    if ([item respondsToSelector:@selector(detailText)] && [item detailText]) {
        [line appendFormat:@" · detail \"%@\"", PFBToastProbeText([item detailText], 32)];
    }
    if ([item respondsToSelector:@selector(iconImage)] && [item iconImage]) {
        [line appendFormat:@" · icon %@", PFBToastProbeImage([item iconImage])];
    }
    if ([item respondsToSelector:@selector(thumbnailImage)] && [item thumbnailImage]) {
        [line appendString:@" · thumbnail"];
    }
    if ([item respondsToSelector:@selector(alternateActionTitle)] && [item alternateActionTitle]) {
        [line appendFormat:@" · button \"%@\"", PFBToastProbeText([item alternateActionTitle], 20)];
    }
    if ([item respondsToSelector:@selector(showsSocialDMIcon)] && [item showsSocialDMIcon]) {
        [line appendString:@" · messages icon"];
    }
    if ([item respondsToSelector:@selector(primaryActionHandler)] && [item primaryActionHandler]) {
        [line appendString:@" · opens on tap"];
    }
    return line;
}

// The toast on screen: where it stands, the sizes Twitter works out for it, and its views.
static void PFBToastProbeDump(id controller, NSString* label) {
    id<PFBProbedToastController> shower = controller;
    UIView* container = [shower respondsToSelector:@selector(toastContainerView)] ? [shower toastContainerView] : nil;
    if (!container) {
        PFBToastProbeLog(@"%@: no container", label);
        return;
    }
    UIWindow* window = container.window;
    NSMutableArray<NSString*>* above = [NSMutableArray array];
    for (UIView* level = container.superview; level && level != window; level = level.superview) {
        [above addObject:PFBToastProbeName(level)];
    }
    NSMutableArray<NSString*>* gestures = [NSMutableArray array];
    for (UIGestureRecognizer* gesture in container.gestureRecognizers) {
        [gestures addObject:PFBToastProbeName(gesture)];
    }
    PFBToastProbeLog(@"%@: container %@ at %@ in %@ < %@ level %.0f safe top %.0f · gestures %@", label,
                     PFBToastProbeName(container), PFBToastProbeRect([container convertRect:container.bounds toView:nil]),
                     [above componentsJoinedByString:@" < "], PFBToastProbeName(window), window.windowLevel,
                     window.safeAreaInsets.top, gestures.count ? [gestures componentsJoinedByString:@", "] : @"none");
    NSMutableString* metrics = [NSMutableString string];
    if ([shower respondsToSelector:@selector(_tfn_toastContainerFrame)]) {
        [metrics appendFormat:@" frame %@", PFBToastProbeRect([shower _tfn_toastContainerFrame])];
    }
    if ([shower respondsToSelector:@selector(_tfn_toastHorizontalPlacementBounds)]) {
        [metrics appendFormat:@" · placement %@", PFBToastProbeRect([shower _tfn_toastHorizontalPlacementBounds])];
    }
    if ([shower respondsToSelector:@selector(_tfn_toastWidth)]) {
        [metrics appendFormat:@" · width %.0f", [shower _tfn_toastWidth]];
    }
    if ([shower respondsToSelector:@selector(currentTop)] && [shower respondsToSelector:@selector(baselineTop)]) {
        [metrics appendFormat:@" · top %.0f baseline %.0f", [shower currentTop], [shower baselineTop]];
    }
    if ([shower respondsToSelector:@selector(minimizedToastViewHeight)]) {
        [metrics appendFormat:@" · minimized %.0f", [shower minimizedToastViewHeight]];
    }
    if ([shower respondsToSelector:@selector(contentFittingWidth)]) {
        [metrics appendFormat:@" · fitting %.0f", [shower contentFittingWidth]];
    }
    if ([shower respondsToSelector:@selector(currentToastsUpdateEnabled)]) {
        [metrics appendFormat:@" · new toasts %@", [shower currentToastsUpdateEnabled] ? @"yes" : @"no"];
    }
    UIView* xds = [shower respondsToSelector:@selector(currentXDSToastView)] ? [shower currentXDSToastView] : nil;
    UIView* legacy = [shower respondsToSelector:@selector(currentContentView)] ? [shower currentContentView] : nil;
    PFBToastProbeLog(@"%@:%@ · content %@ / %@", label, metrics, PFBToastProbeName(xds), PFBToastProbeName(legacy));
    NSInteger budget = kPFBToastProbeTreeLines;
    PFBToastProbeTree(container, 1, &budget);
}

// MARK: - The live step line

static UIView* PFBToastProbeContainer(void) {
    TFNToaster* toaster = [objc_getClass("TFNToaster") defaultToaster];
    id shower = [toaster respondsToSelector:@selector(toastViewController)] ? [toaster toastViewController] : nil;
    return [shower respondsToSelector:@selector(toastContainerView)] ? [(id<PFBProbedToastController>)shower toastContainerView]
                                                                      : nil;
}

static UILabel* PFBToastProbeLabelHolding(UIView* root, NSString* text) {
    __block UILabel* found = nil;
    PFBWalkAllSubviews(root, 14, ^(UIView* view) {
      if (!found && [view isKindOfClass:[UILabel class]] && [((UILabel*)view).text isEqualToString:text]) {
          found = (UILabel*)view;
      }
    });
    return found;
}

// Writes the next step into the label showing the current one, then reads it back.
static void PFBToastProbeWriteStep(NSString* next) {
    UIView* container = PFBToastProbeContainer();
    UILabel* label = container ? PFBToastProbeLabelHolding(container, gPFBToastProbeStep) : nil;
    if (!label) {
        NSMutableArray<NSString*>* texts = [NSMutableArray array];
        if (container) {
            PFBWalkAllSubviews(container, 14, ^(UIView* view) {
              if ([view isKindOfClass:[UILabel class]] && ((UILabel*)view).text.length) {
                  [texts addObject:((UILabel*)view).text];
              }
            });
        }
        PFBToastProbeLog(@"step \"%@\": no label holds \"%@\" · labels: %@", next, gPFBToastProbeStep,
                         texts.count ? [texts componentsJoinedByString:@" | "] : @"none");
        return;
    }
    CGRect labelBefore = label.frame;
    CGRect containerBefore = container.frame;
    label.text = next;
    [label.superview setNeedsLayout];
    [container setNeedsLayout];
    [container layoutIfNeeded];
    gPFBToastProbeStep = next;
    PFBToastProbeLog(@"step written \"%@\" · label %@ -> %@ · lines %ld · container %@ -> %@", next,
                     PFBToastProbeRect(labelBefore), PFBToastProbeRect(label.frame), (long)label.numberOfLines,
                     PFBToastProbeRect(containerBefore), PFBToastProbeRect(container.frame));
    __weak UILabel* weakLabel = label;
    __weak UIView* weakContainer = container;
    PFBToastProbeAfter(0.4, ^{
      PFBToastProbeLog(@"0.4 s later: label says \"%@\" at %@ · container %@", weakLabel ? weakLabel.text : @"(gone)",
                       PFBToastProbeRect(weakLabel.frame), PFBToastProbeRect(weakContainer.frame));
    });
}

// MARK: - Test toasts

static UIImage* PFBToastProbeThumbnail(void) {
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext* context) {
      [[UIColor colorWithRed:0.47 green:0.65 blue:0.85 alpha:1] setFill];
      UIRectFill(CGRectMake(0, 0, 64, 64));
      [[UIColor colorWithRed:0.95 green:0.70 blue:0.54 alpha:1] setFill];
      UIRectFill(CGRectMake(0, 32, 64, 32));
    }];
}

// The tour shows its own toast: no test step runs while it does.
static BOOL PFBToastProbeTourBusy(NSString* name) {
    if (!PFBCompatTourIsRunning()) {
        return NO;
    }
    PFBToastProbeLog(@"test %@ skipped: the tour is running", name);
    return YES;
}

static void PFBToastProbePush(NSString* name, NSString* text, NSString* detail, PFBToastKind kind, NSString* button) {
    if (PFBToastProbeTourBusy(name)) {
        return;
    }
    BOOL pushed = PFBPushTwitterToast(text, detail, kind, button,
                                      button ? ^{
                                        PFBToastProbeLog(@"%@: button tapped", name);
                                      }
                                             : nil,
                                      NO);
    PFBToastProbeLog(@"test %@: %@", name, pushed ? @"pushed" : @"refused");
}

// A persistent toast with a step line rewritten three times, then one toast of each kind the tweak
// shows, each replacing the one before, then one with a thumbnail.
static void PFBToastProbeRunTests(void) {
    Class toasterClass = objc_getClass("TFNToaster");
    PFBToastProbeLog(@"tests start · queue max %lu · throttle %.1f s",
                     [toasterClass respondsToSelector:@selector(normalToastQueueMaxCount)]
                         ? (unsigned long)[toasterClass normalToastQueueMaxCount]
                         : 0UL,
                     [toasterClass respondsToSelector:@selector(normalToastThrottleCooldownDuration)]
                         ? [toasterClass normalToastThrottleCooldownDuration]
                         : -1.0);
    gPFBToastProbeStep = @"Home · 1 of 32";
    BOOL live = PFBPushTwitterToast(@"Check every option", gPFBToastProbeStep, PFBToastKindPlain, @"Cancel", ^{
      PFBToastProbeLog(@"live: Cancel tapped");
    }, YES);
    PFBToastProbeLog(@"test live: %@", live ? @"pushed" : @"refused");
    NSArray<NSString*>* steps = @[ @"Notifications · 2 of 32", @"Messages · 3 of 32", @"Tweet interactions and replies · 4 of 32" ];
    for (NSUInteger i = 0; i < steps.count; i++) {
        NSString* step = steps[i];
        PFBToastProbeAfter(1.8 + 1.2 * (double)i, ^{
          if (!PFBToastProbeTourBusy(@"step")) {
              PFBToastProbeWriteStep(step);
          }
        });
    }
    PFBToastProbeAfter(6.0, ^{
      if (PFBToastProbeTourBusy(@"clear")) {
          return;
      }
      PFBClearTwitterToasts();
      PFBToastProbeAfter(0.8, ^{
        TFNToaster* toaster = [toasterClass defaultToaster];
        PFBToastProbeLog(@"after clear: on screen %@",
                         [toaster respondsToSelector:@selector(activeToast)] ? PFBToastProbeName([toaster activeToast]) : @"?");
      });
    });
    PFBToastProbeAfter(8.0, ^{
      PFBToastProbePush(@"plain", @"Toast probe: plain", nil, PFBToastKindPlain, nil);
    });
    PFBToastProbeAfter(12.0, ^{
      PFBToastProbePush(@"detail", @"Toast probe: detail", @"A second line under the message", PFBToastKindPlain, nil);
    });
    PFBToastProbeAfter(16.0, ^{
      PFBToastProbePush(@"success", @"Toast probe: success", @"Detail under a success", PFBToastKindSuccess, nil);
    });
    PFBToastProbeAfter(20.0, ^{
      PFBToastProbePush(@"error", @"Toast probe: error", nil, PFBToastKindError, nil);
    });
    PFBToastProbeAfter(24.0, ^{
      PFBToastProbePush(@"button", @"Toast probe: button", nil, PFBToastKindPlain, @"Undo");
    });
    PFBToastProbeAfter(28.0, ^{
      if (PFBToastProbeTourBusy(@"thumbnail")) {
          return;
      }
      Class toastClass = objc_getClass("TFNInformationToast");
      SEL make = @selector(initWithMessageText:detailText:iconName:displayDuration:thumbnailImage:);
      TFNToaster* toaster = [toasterClass defaultToaster];
      if (![toastClass instancesRespondToSelector:make] || ![toaster respondsToSelector:@selector(pushToast:withPriority:)]) {
          PFBToastProbeLog(@"test thumbnail: refused");
          return;
      }
      id toast = [[toastClass alloc] initWithMessageText:@"Toast probe: thumbnail"
                                              detailText:@"A picture beside the words"
                                                iconName:nil
                                         displayDuration:0
                                          thumbnailImage:PFBToastProbeThumbnail()];
      [toaster pushToast:toast withPriority:1000];
      PFBToastProbeLog(@"test thumbnail: pushed");
    });
    PFBToastProbeAfter(36.0, ^{
      PFBToastProbeLog(@"tests done · %ld lines", (long)gPFBToastProbeLines);
    });
}

// The tests wait for a running tour to end, three minutes at most.
static void PFBToastProbeStart(NSInteger tries) {
    if (!PFBCompatTourIsRunning()) {
        PFBToastProbeRunTests();
        return;
    }
    if (tries == 0) {
        PFBToastProbeLog(@"tests wait for the tour to end");
    }
    if (tries < 60) {
        PFBToastProbeAfter(3.0, ^{
          PFBToastProbeStart(tries + 1);
        });
    }
}

// MARK: - Hooks

%group PFBToastProbe

%hook TFNToaster

- (void)pushToast:(id)toast withPriority:(NSUInteger)priority {
    PFBToastProbeLog(@"pushed %@ · priority %lu", PFBToastProbeSummary(toast), (unsigned long)priority);
    %orig;
}

- (void)toastViewController:(id)controller didPresentToast:(id)toast {
    %orig;
    PFBToastProbeLog(@"shown %@ · %@ · %@ · %@", PFBToastProbeSummary(toast), gPFBToastProbePresented ?: @"no present step",
                     gPFBToastProbeContent ?: @"no new content view", gPFBToastProbeContainer ?: @"container not prepared");
    gPFBToastProbePresented = nil;
    gPFBToastProbeContent = nil;
    gPFBToastProbeContainer = nil;
    NSString* label = PFBToastProbeText([(id<PFBProbedToast>)toast respondsToSelector:@selector(messageText)]
                                            ? [(id<PFBProbedToast>)toast messageText]
                                            : PFBToastProbeName(toast),
                                        24);
    __weak id weakController = controller;
    PFBToastProbeAfter(0.4, ^{
      PFBToastProbeDump(weakController, label);
    });
}

- (void)toastViewController:(id)controller
            didDismissToast:(id)toast
                  withStyle:(NSUInteger)style
                  byGesture:(BOOL)gesture {
    PFBToastProbeLog(@"dismissed \"%@\" · style %lu · by gesture %@",
                     [(id<PFBProbedToast>)toast respondsToSelector:@selector(messageText)]
                         ? PFBToastProbeText([(id<PFBProbedToast>)toast messageText], 24)
                         : PFBToastProbeName(toast),
                     (unsigned long)style, gesture ? @"yes" : @"no");
    %orig;
}

%end

%hook TFNToastViewController

- (void)presentToast:(id)toast
                withStyle:(NSUInteger)style
      toastsUpdateEnabled:(BOOL)updated
                 animated:(BOOL)animated
               completion:(id)completion {
    gPFBToastProbePresented = [NSString stringWithFormat:@"present style %lu, new toasts %@, animated %@", (unsigned long)style,
                                                         updated ? @"yes" : @"no", animated ? @"yes" : @"no"];
    %orig;
}

%end

%hook XDSToastContentView

- (id)initWithFrame:(CGRect)frame configuration:(id)configuration {
    gPFBToastProbeContent = [@"content " stringByAppendingString:PFBToastProbeConfiguration(configuration)];
    return %orig;
}

%end

%hook T1ToastContainerView

- (void)prepareForToastWithUpdatedStyle:(BOOL)updated {
    %orig;
    gPFBToastProbeContainer = [NSString stringWithFormat:@"container prepared, new style %@", updated ? @"yes" : @"no"];
}

%end

%end

// Installed once the app's images are loaded; the tests run once per launch, a few seconds after
// the app first becomes active.
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!PFBDebugIsRecording()) {
          return;
      }
      NSArray<NSString*>* names = @[ @"TFNToaster", @"TFNToastViewController", @"XDSToastContentView", @"T1ToastContainerView" ];
      NSMutableArray<NSString*>* missing = [NSMutableArray array];
      for (NSString* name in names) {
          if (!objc_getClass(name.UTF8String)) {
              [missing addObject:name];
          }
      }
      PFBToastProbeLog(@"probe on · missing classes: %@", missing.count ? [missing componentsJoinedByString:@", "] : @"none");
      if (missing.count) {
          return;
      }
      %init(PFBToastProbe);
      __block id observer = [[NSNotificationCenter defaultCenter]
          addObserverForName:UIApplicationDidBecomeActiveNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(__unused NSNotification* note) {
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    observer = nil;
                    PFBToastProbeAfter(6.0, ^{
                      PFBToastProbeStart(0);
                    });
                  }];
      if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
          [[NSNotificationCenter defaultCenter] removeObserver:observer];
          observer = nil;
          PFBToastProbeAfter(6.0, ^{
            PFBToastProbeStart(0);
          });
      }
    });
}
