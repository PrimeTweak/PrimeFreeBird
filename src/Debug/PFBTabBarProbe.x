// Temporary probe ([tabprobe]): why Twitter's tab bar shows over the settings. Logs each settings
// screen as it comes and goes with its stack and the bar on screen, every show or hide of the bar's
// chrome with the code that sent it, and every chrome or tab bar entering or leaving a window.

#import <mach-o/loader.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif
#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

@interface _TtC9XSettings26SettingsListViewController : UIViewController
@end

// UIKit's step between will appear and did appear, iOS 17 and later.
@interface UIViewController (PFBTabBarProbe)
- (void)viewIsAppearing:(BOOL)animated;
@end

static Class gProbeChromeClass;
static Class gProbeBarClass;
static Class gProbeClassicClass;
static Class gProbeListClass;
// Whether the chrome class has its own setHidden: and setAlpha:, read before the hooks go in.
static BOOL gProbeOwnSetHidden;
static BOOL gProbeOwnSetAlpha;

// The appearance step or layout pass running now, so a change can be charged to it.
static __weak UIViewController* gProbeScreen;
static NSString* gProbeStep;
// Screens still logged after the settings are left, to see the bar come back.
static NSInteger gProbeTail;

// MARK: - Who sent it

static uintptr_t gProbeOursStart;
static uintptr_t gProbeOursEnd;

// PrimeFreeBird's code is the __TEXT segment of the image this file is in.
static void PFBTabProbeFindOurCode(void) {
    Dl_info info;
    if (!dladdr((const void*)&PFBTabProbeFindOurCode, &info) || !info.dli_fbase) {
        return;
    }
    const struct mach_header_64* header = (const struct mach_header_64*)info.dli_fbase;
    const uint8_t* cursor = (const uint8_t*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command* command = (const struct load_command*)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* segment = (const struct segment_command_64*)cursor;
            if (strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname)) == 0) {
                gProbeOursStart = (uintptr_t)header;
                gProbeOursEnd = gProbeOursStart + (uintptr_t)segment->vmsize;
                return;
            }
        }
        cursor += command->cmdsize;
    }
}

// PrimeFreeBird, or the image and offset of a return address.
static NSString* PFBTabProbeSender(const void* returnAddress) {
#if __has_include(<ptrauth.h>)
    returnAddress = ptrauth_strip(returnAddress, ptrauth_key_return_address);
#endif
    uintptr_t address = (uintptr_t)returnAddress;
    if (address >= gProbeOursStart && address < gProbeOursEnd) {
        return @"PrimeFreeBird";
    }
    Dl_info info;
    if (!dladdr(returnAddress, &info) || !info.dli_fname || !info.dli_fbase) {
        return [NSString stringWithFormat:@"0x%lx", (unsigned long)address];
    }
    return [NSString stringWithFormat:@"%@+0x%lx", [@(info.dli_fname) lastPathComponent],
                                      (unsigned long)(address - (uintptr_t)info.dli_fbase)];
}

// The five callers of the hook that calls this, nearest first, read on the frame chain.
static __attribute__((noinline)) NSString* PFBTabProbeCallers(void) {
    void** frame = (void**)__builtin_frame_address(0);
    // This function's own frame leads back into the hook; the hook's frame to its caller.
    frame = frame ? (void**)frame[0] : NULL;
    NSMutableArray<NSString*>* callers = [NSMutableArray array];
    for (NSUInteger i = 0; frame && frame[1] && i < 5; i++) {
        [callers addObject:PFBTabProbeSender(frame[1])];
        void** next = (void**)frame[0];
        if (next <= frame) {
            break;
        }
        frame = next;
    }
    return [callers componentsJoinedByString:@" < "];
}

// MARK: - What is on screen

// "XSettings.SettingsListViewController" reads "SettingsListViewController".
static NSString* PFBTabProbeName(id object) {
    if (!object) {
        return @"none";
    }
    NSString* name = NSStringFromClass([object class]);
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? name : [name substringFromIndex:dot.location + 1];
}

