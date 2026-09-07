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
#import <execinfo.h>

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

// [p29] Every mutation the tweak makes to a navigation bar, with the function
// that made it. Armed only while a presented bar is on screen, so a normal
// session pays nothing.
#define NFB_MUTATION_SLOTS 48

typedef struct {
    const char* cls;
    const char* sel;
    char caller[72];
    char detail[56];
    int64_t count;
} NFBMutation;

static NFBMutation gNFBMutations[NFB_MUTATION_SLOTS];
static int64_t gNFBMutationsWritten = 0;
static BOOL gNFBRingArmed = NO;

// The caller is frame 2: this function, then the logos trampoline, then whoever
// wrote. dladdr names it, and the image tells our code from UIKit's.
static void nfbTerrainNoteMutation(id owner, const char* sel, const char* detail) {
    if (!gNFBRingArmed || !NFBDebugIsRecording()) {
        return;
    }
    if ([owner isKindOfClass:[UIView class]] &&
        !nfbTerrainInNavigationBar((UIView*)owner)) {
        return;
    }
    void* frames[4];
    int depth = backtrace(frames, 4);
    char caller[72];
    Dl_info info;
    if (depth > 2 && dladdr(frames[2], &info) && info.dli_sname) {
        const char* image = info.dli_fname ? strrchr(info.dli_fname, '/') : NULL;
        snprintf(caller, sizeof(caller), "%s%s",
                 (image && strstr(image, "PrimeFreeBird")) ? "" : "[app] ",
                 info.dli_sname);
    } else {
        strlcpy(caller, "unknown", sizeof(caller));
    }
    const char* cls = object_getClassName(owner);
    if (gNFBMutationsWritten > 0) {
        NFBMutation* last =
            &gNFBMutations[(gNFBMutationsWritten - 1) % NFB_MUTATION_SLOTS];
        if (last->cls == cls && last->sel == sel &&
            strcmp(last->caller, caller) == 0) {
            last->count++;
            return;
        }
    }
    NFBMutation* slot = &gNFBMutations[gNFBMutationsWritten % NFB_MUTATION_SLOTS];
    slot->cls = cls;
    slot->sel = sel;
    strlcpy(slot->caller, caller, sizeof(slot->caller));
    strlcpy(slot->detail, detail ?: "", sizeof(slot->detail));
    slot->count = 1;
    gNFBMutationsWritten++;
}

static NSString* nfbTerrainMutationDump(void) {
    if (gNFBMutationsWritten == 0) {
        return @"MUTATIONS none recorded";
    }
    NSMutableString* text = [NSMutableString stringWithFormat:
        @"MUTATIONS %lld total, last %d:", gNFBMutationsWritten,
        (int)MIN(gNFBMutationsWritten, (int64_t)NFB_MUTATION_SLOTS)];
    int64_t first = gNFBMutationsWritten > NFB_MUTATION_SLOTS
                        ? gNFBMutationsWritten - NFB_MUTATION_SLOTS
                        : 0;
    for (int64_t i = first; i < gNFBMutationsWritten; i++) {
        NFBMutation* m = &gNFBMutations[i % NFB_MUTATION_SLOTS];
        [text appendFormat:@"\n%lld x%lld %s %s %s <- %s", i, m->count,
                           m->cls ?: "?", m->sel ?: "?", m->detail, m->caller];
    }
    return text;
}

%hook UIView

- (void)setFrame:(CGRect)frame {
    char detail[56];
    snprintf(detail, sizeof(detail), "%.0fx%.0f@%.0f,%.0f", frame.size.width,
             frame.size.height, frame.origin.x, frame.origin.y);
    nfbTerrainNoteMutation(self, "setFrame:", detail);
    %orig;
}

- (void)setBounds:(CGRect)bounds {
    char detail[56];
    snprintf(detail, sizeof(detail), "%.0fx%.0f", bounds.size.width,
             bounds.size.height);
    nfbTerrainNoteMutation(self, "setBounds:", detail);
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    nfbTerrainNoteMutation(self, "setHidden:", hidden ? "YES" : "NO");
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    char detail[56];
    snprintf(detail, sizeof(detail), "%.2f", alpha);
    nfbTerrainNoteMutation(self, "setAlpha:", detail);
    %orig;
}

- (void)invalidateIntrinsicContentSize {
    nfbTerrainNoteMutation(self, "invalidateIntrinsicContentSize", "");
    %orig;
}

