// The measurement probe; see PFBProbe.h.

#import "Debug/PFBProbe.h"
#import "Debug/PFBDebugger.h"
#import "Common/PFBCompatibility.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <os/lock.h>

NSNotificationName const PFBProbeTourEndedNotification = @"PFBProbeTourEndedNotification";

static NSString* const kPFBProbeStoreKey = @"pfb_probe";
// Room for every measurement, and a bound if one of them turns out chatty.
static const NSUInteger kPFBProbeLineLimit = 1000;

static NSObject* gPFBProbeLock;
static NSMutableSet<NSString*>* gPFBProbeKeys;
static NSMutableArray<NSString*>* gPFBProbeLines;
static NSString* gPFBProbeBuild;
static NSDateFormatter* gPFBProbeClock;
// Saves happen in order, outside the lock: the defaults are never written while it is held.
// A burst of notes shares one save, which writes the lines as they stand when it runs.
static dispatch_queue_t gPFBProbeWriter;
static BOOL gPFBProbeSaveQueued;
// Whether a note was turned away because the limit was reached, said in the report.
static BOOL gPFBProbeFull;

static CFTimeInterval gPFBProbeLoadedAt;
static os_unfair_lock gPFBProbeTallyLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString*, NSNumber*>* gPFBProbeMarks;
static NSMutableDictionary<NSString*, NSNumber*>* gPFBProbeCounts;

__attribute__((constructor)) static void probeLoaded(void) {
    gPFBProbeLoadedAt = CACurrentMediaTime();
}

// What this build noted on earlier launches; another build starts empty.
static void probeLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gPFBProbeLock = [NSObject new];
      gPFBProbeWriter = dispatch_queue_create("PFBProbeWriter", DISPATCH_QUEUE_SERIAL);
      gPFBProbeBuild = PFBCompatBuildID();
      gPFBProbeClock = [NSDateFormatter new];
      gPFBProbeClock.dateFormat = @"HH:mm:ss.SSS";
      NSDictionary* saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPFBProbeStoreKey];
      BOOL same = [saved[@"build"] isKindOfClass:[NSString class]] && [saved[@"build"] isEqualToString:gPFBProbeBuild];
      NSArray* keys = same && [saved[@"keys"] isKindOfClass:[NSArray class]] ? saved[@"keys"] : @[];
      NSArray* lines = same && [saved[@"lines"] isKindOfClass:[NSArray class]] ? saved[@"lines"] : @[];
      gPFBProbeKeys = [NSMutableSet setWithArray:keys];
      gPFBProbeLines = [lines mutableCopy];
    });
}

// Whether a key can still be noted; caller holds gPFBProbeLock.
static BOOL probeRoomFor(NSString* key) {
    if ([gPFBProbeKeys containsObject:key]) {
        return NO;
    }
    if (gPFBProbeLines.count >= kPFBProbeLineLimit) {
        gPFBProbeFull = YES;
        return NO;
    }
    return YES;
}

// One save for the notes made since the last one; caller holds gPFBProbeLock.
static void probeSaveSoon(void) {
    if (gPFBProbeSaveQueued) {
        return;
    }
    gPFBProbeSaveQueued = YES;
    dispatch_async(gPFBProbeWriter, ^{
      NSDictionary* saved;
      @synchronized(gPFBProbeLock) {
          gPFBProbeSaveQueued = NO;
          saved = @{
              @"build": gPFBProbeBuild ?: @"?",
              @"keys": gPFBProbeKeys.allObjects,
              @"lines": [gPFBProbeLines copy],
          };
      }
      [[NSUserDefaults standardUserDefaults] setObject:saved forKey:kPFBProbeStoreKey];
    });
}

BOOL PFBProbeWants(NSString* key) {
    if (!PFBDebugIsRecording() || !key) {
        return NO;
    }
    probeLoad();
    @synchronized(gPFBProbeLock) {
        return probeRoomFor(key);
    }
}

