//
//  NFBTerrain.x
//  PrimeFreeBird
//
//  Temporary probe [p25]. Read only: no %orig is altered and no view is
//  touched. Remove this file when the three questions it answers are closed.
//
//  It censuses rather than tests a hypothesis, so one build answers all three:
//  which bar items exist and which of them can be flattened, what every view of
//  a settings header actually is, and how often that bar lays out.

#import "Hooks/HookHelpers.h"
#import "Debug/NFBDebugger.h"
#import <QuartzCore/QuartzCore.h>

static const void* kNFBTerrainNotedKey = &kNFBTerrainNotedKey;

// A colour as three numbers, or a word when there is none. Both the view's own
// background and its layer's are reported: a black screen can come from either.
static NSString* nfbTerrainColour(UIColor* colour) {
    if (!colour) {
        return @"nil";
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([colour getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"%.2f,%.2f,%.2f/%.2f", r, g, b, a];
    }
    CGFloat w = 0;
    if ([colour getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"w%.2f/%.2f", w, a];
    }
    return @"?";
}

// The tint a view resolves to. A Liquid Glass capsule takes its fill from this,
// not from backgroundColor, so a census without it cannot name a coloured button.
static NSString* nfbTerrainTint(UIView* view) {
    UIColor* tint = view.tintColor;
    return tint ? nfbTerrainColour(tint) : @"nil";
}

static NSString* nfbTerrainLayerColour(CALayer* layer) {
    if (!layer.backgroundColor) {
        return @"nil";
    }
    return nfbTerrainColour([UIColor colorWithCGColor:layer.backgroundColor]);
}

// One line per view, bounded in depth and in count so a census can never be the
// thing that hangs the screen it is measuring.
static void nfbTerrainWalk(UIView* view, NSInteger depth, NSInteger maxDepth,
                           NSInteger* budget, NSString* tag) {
    if (!view || depth > maxDepth || *budget <= 0) {
        return;
    }
    (*budget)--;
    NSMutableString* pad = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) {
        [pad appendString:@"  "];
    }
    CGRect f = view.frame;
    NFBDebugLog(@"[p25] %@ %@%@ x=%.0f y=%.0f %.0fx%.0f a=%.2f%@ bg=%@ lbg=%@ "
                @"tint=%@%@",
                tag, pad, NSStringFromClass([view class]), f.origin.x, f.origin.y,
                f.size.width, f.size.height, view.alpha,
                view.hidden ? @" HIDDEN" : @"",
                nfbTerrainColour(view.backgroundColor),
                nfbTerrainLayerColour(view.layer), nfbTerrainTint(view),
                view.layer.contents ? @" contents" : @"");
    for (UIView* sub in view.subviews) {
        nfbTerrainWalk(sub, depth + 1, maxDepth, budget, tag);
    }
}

// Everything that decides whether a bar item can be asked to drop its shared
// glass. The gear and the avatar sit on the same bar, so a difference between
// them shows up here rather than in a guess.
static void nfbTerrainItems(UINavigationBar* bar) {
    if (![bar respondsToSelector:@selector(topItem)]) {
        return;
    }
    UINavigationItem* item =
        ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    if (!item) {
        NFBDebugLog(@"[p25] items: topItem is nil");
        return;
    }
    SEL hideShared = NSSelectorFromString(@"setHidesSharedBackground:");
    NSArray* sides = @[ item.leftBarButtonItems ?: @[], item.rightBarButtonItems ?: @[] ];
    NSArray* names = @[ @"left", @"right" ];
    for (NSUInteger s = 0; s < sides.count; s++) {
        NSArray<UIBarButtonItem*>* list = sides[s];
        if (list.count == 0) {
            NFBDebugLog(@"[p25] items %@: none", names[s]);
            continue;
        }
        for (UIBarButtonItem* button in list) {
            id current = nil;
            @try {
                current = [button valueForKey:@"hidesSharedBackground"];
            } @catch (id exception) {
            }
            NFBDebugLog(@"[p25] item %@ %@ title=%@ image=%@ custom=%@ responds=%d "
                        @"flat=%@",
                        names[s], NSStringFromClass([button class]),
                        button.title.length ? button.title : @"-",
                        button.image ? @"yes" : @"no",
                        button.customView
                            ? NSStringFromClass([button.customView class])
                            : @"-",
                        [button respondsToSelector:hideShared] ? 1 : 0,
                        current ?: @"unreadable");
        }
    }
}