- (void)setTintColor:(UIColor*)tint {
    nfbTerrainNoteMutation(self, "setTintColor:", "");
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

// Counters for the writes that invalidate a navigation bar. During a hang their
// deltas name what is feeding the storm, which the layout count alone cannot.
static volatile int64_t gNFBSetTint = 0;
static volatile int64_t gNFBSetTitleAttrs = 0;
static volatile int64_t gNFBSetHidesShared = 0;
static volatile int64_t gNFBSetNeedsLayout = 0;
static volatile int64_t gNFBNeedsInPass = 0;
static volatile int64_t gNFBBarDidMove = 0;
static volatile int32_t gNFBInBarLayout = 0;

// Every counter sampled at the same instant, so the report carries deltas over
// the hang instead of totals since launch.
typedef struct {
    int64_t layouts, needs, needsInPass, didMove, tint, titleAttrs, hidesShared;
} NFBTerrainCounters;

static NFBTerrainCounters nfbTerrainSample(void) {
    NFBTerrainCounters c = { gNFBBarLayouts,     gNFBSetNeedsLayout,
                             gNFBNeedsInPass,    gNFBBarDidMove,
                             gNFBSetTint,        gNFBSetTitleAttrs,
                             gNFBSetHidesShared };
    return c;
}

@interface UIBarButtonItem (NFBTerrain)
- (void)setHidesSharedBackground:(BOOL)hides;
@end

// The stack that invalidates a bar while it is storming. Captured once per run,
// and only past the threshold, so a healthy session pays nothing for it.
static char* gNFBStormStack = NULL;

static void nfbTerrainNoteInvalidation(void) {
    if (gNFBStormStack) {
        return;
    }
    static NSTimeInterval windowStart = 0;
    static int64_t windowCount = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - windowStart > 0.5) {
        windowStart = now;
        windowCount = 0;
    }
    if (++windowCount < 200) {
        return;
    }
    void* frames[24];
    int depth = backtrace(frames, 24);
    char** symbols = backtrace_symbols(frames, depth);
    if (!symbols) {
        return;
    }
    NSMutableString* text = [NSMutableString string];
    for (int i = 0; i < depth; i++) {
        [text appendFormat:@"%s\n", symbols[i]];
    }
    free(symbols);
    gNFBStormStack = strdup(text.UTF8String);
}

static NSString* nfbTerrainHangPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"nfb-hang.txt"];
}

