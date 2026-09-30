// The debugger's implementation; see PFBDebugger.h.

#import "Debug/PFBDebugger.h"
#import "Support/Generated/PFBHookManifest.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import "Support/HookHelpers.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <os/log.h>
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

static os_log_t PFBDebugLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.primefreebird.debug", "debugger"); });
    return log;
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

// A capture writes about 70 lines of its own reports into this ring; 300 keeps
// the scenario that led to it as well.
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

    // Timestamped to the second — enough to order decisions without noise.
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
    os_log(PFBDebugLogHandle(), "%{public}@", line);
}

// MARK: - watch list

// Class names added at runtime from the diagnostics screen. Every lifecycle event
// on a matching view is journaled with a millisecond stamp and the instance
// pointer, so a view being replaced rather than moved is readable.

static NSString* const kPFBWatchDefaultsKey = @"pfb_watch_classes";
static NSArray<NSString*>* gPFBWatchCache;

static void PFBWatchReload(void) {
    gPFBWatchCache = [[NSUserDefaults standardUserDefaults]
                         arrayForKey:kPFBWatchDefaultsKey] ?: @[];
}

NSArray<NSString*>* PFBWatchAll(void) {
    if (!gPFBWatchCache) {
        PFBWatchReload();
    }
    return gPFBWatchCache;
}

void PFBWatchAdd(NSString* fragment) {
    NSString* trimmed = [fragment stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) {
        return;
    }
    NSMutableArray* list = [PFBWatchAll() mutableCopy];
    if ([list containsObject:trimmed]) {
        return;
    }
    [list addObject:trimmed];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kPFBWatchDefaultsKey];
    PFBWatchReload();
    PFBDebugLog(@"[watch] + %@", trimmed);
}

void PFBWatchRemove(NSString* fragment) {
    NSMutableArray* list = [PFBWatchAll() mutableCopy];
    [list removeObject:fragment];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kPFBWatchDefaultsKey];
    PFBWatchReload();
    PFBDebugLog(@"[watch] - %@", fragment);
}

// Case-insensitive substring on the class name, so "Inbox" is enough to catch
// a mangled Swift name. Hot path: the empty-list case costs one count.
BOOL PFBWatchMatchesClassName(NSString* className) {
    if (!PFBDebugEnabled()) {
        return NO;
    }
    NSArray<NSString*>* list = PFBWatchAll();
    if (!list.count || !className.length) {
        return NO;
    }
    for (NSString* fragment in list) {
        if ([className rangeOfString:fragment
                             options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
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

    NSArray* watches = PFBWatchAll();
    NSString* watchLine = watches.count
        ? [NSString stringWithFormat:@"Watching: %@\n",
           [watches componentsJoinedByString:@", "]]
        : @"";
    return [NSString stringWithFormat:
        @"PFB DIAG\n"
        @"Twitter %@ (%@) · iOS %@ · %@\n"
        @"Interface: %@ · Liquid Glass %@\n%@",
        app, build, device.systemVersion, model,
        style, liquidGlass ? @"ON" : @"OFF", watchLine];
}

// MARK: - hook health

// The dead list is collected once per call and shared by the text block and
// the banner count, so the two can never disagree.
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

// The banner counts every hook that cannot run: vanished classes and missing
// methods alike.
NSUInteger PFBDebuggerMissingCount(void) {
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolved = [NSMutableArray array];
    NSMutableArray<NSString*>* deadRuntime = [NSMutableArray array];
    PFBCollectHealth(deadClasses, unresolved, deadRuntime, NULL);
    return deadClasses.count + deadRuntime.count + unresolved.count;
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
        return @"transparente";
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
        return [NSString stringWithFormat:@"alpha effectif %.2f", alpha];
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
    // anything relying on it (the pill mirror does) must be verifiable here.
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

// MARK: - share sheet

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

NSURL* PFBDebuggerWriteReportFile(void) {
    // A file, so the share sheet hands the report off whole — a large
    // hierarchy is painful to paste out of anything else.
    NSString* path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"PrimeFreeBird-diagnostic.txt"];
    NSError* error = nil;
    [PFBDebuggerReport() writeToFile:path
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error];
    return error ? nil : [NSURL fileURLWithPath:path];
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
    // A second tap while the sheet is up refreshes it instead of stacking a
    // twin on top.
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

    // The tab bar as it stands right now, not five seconds after launch: the
    // faults being chased only appear after a scroll, and a fixed
    // delay never catches them.
    PFBReportTabBarStack(@"capture");
    PFBReportNavigationBar(@"capture");

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
    if (!button.currentImage) {
        [button setTitle:@"PFB" forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    }
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
    // Once, after the first screen has settled, so the journal always carries a
    // picture of the branding surfaces without anyone adding a probe.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     PFBReportBrandingSurfaces();
                     PFBReportTabBarStack(@"5s");
                   });
    // The health check runs twice: the first pass catches the obvious, the second
    // gives frameworks that load with their screen time to arrive before their
    // classes are judged. The on-device screen recomputes on every open.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        os_log(PFBDebugLogHandle(), "%{public}@", PFBHealthBlock());
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSUInteger breaks = PFBDebuggerMissingCount();
        os_log(PFBDebugLogHandle(),
               "health (second pass, 12 s): %{public}lu missing class(es)",
               (unsigned long)breaks);
    });
}