// Anything in the bar's subtree that carries a glass host but is not an item:
// a control added as a plain subview never reaches the item list above, which
// is the difference the census is looking for.
static void nfbTerrainGlassHosts(UIView* root, NSInteger depth, NSInteger* budget) {
    if (!root || depth > 12 || *budget <= 0) {
        return;
    }
    NSString* name = NSStringFromClass([root class]);
    if ([name containsString:@"Glass"] || [name containsString:@"ItemWrapperView"] ||
        [name containsString:@"PlatterContainer"]) {
        (*budget)--;
        CGRect f = root.frame;
        NSMutableString* chain = [NSMutableString string];
        UIView* node = root;
        NSInteger up = 0;
        while (node && up < 3) {
            [chain appendFormat:@"%@%@", up ? @" < " : @"",
                                NSStringFromClass([node class])];
            node = node.superview;
            up++;
        }
        NFBDebugLog(@"[p25] glass host %@ x=%.0f %.0fx%.0f a=%.2f | %@", name,
                    f.origin.x, f.size.width, f.size.height, root.alpha, chain);
    }
    for (UIView* sub in root.subviews) {
        nfbTerrainGlassHosts(sub, depth + 1, budget);
    }
}

// The census, once per bar. Depth 10 covers a navigation bar's whole platter
// chain; 60 lines is more than any bar has produced so far.
static void nfbTerrainCensus(UINavigationBar* bar, NSString* moment) {
    NSInteger budget = 60;
    NFBDebugLog(@"[p25] ===== bar census (%@) %@ %.0fx%.0f =====", moment,
                NSStringFromClass([bar class]), bar.bounds.size.width,
                bar.bounds.size.height);
    nfbTerrainItems(bar);
    NSInteger glass = 12;
    nfbTerrainGlassHosts(bar, 0, &glass);
    nfbTerrainWalk(bar, 0, 10, &budget, @"bar");
    NFBDebugLog(@"[p25] ===== end census (%ld lines left) =====", (long)budget);
}

// How often a bar lays out, reported twice a second with the count since the
// previous line. A runaway layout reads as a rate; a normal screen reads as a
// handful.
static void nfbTerrainRate(UINavigationBar* bar) {
    static NSInteger passes = 0;
    static NSTimeInterval lastNote = 0;
    passes++;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - lastNote < 0.5) {
        return;
    }
    NFBDebugLog(@"[p25] %@ laid out %ld time(s) in %.2f s (subviews=%lu)",
                NSStringFromClass([bar class]), (long)passes, now - lastNote,
                (unsigned long)bar.subviews.count);
    passes = 0;
    lastNote = now;
}