// A number given to each chrome and tab bar the first time it is seen, so a replacement shows.
static NSString* PFBTabProbeId(UIView* view) {
    static const void* kSerialKey = &kSerialKey;
    static NSInteger serial;
    NSNumber* number = objc_getAssociatedObject(view, kSerialKey);
    if (!number) {
        number = @(++serial);
        objc_setAssociatedObject(view, kSerialKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [NSString stringWithFormat:@"#%@", number];
}

// How many views down from its window, which the tweak's hide walks to a depth of 12.
static NSInteger PFBTabProbeDepth(UIView* view) {
    NSInteger depth = 0;
    for (UIView* current = view; current && ![current isKindOfClass:[UIWindow class]]; current = current.superview) {
        depth++;
    }
    return depth;
}

static BOOL PFBTabProbeIsOuterChrome(UIView* view) {
    return [view isKindOfClass:gProbeChromeClass] && ![view.superview isKindOfClass:gProbeChromeClass];
}

// The outermost chrome holding a view, or nil.
static UIView* PFBTabProbeChromeOf(UIView* view) {
    UIView* chrome = nil;
    for (UIView* current = view.superview; current; current = current.superview) {
        if ([current isKindOfClass:gProbeChromeClass]) {
            chrome = current;
        }
    }
    return chrome;
}

// On screen: in a shown window, nothing up to it hidden or clear, and inside the window.
static BOOL PFBTabProbeShown(UIView* view) {
    UIWindow* window = view.window;
    if (!window || window.hidden) {
        return NO;
    }
    for (UIView* current = view; current; current = current.superview) {
        if (current.hidden || current.alpha < 0.01) {
            return NO;
        }
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return !CGRectIsEmpty(frame) && CGRectIntersectsRect(frame, window.bounds);
}

static NSString* PFBTabProbeChromeState(UIView* view) {
    CGRect frame = [view convertRect:view.bounds toView:nil];
    NSString* alpha = view.alpha < 0.99 ? [NSString stringWithFormat:@" alpha %.2f", view.alpha] : @"";
    CGAffineTransform t = view.transform;
    NSString* moved = CGAffineTransformIsIdentity(t) ? @"" : [NSString stringWithFormat:@" moved %.0f,%.0f", t.tx, t.ty];
    return [NSString stringWithFormat:@"%@ %@%@%@ y %.0f depth %ld", PFBTabProbeId(view),
                                      view.hidden ? @"hidden" : @"shown", alpha, moved, CGRectGetMinY(frame),
                                      (long)PFBTabProbeDepth(view)];
}

// Each outermost chrome, and each tab bar on screen with the chrome holding it.
static NSString* PFBTabProbeBar(void) {
    NSMutableArray<NSString*>* chromes = [NSMutableArray array];
    NSMutableArray<NSString*>* showing = [NSMutableArray array];
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            PFBWalkAllSubviews(window, 24, ^(UIView* view) {
              if (PFBTabProbeIsOuterChrome(view)) {
                  [chromes addObject:PFBTabProbeChromeState(view)];
              }
              if (((gProbeBarClass && [view isKindOfClass:gProbeBarClass]) || [view isKindOfClass:[UITabBar class]]) &&
                  PFBTabProbeShown(view)) {
                  UIView* chrome = PFBTabProbeChromeOf(view);
                  [showing addObject:[NSString stringWithFormat:@"%@ %@ in %@", PFBTabProbeName(view),
                                                                PFBTabProbeId(view),
                                                                chrome ? PFBTabProbeId(chrome) : @"no chrome"]];
              }
            });
        }
    }
    return [NSString stringWithFormat:@"chrome %@ · showing %@",
                                      chromes.count ? [chromes componentsJoinedByString:@", "] : @"none",
                                      showing.count ? [showing componentsJoinedByString:@", "] : @"no tab bar"];
}

// The stethoscope's own report sheet, which a capture opens.
static BOOL PFBTabProbeIsReportSheet(UIViewController* screen) {
    SEL inSheet = NSSelectorFromString(@"inSheet");
    return [screen respondsToSelector:inSheet] && ((BOOL (*)(id, SEL))objc_msgSend)(screen, inSheet);
}

static BOOL PFBTabProbeIsSettings(UIViewController* screen) {
    return (gProbeClassicClass && [screen isKindOfClass:gProbeClassicClass]) ||
           (gProbeListClass && [screen isKindOfClass:gProbeListClass]) ||
           ([NSStringFromClass([screen class]) hasPrefix:@"PFB"] && !PFBTabProbeIsReportSheet(screen));
}

static void PFBTabProbeSummary(NSString* when) {
    PFBDebugLog(@"[tabprobe] %@ · chrome class %@, own setHidden %@, own setAlpha %@ · tab bar class %@ · New "
                @"Twitter settings %@ · Visual style %@",
                when, gProbeChromeClass ? @"found" : @"missing", gProbeOwnSetHidden ? @"yes" : @"no",
                gProbeOwnSetAlpha ? @"yes" : @"no", gProbeBarClass ? @"found" : @"missing",
                [PFBSettings boolForKey:@"new_twitter_settings"] ? @"on" : @"off",
                [PFBSettings boolForKey:@"enable_liquid_glass"] ? @"Liquid Glass" : @"Standard");
}

// A screen of a stack holding Twitter's settings or PrimeFreeBird's, the top one when it appears,
// and the next screens once the settings are left. Entering the settings repeats the summary.
static BOOL PFBTabProbeWatched(UIViewController* screen, BOOL top) {
    UINavigationController* stack = screen.navigationController;
    if (!stack || screen.parentViewController != stack || (top && stack.topViewController != screen)) {
        return NO;
    }
    for (UIViewController* controller in stack.viewControllers) {
        if (PFBTabProbeIsSettings(controller)) {
            if (gProbeTail == 0) {
                PFBTabProbeSummary(@"settings entered");
            }
            gProbeTail = 2;
            return YES;
        }
    }
    return gProbeTail > 0;
}

// The stack, root first, and what the bar's hide and restore look for in it.
static NSString* PFBTabProbeStack(UIViewController* screen) {
    UINavigationController* stack = screen.navigationController;
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    BOOL classic = NO;
    BOOL list = NO;
    for (UIViewController* controller in stack.viewControllers) {
        [names addObject:PFBTabProbeName(controller)];
        classic = classic || (gProbeClassicClass && [controller isKindOfClass:gProbeClassicClass]);
        list = list || (gProbeListClass && [controller isKindOfClass:gProbeListClass]);
    }
    id tabBar = [screen respondsToSelector:@selector(tfn_tabBarIntegration)] ? [screen tfn_tabBarIntegration] : nil;
    return [NSString stringWithFormat:@"%@ in %@ · glass stack %@ · classic settings in it %@ · new settings list in "
                                      @"it %@ · hides bottom bar %@ · tab bar controller %@ · presented %@",
                                      [names componentsJoinedByString:@" > "], PFBTabProbeName(stack),
                                      PFBOnNativeGlassStack(screen) ? @"yes" : @"no", classic ? @"yes" : @"no",
                                      list ? @"yes" : @"no", screen.hidesBottomBarWhenPushed ? @"yes" : @"no",
                                      PFBTabProbeName(tabBar), stack.presentingViewController ? @"yes" : @"no"];
}

static NSString* PFBTabProbeContext(void) {
    UIViewController* screen = gProbeScreen;
    return screen && gProbeStep ? [NSString stringWithFormat:@"in %@ of %@", gProbeStep, PFBTabProbeName(screen)]
                                : @"outside an appearance";
}

// Runs a step with its screen recorded, then puts back the step around it.
static void PFBTabProbeInStep(UIViewController* screen, NSString* step, void (^body)(void)) {
    UIViewController* outerScreen = gProbeScreen;
    NSString* outerStep = gProbeStep;
    gProbeScreen = screen;
    gProbeStep = step;
    body();
    gProbeScreen = outerScreen;
    gProbeStep = outerStep;
}

// MARK: - Hooks

%group PFBTabBarProbe

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    if (PFBTabProbeWatched(self, YES)) {
        PFBDebugLog(@"[tabprobe] will appear %@ · %@ · %@", PFBTabProbeName(self), PFBTabProbeStack(self),
                    PFBTabProbeBar());
    }
    PFBTabProbeInStep(self, @"will appear", ^{
      %orig;
    });
}

