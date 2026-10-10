// The debugger's implementation; see PFBDebugger.h.

#import "Debug/PFBDebugger.h"
#import "Support/Generated/PFBHookManifest.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import "Support/HookHelpers.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import "Debug/PFBDebugOverlayWindow.h"
#import "Debug/PFBDebugTrigger.h"

// MARK: - gate

static BOOL PFBDebugEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enabled = [PFBSettings boolForKey:@"debug_tools"];
    });
    return enabled;
}

BOOL PFBDebugIsRecording(void) {
    return PFBDebugEnabled();
}

// MARK: - marks

static char kPFBMarkKey;

void PFBMark(UIView* view, NSString* origin) {
    if (!PFBDebugEnabled() || !view || !origin.length) {
        return;
    }
    objc_setAssociatedObject(view, &kPFBMarkKey, origin, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static NSString* PFBMarkOf(UIView* view) {
    return objc_getAssociatedObject(view, &kPFBMarkKey);
}

// MARK: - decision log (ring buffer)

// The last 300 lines: enough to hold the scenario that led to a capture.
#define PFB_LOG_CAPACITY 300

static NSMutableArray<NSString*>* PFBDecisionRing(void) {
    static NSMutableArray* ring;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ring = [NSMutableArray arrayWithCapacity:PFB_LOG_CAPACITY]; });
    return ring;
}

void PFBDebugLog(NSString* format, ...) {
    if (!PFBDebugEnabled() || !format) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString* line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Timestamped to the millisecond, enough to order decisions.
    NSString* stamp;
    @synchronized(PFBDecisionRing()) {
        static NSDateFormatter* formatter;
        if (!formatter) {
            formatter = [NSDateFormatter new];
            formatter.dateFormat = @"HH:mm:ss.SSS";
        }
        stamp = [formatter stringFromDate:[NSDate date]];
        NSMutableArray* ring = PFBDecisionRing();
        [ring addObject:[NSString stringWithFormat:@"%@  %@", stamp, line]];
        if (ring.count > PFB_LOG_CAPACITY) {
            [ring removeObjectAtIndex:0];
        }
    }
}

// MARK: - environment

static NSString* PFBEnvironmentBlock(void) {
    NSDictionary* info = [NSBundle mainBundle].infoDictionary;
    NSString* app = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString* build = info[@"CFBundleVersion"] ?: @"?";
    UIDevice* device = [UIDevice currentDevice];

    // Model identifier (iPhone17,2 and the like), which the marketing name hides.
    struct utsname systemInfo;
    NSString* model = @"?";
    if (uname(&systemInfo) == 0) {
        model = [NSString stringWithCString:systemInfo.machine
                                   encoding:NSUTF8StringEncoding] ?: @"?";
    }

    UITraitCollection* traits = UITraitCollection.currentTraitCollection;
    NSString* style = traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? @"Dark" : @"Light";
    BOOL liquidGlass = [PFBSettings boolForKey:@"enable_liquid_glass"];

    return [NSString stringWithFormat:
        @"PFB DIAG\n"
        @"Twitter %@ (%@) · iOS %@ · %@\n"
        @"Interface: %@ · Liquid Glass %@\n",
        app, build, device.systemVersion, model,
        style, liquidGlass ? @"ON" : @"OFF"];
}

// MARK: - hook health

// The dead lists and the counts come from one pass, so the summary line and
// the lists below it always agree.
typedef struct {
    NSUInteger okClasses;
    NSUInteger okMethods;
    NSUInteger okRuntime;
} PFBHealthCounts;

