//
//  NFBDebugger.m
//
//  See NFBDebugger.h for the shape of the thing. Everything here is inert
//  unless flex_twitter is on, checked once and cached.
//

#import "Debug/NFBDebugger.h"
#import "Generated/NFBHookManifest.h"
#import "Core/BHTSettings.h"
#import "Hooks/HookHelpers.h"
#import "Debug/NFBDiagnosticsViewController.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <sys/utsname.h>

// MARK: - gate

static BOOL NFBDebugEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enabled = [BHTSettings boolForKey:@"flex_twitter"];
    });
    return enabled;
}

BOOL NFBDebugIsRecording(void) {
    return NFBDebugEnabled();
}

static os_log_t NFBDebugLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.primefreebird.debug", "debugger"); });
    return log;
}

// MARK: - marks

static char kNFBMarkKey;

void NFBMark(UIView* view, NSString* origin) {
    if (!NFBDebugEnabled() || !view || !origin.length) {
        return;
    }
    objc_setAssociatedObject(view, &kNFBMarkKey, origin, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static NSString* NFBMarkOf(UIView* view) {
    return objc_getAssociatedObject(view, &kNFBMarkKey);
}

// MARK: - decision log (ring buffer)

#define NFB_LOG_CAPACITY 80

static NSMutableArray<NSString*>* NFBDecisionRing(void) {
    static NSMutableArray* ring;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ring = [NSMutableArray arrayWithCapacity:NFB_LOG_CAPACITY]; });
    return ring;
}

void NFBDebugLog(NSString* format, ...) {
    if (!NFBDebugEnabled() || !format) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString* line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Timestamped to the second — enough to order decisions without noise.
    NSString* stamp;
    @synchronized(NFBDecisionRing()) {
        static NSDateFormatter* formatter;
        if (!formatter) {
            formatter = [NSDateFormatter new];
            formatter.dateFormat = @"HH:mm:ss.SSS";
        }
        stamp = [formatter stringFromDate:[NSDate date]];
        NSMutableArray* ring = NFBDecisionRing();
        [ring addObject:[NSString stringWithFormat:@"%@  %@", stamp, line]];
        if (ring.count > NFB_LOG_CAPACITY) {
            [ring removeObjectAtIndex:0];
        }
    }
    os_log(NFBDebugLogHandle(), "%{public}@", line);
}

// MARK: - watch list
//
// The journal alone could only record
// what the current hypothesis said to record. This is the missing capability:
// class names added HERE, at runtime, from the diagnostics screen — and every
// lifecycle event on matching views is journaled with millisecond stamps and
// the instance pointer. "Removed, then a DIFFERENT instance arrives 100 ms
// later" becomes three journal lines instead of three builds.

static NSString* const kNFBWatchDefaultsKey = @"nfb_watch_classes";
static NSArray<NSString*>* gNFBWatchCache;

static void NFBWatchReload(void) {
    gNFBWatchCache = [[NSUserDefaults standardUserDefaults]
                         arrayForKey:kNFBWatchDefaultsKey] ?: @[];
}

NSArray<NSString*>* NFBWatchAll(void) {
    if (!gNFBWatchCache) {
        NFBWatchReload();
    }
    return gNFBWatchCache;
}

void NFBWatchAdd(NSString* fragment) {
    NSString* trimmed = [fragment stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) {
        return;
    }
    NSMutableArray* list = [NFBWatchAll() mutableCopy];
    if ([list containsObject:trimmed]) {
        return;
    }
    [list addObject:trimmed];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kNFBWatchDefaultsKey];
    NFBWatchReload();
    NFBDebugLog(@"surveillance: + %@", trimmed);
}

void NFBWatchRemove(NSString* fragment) {
    NSMutableArray* list = [NFBWatchAll() mutableCopy];
    [list removeObject:fragment];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kNFBWatchDefaultsKey];
    NFBWatchReload();
    NFBDebugLog(@"surveillance: - %@", fragment);
}