- (void)viewIsAppearing:(BOOL)animated {
    PFBTabProbeInStep(self, @"is appearing", ^{
      %orig;
    });
}

- (void)viewDidAppear:(BOOL)animated {
    BOOL watched = PFBTabProbeWatched(self, YES);
    NSString* before = watched ? PFBTabProbeBar() : nil;
    PFBTabProbeInStep(self, @"did appear", ^{
      %orig;
    });
    if (!watched) {
        return;
    }
    if (!PFBTabProbeIsSettings(self) && gProbeTail > 0) {
        gProbeTail--;
    }
    NSString* after = PFBTabProbeBar();
    PFBDebugLog(@"[tabprobe] did appear %@ · before: %@ · after: %@", PFBTabProbeName(self), before, after);
    __weak UIViewController* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      NSString* later = PFBTabProbeBar();
      if (![later isEqualToString:after]) {
          PFBDebugLog(@"[tabprobe] 0.8 s after %@ appeared: %@", PFBTabProbeName(weakSelf), later);
      }
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    BOOL watched = PFBTabProbeWatched(self, NO);
    PFBTabProbeInStep(self, @"will disappear", ^{
      %orig;
    });
    if (watched) {
        PFBDebugLog(@"[tabprobe] will disappear %@ · leaving %@ · %@", PFBTabProbeName(self),
                    self.isMovingFromParentViewController || self.isBeingDismissed ? @"yes" : @"no", PFBTabProbeBar());
    }
}