void PFBProbeNote(NSString* key, NSString* format, ...) {
    if (!PFBDebugIsRecording() || !key || !format) {
        return;
    }
    probeLoad();
    // A key already noted costs no formatting.
    @synchronized(gPFBProbeLock) {
        if (!probeRoomFor(key)) {
            return;
        }
    }
    va_list arguments;
    va_start(arguments, format);
    NSString* text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString* step = NSThread.isMainThread ? PFBProbeTourStep() : nil;
    NSString* stamp;
    @synchronized(gPFBProbeClock) {
        stamp = [gPFBProbeClock stringFromDate:[NSDate date]];
    }
    NSString* line = step.length ? [NSString stringWithFormat:@"%@  [%@] %@", stamp, step, text]
                                 : [NSString stringWithFormat:@"%@  %@", stamp, text];
    @synchronized(gPFBProbeLock) {
        if (!probeRoomFor(key)) {
            return;
        }
        [gPFBProbeKeys addObject:key];
        [gPFBProbeLines addObject:line];
        probeSaveSoon();
    }
}

NSString* PFBProbeReportText(void) {
    if (!PFBDebugIsRecording()) {
        return @"PROBE  off: debug tools are off\n";
    }
    probeLoad();
    NSArray<NSString*>* lines;
    BOOL full;
    @synchronized(gPFBProbeLock) {
        lines = [gPFBProbeLines copy];
        full = gPFBProbeFull || lines.count >= kPFBProbeLineLimit;
    }
    if (!lines.count) {
        return [NSString stringWithFormat:@"PROBE  build %@ · nothing noted yet\n", gPFBProbeBuild];
    }
    return [NSString stringWithFormat:@"PROBE  build %@ · %lu notes%@\n%@\n", gPFBProbeBuild, (unsigned long)lines.count,
                                      full ? @" · limit reached, later notes lost" : @"",
                                      [lines componentsJoinedByString:@"\n"]];
}

// MARK: - Moments and counters

CFTimeInterval PFBProbeSinceLaunch(void) {
    return CACurrentMediaTime() - gPFBProbeLoadedAt;
}

void PFBProbeMark(NSString* name) {
    if (!PFBDebugIsRecording() || !name) {
        return;
    }
    os_unfair_lock_lock(&gPFBProbeTallyLock);
    if (!gPFBProbeMarks) {
        gPFBProbeMarks = [NSMutableDictionary dictionary];
    }
    gPFBProbeMarks[name] = @(CACurrentMediaTime());
    os_unfair_lock_unlock(&gPFBProbeTallyLock);
}

CFTimeInterval PFBProbeMarkAge(NSString* name) {
    if (!name) {
        return -1;
    }
    os_unfair_lock_lock(&gPFBProbeTallyLock);
    NSNumber* at = gPFBProbeMarks[name];
    os_unfair_lock_unlock(&gPFBProbeTallyLock);
    return at ? CACurrentMediaTime() - at.doubleValue : -1;
}

NSUInteger PFBProbeCount(NSString* name) {
    if (!PFBDebugIsRecording() || !name) {
        return 0;
    }
    os_unfair_lock_lock(&gPFBProbeTallyLock);
    if (!gPFBProbeCounts) {
        gPFBProbeCounts = [NSMutableDictionary dictionary];
    }
    NSUInteger value = gPFBProbeCounts[name].unsignedIntegerValue + 1;
    gPFBProbeCounts[name] = @(value);
    os_unfair_lock_unlock(&gPFBProbeTallyLock);
    return value;
}

NSUInteger PFBProbeCountValue(NSString* name) {
    if (!name) {
        return 0;
    }
    os_unfair_lock_lock(&gPFBProbeTallyLock);
    NSUInteger value = gPFBProbeCounts[name].unsignedIntegerValue;
    os_unfair_lock_unlock(&gPFBProbeTallyLock);
    return value;
}

// MARK: - Reading the app