// True of a bar that is worth censusing: it carries a search field, or a
// settings screen owns it. Everything else is left alone so the journal stays
// about the screens in question.
static BOOL nfbTerrainBarIsInteresting(UINavigationBar* bar, NSInteger depth) {
    NSString* name = NSStringFromClass([bar class]);
    if ([name containsString:@"Search"]) {
        return YES;
    }
    if (depth > 6) {
        return NO;
    }
    for (UIView* sub in bar.subviews) {
        NSString* subName = NSStringFromClass([sub class]);
        if ([subName containsString:@"SearchBar"] ||
            [subName containsString:@"SearchView"] ||
            [subName containsString:@"SearchField"]) {
            return YES;
        }
        if (nfbTerrainBarIsInteresting((UINavigationBar*)sub, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

// Every tint written onto a view that lives in a navigation bar, reported once per
// class and colour. A capsule that renders dark has been told to, by someone: this
// names who is written to, with what, and in which bar.
static BOOL nfbTerrainInNavigationBar(UIView* view) {
    UIView* node = view;
    for (NSInteger up = 0; node && up < 12; up++) {
        if ([node isKindOfClass:[UINavigationBar class]]) {
            return YES;
        }
        node = node.superview;
    }
    return NO;
}

%hook UIView

- (void)setTintColor:(UIColor*)tint {
    %orig;
    @try {
        if (!NFBDebugIsRecording() || !tint) {
            return;
        }
        UIView* view = (UIView*)self;
        if (!view.window || !nfbTerrainInNavigationBar(view)) {
            return;
        }
        static NSMutableSet* seen;
        if (!seen) {
            seen = [NSMutableSet set];
        }
        NSString* key = [NSString stringWithFormat:@"%@|%@",
                                  NSStringFromClass([view class]),
                                  nfbTerrainColour(tint)];
        if ([seen containsObject:key]) {
            return;
        }
        [seen addObject:key];
        NFBDebugLog(@"[p25] tint set on %@ = %@ (in a navigation bar)",
                    NSStringFromClass([view class]), nfbTerrainColour(tint));
    } @catch (id exception) {
    }
}

%end

// [p27] hang watchdog. A frozen main thread cannot run the capture button, so the
// only way to see a hang is to watch from another thread and leave a file behind.
static volatile NSTimeInterval gNFBMainTick = 0;
static volatile int64_t gNFBBarLayouts = 0;
static NSTimeInterval gNFBLastPopAt = 0;
static NSString* gNFBLastBarClass = nil;
static dispatch_source_t gNFBWatchdog = nil;

static NSString* nfbTerrainHangPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"nfb-hang.txt"];
}

// Written from the watchdog thread while the main thread is stuck, so it must not
// touch UIKit or any state the main thread owns beyond these counters.
static void nfbTerrainWriteHang(NSTimeInterval stuckFor, int64_t layoutsAtStart) {
    NSString* report = [NSString
        stringWithFormat:@"HANG %.1f s | bar layouts %lld -> %lld | last bar %@ | "
                         @"pop %.1f s before",
                         stuckFor, layoutsAtStart, gNFBBarLayouts,
                         gNFBLastBarClass ?: @"none",
                         gNFBLastPopAt > 0 ? CACurrentMediaTime() - gNFBLastPopAt : -1.0];
    [report writeToFile:nfbTerrainHangPath()
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:NULL];
}

// A hang report from the previous run is read back into the journal at the first
// bar of this one, so a force-quit does not lose it.
static void nfbTerrainReplayHang(void) {
    NSString* path = nfbTerrainHangPath();
    NSString* report = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
    if (report.length) {
        NFBDebugLog(@"[p27] previous run: %@", report);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

static void nfbTerrainInstallWatchdog(void) {
    if (gNFBWatchdog) {
        return;
    }
    nfbTerrainReplayHang();
    gNFBMainTick = CACurrentMediaTime();
    dispatch_queue_t queue =
        dispatch_queue_create("nfb.watchdog", DISPATCH_QUEUE_SERIAL);
    gNFBWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(gNFBWatchdog, DISPATCH_TIME_NOW,
                              (uint64_t)(0.3 * NSEC_PER_SEC), 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(gNFBWatchdog, ^{
      static BOOL reported = NO;
      static int64_t layoutsAtStart = 0;
      NSTimeInterval idle = CACurrentMediaTime() - gNFBMainTick;
      if (idle < 0.5) {
          reported = NO;
          layoutsAtStart = gNFBBarLayouts;
      } else if (idle > 2.0 && !reported) {
          reported = YES;
          nfbTerrainWriteHang(idle, layoutsAtStart);
      }
      dispatch_async(dispatch_get_main_queue(),
                     ^{ gNFBMainTick = CACurrentMediaTime(); });
    });
    dispatch_resume(gNFBWatchdog);
    NFBDebugLog(@"[p27] hang watchdog armed");
}

// The moment a pop starts, so a hang can be told apart from a slow screen.
%hook UINavigationController

- (UIViewController*)popViewControllerAnimated:(BOOL)animated {
    if (NFBDebugIsRecording()) {
        gNFBLastPopAt = CACurrentMediaTime();
        NFBDebugLog(@"[p27] pop started from %@",
                    NSStringFromClass([self.topViewController class]));
    }
    return %orig;
}

%end

%hook UINavigationBar

- (void)didMoveToWindow {
    %orig;
    @try {
        if (!NFBDebugIsRecording() || !self.window) {
            return;
        }
        if (objc_getAssociatedObject(self, kNFBTerrainNotedKey)) {
            return;
        }
        objc_setAssociatedObject(self, kNFBTerrainNotedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UINavigationBar* bar = self;
        nfbTerrainCensus(bar, @"mounted");
        // Again once the platter has settled: the glass host and the search
        // field are both built after the first mount.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         if (bar.window) {
                             nfbTerrainCensus(bar, @"settled");
                         }
                       });
    } @catch (id exception) {
    }
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        gNFBBarLayouts++;
        gNFBLastBarClass = NSStringFromClass([self class]);
        nfbTerrainInstallWatchdog();
        if (self.window && nfbTerrainBarIsInteresting(self, 0)) {
            nfbTerrainRate(self);
        }
    } @catch (id exception) {
    }
}

%end

// The settled geometry of the two classes the tweak corrects. Only the value the
// view ends up with is reported: three files now hook setFrame:, so an incoming
// frame may already carry another hook's correction and would not be the app's.
%hook TFNSearchBar

- (void)setFrame:(CGRect)frame {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        static CGRect last = {{0, 0}, {0, 0}};
        CGRect after = ((UIView*)self).frame;
        if (CGRectEqualToRect(last, after)) {
            return;
        }
        last = after;
        NFBDebugLog(@"[p25] TFNSearchBar settled x=%.0f y=%.0f %.0fx%.0f a=%.2f%@ "
                    @"super=%@",
                    after.origin.x, after.origin.y, after.size.width,
                    after.size.height, ((UIView*)self).alpha,
                    ((UIView*)self).hidden ? @" HIDDEN" : @"",
                    NSStringFromClass([((UIView*)self).superview class]));
    } @catch (id exception) {
    }
}

%end

%hook TFNNavigationBarSearchView

- (void)setFrame:(CGRect)frame {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        static CGRect last = {{0, 0}, {0, 0}};
        CGRect after = ((UIView*)self).frame;
        if (CGRectEqualToRect(last, after)) {
            return;
        }
        last = after;
        NFBDebugLog(@"[p25] SearchView settled x=%.0f y=%.0f %.0fx%.0f a=%.2f%@ "
                    @"subviews=%lu",
                    after.origin.x, after.origin.y, after.size.width,
                    after.size.height, ((UIView*)self).alpha,
                    ((UIView*)self).hidden ? @" HIDDEN" : @"",
                    (unsigned long)((UIView*)self).subviews.count);
    } @catch (id exception) {
    }
}