#pragma mark - Branding surfaces

static NSString* PFBSurfaceImageInfo(UIImageView* view) {
    UIImage* image = view.image;
    if (!image) {
        return @"no image";
    }
    return [NSString stringWithFormat:@"%.0fx%.0f mode=%ld tint=%@ filters=%lu",
                                      image.size.width, image.size.height,
                                      (long)image.renderingMode,
                                      view.tintColor ?: (id)@"nil",
                                      (unsigned long)view.layer.filters.count];
}

void PFBReportBrandingSurfaces(void) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    UIWindow* window = nil;
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene respondsToSelector:@selector(windows)]) {
            continue;
        }
        for (UIWindow* candidate in [scene windows]) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
        if (window) {
            break;
        }
    }
    if (!window) {
        PFBDebugLog(@"[surfaces] no key window");
        return;
    }

    __block NSInteger logos = 0;
    __block NSInteger tabIcons = 0;
    __block NSString* tabHost = @"absent";
    __block NSString* tabGlass = @"none";
    __block NSString* opaquePanel = @"none";
    __block NSString* exploreBar = @"absent";

    PFBEnumerateSubviewsRecursively(window, ^(UIView* view) {
      NSString* name = NSStringFromClass([view class]);

      if ([name containsString:@"NavigationBarTitleControl"]) {
          PFBEnumerateSubviewsRecursively(view, ^(UIView* inner) {
            if ([inner isKindOfClass:[UIImageView class]] && logos < 3) {
                logos++;
                PFBDebugLog(@"[surfaces] logo #%ld %@ | %@", (long)logos,
                            NSStringFromClass([inner class]),
                            PFBSurfaceImageInfo((UIImageView*)inner));
            }
          });
      }

      if ([name containsString:@"CustomTabBar"]) {
          NSArray* siblings = view.superview.subviews;
          PFBDebugLog(@"[surfaces] custom tab bar at %lu/%lu in %@",
                      (unsigned long)[siblings indexOfObject:view],
                      (unsigned long)siblings.count,
                      NSStringFromClass([view.superview class]));
      }

      if ([name isEqualToString:@"T1TabBarHostView"]) {
          tabHost = name;
          CGFloat wide = view.bounds.size.width - 1;
          NSMutableArray* opaque = [NSMutableArray array];
          // The whole subtree, not the direct children: the panel that covers
          // the glass sits two wrappers down, and reading only the top level
          // reported "none" while a white panel was plainly on screen.
          PFBEnumerateSubviewsRecursively(view, ^(UIView* sub) {
            if ([sub isKindOfClass:[UIVisualEffectView class]]) {
                UIVisualEffect* effect = ((UIVisualEffectView*)sub).effect;
                // Present is not enough: the panel it is meant to cover sits in
                // the same parent, so the index decides whether it is seen.
                NSArray* siblings = sub.superview.subviews;
                tabGlass = [NSString
                    stringWithFormat:@"%@ at %lu/%lu in %@",
                                     effect ? NSStringFromClass([effect class]) : @"nil effect",
                                     (unsigned long)[siblings indexOfObject:sub],
                                     (unsigned long)siblings.count,
                                     NSStringFromClass([sub.superview class])];
                return;
            }
            if (sub.bounds.size.width < wide || sub.bounds.size.height < 8) {
                return;
            }
            CGFloat alpha = 0;
            if (![sub.backgroundColor getWhite:NULL alpha:&alpha]) {
                [sub.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&alpha];
            }
            if (alpha > 0.9 && opaque.count < 4) {
                NSArray* siblings = sub.superview.subviews;
                [opaque addObject:[NSString
                    stringWithFormat:@"%@ %.0fx%.0f a=%.2f at %lu/%lu",
                                     NSStringFromClass([sub class]), sub.bounds.size.width,
                                     sub.bounds.size.height, alpha,
                                     (unsigned long)[siblings indexOfObject:sub],
                                     (unsigned long)siblings.count]];
            }
          });
          if (opaque.count) {
              opaquePanel = [opaque componentsJoinedByString:@" // "];
          }
      }

      if ([name isEqualToString:@"T1TabView"] && tabIcons < 4) {
          PFBEnumerateSubviewsRecursively(view, ^(UIView* leaf) {
            if ([leaf isKindOfClass:[UIImageView class]] && leaf.bounds.size.width >= 16 &&
                tabIcons < 4) {
                tabIcons++;
                PFBDebugLog(@"[surfaces] tab icon #%ld | %@", (long)tabIcons,
                            PFBSurfaceImageInfo((UIImageView*)leaf));
            }
          });
      }

      if ([name containsString:@"SegmentedTabBarView"]) {
          exploreBar = name;
      }
    });

    PFBDebugLog(@"[surfaces] tab host=%@ | glass=%@ | opaque panel=%@", tabHost, tabGlass,
                opaquePanel);
    PFBDebugLog(@"[surfaces] explore bar=%@ | logos seen=%ld | tab icons seen=%ld", exploreBar,
                (long)logos, (long)tabIcons);
    PFBDebugLog(@"[surfaces] settings: names=%d icon=%d tabbar=%d glass=%d",
                [PFBSettings boolForKey:@"restore_twitter_names"],
                [PFBSettings boolForKey:@"color_twitter_icon_in_top_bar"],
                [PFBSettings boolForKey:@"tab_bar_theming"],
                [PFBSettings boolForKey:@"enable_liquid_glass"]);
}