// Written from the watchdog thread while the main thread is stuck, so it must not
// touch UIKit or any state the main thread owns beyond these counters.
static void nfbTerrainWriteHang(NSTimeInterval stuckFor,
                                NFBTerrainCounters start) {
    NFBTerrainCounters now = nfbTerrainSample();
    NSString* report = [NSString
        stringWithFormat:@"HANG %.1f s | layouts +%lld | needsLayout +%lld "
                         @"(inside a UIKit pass %lld) | didMove +%lld | tint +%lld "
                         @"| titleAttrs +%lld | hidesShared +%lld | last bar %@ | "
                         @"pop %.1f s before",
                         stuckFor, now.layouts - start.layouts,
                         now.needs - start.needs,
                         now.needsInPass - start.needsInPass,
                         now.didMove - start.didMove, now.tint - start.tint,
                         now.titleAttrs - start.titleAttrs,
                         now.hidesShared - start.hidesShared,
                         gNFBLastBarClass ?: @"none",
                         gNFBLastPopAt > 0 ? CACurrentMediaTime() - gNFBLastPopAt : -1.0];
    report = [report stringByAppendingFormat:@"\n%@",
                                             nfbTerrainMutationDump()];
    if (gNFBStormStack) {
        report = [report stringByAppendingFormat:@"\nSTORM STACK\n%s",
                                                 gNFBStormStack];
    }
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
        for (NSString* line in [report componentsSeparatedByString:@"\n"]) {
            if (line.length) {
                NFBDebugLog(@"[p27] previous run: %@", line);
            }
        }
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

static void nfbTerrainInstallWatchdog(void) {
    if (gNFBWatchdog) {
        return;
    }
    nfbTerrainReplayHang();
    NFBDebugLog(@"[p29] probe: mutations+stack+counters, all hooks live");
    gNFBMainTick = CACurrentMediaTime();
    dispatch_queue_t queue =
        dispatch_queue_create("nfb.watchdog", DISPATCH_QUEUE_SERIAL);
    gNFBWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(gNFBWatchdog, DISPATCH_TIME_NOW,
                              (uint64_t)(0.3 * NSEC_PER_SEC), 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(gNFBWatchdog, ^{
      static BOOL reported = NO;
      static NFBTerrainCounters start;
      NSTimeInterval idle = CACurrentMediaTime() - gNFBMainTick;
      if (idle < 0.5) {
          reported = NO;
          start = nfbTerrainSample();
      } else if (idle > 2.0 && !reported) {
          reported = YES;
          nfbTerrainWriteHang(idle, start);
      }
      dispatch_async(dispatch_get_main_queue(),
                     ^{ gNFBMainTick = CACurrentMediaTime(); });
    });
    dispatch_resume(gNFBWatchdog);
    NFBDebugLog(@"[p27] hang watchdog armed");
}

// The moment a pop starts, so a hang can be told apart from a slow screen.
%hook UIImageView

// An image of a different size changes the intrinsic size of the button that
// holds it, which invalidates the whole bar. Both sizes are recorded.
- (void)setImage:(UIImage*)image {
    if (gNFBRingArmed) {
        char detail[56];
        UIImage* was = self.image;
        snprintf(detail, sizeof(detail), "%.0fx%.0f was %.0fx%.0f",
                 image.size.width, image.size.height, was.size.width,
                 was.size.height);
        nfbTerrainNoteMutation(self, "setImage:", detail);
    }
    %orig;
}

%end

%hook UIBarButtonItem

- (void)setImage:(UIImage*)image {
    char detail[56];
    snprintf(detail, sizeof(detail), "%.0fx%.0f", image.size.width,
             image.size.height);
    nfbTerrainNoteMutation(self, "item setImage:", detail);
    %orig;
}

- (void)setWidth:(CGFloat)width {
    char detail[56];
    snprintf(detail, sizeof(detail), "%.0f", width);
    nfbTerrainNoteMutation(self, "item setWidth:", detail);
    %orig;
}

- (void)setTitleTextAttributes:(NSDictionary*)attributes
                      forState:(UIControlState)state {
    gNFBSetTitleAttrs++;
    nfbTerrainNoteMutation(self, "item setTitleTextAttributes:", "");
    %orig;
}

- (void)setHidesSharedBackground:(BOOL)hides {
    gNFBSetHidesShared++;
    nfbTerrainNoteMutation(self, "item setHidesSharedBackground:",
                           hides ? "YES" : "NO");
    %orig;
}

- (void)setTintColor:(UIColor*)tint {
    gNFBSetTint++;
    nfbTerrainNoteMutation(self, "item setTintColor:", "");
    %orig;
}

%end

%hook UINavigationController

- (UIViewController*)popViewControllerAnimated:(BOOL)animated {
    if (NFBDebugIsRecording()) {
        gNFBLastPopAt = CACurrentMediaTime();
        NFBDebugLog(@"[p27] pop started from %@",
                    NSStringFromClass([self.topViewController class]));
    }
    return %orig;
}

// A back button does not go through the method above: UIKit asks the bar's
// delegate, which is the navigation controller itself. This is the one a tap on
// the chevron reaches.
- (BOOL)navigationBar:(UINavigationBar*)bar shouldPopItem:(UINavigationItem*)item {
    if (NFBDebugIsRecording()) {
        gNFBLastPopAt = CACurrentMediaTime();
        NFBDebugLog(@"[p27] back button pop from %@",
                    NSStringFromClass([self.topViewController class]));
    }
    return %orig;
}

%end

%hook UINavigationBar

- (void)setNeedsLayout {
    gNFBSetNeedsLayout++;
    if (gNFBInBarLayout > 0) {
        gNFBNeedsInPass++;
    }
    @try {
        nfbTerrainNoteInvalidation();
    } @catch (id exception) {
    }
    %orig;
}

- (void)didMoveToWindow {
    gNFBBarDidMove++;
    %orig;
    @try {
        // The ring only runs while a modally presented bar is on screen, which
        // is the settings sheet and the moment the chevron acts on.
        UIResponder* responder = (UIResponder*)self;
        BOOL presented = NO;
        for (NSInteger up = 0; responder && up < 6; up++) {
            responder = responder.nextResponder;
            if ([responder isKindOfClass:[UINavigationController class]]) {
                presented = ((UINavigationController*)responder)
                                .presentingViewController != nil;
                break;
            }
        }
        if (self.window && presented) {
            if (!gNFBRingArmed) {
                gNFBRingArmed = YES;
                NFBDebugLog(@"[p29] mutation ring armed on %@",
                            NSStringFromClass([self class]));
            }
        } else if (!self.window && gNFBRingArmed) {
            gNFBRingArmed = NO;
        }
    } @catch (id exception) {
    }
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
    // The bracket covers UIKit's own pass only: this hook loads first, so the
    // other files' hooks wrap it rather than run inside it.
    gNFBInBarLayout++;
    %orig;
    gNFBInBarLayout--;
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