// deadClasses: the class is gone, a real break. unresolved: class present, method
// not found statically, usually a Swift or category method the hook still reaches.
// deadRuntime: a by-name class is gone, a real break.
static void PFBCollectHealth(NSMutableArray<NSString*>* deadClasses,
                             NSMutableArray<NSString*>* unresolvedMethods,
                             NSMutableArray<NSString*>* deadRuntime,
                             PFBHealthCounts* counts) {
    NSUInteger okClasses = 0;
    NSUInteger okMethods = 0;

    // A NULL method means the class alone is checked. Methods carry their full
    // selector, so one the runtime cannot find is a hook that never runs.
    for (size_t i = 0; i < PFBHookRecordCount; i++) {
        PFBHookRecord record = PFBHookRecords[i];
        Class cls = objc_getClass(record.className);
        if (!cls) {
            // Deduplicate: several methods of one class each produced a row.
            NSString* entry = [NSString stringWithFormat:@"  x class %s  (%s)",
                               record.className, record.file];
            if (![deadClasses containsObject:entry]) {
                [deadClasses addObject:entry];
            }
            continue;
        }
        okClasses++;
        if (!record.methodName) {
            continue;
        }
        SEL selector = sel_registerName(record.methodName);
        // class_getInstanceMethod and getClassMethod both walk the superclass
        // chain already; respondsToSelector catches dynamically provided ones.
        BOOL exists = class_getInstanceMethod(cls, selector) != NULL ||
                      class_getClassMethod(cls, selector) != NULL ||
                      [cls instancesRespondToSelector:selector] ||
                      [cls respondsToSelector:selector];
        if (exists) {
            okMethods++;
        } else {
            [unresolvedMethods addObject:
                [NSString stringWithFormat:@"  · %s -%s  (%s)",
                 record.className, record.methodName, record.file]];
        }
    }

    // Classes resolved by name at runtime (%c / objc_getClass / …).
    NSUInteger okRuntime = 0;
    for (size_t i = 0; i < PFBRuntimeClassCount; i++) {
        if (objc_getClass(PFBRuntimeClasses[i])) {
            okRuntime++;
        } else {
            NSString* entry = [NSString stringWithFormat:@"  x class (by name) %s",
                               PFBRuntimeClasses[i]];
            if (![deadRuntime containsObject:entry]) {
                [deadRuntime addObject:entry];
            }
        }
    }

    if (counts) {
        counts->okClasses = okClasses;
        counts->okMethods = okMethods;
        counts->okRuntime = okRuntime;
    }
}