%end

// Twitter's settings screens run the tweak's hide and restore after their own appearance steps.
%hook T1GenericSettingsViewController

- (void)viewWillAppear:(BOOL)animated {
    PFBTabProbeInStep(self, @"will appear", ^{
      %orig;
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    PFBTabProbeInStep(self, @"will disappear", ^{
      %orig;
    });
}

%end

%hook _TtC9XSettings26SettingsListViewController

- (void)viewWillAppear:(BOOL)animated {
    PFBTabProbeInStep(self, @"will appear", ^{
      %orig;
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    PFBTabProbeInStep(self, @"will disappear", ^{
      %orig;
    });
}

%end

// Twitter's navigation applies each screen's configuration, the bar's included, while it lays out.
%hook XNAVNavigationController

- (void)viewWillLayoutSubviews {
    PFBTabProbeInStep((UIViewController*)self, @"layout", ^{
      %orig;
    });
}

%end

%hook UIView

- (void)setHidden:(BOOL)hidden {
    if (PFBTabProbeIsOuterChrome(self) && hidden != self.hidden) {
        PFBDebugLog(@"[tabprobe] chrome %@ %@ · sent by %@ · %@", PFBTabProbeId(self), hidden ? @"hidden" : @"shown",
                    PFBTabProbeCallers(), PFBTabProbeContext());
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (PFBTabProbeIsOuterChrome(self) && (alpha < 0.01) != (self.alpha < 0.01)) {
        PFBDebugLog(@"[tabprobe] chrome %@ alpha %.2f · sent by %@ · %@", PFBTabProbeId(self), alpha,
                    PFBTabProbeCallers(), PFBTabProbeContext());
    }
    %orig;
}

- (void)didMoveToWindow {
    %orig;
    BOOL chrome = PFBTabProbeIsOuterChrome(self);
    if (!chrome && !(gProbeBarClass && [self isKindOfClass:gProbeBarClass])) {
        return;
    }
    UIView* holder = chrome ? nil : PFBTabProbeChromeOf(self);
    PFBDebugLog(@"[tabprobe] %@ %@ %@ · depth %ld · %@ · %@", chrome ? @"chrome" : @"tab bar", PFBTabProbeId(self),
                self.window ? @"entered a window" : @"left its window", (long)PFBTabProbeDepth(self),
                chrome ? (self.hidden ? @"hidden" : @"shown")
                       : (holder ? [NSString stringWithFormat:@"in chrome %@", PFBTabProbeId(holder)] : @"in no chrome"),
                PFBTabProbeContext());
}

%end

%hook T1TabBarViewController

- (void)setTabBarHidden:(BOOL)hidden withDuration:(double)duration {
    PFBDebugLog(@"[tabprobe] tab bar controller asked to %@ · sent by %@ · %@", hidden ? @"hide" : @"show",
                PFBTabProbeCallers(), PFBTabProbeContext());
    %orig;
}

%end

%end

// Every other file installs its hooks from its constructor. The main queue first runs once they
// all have, so these are installed last and run first.
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!PFBDebugIsRecording()) {
          return;
      }
      gProbeChromeClass = NSClassFromString(@"_TtC11XNavigation25TabBarChromeContainerView");
      gProbeBarClass = NSClassFromString(@"_TtC11XNavigation10TabBarView");
      gProbeClassicClass = objc_getClass("T1GenericSettingsViewController");
      gProbeListClass = objc_getClass("_TtC9XSettings26SettingsListViewController");
      PFBTabProbeFindOurCode();
      if (gProbeChromeClass) {
          Class view = [UIView class];
          gProbeOwnSetHidden = class_getMethodImplementation(gProbeChromeClass, @selector(setHidden:)) !=
                               class_getMethodImplementation(view, @selector(setHidden:));
          gProbeOwnSetAlpha = class_getMethodImplementation(gProbeChromeClass, @selector(setAlpha:)) !=
                              class_getMethodImplementation(view, @selector(setAlpha:));
      }
      PFBTabProbeSummary(@"probe on");
      if (!gProbeChromeClass) {
          return;
      }
      %init(PFBTabBarProbe);
    });
}