NSString* PFBProbeClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"none";
}

UIViewController* PFBProbeControllerOfView(UIView* view) {
    for (UIResponder* responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
    }
    return nil;
}

NSString* PFBProbeScreenName(UIViewController* controller) {
    UIViewController* screen = controller;
    while (screen.parentViewController && ![screen.parentViewController isKindOfClass:[UINavigationController class]]) {
        screen = screen.parentViewController;
    }
    return screen ? NSStringFromClass([screen class]) : @"no screen";
}

UIWindow* PFBProbeAppWindow(void) {
    if (!NSThread.isMainThread) {
        return nil;
    }
    UIWindow* fallback = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NSString* name = NSStringFromClass([window class]);
            if ([name isEqualToString:@"T1Window"]) {
                return window;
            }
            if (!fallback && !window.hidden && window.windowLevel == UIWindowLevelNormal &&
                window.rootViewController && ![name hasPrefix:@"PFB"]) {
                fallback = window;
            }
        }
    }
    return fallback;
}

NSString* PFBProbeFrontScreen(void) {
    if (!NSThread.isMainThread) {
        return @"?";
    }
    UIWindow* window = PFBProbeAppWindow();
    if (!window) {
        return @"no window";
    }
    UIView* front = [window hitTest:CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds)) withEvent:nil];
    return PFBProbeScreenName([front isKindOfClass:[UIView class]] ? PFBProbeControllerOfView(front) : nil);
}

NSString* PFBProbeKeyWindowName(void) {
    if (!NSThread.isMainThread) {
        return @"?";
    }
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow) {
                return NSStringFromClass([window class]);
            }
        }
    }
    return @"none";
}

// Whether a selector belongs to a method family that hands back an object the caller owns
// (alloc, copy, mutableCopy, new, init): never called by the getters below.
static BOOL probeReturnsOwned(SEL selector) {
    static const char* const families[] = {"alloc", "copy", "mutableCopy", "new", "init"};
    const char* name = sel_getName(selector);
    for (size_t i = 0; i < sizeof(families) / sizeof(families[0]); i++) {
        size_t length = strlen(families[i]);
        if (strncmp(name, families[i], length) == 0 && !islower((unsigned char)name[length])) {
            return YES;
        }
    }
    return NO;
}

id PFBProbeGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || probeReturnsOwned(selector) || ![object respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

long long PFBProbeIntegerGetter(id object, NSString* name, BOOL* found) {
    if (found) {
        *found = NO;
    }
    SEL selector = NSSelectorFromString(name);
    if (!object || probeReturnsOwned(selector) || ![object respondsToSelector:selector]) {
        return 0;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2) {
        return 0;
    }
    long long value = 0;
    switch (signature.methodReturnType[0]) {
        case 'q':
        case 'Q':
            value = ((long long (*)(id, SEL))objc_msgSend)(object, selector);
            break;
        case 'l':
        case 'L':
            value = ((long (*)(id, SEL))objc_msgSend)(object, selector);
            break;
        case 'i':
        case 'I':
            value = ((int (*)(id, SEL))objc_msgSend)(object, selector);
            break;
        case 's':
        case 'S':
            value = ((short (*)(id, SEL))objc_msgSend)(object, selector);
            break;
        case 'c':
        case 'C':
        case 'B':
            value = ((char (*)(id, SEL))objc_msgSend)(object, selector);
            break;
        default:
            return 0;
    }
    if (found) {
        *found = YES;
    }
    return value;
}

NSString* PFBProbeColor(UIColor* color, UITraitCollection* traits) {
    if (!color) {
        return @"none";
    }
    UIColor* resolved = traits ? [color resolvedColorWithTraitCollection:traits] : color;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![resolved getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if (![resolved getWhite:&white alpha:&a]) {
            return @"unreadable";
        }
        r = g = b = white;
    }
    return [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.2f", r * 255.0, g * 255.0, b * 255.0, a];
}