// Case-insensitive substring on the class name, so "Inbox" is enough to catch
// a mangled Swift name. Hot path: the empty-list case costs one count.
BOOL NFBWatchMatchesClassName(NSString* className) {
    if (!NFBDebugEnabled()) {
        return NO;
    }
    NSArray<NSString*>* list = NFBWatchAll();
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

static NSString* NFBEnvironmentBlock(void) {
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
        ? @"Sombre" : @"Clair";
    BOOL liquidGlass = [BHTSettings boolForKey:@"enable_liquid_glass"];

    NSArray* watches = NFBWatchAll();
    NSString* watchLine = watches.count
        ? [NSString stringWithFormat:@"Surveillance: %@\n",
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
} NFBHealthCounts;

// deadClasses  — the class is gone: a real break, counted and shown loud.
// unresolved   — class present, method not found statically: usually a Swift or
//                category method the hook still reaches; shown quietly.
// deadRuntime  — a by-name class is gone: a real break.
static void NFBCollectHealth(NSMutableArray<NSString*>* deadClasses,
                             NSMutableArray<NSString*>* unresolvedMethods,
                             NSMutableArray<NSString*>* deadRuntime,
                             NFBHealthCounts* counts) {
    NSUInteger okClasses = 0;
    NSUInteger okMethods = 0;

    // Class + method dependencies. A NULL method means "class hooked, no
    // specific method" — the class alone is checked.
    //
    // Two failure kinds, kept apart because they mean different things:
    //   · the CLASS is gone      → the whole hook is dead, a real break
    //   · the class is here but   → often a false alarm: Swift methods and
    //     the method isn't found     category methods don't always answer
    //     statically                 class_getInstanceMethod, yet the hook
    //                                still lands. Reported quietly, not counted
    //                                as a break.
    for (size_t i = 0; i < NFBHookRecordCount; i++) {
        NFBHookRecord record = NFBHookRecords[i];
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
    for (size_t i = 0; i < NFBRuntimeClassCount; i++) {
        if (objc_getClass(NFBRuntimeClasses[i])) {
            okRuntime++;
        } else {
            NSString* entry = [NSString stringWithFormat:@"  x class (by name) %s",
                               NFBRuntimeClasses[i]];
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

static NSString* NFBHealthBlock(void) {
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolved = [NSMutableArray array];
    NSMutableArray<NSString*>* deadRuntime = [NSMutableArray array];
    NFBHealthCounts counts = {0, 0, 0};
    NFBCollectHealth(deadClasses, unresolved, deadRuntime, &counts);

    // Only vanished classes count as breaks — the loud number. Unresolved
    // methods are listed below under their own quiet heading.
    NSUInteger breaks = deadClasses.count + deadRuntime.count;
    NSMutableString* out = [NSMutableString string];
    [out appendFormat:@"HOOKS  %lu classes, %lu methods, %lu by name - %@\n",
        (unsigned long)counts.okClasses, (unsigned long)counts.okMethods,
        (unsigned long)counts.okRuntime,
        breaks ? [NSString stringWithFormat:@"%lu MISSING CLASS%@",
                    (unsigned long)breaks, breaks > 1 ? @"ES" : @""]
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
            @"\nMETHODS NOT RESOLVED STATICALLY (%lu) - often Swift or a "
            @"category, in which case the hook still works:\n", (unsigned long)unresolved.count];
        [out appendString:[unresolved componentsJoinedByString:@"\n"]];
        [out appendString:@"\n"];
    }
    return out;
}

// The banner counts only real breaks — vanished classes — not the quiet
// unresolved-method list, which is mostly false alarms.
NSUInteger NFBDebuggerMissingCount(void) {
    NSMutableArray<NSString*>* deadClasses = [NSMutableArray array];
    NSMutableArray<NSString*>* unresolved = [NSMutableArray array];
    NSMutableArray<NSString*>* deadRuntime = [NSMutableArray array];
    NFBCollectHealth(deadClasses, unresolved, deadRuntime, NULL);
    return deadClasses.count + deadRuntime.count;
}

// MARK: - view capture


// The colour actually PAINTED in an image, and the visibility of the view that
// carries it.
//
// An AlwaysOriginal image carries its own pixels, so the view's tint says
// nothing about what is drawn: a glyph baked white reads exactly like a glyph
// baked grey. Size and tint alone therefore cannot separate "the image is
// invisible" from "something covers it".
//
// ink= is the average colour of the image's non-transparent pixels (nil when
// the image is fully transparent), and cover= the effective alpha down the
// ancestor chain plus any ancestor that clips it away.
static NSString* NFBImageInk(UIImage* image) {
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
        // undo premultiplication so the reported colour is the drawn colour
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
static NSString* NFBViewCover(UIView* view) {
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

static NSString* NFBColourText(UIColor* colour) {
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

static void NFBCaptureView(UIView* view, NSInteger depth, NSMutableString* out) {
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

    // Only note colours and effects that are actually set, to keep it readable.
    if (view.backgroundColor) {
        [line appendFormat:@" bg=%@", NFBColourText(view.backgroundColor)];
    }
    if (view.layer.backgroundColor) {
        [line appendFormat:@" layer=%@",
            NFBColourText([UIColor colorWithCGColor:view.layer.backgroundColor])];
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
        [line appendFormat:@" tint=%@", NFBColourText(view.tintColor)];
        NSString* ink = NFBImageInk(image);
        if (ink) {
            [line appendFormat:@" ink=%@", ink];
        }
        NSString* cover = NFBViewCover(view);
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
    NSString* mark = NFBMarkOf(view);
    if (mark) {
        [out appendFormat:@"%s  ⟨PFB: %@⟩\n", indent.UTF8String, mark];
    }

    for (UIView* sub in view.subviews) {
        NFBCaptureView(sub, depth + 1, out);
    }
}

static NSString* gNFBLastCapture;

static NSString* NFBCaptureBlock(void) {
    if (!gNFBLastCapture.length) {
        return @"CAPTURE  none - shake the device on the screen to inspect\n";
    }
    return [NSString stringWithFormat:@"CAPTURE\n%@", gNFBLastCapture];
}

static NSString* NFBDecisionBlock(void) {
    @synchronized(NFBDecisionRing()) {
        NSArray* ring = NFBDecisionRing();
        if (!ring.count) {
            return @"DECISIONS  (none recorded)\n";
        }
        return [NSString stringWithFormat:@"DECISIONS (last %lu)\n%@\n",
                (unsigned long)ring.count, [ring componentsJoinedByString:@"\n"]];
    }
}

// MARK: - report

NSString* NFBDebuggerReport(void) {
    NSMutableString* report = [NSMutableString string];
    [report appendString:NFBEnvironmentBlock()];
    [report appendString:@"\n"];
    [report appendString:NFBHealthBlock()];
    [report appendString:@"\n"];
    [report appendString:NFBDecisionBlock()];
    [report appendString:@"\n"];
    [report appendString:NFBCaptureBlock()];
    return report;
}

// MARK: - share sheet

// MARK: - floating trigger
//
// The shake gesture proved unreliable: motion events travel the first-responder
// chain, and when nothing is first responder — or the app consumes the event —
// the window never sees them. A button is not a gesture: it is always there and
// always answers, the way FLEX's is.

// Its own window so it survives every screen change, above everything, and
// never becomes key — the capture must read the app's window, not this one.
@interface NFBDebugOverlayWindow : UIWindow
@end

@implementation NFBDebugOverlayWindow
// Everything except the button falls through to the app underneath, so the
// overlay costs nothing in use.
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end

static NFBDebugOverlayWindow* gNFBOverlay;

static UIWindow* NFBActiveWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            // Never the overlay: the report is about the app's screen.
            if ([window isKindOfClass:[NFBDebugOverlayWindow class]]) {
                continue;
            }
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        if (![window isKindOfClass:[NFBDebugOverlayWindow class]]) {
            return window;
        }
    }
    return nil;
}

void NFBDebuggerSetTriggerHidden(BOOL hidden) {
    gNFBOverlay.hidden = hidden;
}

NSURL* NFBDebuggerWriteReportFile(void) {
    // A file, so the share sheet hands the report off whole — a large
    // hierarchy is painful to paste out of anything else.
    NSString* path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"PrimeFreeBird-diagnostic.txt"];
    NSError* error = nil;
    [NFBDebuggerReport() writeToFile:path
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error];
    return error ? nil : [NSURL fileURLWithPath:path];
}

void NFBDebuggerPresent(void) {
    UIWindow* window = NFBActiveWindow();
    UIViewController* host = window.rootViewController;
    while (host.presentedViewController) {
        host = host.presentedViewController;
    }
    if (!host) {
        return;
    }
    // A second shake while the sheet is up refreshes it instead of stacking a
    // twin on top.
    if ([host isKindOfClass:[UINavigationController class]] &&
        [((UINavigationController*)host).topViewController
            isKindOfClass:[NFBDiagnosticsViewController class]]) {
        return;
    }
    NFBDiagnosticsViewController* screen = [NFBDiagnosticsViewController new];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:screen];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:nav animated:YES completion:nil];
}

// MARK: - shake

// The tweak's own window subclass would be heavy; instead the shake is caught
// on UIWindow via a hook (see NFBDebugShake.x) which calls this.
void NFBDebuggerCaptureAndPresent(void) {
    if (!NFBDebugEnabled()) {
        return;
    }
    UIWindow* window = NFBActiveWindow();
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
    NFBCaptureView(root, 0, capture);
    gNFBLastCapture = capture;
    NFBDebugLog(@"capture taken (%lu characters)", (unsigned long)capture.length);

    NFBDebuggerPresent();
}

// MARK: - install

// The button's target lives on an object because a UIControl needs one; it does
// nothing but forward to the capture, and drags itself out of the way.
@interface NFBDebugTrigger : NSObject
@end

@implementation NFBDebugTrigger

+ (instancetype)shared {
    static NFBDebugTrigger* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [NFBDebugTrigger new]; });
    return shared;
}

- (void)tapped {
    NFBDebuggerCaptureAndPresent();
}

// Dragged rather than fixed: a diagnostics button that covers the thing being
// diagnosed is worse than none.
- (void)dragged:(UIPanGestureRecognizer*)pan {
    UIView* button = pan.view;
    CGPoint delta = [pan translationInView:button.superview];
    CGPoint centre = button.center;
    centre.x += delta.x;
    centre.y += delta.y;
    CGRect bounds = button.superview.bounds;
    CGFloat inset = button.bounds.size.width / 2 + 4;
    centre.x = MAX(inset, MIN(bounds.size.width - inset, centre.x));
    centre.y = MAX(inset, MIN(bounds.size.height - inset, centre.y));
    button.center = centre;
    [pan setTranslation:CGPointZero inView:button.superview];
}

@end

static void NFBInstallTrigger(void) {
    if (gNFBOverlay) {
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

    gNFBOverlay = [[NFBDebugOverlayWindow alloc] initWithWindowScene:scene];
    gNFBOverlay.windowLevel = UIWindowLevelAlert + 100;
    gNFBOverlay.backgroundColor = UIColor.clearColor;
    gNFBOverlay.rootViewController = [UIViewController new];
    gNFBOverlay.rootViewController.view.backgroundColor = UIColor.clearColor;
    // Shown, never made key: making it key would put the report's own window
    // in front of the screen it is meant to describe.
    gNFBOverlay.hidden = NO;

    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 46, 46);
    button.center = CGPointMake(scene.coordinateSpace.bounds.size.width - 38,
                                scene.coordinateSpace.bounds.size.height * 0.62);
    button.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.82];
    button.layer.cornerRadius = 23.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    button.tintColor = UIColor.whiteColor;
    [button setImage:[UIImage systemImageNamed:@"stethoscope"] forState:UIControlStateNormal];
    if (!button.currentImage) {
        [button setTitle:@"PFB" forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    }
    [button addTarget:[NFBDebugTrigger shared]
               action:@selector(tapped)
     forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:[NFBDebugTrigger shared]
                                                action:@selector(dragged:)]];
    [gNFBOverlay.rootViewController.view addSubview:button];
}

void NFBDebuggerInstall(void) {
    if (!NFBDebugEnabled()) {
        return;
    }
    // The scene is not connected at launch, so the button is placed once the
    // first screen is up, and retried if it was not ready.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ NFBInstallTrigger(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ NFBInstallTrigger(); });
    // Once, after the first screen has settled, so the journal always carries a
    // picture of the branding surfaces without anyone adding a probe.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     NFBReportBrandingSurfaces();
                     NFBReportTabBarStack(@"5s");
                   });
    // A second look once the app has settled: anything the app repaints between
    // the two reads shows up as a difference instead of a theory.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ NFBReportTabBarStack(@"12s"); });
    // The health check runs twice. The first pass, soon after launch, catches
    // the obvious. The second, later, gives frameworks that only load with
    // their screen (DM, Immersive, Guide) time to arrive before their classes
    // are judged — otherwise every not-yet-loaded class reads as a false break.
    // The on-device screen recomputes on every open anyway, so it is always
    // current; these log passes are for a developer watching at launch.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        os_log(NFBDebugLogHandle(), "%{public}@", NFBHealthBlock());
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSUInteger breaks = NFBDebuggerMissingCount();
        os_log(NFBDebugLogHandle(),
               "health (second pass, 12 s): %{public}lu missing class(es)",
               (unsigned long)breaks);
    });
}