%end

// The screen itself, named as it appears, with the header zone censused from
// the controller's own view. A black field shows up here as a view with a dark
// background or a zero size, whichever it turns out to be.
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        NSString* name = NSStringFromClass([self class]);
        if (![name containsString:@"Settings"] && ![name containsString:@"Search"] &&
            ![name containsString:@"Explore"]) {
            return;
        }
        if (objc_getAssociatedObject(self, kNFBTerrainNotedKey)) {
            return;
        }
        objc_setAssociatedObject(self, kNFBTerrainNotedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UINavigationController* nav = self.navigationController;
        NFBDebugLog(@"[p25] screen %@ appeared | nav=%@ depth=%lu presented=%d",
                    name,
                    nav ? NSStringFromClass([nav class]) : @"none",
                    (unsigned long)nav.viewControllers.count,
                    nav.presentingViewController ? 1 : 0);
        UIViewController* controller = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         @try {
                             UIView* view = controller.viewIfLoaded;
                             if (!view.window) {
                                 return;
                             }
                             NSInteger budget = 24;
                             NFBDebugLog(@"[p25] ----- header of %@ -----", name);
                             nfbTerrainWalk(view, 0, 4, &budget, @"scr");
                             UINavigationBar* bar =
                                 controller.navigationController.navigationBar;
                             if (bar) {
                                 nfbTerrainCensus(bar, @"screen");
                             }
                         } @catch (id exception) {
                         }
                       });
    } @catch (id exception) {
    }
}

%end