#pragma mark - Tab bar stack

// Shared with Theme.x, which records the rung that carried the last tap.
const void* PFBTabRouteProbeKey(void) {
    static const void* key = &key;
    return key;
}

// Reports every property that can put an opaque pixel in front of the glass.
// Written after five builds spent guessing one cause at a time.
// Walks a view tree depth-first, handing each view and its depth to the block.
static void PFBDescribeTree(UIView* view, NSInteger depth,
                            void (^describe)(UIView*, NSInteger)) {
    describe(view, depth);
    for (UIView* sub in view.subviews) {
        PFBDescribeTree(sub, depth + 1, describe);
    }
}

void PFBReportTabBarStack(NSString* moment) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    // Every window, not the key one: during a capture the key window is the
    // debugger's own overlay, and the host lives in the app's window.
    __block UIView* host = nil;
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene respondsToSelector:@selector(windows)]) {
            continue;
        }
        for (UIWindow* candidate in [scene windows]) {
            PFBEnumerateSubviewsRecursively(candidate, ^(UIView* view) {
              if (!host && [NSStringFromClass([view class]) isEqualToString:@"T1TabBarHostView"]) {
                  host = view;
              }
            });
            if (host) {
                break;
            }
        }
        if (host) {
            break;
        }
    }
    UIWindow* window = host.window;
    if (!host) {
        PFBDebugLog(@"[stack:%@] no T1TabBarHostView on screen", moment);
        return;
    }

    PFBDebugLog(@"[stack:%@] --- T1TabBarHostView %.0fx%.0f ---", moment,
                host.bounds.size.width, host.bounds.size.height);

    __block NSInteger line = 0;
    void (^describe)(UIView*, NSInteger) = ^(UIView* view, NSInteger depth) {
      if (line >= 30) {
          return;
      }
      line++;
      NSMutableString* note = [NSMutableString string];
      for (NSInteger i = 0; i < depth; i++) {
          [note appendString:@"  "];
      }
      [note appendFormat:@"%@ %.0fx%.0f", NSStringFromClass([view class]),
                         view.bounds.size.width, view.bounds.size.height];
      if (view.hidden) {
          [note appendString:@" HIDDEN"];
      }
      if (view.alpha < 0.999) {
          [note appendFormat:@" alpha=%.2f", view.alpha];
      }
      CGFloat a = 0;
      if (view.backgroundColor &&
          ([view.backgroundColor getWhite:NULL alpha:&a] ||
           [view.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&a])) {
          [note appendFormat:@" bg=%@", view.backgroundColor];
      }
      if (view.layer.backgroundColor) {
          const CGFloat* c = CGColorGetComponents(view.layer.backgroundColor);
          size_t n = CGColorGetNumberOfComponents(view.layer.backgroundColor);
          if (c && n >= 2) {
              [note appendFormat:@" layerBg=(%.2f,%.2f)", c[0], c[n - 1]];
          }
      }
      if (view.layer.contents) {
          [note appendString:@" layerContents=YES"];
      }
      if (view.layer.filters.count) {
          [note appendFormat:@" filters=%lu", (unsigned long)view.layer.filters.count];
      }
      if (view.layer.sublayers.count > view.subviews.count) {
          [note appendFormat:@" extraSublayers=%lu",
                             (unsigned long)(view.layer.sublayers.count - view.subviews.count)];
      }
      if ([view isKindOfClass:[UIVisualEffectView class]]) {
          UIVisualEffect* effect = ((UIVisualEffectView*)view).effect;
          [note appendFormat:@" EFFECT=%@",
                             effect ? NSStringFromClass([effect class]) : @"nil"];
      }
      PFBDebugLog(@"[stack:%@] %@", moment, note);
    };

    // Depth-first, in draw order, so the report reads the way the screen does.
    // Recursion through a function pointer rather than a self-capturing block:
    // the block form warns about a retain cycle and needs clearing afterwards.
    PFBDescribeTree(host, 0, describe);

    // The native bar in detail: whether iOS grafted its own glass machinery on,
    // where it sits, how many items it carries and which one is selected.
    __block UITabBar* native = nil;
    PFBEnumerateSubviewsRecursively(host, ^(UIView* sub) {
      if (!native && [sub isKindOfClass:[UITabBar class]]) {
          native = (UITabBar*)sub;
      }
    });
    if (!native) {
        PFBDebugLog(@"[stack:%@] native UITabBar: ABSENT under the host", moment);
    } else {
        NSArray* siblings = native.superview.subviews;
        NSUInteger sel = native.selectedItem
                             ? [native.items indexOfObject:native.selectedItem]
                             : NSNotFound;
        PFBDebugLog(@"[stack:%@] native UITabBar %.0fx%.0f at %lu/%lu in %@ | items=%lu "
                    @"selected=%@ hidden=%d alpha=%.2f interaction=%d",
                    moment, native.bounds.size.width, native.bounds.size.height,
                    (unsigned long)[siblings indexOfObject:native],
                    (unsigned long)siblings.count,
                    NSStringFromClass([native.superview class]),
                    (unsigned long)native.items.count,
                    sel == NSNotFound ? @"none" : @(sel),
                    native.hidden, native.alpha, native.isUserInteractionEnabled);

        // What each item actually carries. The painting happens once at launch
        // and its line has scrolled out of the journal by the time of a capture,
        // so the state is read here instead of trusted from a log.
        NSMutableArray* itemState = [NSMutableArray array];
        for (UITabBarItem* item in native.items) {
            // The vector name each image was loaded under, when Branding.x
            // tagged it, and whether the selected image is a distinct object.
            NSString* imageName =
                item.image ? objc_getAssociatedObject(
                                 item.image, @selector(tfn_vectorImageNamed:fitsSize:fillColor:))
                           : nil;
            [itemState addObject:[NSString
                stringWithFormat:@"[%ld img=%@ mode=%ld sel=%@ %@]", (long)item.tag,
                                 imageName ?: (item.image ? @"untagged" : @"nil"),
                                 (long)item.image.renderingMode,
                                 item.selectedImage ? @"yes" : @"nil",
                                 item.selectedImage == item.image ? @"SAME" : @"distinct"]];
        }
        PFBDebugLog(@"[stack:%@] items: %@", moment,
                    itemState.count ? [itemState componentsJoinedByString:@" "] : @"(none)");

        NSMutableArray* inside = [NSMutableArray array];
        PFBEnumerateSubviewsRecursively(native, ^(UIView* sub) {
          if (inside.count < 14) {
              [inside addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f",
                                                           NSStringFromClass([sub class]),
                                                           sub.bounds.size.width,
                                                           sub.bounds.size.height]];
          }
        });
        PFBDebugLog(@"[stack:%@] native tree: %@", moment,
                    inside.count ? [inside componentsJoinedByString:@" // "] : @"(empty)");

        NSString* appearance = @"nil";
        if (native.standardAppearance) {
            appearance = [NSString
                stringWithFormat:@"bg=%@ effect=%@",
                                 native.standardAppearance.backgroundColor ?: (id)@"nil",
                                 native.standardAppearance.backgroundEffect
                                     ? NSStringFromClass(
                                           [native.standardAppearance.backgroundEffect class])
                                     : @"nil"];
        }
        PFBDebugLog(@"[stack:%@] native appearance: %@", moment, appearance);
    }

    // Twitter's own tab views: still on top, still touchable, and which one the
    // app treats as selected - the value the capsule is meant to follow.
    NSMutableArray* twitterTabs = [NSMutableArray array];
    PFBEnumerateSubviewsRecursively(host, ^(UIView* sub) {
      if ([NSStringFromClass([sub class]) isEqualToString:@"T1TabView"] &&
          twitterTabs.count < 6) {
          BOOL sel = [sub respondsToSelector:@selector(isSelected)] &&
                     [(id)sub isSelected];
          [twitterTabs addObject:[NSString stringWithFormat:@"%@%@%@",
                                                            sel ? @"[SEL]" : @"",
                                                            sub.hidden ? @"HIDDEN" : @"",
                                                            sub.isUserInteractionEnabled
                                                                ? @"tappable"
                                                                : @"INERT"]];
      }
    });
    PFBDebugLog(@"[stack:%@] twitter tabs: %@", moment,
                twitterTabs.count ? [twitterTabs componentsJoinedByString:@" "]
                                  : @"(none found)");

    // Which selection route exists, measured before any tap: the responder
    // chain above the app's bar is walked and every candidate reported, so a
    // bar that renders but does not navigate names its own cause.
    __block UIView* appBar = nil;
    PFBEnumerateSubviewsRecursively(host, ^(UIView* sub) {
      if (!appBar && [NSStringFromClass([sub class]) containsString:@"CustomTabBar"]) {
          appBar = sub;
      }
    });
    if (appBar) {
        NSMutableArray* chain = [NSMutableArray array];
        NSMutableArray* routes = [NSMutableArray array];
        UIResponder* up = appBar;
        NSInteger depth = 0;
        while (up && depth < 8) {
            [chain addObject:NSStringFromClass([up class])];
            if ([up respondsToSelector:NSSelectorFromString(@"selectTabAtIndex:")]) {
                [routes addObject:[NSString stringWithFormat:@"selectTabAtIndex: on %@",
                                                             NSStringFromClass([up class])]];
            }
            if ([up respondsToSelector:NSSelectorFromString(@"setSelectedIndex:")]) {
                [routes addObject:[NSString stringWithFormat:@"setSelectedIndex: on %@",
                                                             NSStringFromClass([up class])]];
            }
            if ([up respondsToSelector:NSSelectorFromString(@"setSelectedTab:")]) {
                [routes addObject:[NSString stringWithFormat:@"setSelectedTab: on %@",
                                                             NSStringFromClass([up class])]];
            }
            up = up.nextResponder;
            depth++;
        }
        PFBDebugLog(@"[stack:%@] responder chain: %@", moment,
                    [chain componentsJoinedByString:@" > "]);
        PFBDebugLog(@"[stack:%@] selection routes: %@", moment,
                    routes.count ? [routes componentsJoinedByString:@" // "] : @"NONE FOUND");

        // The tab views themselves: controls, gestures, and what the app calls
        // them - the raw material for any other route.
        NSMutableArray* tabInfo = [NSMutableArray array];
        PFBEnumerateSubviewsRecursively(appBar, ^(UIView* sub) {
          if (![NSStringFromClass([sub class]) isEqualToString:@"T1TabView"] ||
              tabInfo.count >= 5) {
              return;
          }
          NSMutableString* line = [NSMutableString string];
          [line appendFormat:@"%@", [sub respondsToSelector:@selector(isSelected)] &&
                                            [(id)sub isSelected]
                                        ? @"[SEL]"
                                        : @""];
          UIView* control = nil;
          for (UIView* u = sub; u && u != appBar.superview; u = u.superview) {
              if ([u isKindOfClass:[UIControl class]]) {
                  control = u;
                  break;
              }
          }
          [line appendFormat:@"control=%@", control ? NSStringFromClass([control class])
                                                    : @"none"];
          NSMutableArray* gestures = [NSMutableArray array];
          for (UIView* u = sub; u && u != appBar.superview; u = u.superview) {
              for (UIGestureRecognizer* g in u.gestureRecognizers) {
                  [gestures addObject:NSStringFromClass([g class])];
              }
          }
          [line appendFormat:@" gestures=%@",
                             gestures.count ? [gestures componentsJoinedByString:@","]
                                            : @"none"];
          [tabInfo addObject:line];
        });
        PFBDebugLog(@"[stack:%@] tab chain: %@", moment,
                    tabInfo.count ? [tabInfo componentsJoinedByString:@" || "] : @"(none)");
        PFBDebugLog(@"[stack:%@] app bar hidden=%d | last route used=%@", moment, appBar.hidden,
                    objc_getAssociatedObject(host, PFBTabRouteProbeKey()) ?: @"(no tap yet)");
    }

    // Who actually answers a touch at each tab's center. This is the question
    // three failed theories danced around: the native bar can be present,
    // interactive and on top and still not be the view UIKit hands the touch to.
    if (native) {
        NSMutableArray* hits = [NSMutableArray array];
        for (NSUInteger i = 0; i < native.items.count && i < 4; i++) {
            CGFloat step = native.bounds.size.width / MAX(1u, (unsigned)native.items.count);
            CGPoint point = CGPointMake(step * (i + 0.5), native.bounds.size.height / 2.0);
            UIView* hit = [window hitTest:[native convertPoint:point toView:window]
                                withEvent:nil];
            [hits addObject:hit ? NSStringFromClass([hit class]) : @"nil"];
        }
        PFBDebugLog(@"[stack:%@] hit test at each tab: %@", moment,
                    [hits componentsJoinedByString:@" | "]);
    }

    PFBDebugLog(@"[stack:%@] host.clipsToBounds=%d hostAlpha=%.2f windowLevel=%.0f", moment,
                host.clipsToBounds, host.alpha, window.windowLevel);
    PFBDebugLog(@"[stack:%@] glass setting=%d, accent active=%d", moment,
                [PFBSettings boolForKey:@"enable_liquid_glass"],
                [PFBSettings boolForKey:@"tab_bar_theming"]);
}