// The shake hook still calls this; kept because it costs nothing and works on
// screens where the responder chain cooperates.
void NFBDebuggerHandleShake(void) {
    NFBDebuggerCaptureAndPresent();
}

#pragma mark - Branding surfaces

static NSString* NFBSurfaceImageInfo(UIImageView* view) {
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

void NFBReportBrandingSurfaces(void) {
    if (!NFBDebugIsRecording()) {
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
        NFBDebugLog(@"[surfaces] no key window");
        return;
    }

    __block NSInteger logos = 0;
    __block NSInteger tabIcons = 0;
    __block NSString* tabHost = @"absent";
    __block NSString* tabGlass = @"none";
    __block NSString* opaquePanel = @"none";
    __block NSString* exploreBar = @"absent";

    EnumerateSubviewsRecursively(window, ^(UIView* view) {
      NSString* name = NSStringFromClass([view class]);

      if ([name containsString:@"NavigationBarTitleControl"]) {
          EnumerateSubviewsRecursively(view, ^(UIView* inner) {
            if ([inner isKindOfClass:[UIImageView class]] && logos < 3) {
                logos++;
                NFBDebugLog(@"[surfaces] logo #%ld %@ | %@", (long)logos,
                            NSStringFromClass([inner class]),
                            NFBSurfaceImageInfo((UIImageView*)inner));
            }
          });
      }

      if ([name containsString:@"CustomTabBar"]) {
          NSArray* siblings = view.superview.subviews;
          NFBDebugLog(@"[surfaces] custom tab bar at %lu/%lu in %@",
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
          EnumerateSubviewsRecursively(view, ^(UIView* sub) {
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
          EnumerateSubviewsRecursively(view, ^(UIView* leaf) {
            if ([leaf isKindOfClass:[UIImageView class]] && leaf.bounds.size.width >= 16 &&
                tabIcons < 4) {
                tabIcons++;
                NFBDebugLog(@"[surfaces] tab icon #%ld | %@", (long)tabIcons,
                            NFBSurfaceImageInfo((UIImageView*)leaf));
            }
          });
      }

      if ([name containsString:@"SegmentedTabBarView"]) {
          exploreBar = name;
      }
    });

    NFBDebugLog(@"[surfaces] tab host=%@ | glass=%@ | opaque panel=%@", tabHost, tabGlass,
                opaquePanel);
    NFBDebugLog(@"[surfaces] explore bar=%@ | logos seen=%ld | tab icons seen=%ld", exploreBar,
                (long)logos, (long)tabIcons);
    NFBDebugLog(@"[surfaces] settings: names=%d icon=%d tabbar=%d glass=%d",
                [BHTSettings boolForKey:@"restore_twitter_names"],
                [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"],
                [BHTSettings boolForKey:@"tab_bar_theming"],
                [BHTSettings boolForKey:@"enable_liquid_glass"]);
}

#pragma mark - Tab bar stack

// Shared with Theme.x, which records the rung that carried the last tap.
const void* NFBTabRouteProbeKey(void) {
    static const void* key = &key;
    return key;
}

// Reports every property that can put an opaque pixel in front of the glass.
// Written after five builds spent guessing one cause at a time.
// Walks a view tree depth-first, handing each view and its depth to the block.
static void NFBDescribeTree(UIView* view, NSInteger depth,
                            void (^describe)(UIView*, NSInteger)) {
    describe(view, depth);
    for (UIView* sub in view.subviews) {
        NFBDescribeTree(sub, depth + 1, describe);
    }
}

void NFBReportTabBarStack(NSString* moment) {
    if (!NFBDebugIsRecording()) {
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
    __block UIView* host = nil;
    EnumerateSubviewsRecursively(window, ^(UIView* view) {
      if (!host && [NSStringFromClass([view class]) isEqualToString:@"T1TabBarHostView"]) {
          host = view;
      }
    });
    if (!host) {
        NFBDebugLog(@"[stack:%@] no T1TabBarHostView on screen", moment);
        return;
    }

    NFBDebugLog(@"[stack:%@] --- T1TabBarHostView %.0fx%.0f ---", moment,
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
      NFBDebugLog(@"[stack:%@] %@", moment, note);
    };

    // Depth-first, in draw order, so the report reads the way the screen does.
    // Recursion through a function pointer rather than a self-capturing block:
    // the block form warns about a retain cycle and needs clearing afterwards.
    NFBDescribeTree(host, 0, describe);

    // The native bar, in detail: whether iOS grafted its own glass machinery on
    // (the _UILiquidLens / platter / floating-provider views), where it sits,
    // how many items it carries and which one is selected. If the capsule never
    // appears, this is the line that says whether UIKit built it at all.
    __block UITabBar* native = nil;
    EnumerateSubviewsRecursively(host, ^(UIView* sub) {
      if (!native && [sub isKindOfClass:[UITabBar class]]) {
          native = (UITabBar*)sub;
      }
    });
    if (!native) {
        NFBDebugLog(@"[stack:%@] native UITabBar: ABSENT under the host", moment);
    } else {
        NSArray* siblings = native.superview.subviews;
        NSUInteger sel = native.selectedItem
                             ? [native.items indexOfObject:native.selectedItem]
                             : NSNotFound;
        NFBDebugLog(@"[stack:%@] native UITabBar %.0fx%.0f at %lu/%lu in %@ | items=%lu "
                    @"selected=%@ hidden=%d alpha=%.2f interaction=%d",
                    moment, native.bounds.size.width, native.bounds.size.height,
                    (unsigned long)[siblings indexOfObject:native],
                    (unsigned long)siblings.count,
                    NSStringFromClass([native.superview class]),
                    (unsigned long)native.items.count,
                    sel == NSNotFound ? @"none" : @(sel),
                    native.hidden, native.alpha, native.isUserInteractionEnabled);

        NSMutableArray* inside = [NSMutableArray array];
        EnumerateSubviewsRecursively(native, ^(UIView* sub) {
          if (inside.count < 14) {
              [inside addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f",
                                                           NSStringFromClass([sub class]),
                                                           sub.bounds.size.width,
                                                           sub.bounds.size.height]];
          }
        });
        NFBDebugLog(@"[stack:%@] native tree: %@", moment,
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
        NFBDebugLog(@"[stack:%@] native appearance: %@", moment, appearance);
    }

    // Twitter's own tab views: still on top, still touchable, and which one the
    // app treats as selected - the value the capsule is meant to follow.
    NSMutableArray* twitterTabs = [NSMutableArray array];
    EnumerateSubviewsRecursively(host, ^(UIView* sub) {
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
    NFBDebugLog(@"[stack:%@] twitter tabs: %@", moment,
                twitterTabs.count ? [twitterTabs componentsJoinedByString:@" "]
                                  : @"(none found)");

    // Which selection route exists, measured before any tap: the responder
    // chain above the app's bar is walked and every candidate reported, so a
    // bar that renders but does not navigate names its own cause.
    __block UIView* appBar = nil;
    EnumerateSubviewsRecursively(host, ^(UIView* sub) {
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
        NFBDebugLog(@"[stack:%@] responder chain: %@", moment,
                    [chain componentsJoinedByString:@" > "]);
        NFBDebugLog(@"[stack:%@] selection routes: %@", moment,
                    routes.count ? [routes componentsJoinedByString:@" // "] : @"NONE FOUND");

        // The tab views themselves: controls, gestures, and what the app calls
        // them - the raw material for any other route.
        NSMutableArray* tabInfo = [NSMutableArray array];
        EnumerateSubviewsRecursively(appBar, ^(UIView* sub) {
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
        NFBDebugLog(@"[stack:%@] tab chain: %@", moment,
                    tabInfo.count ? [tabInfo componentsJoinedByString:@" || "] : @"(none)");
        NFBDebugLog(@"[stack:%@] app bar hidden=%d | last route used=%@", moment, appBar.hidden,
                    objc_getAssociatedObject(host, NFBTabRouteProbeKey()) ?: @"(no tap yet)");
    }

    NFBDebugLog(@"[stack:%@] host.clipsToBounds=%d hostAlpha=%.2f windowLevel=%.0f", moment,
                host.clipsToBounds, host.alpha, window.windowLevel);
    NFBDebugLog(@"[stack:%@] glass setting=%d, accent active=%d", moment,
                [BHTSettings boolForKey:@"enable_liquid_glass"],
                [BHTSettings boolForKey:@"tab_bar_theming"]);
}

