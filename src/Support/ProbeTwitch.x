// Probe for Twitter 12.45, removed once read: where the tab bar's twitch comes from. Each move of the
// bar's tabs, selection lens or button is counted inside or outside Twitter's animation frames; the
// first moves outside them, and two inside, are written with the chain of calls that made them.

#import "Support/HookHelpers.h"
#import <dlfcn.h>
#import <objc/runtime.h>

@interface _TtCC11XNavigation17DisplayLinkDriverP33_DC9744A9B855F36B00902ED7FE8B664F5Proxy : NSObject
@end

@interface _TtCC11XNavigation14CollapseEngine14ScrollObserver : NSObject
- (void)handlePan:(UIPanGestureRecognizer*)recognizer;
@end

static NSString* const kPFBTwitchTopic = @"probe tab bar twitch";
static const NSUInteger kPFBTwitchCap = 40;
static const NSUInteger kPFBTwitchOutside = 8;
static const NSUInteger kPFBTwitchInside = 2;
static NSUInteger gPFBTwitchSeq;
static CFAbsoluteTime gPFBTwitchStart;
static NSUInteger gPFBTwitchTickDepth;
static BOOL gPFBTwitchDragging;
static CFAbsoluteTime gPFBTwitchDragEnd;
static NSUInteger gPFBTwitchInsideMoves;
static NSUInteger gPFBTwitchOutsideMoves;
static NSUInteger gPFBTwitchInsideStacks;
static NSUInteger gPFBTwitchOutsideStacks;
static NSUInteger gPFBTwitchPans;

static void PFBTwitchLine(NSString* line) {
    PFBCompatMeasure(kPFBTwitchTopic,
                     [NSString stringWithFormat:@"%02lu %.2f s %@", (unsigned long)++gPFBTwitchSeq, CFAbsoluteTimeGetCurrent() - gPFBTwitchStart, line],
                     kPFBTwitchCap);
}

static NSString* PFBTwitchName(id object) {
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

// The calls that led here, as image and offset, with the nearest exported name when there is one.
static NSString* PFBTwitchStack(void) {
    NSArray<NSNumber*>* addresses = [NSThread callStackReturnAddresses];
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for (NSUInteger i = 2; i < addresses.count && frames.count < 28; i++) {
        void* address = (void*)addresses[i].unsignedLongValue;
        Dl_info info;
        if (!dladdr(address, &info) || !info.dli_fname) {
            continue;
        }
        NSString* symbol = info.dli_sname ? [NSString stringWithUTF8String:info.dli_sname] : @"";
        if (symbol.length > 60) {
            symbol = [symbol substringToIndex:60];
        }
        [frames addObject:[NSString stringWithFormat:@"%@+0x%lx %@", [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent],
                                                     (unsigned long)((uintptr_t)address - (uintptr_t)info.dli_fbase), symbol]];
    }
    return [frames componentsJoinedByString:@" < "];
}

// The tab bar controller's collapse driver: latch and target, read where Always visible reads them.
static NSString* PFBTwitchDriver(UIView* view) {
    static Class controllerClass;
    static Class driverClass;
    static ptrdiff_t driverOffset = -1, latchedOffset = -1, targetOffset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      controllerClass = NSClassFromString(@"_TtC11XNavigation16TabBarController");
      driverClass = NSClassFromString(@"_TtC11XNavigation20TabBarCollapseDriver");
      Ivar driver = controllerClass ? class_getInstanceVariable(controllerClass, "$__lazy_storage_$_collapseDriver") : NULL;
      Ivar latched = driverClass ? class_getInstanceVariable(driverClass, "isLatched") : NULL;
      Ivar target = driverClass ? class_getInstanceVariable(driverClass, "progressTarget") : NULL;
      driverOffset = driver ? ivar_getOffset(driver) : -1;
      latchedOffset = latched ? ivar_getOffset(latched) : -1;
      targetOffset = target ? ivar_getOffset(target) : -1;
    });
    UIResponder* next = view;
    while (next && ![next isKindOfClass:controllerClass]) {
        next = next.nextResponder;
    }
    if (!next || driverOffset < 0 || latchedOffset < 0 || targetOffset < 0) {
        return @"driver -";
    }
    void* driver = NULL;
    memcpy(&driver, (const uint8_t*)(__bridge void*)next + driverOffset, sizeof(driver));
    if (!driver || object_getClass((__bridge id)driver) != driverClass) {
        return @"no driver";
    }
    double target = 0;
    memcpy(&target, (const uint8_t*)driver + targetOffset, sizeof(target));
    return [NSString stringWithFormat:@"driver latched %d target %.2f", ((const uint8_t*)driver)[latchedOffset], target];
}