#pragma mark - Navigation bar

// The top bar's own tree, with each view's frame. Captured once on a good screen
// and once on a bad one, the two reports name the view that moved.
void PFBReportNavigationBar(NSString* moment) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    // Every window of every scene, not just the key one: the first pass looked
    // at a single window and reported nothing while a capture taken moments
    // later plainly showed a TFNNavigationBar.
    __block UIView* bar = nil;
    NSMutableArray* candidates = [NSMutableArray array];
    NSMutableArray* roots = [NSMutableArray array];
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene respondsToSelector:@selector(windows)]) {
            continue;
        }
        for (UIWindow* w in [scene windows]) {
            [roots addObject:[NSString stringWithFormat:@"%@%@ %.0fx%.0f",
                                                        NSStringFromClass([w class]),
                                                        w.isKeyWindow ? @"(key)" : @"",
                                                        w.bounds.size.width,
                                                        w.bounds.size.height]];
            PFBDescribeTree(w, 0, ^(UIView* view, NSInteger depth) {
              NSString* name = NSStringFromClass([view class]);
              if ([name containsString:@"NavigationBar"]) {
                  if (candidates.count < 8) {
                      [candidates addObject:name];
                  }
                  if (!bar && view.bounds.size.width > 200) {
                      bar = view;
                  }
              }
            });
        }
    }
    PFBDebugLog(@"[navbar:%@] windows: %@", moment,
                roots.count ? [roots componentsJoinedByString:@" // "] : @"(none)");
    if (!bar) {
        PFBDebugLog(@"[navbar:%@] nothing named NavigationBar; saw: %@", moment,
                    candidates.count ? [candidates componentsJoinedByString:@", "] : @"(none)");
        return;
    }
    PFBDebugLog(@"[navbar:%@] candidates: %@", moment,
                [candidates componentsJoinedByString:@", "]);
    PFBDebugLog(@"[navbar:%@] --- %@ %.0fx%.0f ---", moment,
                NSStringFromClass([bar class]), bar.bounds.size.width,
                bar.bounds.size.height);
    __block NSInteger line = 0;
    PFBDescribeTree(bar, 0, ^(UIView* view, NSInteger depth) {
      if (line >= 26) {
          return;
      }
      line++;
      NSMutableString* note = [NSMutableString string];
      for (NSInteger i = 0; i < depth; i++) {
          [note appendString:@"  "];
      }
      CGRect inBar = [view convertRect:view.bounds toView:bar];
      [note appendFormat:@"%@ x=%.0f w=%.0f h=%.0f", NSStringFromClass([view class]),
                         inBar.origin.x, inBar.size.width, inBar.size.height];
      if (view.hidden) {
          [note appendString:@" HIDDEN"];
      }
      PFBDebugLog(@"[navbar:%@] %@", moment, note);
    });
}