static NSString* PFBHealthBlock(void) {
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolved = [NSMutableArray array];
    NSMutableArray<NSString*>* deadRuntime = [NSMutableArray array];
    PFBHealthCounts counts = {0, 0, 0};
    PFBCollectHealth(deadClasses, unresolved, deadRuntime, &counts);

    // A vanished class and a missing method both mean a hook that never runs.
    NSUInteger breaks = deadClasses.count + deadRuntime.count;
    NSUInteger absent = unresolved.count;
    NSMutableString* out = [NSMutableString string];
    [out appendFormat:@"HOOKS  %lu classes, %lu methods, %lu by name - %@\n",
        (unsigned long)counts.okClasses, (unsigned long)counts.okMethods,
        (unsigned long)counts.okRuntime,
        (breaks || absent)
            ? [NSString stringWithFormat:@"%lu MISSING CLASS%@, %lu MISSING METHOD%@",
                  (unsigned long)breaks, breaks == 1 ? @"" : @"ES", (unsigned long)absent,
                  absent == 1 ? @"" : @"S"]
            : @"all present"];
    if (deadClasses.count) {
        [out appendString:[deadClasses componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    if (deadRuntime.count) {
        [out appendString:[deadRuntime componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    if (unresolved.count) {
        [out appendFormat:
            @"\nMETHODS ABSENT AT RUNTIME (%lu) - these hooks never run:\n",
            (unsigned long)unresolved.count];
        [out appendString:[unresolved componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    return out;
}

// MARK: - view capture

// The color actually painted in an image, since an AlwaysOriginal image carries
// its own pixels and the view's tint says nothing about what is drawn. ink is the
// average of the non-transparent pixels; cover is the effective ancestor alpha.
static NSString* PFBImageInk(UIImage* image) {
    if (!image) {
        return nil;
    }
    CGSize size = image.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return nil;
    }
    // Downsampled to 8x8: enough for an average, cheap enough for a full tree.
    const int side = 8;
    unsigned char bytes[8 * 8 * 4];
    memset(bytes, 0, sizeof(bytes));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(bytes, side, side, 8, side * 4, space,
                                             kCGImageAlphaPremultipliedLast |
                                             kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) {
        return nil;
    }
    UIGraphicsPushContext(ctx);
    CGContextClearRect(ctx, CGRectMake(0, 0, side, side));
    [image drawInRect:CGRectMake(0, 0, side, side)];
    UIGraphicsPopContext();
    CGContextRelease(ctx);

    double r = 0, g = 0, b = 0, n = 0;
    for (int i = 0; i < side * side; i++) {
        double a = bytes[i * 4 + 3] / 255.0;
        if (a < 0.15) {
            continue;   // transparent: not ink
        }
        // undo premultiplication so the reported color is the drawn color
        r += bytes[i * 4 + 0] / 255.0 / a;
        g += bytes[i * 4 + 1] / 255.0 / a;
        b += bytes[i * 4 + 2] / 255.0 / a;
        n += 1;
    }
    if (n < 1) {
        return @"transparent";
    }
    return [NSString stringWithFormat:@"rgb(%.0f,%.0f,%.0f)",
            MIN(r / n, 1.0) * 255, MIN(g / n, 1.0) * 255, MIN(b / n, 1.0) * 255];
}

// Effective visibility: alpha multiplied down the chain, and the first ancestor
// that clips this view out of its own bounds.
static NSString* PFBViewCover(UIView* view) {
    CGFloat alpha = 1.0;
    NSString* clipper = nil;
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 12) {
        alpha *= node.alpha;
        if (node.hidden) {
            return [NSString stringWithFormat:@"COVERED by %@",
                    NSStringFromClass([node class])];
        }
        UIView* parent = node.superview;
        if (parent && parent.clipsToBounds && !clipper) {
            CGRect inParent = [node convertRect:node.bounds toView:parent];
            if (!CGRectIntersectsRect(inParent, parent.bounds)) {
                clipper = NSStringFromClass([parent class]);
            }
        }
        node = parent;
        depth++;
    }
    if (clipper) {
        return [NSString stringWithFormat:@"OUT OF FRAME of %@", clipper];
    }
    if (alpha < 0.99) {
        return [NSString stringWithFormat:@"effective alpha %.2f", alpha];
    }
    return nil;
}

static NSString* PFBColourText(UIColor* colour) {
    if (!colour) {
        return @"nil";
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([colour getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.2f)", r*255, g*255, b*255, a];
    }
    CGFloat w = 0;
    if ([colour getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"white(%.2f,%.2f)", w, a];
    }
    return @"?";
}

static void PFBCaptureView(UIView* view, NSInteger depth, NSMutableString* out) {
    if (!view || depth > 24) {
        return;
    }
    NSMutableString* indent = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) {
        [indent appendString:@"  "];
    }

    CGRect inWindow = [view convertRect:view.bounds toView:nil];
    NSMutableString* line = [NSMutableString stringWithFormat:@"%@%@ %@",
        indent,
        NSStringFromClass([view classForCoder]),
        NSStringFromCGRect(view.frame)];

    // Only note colors and effects that are actually set, to keep it readable.
    if (view.backgroundColor) {
        [line appendFormat:@" bg=%@", PFBColourText(view.backgroundColor)];
    }
    if (view.layer.backgroundColor) {
        [line appendFormat:@" layer=%@",
            PFBColourText([UIColor colorWithCGColor:view.layer.backgroundColor])];
    }
    if (view.alpha < 0.999) {
        [line appendFormat:@" alpha=%.2f", view.alpha];
    }
    if (view.hidden) {
        [line appendString:@" HIDDEN"];
    }
    // zPosition orders sibling subtrees before add-order at composition time;
    // anything relying on it must be verifiable here.
    if (view.layer.zPosition != 0) {
        [line appendFormat:@" z=%.0f", view.layer.zPosition];
    }
    if ([view isKindOfClass:[UILabel class]]) {
        NSString* text = ((UILabel*)view).text ?: @"";
        if (text.length > 14) {
            text = [[text substringToIndex:14] stringByAppendingString:@"…"];
        }
        [line appendFormat:@" \"%@\"", text];
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage* image = ((UIImageView*)view).image;
        [line appendFormat:@" img=%@ mode=%ld",
            image ? NSStringFromCGSize(image.size) : @"nil",
            image ? (long)image.renderingMode : -1L];
        [line appendFormat:@" tint=%@", PFBColourText(view.tintColor)];
        NSString* ink = PFBImageInk(image);
        if (ink) {
            [line appendFormat:@" ink=%@", ink];
        }
        NSString* cover = PFBViewCover(view);
        if (cover) {
            [line appendFormat:@" [%@]", cover];
        }
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffect* fx = ((UIVisualEffectView*)view).effect;
        [line appendFormat:@" effect=%@",
            fx ? NSStringFromClass([fx classForCoder]) : @"nil"];
    }
    [line appendFormat:@" win=%@",
        NSStringFromCGRect(CGRectIntegral(inWindow))];
    [out appendString:line];
    [out appendString:@"\n"];

    // The tweak's own mark, if this view carries one — the line that turns
    // "what is this view" into "what did the tweak do to it".
    NSString* mark = PFBMarkOf(view);
    if (mark) {
        [out appendFormat:@"%s  ⟨PFB: %@⟩\n", indent.UTF8String, mark];
    }

    for (UIView* sub in view.subviews) {
        PFBCaptureView(sub, depth + 1, out);
    }
}

static NSString* gPFBLastCapture;

static NSString* PFBCaptureBlock(void) {
    if (!gPFBLastCapture.length) {
        return @"CAPTURE  none - tap the floating button on the screen to inspect\n";
    }
    return [NSString stringWithFormat:@"CAPTURE\n%@", gPFBLastCapture];
}

static NSString* PFBDecisionBlock(void) {
    @synchronized(PFBDecisionRing()) {
        NSArray* ring = PFBDecisionRing();
        if (!ring.count) {
            return @"DECISIONS  (none recorded)\n";
        }
        return [NSString stringWithFormat:@"DECISIONS (last %lu)\n%@\n",
                (unsigned long)ring.count, [ring componentsJoinedByString:@"\n"]];
    }
}

// MARK: - report

NSString* PFBDebuggerReport(void) {
    NSMutableString* report = [NSMutableString string];
    [report appendString:PFBEnvironmentBlock()];
    [report appendString:@"\n"];
    [report appendString:PFBHealthBlock()];
    [report appendString:@"\n"];
    [report appendString:PFBDecisionBlock()];
    [report appendString:@"\n"];
    [report appendString:PFBCaptureBlock()];
    return report;
}

// MARK: - floating trigger

// A motion gesture travels the first-responder chain, so with nothing first
// responder, or with the app consuming the event, the window never sees it. A
// button is always there and always answers.

static PFBDebugOverlayWindow* gPFBOverlay;

static UIWindow* PFBActiveWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            // Never the overlay: the report is about the app's screen.
            if ([window isKindOfClass:[PFBDebugOverlayWindow class]]) {
                continue;
            }
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        if (![window isKindOfClass:[PFBDebugOverlayWindow class]]) {
            return window;
        }
    }
    return nil;
}

void PFBDebuggerSetTriggerHidden(BOOL hidden) {
    gPFBOverlay.hidden = hidden;
}

void PFBDebuggerPresent(void) {
    UIWindow* window = PFBActiveWindow();
    UIViewController* host = window.rootViewController;
    while (host.presentedViewController) {
        host = host.presentedViewController;
    }
    if (!host) {
        return;
    }
    // A second tap while the sheet is up does nothing, so no twin stacks on top.
    if ([host isKindOfClass:[UINavigationController class]] &&
        [((UINavigationController*)host).topViewController
            isKindOfClass:[PFBCompatibilityReportViewController class]]) {
        return;
    }
    PFBCompatibilityReportViewController* screen =
        [[PFBCompatibilityReportViewController alloc] initWithStyle:UITableViewStyleGrouped];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:screen];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:nav animated:YES completion:nil];
}

// MARK: - capture

// Captures the screen and the journal, then presents them; the floating button calls it.
void PFBDebuggerCaptureAndPresent(void) {
    if (!PFBDebugEnabled()) {
        return;
    }
    UIWindow* window = PFBActiveWindow();
    if (!window) {
        return;
    }
    NSMutableString* capture = [NSMutableString string];
    // The frontmost view controller's view is the useful root — its own
    // hierarchy, not the whole window chrome.
    UIViewController* top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIView* root = top.viewIfLoaded ?: window;
    PFBCaptureView(root, 0, capture);
    gPFBLastCapture = capture;
    PFBDebugLog(@"[capture] taken (%lu characters)", (unsigned long)capture.length);

    PFBDebuggerPresent();
}

// MARK: - install

static UIView* PFBFirstSubviewOfClass(UIView* root, Class cls) {
    if ([root isKindOfClass:cls]) {
        return root;
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBFirstSubviewOfClass(sub, cls);
        if (found) {
            return found;
        }
    }
    return nil;
}

// Centered on Twitter's compose button and 16 pt above it, whether the button
// shows or not; without one on screen, at the fixed spot the button occupies.
static CGPoint PFBTriggerCenter(UIWindowScene* scene) {
    CGSize size = scene.coordinateSpace.bounds.size;
    Class composeClass = NSClassFromString(@"TFNFloatingActionButton");
    for (UIWindow* window in scene.windows) {
        UIView* compose = composeClass ? PFBFirstSubviewOfClass(window, composeClass) : nil;
        if (compose && !CGRectIsEmpty(compose.bounds)) {
            CGRect frame = [compose convertRect:compose.bounds toView:nil];
            return CGPointMake(CGRectGetMidX(frame), CGRectGetMinY(frame) - 16.0 - 25.0);
        }
    }
    return CGPointMake(size.width - 37.0, size.height - 189.0);
}

static void PFBInstallTrigger(void) {
    if (gPFBOverlay) {
        return;
    }
    UIWindowScene* scene = nil;
    for (UIScene* candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene*)candidate;
            break;
        }
    }
    if (!scene) {
        return;
    }

    gPFBOverlay = [[PFBDebugOverlayWindow alloc] initWithWindowScene:scene];
    gPFBOverlay.windowLevel = UIWindowLevelAlert + 100;
    gPFBOverlay.backgroundColor = UIColor.clearColor;
    gPFBOverlay.rootViewController = [UIViewController new];
    gPFBOverlay.rootViewController.view.backgroundColor = UIColor.clearColor;
    // Shown, never made key: making it key would put the report's own window
    // in front of the screen it is meant to describe.
    gPFBOverlay.hidden = NO;

    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 50, 50);
    button.center = PFBTriggerCenter(scene);
    button.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.82];
    button.layer.cornerRadius = 25.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    button.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration* glyph =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:@"stethoscope" withConfiguration:glyph]
            forState:UIControlStateNormal];
    [button addTarget:[PFBDebugTrigger shared]
               action:@selector(tapped)
     forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:[PFBDebugTrigger shared]
                                                action:@selector(dragged:)]];
    [gPFBOverlay.rootViewController.view addSubview:button];
}

void PFBDebuggerInstall(void) {
    if (!PFBDebugEnabled()) {
        return;
    }
    // The scene is not connected at launch, so the button is placed once the
    // first screen is up, and retried if it was not ready.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ PFBInstallTrigger(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ PFBInstallTrigger(); });
}