// One move of a bar piece: counted, and written with its calls while the first ones last.
static void PFBTwitchMove(UIView* view, NSString* what, NSString* from, NSString* to) {
    if (![PFBSettings boolForKey:@"no_tab_bar_hiding"]) {
        return;
    }
    BOOL inside = gPFBTwitchTickDepth > 0;
    BOOL dragging = gPFBTwitchDragging || CFAbsoluteTimeGetCurrent() - gPFBTwitchDragEnd < 0.6;
    if (inside) {
        gPFBTwitchInsideMoves++;
    } else {
        gPFBTwitchOutsideMoves++;
    }
    BOOL write = dragging && (inside ? gPFBTwitchInsideStacks++ < kPFBTwitchInside : gPFBTwitchOutsideStacks++ < kPFBTwitchOutside);
    if (!write) {
        return;
    }
    PFBTwitchLine([NSString stringWithFormat:@"%@ frame: %@ %@ %@ -> %@, %@ | %@", inside ? @"inside" : @"outside", PFBTwitchName(view), what, from, to,
                                             PFBTwitchDriver(view), PFBTwitchStack()]);
}

#define PFBTWITCH_RECT(r) [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", (r).origin.x, (r).origin.y, (r).size.width, (r).size.height]
#define PFBTWITCH_POINT(p) [NSString stringWithFormat:@"%.0f,%.0f", (p).x, (p).y]

%hook _TtC11XNavigation14TabBarItemView

- (void)setFrame:(CGRect)frame {
    UIView* view = (UIView*)self;
    if (!CGRectEqualToRect(view.frame, frame)) {
        PFBTwitchMove(view, @"frame", PFBTWITCH_RECT(view.frame), PFBTWITCH_RECT(frame));
    }
    %orig;
}

- (void)setCenter:(CGPoint)center {
    UIView* view = (UIView*)self;
    if (!CGPointEqualToPoint(view.center, center)) {
        PFBTwitchMove(view, @"center", PFBTWITCH_POINT(view.center), PFBTWITCH_POINT(center));
    }
    %orig;
}

%end

%hook _TtC13XDesignSystem10LiquidLens

- (void)setFrame:(CGRect)frame {
    UIView* view = (UIView*)self;
    if (!CGRectEqualToRect(view.frame, frame)) {
        PFBTwitchMove(view, @"frame", PFBTWITCH_RECT(view.frame), PFBTWITCH_RECT(frame));
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
    UIView* view = (UIView*)self;
    if (!CGSizeEqualToSize(view.bounds.size, bounds.size)) {
        PFBTwitchMove(view, @"bounds", PFBTWITCH_RECT(view.bounds), PFBTWITCH_RECT(bounds));
    }
    %orig;
}

- (void)setCenter:(CGPoint)center {
    UIView* view = (UIView*)self;
    if (!CGPointEqualToPoint(view.center, center)) {
        PFBTwitchMove(view, @"center", PFBTWITCH_POINT(view.center), PFBTWITCH_POINT(center));
    }
    %orig;
}

%end

%hook _TtC11XNavigation23TabBarAccessoryHostView

- (void)setFrame:(CGRect)frame {
    UIView* view = (UIView*)self;
    if (!CGRectEqualToRect(view.frame, frame)) {
        PFBTwitchMove(view, @"frame", PFBTWITCH_RECT(view.frame), PFBTWITCH_RECT(frame));
    }
    %orig;
}

- (void)setCenter:(CGPoint)center {
    UIView* view = (UIView*)self;
    if (!CGPointEqualToPoint(view.center, center)) {
        PFBTwitchMove(view, @"center", PFBTWITCH_POINT(view.center), PFBTWITCH_POINT(center));
    }
    %orig;
}

%end

// Twitter's animation frames, counted so a move inside one is told from a move outside.
%hook _TtCC11XNavigation17DisplayLinkDriverP33_DC9744A9B855F36B00902ED7FE8B664F5Proxy

- (void)handleTick:(CADisplayLink*)link {
    gPFBTwitchTickDepth++;
    %orig;
    gPFBTwitchTickDepth--;
}

%end

%hook _TtCC11XNavigation14CollapseEngine14ScrollObserver

- (void)handlePan:(UIPanGestureRecognizer*)recognizer {
    UIGestureRecognizerState state = recognizer.state;
    BOOL note = gPFBTwitchPans < 8;
    if (state == UIGestureRecognizerStateBegan) {
        gPFBTwitchDragging = YES;
        gPFBTwitchPans++;
        if (note) {
            PFBTwitchLine(@"pan began");
        }
    }
    %orig;
    if ((state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) && gPFBTwitchDragging) {
        gPFBTwitchDragging = NO;
        gPFBTwitchDragEnd = CFAbsoluteTimeGetCurrent();
        if (!note) {
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          PFBTwitchLine([NSString stringWithFormat:@"pan ended 0.8 s ago: moves inside frames %lu, outside %lu", (unsigned long)gPFBTwitchInsideMoves,
                                                   (unsigned long)gPFBTwitchOutsideMoves]);
        });
    }
}

%end

%ctor {
    %init;
    gPFBTwitchStart = CFAbsoluteTimeGetCurrent();
}
