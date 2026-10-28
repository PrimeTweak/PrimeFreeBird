// Measures Twitter's own Liquid Glass chrome. The tab bar: what changes in it, who changes
// it, where the touches land, how busy the main thread is. The rest: which hook points the
// options rely on still run, what Twitter's new navigation calls instead, and what the
// main screens show in their bars, compose button, Explore tabs and side menu.
//
// A summary goes to MEASUREMENTS. When Twitter leaves the screen, this report and the
// whole Compatibility report go to the pasteboard, unless something was copied while
// Twitter was in front. The hooks are installed after every other file's, so they run
// first: an animation another hook refuses is seen not landing, and each write is
// charged to the code that sent it.

#import <mach-o/loader.h>
#import <pthread.h>
#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"

extern BOOL PFBAccentIsActive(void);

// The methods hooked below that no header declares.
@interface T1TabBarViewController (PFBGlassChromeProbe)
- (void)setTabBarCollapseRatio:(double)ratio;
- (void)_t1_layoutTabBar;
- (void)_t1_updateTabBarHidden;
@end

@interface T1TabbedAppNavigationViewController (PFBGlassChromeProbe)
- (void)setVisibleTabEntries:(NSArray*)entries;
- (NSArray*)_t1_tabEntriesLimitedToBottomCapacity:(NSArray*)entries;
- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation;
@end

@interface _TtC11XNavigation10TabBarView : UIView
- (void)handleTracking:(UIGestureRecognizer*)recognizer;
@end

@interface T1DashContentController : NSObject
- (void)updateVisiblePanelIDs;
@end

@interface T1TabNavigationController : UINavigationController
- (void)_t1_main_updateNavigationItemForViewController:(id)controller
                                                isRoot:(BOOL)isRoot
                           providingLeftBarButtonItems:(__unsafe_unretained id)left
                                 rightBarButtonItems:(__unsafe_unretained id)right;
@end

@interface TFNExpandingButtonItemView : UIView
- (void)_tfn_updateIcon;
@end

@interface _TtC14T1TwitterSwift28GuideContainerViewController : UIViewController
- (UIView*)tfn_navigationBarAccessoryView;
@end

@interface _TtC14T1TwitterSwift20XTabbedAppNavigation : NSObject
- (NSArray*)visiblePanelIDs;
- (void)recalculateVisiblePanels;
- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(id)panelIDs;
- (void)setCurrentPanel:(long long)panel animated:(BOOL)animated completion:(id)completion;
@end

// MARK: - Counters

typedef NS_ENUM(NSInteger, PFBProbeEvent) {
    PFBProbeBarLayout,
    PFBProbeItemLayout,
    PFBProbeControllerLayout,
    PFBProbeControllerTraits,
    PFBProbePillTraits,
    PFBProbeLensLayout,
    PFBProbeAnimation,
    PFBProbeFilterAnimation,
    PFBProbeAnimationMissed,
    PFBProbeFiltersGone,
    PFBProbeFiltersSet,
    PFBProbeFiltersEmptied,
    PFBProbeTint,
    PFBProbeImage,
    PFBProbeAlpha,
    PFBProbeAlphaFlip,
    PFBProbeHidden,
    PFBProbeHiddenFlip,
    PFBProbeBackground,
    PFBProbeWindowTint,
    PFBProbeWindowLayout,
    PFBProbeColorReload,
    PFBProbeTracking,
    PFBProbeEventAsked,
    PFBProbeEventRefused,
    PFBProbeOldTabIcon,
    PFBProbeOldTabLayout,
    PFBProbeOldTabSelected,
    PFBProbeOldCollapse,
    PFBProbeOldBarLayout,
    PFBProbeOldBarHidden,
    PFBProbeOldHostLayout,
    PFBProbeOldCustomBarLayout,
    PFBProbeOldTabEntries,
    PFBProbeOldTabCapacity,
    PFBProbeOldPanelsAsked,
    PFBProbeDashUpdate,
    PFBProbeOldNavigationItems,
    PFBProbeOldNavigationBar,
    PFBProbeOldComposeIcon,
    PFBProbeOldComposeButton,
    PFBProbeExploreAccessory,
    PFBProbeExploreTabs,
    PFBProbeFleetLine,
    PFBProbeTweetFooter,
    PFBProbeNewPanelsAsked,
    PFBProbeNewPanelsAskedByDash,
    PFBProbeNewRecalculate,
    PFBProbeNewSetPanel,
    PFBProbeDashShown,
    PFBProbeEventCount
};

typedef struct {
    NSUInteger total;
    NSUInteger ours;  // sent straight from PrimeFreeBird's code
    NSUInteger second;
    NSUInteger peak;  // the most in one second
    NSInteger secondIndex;
    CFTimeInterval spent;  // inside the hooked call, ours included
} PFBProbeCount;

static PFBProbeCount gProbeCounts[PFBProbeEventCount];

// Seconds kept one by one, from the start of the probe.
#define PFB_PROBE_SECONDS 600
#define PFB_PROBE_SERIES 3
static const PFBProbeEvent kPFBProbeSeriesEvents[PFB_PROBE_SERIES] = {PFBProbeAnimationMissed, PFBProbeBarLayout,
                                                                       PFBProbeAlphaFlip};
static uint16_t gProbeSeries[PFB_PROBE_SERIES][PFB_PROBE_SECONDS];
static float gProbeBusy[PFB_PROBE_SECONDS];

static CFTimeInterval gProbeStart;
static NSString* gProbeLaunchClock;

// Main thread only, so the counters need no lock.
static void PFBProbeNote(PFBProbeEvent event, BOOL ours, CFTimeInterval spent) {
    if (gProbeStart <= 0 || !pthread_main_np()) {
        return;
    }
    NSInteger second = (NSInteger)(CACurrentMediaTime() - gProbeStart);
    PFBProbeCount* count = &gProbeCounts[event];
    if (count->secondIndex != second) {
        count->secondIndex = second;
        count->second = 0;
    }
    count->total++;
    count->second++;
    count->peak = MAX(count->peak, count->second);
    count->ours += ours ? 1 : 0;
    count->spent += spent;
    if (second < 0 || second >= PFB_PROBE_SECONDS) {
        return;
    }
    for (NSUInteger slot = 0; slot < PFB_PROBE_SERIES; slot++) {
        if (kPFBProbeSeriesEvents[slot] == event && gProbeSeries[slot][second] < UINT16_MAX) {
            gProbeSeries[slot][second]++;
        }
    }
}

// A name counted in a table that keeps at most 24 names; the rest go under "others".
static void PFBProbeTally(NSMutableDictionary<NSString*, NSNumber*>* tally, NSString* name) {
    NSNumber* count = tally[name];
    if (!count && tally.count >= 24) {
        name = @"others";
        count = tally[name];
    }
    tally[name] = @(count.unsignedIntegerValue + 1);
}

// MARK: - Who sent it

// PrimeFreeBird's code is the __TEXT segment of the image this file is in. A write whose
// return address falls inside it was sent by PrimeFreeBird, not by Twitter or UIKit.
static uintptr_t gProbeOursStart;
static uintptr_t gProbeOursEnd;

static void PFBProbeFindOurCode(void) {
    Dl_info info;
    if (!dladdr((const void*)&PFBProbeFindOurCode, &info) || !info.dli_fbase) {
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

static BOOL PFBProbeFromUs(const void* returnAddress) {
    uintptr_t address = (uintptr_t)returnAddress;
    return address >= gProbeOursStart && address < gProbeOursEnd;
}

// "_TtC11XNavigation10TabBarView" reads "XNavigation.TabBarView".
static NSString* PFBProbeName(Class cls) {
    if (!cls) {
        return @"none";
    }
    NSString* name = NSStringFromClass(cls);
    if (![name hasPrefix:@"_TtC"] || [name hasPrefix:@"_TtCC"]) {
        return name;
    }
    const char* cursor = name.UTF8String + 4;
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    while (*cursor >= '0' && *cursor <= '9') {
        char* end = NULL;
        long length = strtol(cursor, &end, 10);
        if (length <= 0 || (long)strlen(end) < length) {
            return name;
        }
        NSString* part = [[NSString alloc] initWithBytes:end length:(NSUInteger)length encoding:NSUTF8StringEncoding];
        [parts addObject:part ?: @"?"];
        cursor = end + length;
    }
    return parts.count == 2 && *cursor == '\0' ? [parts componentsJoinedByString:@"."] : name;
}

// MARK: - The bar

// The glass bar last laid out, held so the hot paths below compare pointers only.
static UIView* gProbeBar;
static CALayer* gProbeBarLayer;
static NSHashTable* gProbeBarsSeen;
static NSHashTable* gProbeItemsSeen;
static NSHashTable* gProbeLensesSeen;
static NSUInteger gProbeBarsMade;
static NSUInteger gProbeItemsMade;
static NSUInteger gProbeLensesMade;

static BOOL PFBProbeViewInBar(UIView* view) {
    __unsafe_unretained UIView* bar = gProbeBar;
    __unsafe_unretained UIView* node = view;
    for (NSInteger depth = 0; bar && node && depth < 48; depth++) {
        if (node == bar) {
            return YES;
        }
        node = node.superview;
    }
    return NO;
}

static BOOL PFBProbeLayerInBar(CALayer* layer) {
    __unsafe_unretained CALayer* target = gProbeBarLayer;
    __unsafe_unretained CALayer* node = layer;
    for (NSInteger depth = 0; target && node && depth < 64; depth++) {
        if (node == target) {
            return YES;
        }
        node = node.superlayer;
    }
    return NO;
}

// Inside the old bar, the one Twitter draws without its glass.
static BOOL PFBProbeViewInOldBar(UIView* view) {
    for (UIView* node = view; node; node = node.superview) {
        NSString* name = NSStringFromClass([node class]);
        if ([name isEqualToString:@"T1TabBarHostView"] || [name isEqualToString:@"TFNCustomTabBar"]) {
            return YES;
        }
    }
    return NO;
}

// Counts an object the first time it is seen.
static void PFBProbeSeen(NSHashTable* __strong* table, NSUInteger* made, id object) {
    if (!*table) {
        *table = [NSHashTable weakObjectsHashTable];
    }
    if (![*table containsObject:object]) {
        [*table addObject:object];
        (*made)++;
    }
}

static void PFBProbeNoteBar(UIView* bar) {
    if (gProbeBar != bar) {
        gProbeBar = bar;
        gProbeBarLayer = bar.layer;
    }
    PFBProbeSeen(&gProbeBarsSeen, &gProbeBarsMade, bar);
}

// MARK: - Animations and filters in the bar

static NSMutableDictionary<NSString*, NSNumber*>* gProbeAnimationKinds;
static NSMutableDictionary<NSString*, NSNumber*>* gProbeMissedKinds;
static NSMutableDictionary<NSString*, NSNumber*>* gProbeMissedOwners;

// "filters.gaussianBlur.inputRadius" counts as "filters.gaussianBlur", "position.x" as "position".
static NSString* PFBProbeAnimationKind(NSString* key) {
    if (!key.length) {
        return @"(no key)";
    }
    NSArray<NSString*>* parts = [key componentsSeparatedByString:@"."];
    if (parts.count >= 2 && [parts[0] isEqualToString:@"filters"]) {
        return [NSString stringWithFormat:@"filters.%@", parts[1]];
    }
    return parts[0];
}

static NSString* PFBProbeLayerOwner(CALayer* layer) {
    id delegate = layer.delegate;
    return PFBProbeName([delegate isKindOfClass:[UIView class]] ? [delegate class] : [layer class]);
}

static void PFBProbeNoteAnimation(CALayer* layer, NSString* key, BOOL landed, BOOL filtersGone) {
    if (!gProbeAnimationKinds) {
        gProbeAnimationKinds = [NSMutableDictionary dictionary];
        gProbeMissedKinds = [NSMutableDictionary dictionary];
        gProbeMissedOwners = [NSMutableDictionary dictionary];
    }
    NSString* kind = PFBProbeAnimationKind(key);
    PFBProbeNote(PFBProbeAnimation, NO, 0);
    if ([kind hasPrefix:@"filters"]) {
        PFBProbeNote(PFBProbeFilterAnimation, NO, 0);
    }
    PFBProbeTally(gProbeAnimationKinds, kind);
    if (landed) {
        return;
    }
    PFBProbeNote(PFBProbeAnimationMissed, NO, 0);
    if (filtersGone) {
        PFBProbeNote(PFBProbeFiltersGone, NO, 0);
    }
    PFBProbeTally(gProbeMissedKinds, kind);
    PFBProbeTally(gProbeMissedOwners, PFBProbeLayerOwner(layer));
}

// MARK: - Touches on the bar

@interface PFBProbeTap : NSObject
@property(nonatomic) CFTimeInterval began;
@property(nonatomic) CFTimeInterval ended;
@property(nonatomic) CGFloat x;
@property(nonatomic, copy) NSString* view;
@property(nonatomic, copy) NSString* place;
@property(nonatomic, copy) NSString* phase;
@property(nonatomic, copy) NSString* screenBefore;
@property(nonatomic, copy) NSString* screenAfter;
@property(nonatomic) NSUInteger trackingBefore;
@property(nonatomic) NSUInteger trackingAfter;
@end

@implementation PFBProbeTap
@end

static NSMutableDictionary<NSValue*, PFBProbeTap*>* gProbeOpenTaps;
static NSMutableArray<PFBProbeTap*>* gProbeTaps;
static NSUInteger gProbeTapCount;
static NSUInteger gProbeTapsOnBar;
static NSUInteger gProbeTapsOnOldBar;
static NSUInteger gProbeTapsEnded;
static NSUInteger gProbeTapsCancelled;
static NSUInteger gProbeTapsWithScreen;
static NSUInteger gProbeTrackingStates[6];
static NSString* gProbeTrackingRecognizer;

// The screen in front: the last full-height controller that appeared.
static NSString* gProbeScreen;
static CFTimeInterval gProbeScreenTime;

static void PFBProbeNoteScreen(UIViewController* controller) {
    static Class barController;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      barController = NSClassFromString(@"_TtC11XNavigation16TabBarController");
    });
    if ([controller isKindOfClass:[UINavigationController class]] ||
        [controller isKindOfClass:[UITabBarController class]] ||
        (barController && [controller isKindOfClass:barController])) {
        return;
    }
    UIView* view = controller.viewIfLoaded;
    UIWindow* window = view.window;
    if (!window || CGRectGetHeight(view.bounds) < CGRectGetHeight(window.bounds) * 0.5) {
        return;
    }
    gProbeScreen = PFBProbeName([controller class]);
    gProbeScreenTime = CACurrentMediaTime();
}

// Touches that start in the bottom fifth of the screen, where the bar sits.
static void PFBProbeTouches(UIWindow* window, UIEvent* event) {
    if (!gProbeOpenTaps) {
        gProbeOpenTaps = [NSMutableDictionary dictionary];
        gProbeTaps = [NSMutableArray array];
    }
    for (UITouch* touch in [event touchesForWindow:window]) {
        NSValue* key = [NSValue valueWithNonretainedObject:touch];
        if (touch.phase == UITouchPhaseBegan) {
            CGPoint point = [touch locationInView:window];
            CGRect bounds = window.bounds;
            if (CGRectGetHeight(bounds) <= 0 || point.y < CGRectGetHeight(bounds) * 0.8) {
                continue;
            }
            if (gProbeOpenTaps.count > 16) {
                [gProbeOpenTaps removeAllObjects];
            }
            PFBProbeTap* tap = [PFBProbeTap new];
            tap.began = CACurrentMediaTime();
            tap.x = point.x / MAX(CGRectGetWidth(bounds), 1.0);
            tap.view = PFBProbeName([touch.view class]);
            if (PFBProbeViewInBar(touch.view)) {
                tap.place = @"glass bar";
                gProbeTapsOnBar++;
            } else if (PFBProbeViewInOldBar(touch.view)) {
                tap.place = @"old bar";
                gProbeTapsOnOldBar++;
            } else {
                tap.place = @"elsewhere";
            }
            tap.phase = @"still down";
            tap.screenBefore = gProbeScreen ?: @"?";
            tap.trackingBefore = gProbeCounts[PFBProbeTracking].total;
            gProbeOpenTaps[key] = tap;
            [gProbeTaps addObject:tap];
            if (gProbeTaps.count > 12) {
                [gProbeTaps removeObjectAtIndex:0];
            }
            gProbeTapCount++;
        } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            PFBProbeTap* tap = gProbeOpenTaps[key];
            if (!tap) {
                continue;
            }
            [gProbeOpenTaps removeObjectForKey:key];
            tap.ended = CACurrentMediaTime();
            BOOL ended = touch.phase == UITouchPhaseEnded;
            tap.phase = ended ? @"ended" : @"cancelled";
            if (ended) {
                gProbeTapsEnded++;
            } else {
                gProbeTapsCancelled++;
            }
            // A tab change shows its screen within a second and a half.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              tap.trackingAfter = gProbeCounts[PFBProbeTracking].total;
              if (gProbeScreenTime > tap.began && gProbeScreen) {
                  tap.screenAfter = gProbeScreen;
                  gProbeTapsWithScreen++;
              }
            });
        }
    }
}

// MARK: - Twitter's new navigation

// What the new navigation last answered or was told: the panels it shows, the update it
// was given, the panels it was sent to.
static NSArray* gProbePanels;
static NSString* gProbeUpdatedPanels;
static NSMutableArray<NSNumber*>* gProbePanelsSet;
// Set while the side menu works out which panels the tab bar already shows.
static BOOL gProbeDashQuery;

static NSString* PFBProbePanelsText(NSArray* panels) {
    if (![panels isKindOfClass:[NSArray class]]) {
        return panels ? [panels description] : @"none";
    }
    return [NSString stringWithFormat:@"[%@]", [[panels valueForKey:@"description"] componentsJoinedByString:@" "]];
}

// MARK: - The main screens

// Each main screen is taken once per launch, a moment after it appeared.
static NSMutableDictionary<NSString*, NSString*>* gProbeScreenTexts;
static NSMutableSet<NSString*>* gProbeScreensTaken;

// A glyph by the name it was loaded with, its system symbol, or its size.
static NSString* PFBProbeImageText(UIImage* image) {
    if (!image) {
        return @"no image";
    }
    id vector = objc_getAssociatedObject(image, (const void*)NSSelectorFromString(@"tfn_vectorImageNamed:fitsSize:fillColor:"));
    if ([vector isKindOfClass:[NSString class]]) {
        return [@"vector " stringByAppendingString:vector];
    }
    if (image.isSymbolImage) {
        NSString* description = image.description;
        NSRange start = [description rangeOfString:@"symbol("];
        NSRange end = start.location == NSNotFound
                          ? start
                          : [description rangeOfString:@")"
                                                options:0
                                                  range:NSMakeRange(NSMaxRange(start), description.length - NSMaxRange(start))];
        return end.location == NSNotFound
                   ? @"symbol"
                   : [description substringWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
    }
    return [NSString stringWithFormat:@"image %.0fx%.0f", image.size.width, image.size.height];
}

static NSString* PFBProbeItemText(UIBarButtonItem* item) {
    NSMutableArray<NSString*>* parts = [NSMutableArray arrayWithObject:PFBProbeName([item class])];
    if (item.tag) {
        [parts addObject:[NSString stringWithFormat:@"tag %ld", (long)item.tag]];
    }
    if (item.title.length) {
        [parts addObject:[NSString stringWithFormat:@"\"%@\"", item.title]];
    }
    if (item.image) {
        [parts addObject:PFBProbeImageText(item.image)];
    }
    if (item.customView) {
        [parts addObject:[@"view " stringByAppendingString:PFBProbeName([item.customView class])]];
    }
    if (item.action) {
        [parts addObject:NSStringFromSelector(item.action)];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString* PFBProbeItemsText(NSArray<UIBarButtonItem*>* items) {
    if (!items.count) {
        return @"none";
    }
    NSMutableArray<NSString*>* texts = [NSMutableArray array];
    for (UIBarButtonItem* item in items) {
        [texts addObject:PFBProbeItemText(item)];
    }
    return [texts componentsJoinedByString:@" | "];
}

// Views whose class name holds one of the parts, outside each other, at most cap.
static NSArray<UIView*>* PFBProbeViewsNamed(UIView* root, NSArray<NSString*>* parts, NSUInteger cap) {
    NSMutableArray<UIView*>* found = [NSMutableArray array];
    PFBWalkAllSubviews(root, 40, ^(UIView* view) {
      if (found.count >= cap) {
          return;
      }
      for (UIView* earlier in found) {
          if ([view isDescendantOfView:earlier]) {
              return;
          }
      }
      NSString* name = NSStringFromClass([view class]);
      for (NSString* part in parts) {
          if ([name containsString:part]) {
              [found addObject:view];
              return;
          }
      }
    });
    return found;
}

static NSString* PFBProbeFrameText(UIView* view) {
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return [NSString stringWithFormat:@"at %.0f,%.0f %.0fx%.0f%@%@", frame.origin.x, frame.origin.y, frame.size.width,
                                      frame.size.height, view.hidden ? @", hidden" : @"",
                                      view.alpha <= 0.01 ? @", clear" : @""];
}

// The controls a bar draws, in order: class, place, label and glyph.
static NSString* PFBProbeDrawnButtons(UIView* bar) {
    NSMutableArray<NSString*>* found = [NSMutableArray array];
    PFBWalkAllSubviews(bar, 16, ^(UIView* view) {
      if (found.count >= 12 || view == bar || !view.window || view.hidden || view.alpha <= 0.01 ||
          (![view isKindOfClass:[UIControl class]] && ![NSStringFromClass([view class]) containsString:@"Button"])) {
          return;
      }
      __block UIImage* glyph = nil;
      PFBWalkAllSubviews(view, 5, ^(UIView* sub) {
        if (!glyph && [sub isKindOfClass:[UIImageView class]]) {
            glyph = ((UIImageView*)sub).image;
        }
      });
      CGRect frame = [view convertRect:view.bounds toView:nil];
      NSString* label = view.accessibilityLabel ?: view.accessibilityIdentifier;
      [found addObject:[NSString stringWithFormat:@"%@ at x %.0f w %.0f%@ %@", PFBProbeName([view class]),
                                                  frame.origin.x, frame.size.width,
                                                  label.length ? [NSString stringWithFormat:@" \"%@\"", label] : @"",
                                                  PFBProbeImageText(glyph)]];
    });
    return found.count ? [found componentsJoinedByString:@" | "] : @"none";
}

// The screen's navigation, the items it asks its bar for, and what the bar draws.
static NSString* PFBProbeTopBarText(UIViewController* controller) {
    UINavigationController* navigation = controller.navigationController;
    UINavigationBar* bar = navigation.navigationBar;
    UINavigationItem* item = controller.navigationItem;
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"navigation %@, bar %@%@ · items left: %@ · items right: %@ · title view %@",
                         PFBProbeName([navigation class]), PFBProbeName([bar class]),
                         bar.hidden || navigation.navigationBarHidden ? @" (hidden)" : @"",
                         PFBProbeItemsText(item.leftBarButtonItems), PFBProbeItemsText(item.rightBarButtonItems),
                         PFBProbeName([item.titleView class])];
    if (@available(iOS 16.0, *)) {
        NSMutableArray<UIBarButtonItem*>* trailing = [NSMutableArray array];
        for (UIBarButtonItemGroup* group in item.trailingItemGroups) {
            [trailing addObjectsFromArray:group.barButtonItems];
        }
        [text appendFormat:@" · trailing groups: %@", PFBProbeItemsText(trailing)];
    }
    [text appendFormat:@" · the bar draws: %@", bar ? PFBProbeDrawnButtons(bar) : @"no bar"];
    return text;
}

static NSString* PFBProbeComposeText(UIWindow* window) {
    NSArray<UIView*>* buttons =
        PFBProbeViewsNamed(window, @[ @"FloatingActionButton", @"TabBarAccessoryButtonView", @"ExpandingButton" ], 4);
    NSMutableArray<NSString*>* texts = [NSMutableArray array];
    for (UIView* button in buttons) {
        NSMutableArray<NSString*>* glyphs = [NSMutableArray array];
        PFBWalkAllSubviews(button, 10, ^(UIView* sub) {
          if (glyphs.count < 4 && [sub isKindOfClass:[UIImageView class]] && ((UIImageView*)sub).image) {
              [glyphs addObject:PFBProbeImageText(((UIImageView*)sub).image)];
          }
        });
        [texts addObject:[NSString stringWithFormat:@"%@ %@, glyphs [%@]", PFBProbeName([button class]),
                                                    PFBProbeFrameText(button), [glyphs componentsJoinedByString:@", "]]];
    }
    return texts.count ? [texts componentsJoinedByString:@" | "] : @"none found";
}

// Views by class name, with their labels: Explore's tabs, the Spaces line, a Tweet's footer.
static NSString* PFBProbeNamedViewsText(UIWindow* window, NSArray<NSString*>* parts) {
    NSMutableArray<NSString*>* texts = [NSMutableArray array];
    for (UIView* view in PFBProbeViewsNamed(window, parts, 4)) {
        NSMutableArray<NSString*>* labels = [NSMutableArray array];
        PFBWalkAllSubviews(view, 12, ^(UIView* sub) {
          NSString* label = [sub isKindOfClass:[UILabel class]] ? ((UILabel*)sub).text : nil;
          if (labels.count < 10 && label.length && !sub.hidden) {
              [labels addObject:label];
          }
        });
        [texts addObject:[NSString stringWithFormat:@"%@ %@, labels [%@]", PFBProbeName([view class]),
                                                    PFBProbeFrameText(view), [labels componentsJoinedByString:@", "]]];
    }
    return texts.count ? [texts componentsJoinedByString:@" | "] : @"none found";
}

// What the side menu offers, as accessibility reads it: its rows are SwiftUI.
static void PFBProbeCollectLabels(id element, NSInteger depth, NSMutableArray<NSString*>* labels) {
    if (!element || depth > 14 || labels.count >= 40) {
        return;
    }
    if ([element isAccessibilityElement]) {
        NSString* label = [element accessibilityLabel];
        if (label.length && ![labels containsObject:label]) {
            [labels addObject:label];
        }
        return;
    }
    NSArray* children = [element accessibilityElements];
    if (!children.count && [element isKindOfClass:[UIView class]]) {
        children = ((UIView*)element).subviews;
    }
    for (id child in children) {
        PFBProbeCollectLabels(child, depth + 1, labels);
    }
}

static NSString* const kPFBProbeTopic = @"glass probe";

static NSDictionary<NSString*, NSString*>* PFBProbeScreenNames(void) {
    return @{
        @"HomeTimelineContainerViewController" : @"Home",
        @"GuideContainerViewController" : @"Explore",
        @"T1NotificationsViewController" : @"Notifications",
        @"XChatViewController" : @"Chat",
        @"T1ConversationContainerViewController" : @"Tweet",
        @"DashHostingController" : @"side menu",
    };
}

static NSString* PFBProbeSnapshot(NSString* screen, UIViewController* controller) {
    UIWindow* window = controller.viewIfLoaded.window;
    if ([screen isEqualToString:@"side menu"]) {
        NSMutableArray<NSString*>* labels = [NSMutableArray array];
        PFBProbeCollectLabels(controller.view, 0, labels);
        return [NSString stringWithFormat:@"entries [%@]", [labels componentsJoinedByString:@", "]];
    }
    NSMutableString* text = [PFBProbeTopBarText(controller) mutableCopy];
    if ([screen isEqualToString:@"Home"]) {
        [text appendFormat:@" · compose button: %@ · Spaces line: %@", PFBProbeComposeText(window),
                           PFBProbeNamedViewsText(window, @[ @"FleetLine" ])];
    } else if ([screen isEqualToString:@"Explore"]) {
        [text appendFormat:@" · tabs: %@", PFBProbeNamedViewsText(window, @[ @"Segmented" ])];
    } else if ([screen isEqualToString:@"Tweet"]) {
        [text appendFormat:@" · footer: %@", PFBProbeNamedViewsText(window, @[ @"ConversationFooter" ])];
    }
    return text;
}

static void PFBProbeScheduleSnapshot(UIViewController* controller) {
    NSString* name = NSStringFromClass([controller class]);
    __block NSString* screen = nil;
    [PFBProbeScreenNames() enumerateKeysAndObjectsUsingBlock:^(NSString* part, NSString* label, BOOL* stop) {
      if ([name containsString:part]) {
          screen = label;
          *stop = YES;
      }
    }];
    if (!gProbeScreensTaken) {
        gProbeScreensTaken = [NSMutableSet set];
        gProbeScreenTexts = [NSMutableDictionary dictionary];
    }
    if (!screen || [gProbeScreensTaken containsObject:screen]) {
        return;
    }
    [gProbeScreensTaken addObject:screen];
    __weak UIViewController* weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIViewController* shown = weakController;
      if (!shown.viewIfLoaded.window) {
          [gProbeScreensTaken removeObject:screen];
          return;
      }
      @try {
          NSString* text = PFBProbeSnapshot(screen, shown);
          gProbeScreenTexts[screen] = text;
          PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"launch %@, %@: %@", gProbeLaunchClock, screen, text],
                           60);
      } @catch (id exception) {
          gProbeScreenTexts[screen] = [NSString stringWithFormat:@"stopped: %@", exception];
      }
    });
}

// MARK: - Main thread

// Time between waking up and going back to sleep, with Core Animation's commit, which
// runs just before the sleep, included.
static CFTimeInterval gProbeAwakeSince;
static CFTimeInterval gProbeBusyTotal;
static CFTimeInterval gProbeLongestPass;

static void PFBProbeBusy(CFTimeInterval from, CFTimeInterval to) {
    while (from < to) {
        NSInteger second = (NSInteger)(from - gProbeStart);
        CFTimeInterval chunkEnd = MIN(to, gProbeStart + (CFTimeInterval)(second + 1));
        if (chunkEnd <= from) {
            break;
        }
        if (second >= 0 && second < PFB_PROBE_SECONDS) {
            gProbeBusy[second] += (float)(chunkEnd - from);
        }
        gProbeBusyTotal += chunkEnd - from;
        from = chunkEnd;
    }
}

static void PFBProbeWake(__unused CFRunLoopObserverRef observer, __unused CFRunLoopActivity activity,
                         __unused void* info) {
    gProbeAwakeSince = CACurrentMediaTime();
}

static void PFBProbeSleep(__unused CFRunLoopObserverRef observer, __unused CFRunLoopActivity activity,
                          __unused void* info) {
    if (gProbeAwakeSince <= 0) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    PFBProbeBusy(gProbeAwakeSince, now);
    gProbeLongestPass = MAX(gProbeLongestPass, now - gProbeAwakeSince);
    gProbeAwakeSince = 0;
}

// A pass still running is counted up to now.
static void PFBProbeBusyCatchUp(void) {
    if (gProbeAwakeSince > 0) {
        CFTimeInterval now = CACurrentMediaTime();
        PFBProbeBusy(gProbeAwakeSince, now);
        gProbeAwakeSince = now;
    }
}

// MARK: - The report

static NSString* PFBProbeCountText(PFBProbeEvent event, BOOL withOurs) {
    PFBProbeCount count = gProbeCounts[event];
    NSMutableString* text = [NSMutableString stringWithFormat:@"%lu", (unsigned long)count.total];
    if (withOurs && count.total) {
        [text appendFormat:@" (%lu by PrimeFreeBird)", (unsigned long)count.ours];
    }
    if (count.peak > 1) {
        [text appendFormat:@", peak %lu/s", (unsigned long)count.peak];
    }
    if (count.spent >= 0.001) {
        [text appendFormat:@", %.0f ms", count.spent * 1000.0];
    }
    return text;
}

static NSString* PFBProbeTallyText(NSDictionary<NSString*, NSNumber*>* tally) {
    if (!tally.count) {
        return @"none";
    }
    NSArray<NSString*>* names = [tally keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b) {
      return [b compare:a];
    }];
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* name in names) {
        [parts addObject:[NSString stringWithFormat:@"%@ %@", name, tally[name]]];
        if (parts.count == 10) {
            break;
        }
    }
    return [parts componentsJoinedByString:@", "];
}

// The first minute, one value a second, without the zeros at the end.
static NSString* PFBProbeSeriesText(NSUInteger slot) {
    NSInteger last = -1;
    for (NSInteger second = 0; second < 60; second++) {
        if (gProbeSeries[slot][second]) {
            last = second;
        }
    }
    if (last < 0) {
        return @"none";
    }
    NSMutableArray<NSString*>* values = [NSMutableArray array];
    for (NSInteger second = 0; second <= last; second++) {
        [values addObject:[NSString stringWithFormat:@"%u", (unsigned)gProbeSeries[slot][second]]];
    }
    return [values componentsJoinedByString:@" "];
}

static NSString* PFBProbeBusyText(BOOL withSeries) {
    PFBProbeBusyCatchUp();
    CFTimeInterval elapsed = CACurrentMediaTime() - gProbeStart;
    NSInteger seconds = MIN((NSInteger)elapsed, (NSInteger)PFB_PROBE_SECONDS);
    float worst = 0;
    NSInteger worstAt = 0;
    NSInteger over = 0;
    for (NSInteger second = 0; second < seconds; second++) {
        if (gProbeBusy[second] > worst) {
            worst = gProbeBusy[second];
            worstAt = second;
        }
        over += gProbeBusy[second] > 0.8f ? 1 : 0;
    }
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"busy %.0f%% on average, worst second %.0f%% at %ld s, %ld s over 80%%, longest pass %.0f ms",
                         elapsed > 0 ? gProbeBusyTotal / elapsed * 100.0 : 0.0, worst * 100.0, (long)worstAt,
                         (long)over, gProbeLongestPass * 1000.0];
    if (withSeries) {
        NSMutableArray<NSString*>* values = [NSMutableArray array];
        for (NSInteger second = 0; second < MIN(seconds, (NSInteger)60); second++) {
            [values addObject:[NSString stringWithFormat:@"%.0f", MIN(gProbeBusy[second], 1.0f) * 100.0]];
        }
        [text appendFormat:@"\n  busy %% each second: %@", values.count ? [values componentsJoinedByString:@" "] : @"none"];
    }
    return text;
}

static void PFBProbeWalkLayers(CALayer* layer, NSInteger depth, NSUInteger* layers, NSUInteger* filtered,
                               NSUInteger* running) {
    if (!layer || depth > 30) {
        return;
    }
    (*layers)++;
    *filtered += layer.filters.count ? 1 : 0;
    *running += layer.animationKeys.count;
    for (CALayer* sublayer in layer.sublayers) {
        PFBProbeWalkLayers(sublayer, depth + 1, layers, filtered, running);
    }
}

// A view of the old bar: where it is, whether it can be seen and touched, and whether
// it sits over the glass bar.
static NSString* PFBProbeOldBarText(NSString* name, UIView* view, CGRect glass) {
    if (!view) {
        return [NSString stringWithFormat:@"%@ none", name];
    }
    CGRect frame = [view convertRect:view.bounds toView:nil];
    return [NSString stringWithFormat:@"%@ at %.0f,%.0f %.0fx%.0f, alpha %.2f%@%@%@", name, frame.origin.x,
                                      frame.origin.y, frame.size.width, frame.size.height, view.alpha,
                                      view.hidden ? @", hidden" : @"",
                                      view.userInteractionEnabled ? @"" : @", no touches",
                                      CGRectIntersectsRect(frame, glass) ? @", over the glass bar" : @""];
}

// Drawn on screen: neither it nor anything between it and the bar is hidden or clear.
// The bar keeps three rows of tabs, and only one of them shows.
static BOOL PFBProbeShownInBar(UIView* view) {
    for (UIView* node = view; node && node != gProbeBar; node = node.superview) {
        if (node.hidden || node.alpha <= 0.01) {
            return NO;
        }
    }
    return YES;
}

// The bar as it is now: its parts, its layers, the old bar, and what a tap at the
// center of each tab on screen would reach.
static NSString* PFBProbeBarText(void) {
    UIView* bar = gProbeBar;
    if (!bar) {
        return NSClassFromString(@"_TtC11XNavigation10TabBarView") ? @"Glass bar: never laid out"
                                                                   : @"Glass bar: not in this Twitter";
    }
    UIWindow* window = bar.window;
    CGRect frame = [bar convertRect:bar.bounds toView:nil];
    Class itemClass = NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    Class pillClass = NSClassFromString(@"_TtC11XNavigation10TabBarPill");
    Class lensClass = NSClassFromString(@"_TtC13XDesignSystem10LiquidLens");
    NSMutableArray<UIView*>* items = [NSMutableArray array];
    __block NSUInteger allItems = 0;
    __block NSUInteger pills = 0;
    __block NSUInteger lenses = 0;
    PFBWalkAllSubviews(bar, 30, ^(UIView* view) {
      if (itemClass && [view isKindOfClass:itemClass]) {
          allItems++;
          if (PFBProbeShownInBar(view)) {
              [items addObject:view];
          }
      } else if (pillClass && [view isKindOfClass:pillClass]) {
          pills++;
      } else if (lensClass && [view isKindOfClass:lensClass]) {
          lenses++;
      }
    });
    NSUInteger layers = 0;
    NSUInteger filtered = 0;
    NSUInteger running = 0;
    PFBProbeWalkLayers(bar.layer, 0, &layers, &filtered, &running);
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"Glass bar: %@ at %.0f,%.0f %.0fx%.0f in %@, alpha %.2f%@ · tabs shown %lu of %lu (made %lu) · "
                         @"pills %lu · lenses %lu (made %lu) · bars made %lu",
                         PFBProbeName([bar class]), frame.origin.x, frame.origin.y, frame.size.width,
                         frame.size.height, PFBProbeName([window class]), bar.alpha, bar.hidden ? @", hidden" : @"",
                         (unsigned long)items.count, (unsigned long)allItems, (unsigned long)gProbeItemsMade,
                         (unsigned long)pills, (unsigned long)lenses, (unsigned long)gProbeLensesMade,
                         (unsigned long)gProbeBarsMade];
    [text appendFormat:@"\n  layers %lu, with filters now %lu, animations running now %lu", (unsigned long)layers,
                       (unsigned long)filtered, (unsigned long)running];

    // What a tap at the center of each tab reaches, from left to right. A window of a higher
    // level that answers the point takes the tap first.
    [items sortUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
      CGFloat ax = [a convertPoint:CGPointZero toView:nil].x;
      CGFloat bx = [b convertPoint:CGPointZero toView:nil].x;
      return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString*>* hits = [NSMutableArray array];
    for (UIView* item in items) {
        if (!window) {
            break;
        }
        CGPoint center = [item convertPoint:CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds))
                                     toView:nil];
        NSString* cover = nil;
        for (UIWindow* other in window.windowScene.windows) {
            if (other == window || other.hidden || other.windowLevel <= window.windowLevel) {
                continue;
            }
            UIView* hit = [other hitTest:[other convertPoint:center fromWindow:window] withEvent:nil];
            if (hit) {
                cover = [NSString stringWithFormat:@"%@ in %@", PFBProbeName([hit class]), PFBProbeName([other class])];
                break;
            }
        }
        UIView* hit = cover ? nil : [window hitTest:center withEvent:nil];
        NSString* place = PFBProbeViewInBar(hit) ? @"" : (PFBProbeViewInOldBar(hit) ? @" (old bar)" : @" (outside)");
        [hits addObject:cover ?: [NSString stringWithFormat:@"%@%@", PFBProbeName([hit class]), place]];
    }
    [text appendFormat:@"\n  a tap at each tab reaches: %@", hits.count ? [hits componentsJoinedByString:@" | "] : @"no tab"];

    __block UIView* host = nil;
    __block UIView* custom = nil;
    if (window) {
        PFBWalkAllSubviews(window, 40, ^(UIView* view) {
          NSString* name = NSStringFromClass([view class]);
          if (!host && [name isEqualToString:@"T1TabBarHostView"]) {
              host = view;
          } else if (!custom && [name isEqualToString:@"TFNCustomTabBar"]) {
              custom = view;
          }
        });
    }
    [text appendFormat:@"\n  old bar: %@ · %@", PFBProbeOldBarText(@"T1TabBarHostView", host, frame),
                       PFBProbeOldBarText(@"TFNCustomTabBar", custom, frame)];
    return text;
}

static NSString* PFBProbeSettingsText(void) {
    NSString* (^on)(NSString*) = ^NSString*(NSString* key) {
      return [PFBSettings boolForKey:key] ? @"on" : @"off";
    };
    return [NSString
        stringWithFormat:@"Liquid Glass %@, Twitter's glass asked %@ · Selected tab %@, glass filter drop %@ · Tab labels "
                         @"%@ · Always visible %@ · custom glass bar %@ · accent %@ · Customize tabs %@ · Classic Tweet "
                         @"button %@ · Hide Tweet button %@ · Hide a notification %@ · Hide sidebar shortcut %@ · Choose "
                         @"tabs %@ · Hide Spaces bar %@ · Tweet source %@",
                         on(@"enable_liquid_glass"), PFBNativeGlassAsked() ? @"yes" : @"no", on(@"tab_bar_theming"),
                         PFBThemedTabBarWanted() ? @"armed" : @"off", on(@"restore_tab_labels"),
                         on(@"no_tab_bar_hiding"), on(@"custom_glass_tab_bar"),
                         PFBAccentIsActive() ? @"active" : @"none",
                         [PFBCustomTabBarUtility visiblePageIDsInOrder] ? @"customized" : @"default",
                         on(@"restore_tweet_button"), on(@"hide_tweet_button"), on(@"hide_notifications"),
                         on(@"hide_grok_sidebar"), on(@"choose_explore_tabs"), on(@"hide_spaces"),
                         on(@"show_tweet_source")];
}

// The tabs asked for in Customize tabs, by page and panel, beside the panels Twitter shows.
static NSString* PFBProbeTabsText(void) {
    NSArray<NSString*>* pages = [PFBCustomTabBarUtility visiblePageIDsInOrder] ?: [PFBCustomTabBarUtility defaultVisiblePageIDs];
    NSMutableArray<NSString*>* panels = [NSMutableArray array];
    for (NSString* page in pages) {
        id panel = [PFBCustomTabBarUtility metadataForPage:page][PFBTabPanelIDKey];
        [panels addObject:panel ? [panel description] : @"?"];
    }
    return [NSString stringWithFormat:@"asked %@ [%@] = panels [%@] · Twitter shows panels %@",
                                      [PFBCustomTabBarUtility visiblePageIDsInOrder] ? @"pages" : @"default pages",
                                      [pages componentsJoinedByString:@" "], [panels componentsJoinedByString:@" "],
                                      PFBProbePanelsText(gProbePanels)];
}

// Where the options hook, beside what Twitter's new navigation calls instead.
static NSString* PFBProbeHookPointsText(void) {
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"Hook points of the old navigation: tab entries %@ · tab capacity %@ · panels asked %@ · side "
                         @"menu update %@ · bar items %@ · TFN bar layout %@ · compose glyph %@ · compose button %@ · "
                         @"Explore accessory %@ · Explore tabs layout %@ · Spaces line %@ · Tweet footer %@",
                         PFBProbeCountText(PFBProbeOldTabEntries, NO), PFBProbeCountText(PFBProbeOldTabCapacity, NO),
                         PFBProbeCountText(PFBProbeOldPanelsAsked, NO), PFBProbeCountText(PFBProbeDashUpdate, NO),
                         PFBProbeCountText(PFBProbeOldNavigationItems, NO),
                         PFBProbeCountText(PFBProbeOldNavigationBar, NO), PFBProbeCountText(PFBProbeOldComposeIcon, NO),
                         PFBProbeCountText(PFBProbeOldComposeButton, NO),
                         PFBProbeCountText(PFBProbeExploreAccessory, NO), PFBProbeCountText(PFBProbeExploreTabs, NO),
                         PFBProbeCountText(PFBProbeFleetLine, NO), PFBProbeCountText(PFBProbeTweetFooter, NO)];
    [text appendFormat:@"\n  old tab bar: tab icon %@ · tab layout %@ · tab selected %@ · collapse ratio %@ · bar layout "
                       @"%@ · bar hidden %@ · host layout %@ · app bar layout %@",
                       PFBProbeCountText(PFBProbeOldTabIcon, NO), PFBProbeCountText(PFBProbeOldTabLayout, NO),
                       PFBProbeCountText(PFBProbeOldTabSelected, NO), PFBProbeCountText(PFBProbeOldCollapse, NO),
                       PFBProbeCountText(PFBProbeOldBarLayout, NO), PFBProbeCountText(PFBProbeOldBarHidden, NO),
                       PFBProbeCountText(PFBProbeOldHostLayout, NO), PFBProbeCountText(PFBProbeOldCustomBarLayout, NO)];
    NSMutableArray<NSString*>* set = [NSMutableArray array];
    for (NSNumber* panel in gProbePanelsSet) {
        [set addObject:panel.description];
    }
    [text appendFormat:@"\nTwitter's new navigation: visible panels asked %@ (by the side menu %@), last %@ · "
                       @"recalculated %@, last update %@ · panel set %@, last [%@] · side menu shown %@",
                       PFBProbeCountText(PFBProbeNewPanelsAsked, NO), PFBProbeCountText(PFBProbeNewPanelsAskedByDash, NO),
                       PFBProbePanelsText(gProbePanels), PFBProbeCountText(PFBProbeNewRecalculate, NO),
                       gProbeUpdatedPanels ?: @"none", PFBProbeCountText(PFBProbeNewSetPanel, NO),
                       [set componentsJoinedByString:@" "], PFBProbeCountText(PFBProbeDashShown, NO)];
    [text appendFormat:@"\nCustomize tabs: %@", PFBProbeTabsText()];
    return text;
}

static NSString* PFBProbeScreensText(void) {
    NSMutableString* text = [NSMutableString stringWithString:@"Screens, a moment after they appeared:"];
    for (NSString* screen in @[ @"Home", @"Explore", @"Notifications", @"Chat", @"Tweet", @"side menu" ]) {
        [text appendFormat:@"\n  %@: %@", screen, gProbeScreenTexts[screen] ?: @"not shown yet"];
    }
    return text;
}

static NSString* PFBProbeTapsText(void) {
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"Taps from the bottom: %lu · on the glass bar %lu · on the old bar %lu · ended %lu · "
                         @"cancelled %lu · a screen appeared after %lu",
                         (unsigned long)gProbeTapCount, (unsigned long)gProbeTapsOnBar,
                         (unsigned long)gProbeTapsOnOldBar, (unsigned long)gProbeTapsEnded,
                         (unsigned long)gProbeTapsCancelled, (unsigned long)gProbeTapsWithScreen];
    [text appendFormat:@"\n  bar tracking %@ (%@): began %lu, changed %lu, ended %lu, cancelled %lu, failed %lu · "
                       @"events asked %@, refused %@",
                       PFBProbeCountText(PFBProbeTracking, NO), gProbeTrackingRecognizer ?: @"no recognizer",
                       (unsigned long)gProbeTrackingStates[1], (unsigned long)gProbeTrackingStates[2],
                       (unsigned long)gProbeTrackingStates[3], (unsigned long)gProbeTrackingStates[4],
                       (unsigned long)gProbeTrackingStates[5], PFBProbeCountText(PFBProbeEventAsked, NO),
                       PFBProbeCountText(PFBProbeEventRefused, NO)];
    for (PFBProbeTap* tap in gProbeTaps) {
        NSString* held = tap.ended > 0 ? [NSString stringWithFormat:@" after %.2f s", tap.ended - tap.began] : @"";
        [text appendFormat:@"\n  %.1f s · x %.2f · %@ (%@) · %@%@ · tracking calls %lu · screen %@ -> %@",
                           tap.began - gProbeStart, tap.x, tap.view, tap.place, tap.phase, held,
                           (unsigned long)(tap.trackingAfter >= tap.trackingBefore
                                               ? tap.trackingAfter - tap.trackingBefore
                                               : 0),
                           tap.screenBefore, tap.screenAfter ?: @"no new screen"];
    }
    return text;
}

static NSString* PFBProbeText(void) {
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"GLASS PROBE · PrimeFreeBird %@ · Twitter %@ · iOS %@ · launched %@, %.0f s ago\n%@\n",
                         PFBCompatBuildID(), info[@"CFBundleShortVersionString"],
                         UIDevice.currentDevice.systemVersion, gProbeLaunchClock,
                         CACurrentMediaTime() - gProbeStart, PFBProbeSettingsText()];
    [text appendFormat:@"Main thread: %@\n", PFBProbeBusyText(YES)];
    [text appendFormat:@"%@\n", PFBProbeBarText()];
    [text appendFormat:@"Animations in the bar: %@ · on filters %@ · did not land %@ · filters gone after %@\n",
                       PFBProbeCountText(PFBProbeAnimation, NO), PFBProbeCountText(PFBProbeFilterAnimation, NO),
                       PFBProbeCountText(PFBProbeAnimationMissed, NO), PFBProbeCountText(PFBProbeFiltersGone, NO)];
    [text appendFormat:@"  kinds: %@\n  not landed: %@\n  not landed on: %@\n  not landed each second: %@\n",
                       PFBProbeTallyText(gProbeAnimationKinds), PFBProbeTallyText(gProbeMissedKinds),
                       PFBProbeTallyText(gProbeMissedOwners), PFBProbeSeriesText(0)];
    [text appendFormat:@"Filters set in the bar: %@, emptied %@\n", PFBProbeCountText(PFBProbeFiltersSet, YES),
                       PFBProbeCountText(PFBProbeFiltersEmptied, NO)];
    [text appendFormat:@"Writes in the bar: tint %@ · images %@ · alpha %@, visibility flips %@ · hidden %@, flips %@ · "
                       @"backgrounds %@\n",
                       PFBProbeCountText(PFBProbeTint, YES), PFBProbeCountText(PFBProbeImage, YES),
                       PFBProbeCountText(PFBProbeAlpha, YES), PFBProbeCountText(PFBProbeAlphaFlip, NO),
                       PFBProbeCountText(PFBProbeHidden, YES), PFBProbeCountText(PFBProbeHiddenFlip, NO),
                       PFBProbeCountText(PFBProbeBackground, YES)];
    [text appendFormat:@"  visibility flips each second: %@\n", PFBProbeSeriesText(2)];
    [text appendFormat:@"Windows: tint set %@ · forced layouts %@ · Twitter color reloads %@\n",
                       PFBProbeCountText(PFBProbeWindowTint, YES), PFBProbeCountText(PFBProbeWindowLayout, YES),
                       PFBProbeCountText(PFBProbeColorReload, NO)];
    [text appendFormat:@"Layout: bar %@ · tabs %@ · bar controller %@ · lens %@ · trait changes: pill %@, bar "
                       @"controller %@\n  bar layouts each second: %@\n",
                       PFBProbeCountText(PFBProbeBarLayout, NO), PFBProbeCountText(PFBProbeItemLayout, NO),
                       PFBProbeCountText(PFBProbeControllerLayout, NO), PFBProbeCountText(PFBProbeLensLayout, NO),
                       PFBProbeCountText(PFBProbePillTraits, NO), PFBProbeCountText(PFBProbeControllerTraits, NO),
                       PFBProbeSeriesText(1)];
    [text appendFormat:@"%@\nScreen in front: %@\n", PFBProbeTapsText(), gProbeScreen ?: @"?"];
    [text appendFormat:@"%@\n%@\n", PFBProbeHookPointsText(), PFBProbeScreensText()];
    return text;
}

// A few lines for MEASUREMENTS, kept until a new build.
static void PFBProbePersist(NSString* moment) {
    if (gProbeStart <= 0) {
        return;
    }
    NSString* stamp = [NSString stringWithFormat:@"launch %@, %@", gProbeLaunchClock, moment];
    static BOOL settingsKept;
    if (!settingsKept) {
        settingsKept = YES;
        PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"%@: %@", stamp, PFBProbeSettingsText()], 60);
    }
    NSString* bar = [[PFBProbeBarText() componentsSeparatedByString:@"\n  "] componentsJoinedByString:@" · "];
    NSArray<NSString*>* lines = @[
        [NSString stringWithFormat:@"%@: %@", stamp, bar],
        [NSString stringWithFormat:@"%@: main thread %@", stamp, PFBProbeBusyText(NO)],
        [NSString stringWithFormat:@"%@: bar animations %@, did not land %@, filters gone after %@; filters set %@ · "
                                   @"not landed: %@",
                                   stamp, PFBProbeCountText(PFBProbeAnimation, NO),
                                   PFBProbeCountText(PFBProbeAnimationMissed, NO),
                                   PFBProbeCountText(PFBProbeFiltersGone, NO), PFBProbeCountText(PFBProbeFiltersSet, YES),
                                   PFBProbeTallyText(gProbeMissedKinds)],
        [NSString stringWithFormat:@"%@: bar writes tint %@, images %@, alpha %@ (flips %@), hidden %@; window tint %@, "
                                   @"forced layouts %@; color reloads %@; bar layouts %@",
                                   stamp, PFBProbeCountText(PFBProbeTint, YES), PFBProbeCountText(PFBProbeImage, YES),
                                   PFBProbeCountText(PFBProbeAlpha, YES), PFBProbeCountText(PFBProbeAlphaFlip, NO),
                                   PFBProbeCountText(PFBProbeHidden, YES), PFBProbeCountText(PFBProbeWindowTint, YES),
                                   PFBProbeCountText(PFBProbeWindowLayout, YES),
                                   PFBProbeCountText(PFBProbeColorReload, NO), PFBProbeCountText(PFBProbeBarLayout, NO)],
        [NSString stringWithFormat:@"%@: taps %lu, on the glass bar %lu, on the old bar %lu, cancelled %lu, a screen after "
                                   @"%lu; tracking ended %lu, cancelled %lu; events refused %lu",
                                   stamp, (unsigned long)gProbeTapCount, (unsigned long)gProbeTapsOnBar,
                                   (unsigned long)gProbeTapsOnOldBar, (unsigned long)gProbeTapsCancelled,
                                   (unsigned long)gProbeTapsWithScreen, (unsigned long)gProbeTrackingStates[3],
                                   (unsigned long)gProbeTrackingStates[4],
                                   (unsigned long)gProbeCounts[PFBProbeEventRefused].total],
        [NSString stringWithFormat:@"%@: %@", stamp,
                                   [[PFBProbeHookPointsText() componentsSeparatedByString:@"\n"]
                                       componentsJoinedByString:@" · "]],
    ];
    for (NSString* line in lines) {
        PFBCompatMeasure(kPFBProbeTopic, line, 60);
    }
}

// MARK: - Leaving the screen

// The pasteboard's count when Twitter came to the front: any other count when it leaves
// means something was copied meanwhile, and that copy is left alone.
static NSInteger gProbeBoardCount;

static void PFBProbeLeave(void) {
    @try {
        PFBProbePersist([NSString stringWithFormat:@"leaving at %.0f s", CACurrentMediaTime() - gProbeStart]);
        UIPasteboard* board = UIPasteboard.generalPasteboard;
        if (!gProbeBar || board.changeCount != gProbeBoardCount) {
            return;
        }
        board.string = [NSString stringWithFormat:@"%@\n\n%@", PFBProbeText(), PFBCompatReportText()];
        gProbeBoardCount = board.changeCount;
    } @catch (id exception) {
        PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"report stopped: %@", exception], 60);
    }
}

static void PFBProbeStart(void) {
    gProbeStart = CACurrentMediaTime();
    NSDateFormatter* clock = [[NSDateFormatter alloc] init];
    clock.dateFormat = @"HH:mm:ss";
    gProbeLaunchClock = [clock stringFromDate:[NSDate date]];
    PFBProbeFindOurCode();
    gProbeBoardCount = UIPasteboard.generalPasteboard.changeCount;

    // First after the wake, last before the sleep: after Core Animation's commit.
    CFRunLoopRef loop = CFRunLoopGetMain();
    CFRunLoopObserverRef wakeObserver =
        CFRunLoopObserverCreate(NULL, kCFRunLoopAfterWaiting, true, LONG_MIN, PFBProbeWake, NULL);
    CFRunLoopObserverRef sleepObserver =
        CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting, true, LONG_MAX, PFBProbeSleep, NULL);
    CFRunLoopAddObserver(loop, wakeObserver, kCFRunLoopCommonModes);
    CFRunLoopAddObserver(loop, sleepObserver, kCFRunLoopCommonModes);
    CFRelease(wakeObserver);
    CFRelease(sleepObserver);
    gProbeAwakeSince = gProbeStart;

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification* note) {
                      gProbeBoardCount = UIPasteboard.generalPasteboard.changeCount;
                    }];
    [center addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification* note) {
                      PFBProbeLeave();
                    }];
    [center addObserverForName:@"TFNDynamicColorsDidReloadNotification"
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification* note) {
                      PFBProbeNote(PFBProbeColorReload, NO, 0);
                    }];
    for (NSNumber* moment in @[ @20, @60 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(moment.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         @try {
                             PFBProbePersist([NSString stringWithFormat:@"at %@ s", moment]);
                         } @catch (id exception) {
                             PFBCompatMeasure(kPFBProbeTopic, [NSString stringWithFormat:@"stopped: %@", exception],
                                              60);
                         }
                       });
    }
}

// MARK: - Hooks

%group PFBGlassProbe

// MARK: Twitter's glass bar

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNoteBar((UIView*)self);
    PFBProbeNote(PFBProbeBarLayout, NO, CACurrentMediaTime() - start);
}

- (void)handleTracking:(UIGestureRecognizer*)recognizer {
    if (!gProbeTrackingRecognizer) {
        gProbeTrackingRecognizer = PFBProbeName([recognizer class]);
    }
    gProbeTrackingStates[MIN(MAX((NSInteger)recognizer.state, 0), 5)]++;
    PFBProbeNote(PFBProbeTracking, NO, 0);
    %orig;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)recognizer shouldReceiveEvent:(UIEvent*)event {
    BOOL receive = %orig;
    PFBProbeNote(PFBProbeEventAsked, NO, 0);
    if (!receive) {
        PFBProbeNote(PFBProbeEventRefused, NO, 0);
    }
    return receive;
}

%end

%hook _TtC11XNavigation14TabBarItemView

- (void)layoutSubviews {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeSeen(&gProbeItemsSeen, &gProbeItemsMade, self);
    PFBProbeNote(PFBProbeItemLayout, NO, CACurrentMediaTime() - start);
}

%end

%hook _TtC11XNavigation10TabBarPill

- (void)traitCollectionDidChange:(UITraitCollection*)previous {
    %orig;
    PFBProbeNote(PFBProbePillTraits, NO, 0);
}

%end

%hook _TtC13XDesignSystem10LiquidLens

- (void)layoutSubviews {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeSeen(&gProbeLensesSeen, &gProbeLensesMade, self);
    PFBProbeNote(PFBProbeLensLayout, NO, CACurrentMediaTime() - start);
}

%end

%hook _TtC11XNavigation16TabBarController

- (void)viewDidLayoutSubviews {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeControllerLayout, NO, CACurrentMediaTime() - start);
}

- (void)traitCollectionDidChange:(UITraitCollection*)previous {
    %orig;
    PFBProbeNote(PFBProbeControllerTraits, NO, 0);
}

%end

// MARK: Writes in the bar

%hook CALayer

// Landed when the layer holds a new animation under the key afterwards.
- (void)addAnimation:(CAAnimation*)animation forKey:(NSString*)key {
    if (!gProbeBarLayer || !pthread_main_np() || !PFBProbeLayerInBar(self)) {
        %orig;
        return;
    }
    CAAnimation* before = key ? [self animationForKey:key] : nil;
    NSUInteger keysBefore = key ? 0 : self.animationKeys.count;
    NSUInteger filtersBefore = self.filters.count;
    %orig;
    CAAnimation* after = key ? [self animationForKey:key] : nil;
    BOOL landed = key ? (after != nil && after != before) : self.animationKeys.count > keysBefore;
    PFBProbeNoteAnimation(self, key, landed, filtersBefore > 0 && self.filters.count == 0);
}

- (void)setFilters:(NSArray*)filters {
    if (gProbeBarLayer && pthread_main_np() && PFBProbeLayerInBar(self)) {
        PFBProbeNote(PFBProbeFiltersSet, PFBProbeFromUs(__builtin_return_address(0)), 0);
        if (!filters.count) {
            PFBProbeNote(PFBProbeFiltersEmptied, NO, 0);
        }
    }
    %orig;
}

%end

%hook UIView

- (void)setTintColor:(UIColor*)color {
    if (pthread_main_np()) {
        if ([self isKindOfClass:[UIWindow class]]) {
            PFBProbeNote(PFBProbeWindowTint, PFBProbeFromUs(__builtin_return_address(0)), 0);
        } else if (gProbeBar && PFBProbeViewInBar(self)) {
            PFBProbeNote(PFBProbeTint, PFBProbeFromUs(__builtin_return_address(0)), 0);
        }
    }
    %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if (gProbeBar && pthread_main_np() && PFBProbeViewInBar(self)) {
        PFBProbeNote(PFBProbeAlpha, PFBProbeFromUs(__builtin_return_address(0)), 0);
        if ((self.alpha <= 0.01) != (alpha <= 0.01)) {
            PFBProbeNote(PFBProbeAlphaFlip, NO, 0);
        }
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (gProbeBar && pthread_main_np() && PFBProbeViewInBar(self)) {
        PFBProbeNote(PFBProbeHidden, PFBProbeFromUs(__builtin_return_address(0)), 0);
        if (self.hidden != hidden) {
            PFBProbeNote(PFBProbeHiddenFlip, NO, 0);
        }
    }
    %orig;
}

- (void)setBackgroundColor:(UIColor*)color {
    if (gProbeBar && pthread_main_np() && PFBProbeViewInBar(self)) {
        PFBProbeNote(PFBProbeBackground, PFBProbeFromUs(__builtin_return_address(0)), 0);
    }
    %orig;
}

// A whole window laid out on demand, as the accent repaint does.
- (void)layoutIfNeeded {
    if (!pthread_main_np() || ![self isKindOfClass:[UIWindow class]]) {
        %orig;
        return;
    }
    BOOL ours = PFBProbeFromUs(__builtin_return_address(0));
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeWindowLayout, ours, CACurrentMediaTime() - start);
}

%end

%hook UIImageView

- (void)setImage:(UIImage*)image {
    if (gProbeBar && pthread_main_np() && image != self.image && PFBProbeViewInBar(self)) {
        PFBProbeNote(PFBProbeImage, PFBProbeFromUs(__builtin_return_address(0)), 0);
    }
    %orig;
}

%end

// MARK: Touches and screens

%hook UIWindow

- (void)sendEvent:(UIEvent*)event {
    %orig;
    if (event.type != UIEventTypeTouches || gProbeStart <= 0) {
        return;
    }
    @try {
        PFBProbeTouches((UIWindow*)self, event);
    } @catch (__unused id exception) {
        // A touch the probe cannot read is left out.
    }
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PFBProbeNoteScreen((UIViewController*)self);
    PFBProbeScheduleSnapshot((UIViewController*)self);
}

%end

%hook _TtC11TwitterDash21DashHostingController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PFBProbeNote(PFBProbeDashShown, NO, 0);
    PFBProbeScheduleSnapshot((UIViewController*)self);
}

%end

// MARK: Twitter's new navigation

%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (NSArray*)visiblePanelIDs {
    NSArray* panels = %orig;
    PFBProbeNote(PFBProbeNewPanelsAsked, NO, 0);
    if (gProbeDashQuery) {
        PFBProbeNote(PFBProbeNewPanelsAskedByDash, NO, 0);
    }
    if (pthread_main_np() && ![panels isEqual:gProbePanels]) {
        gProbePanels = [panels copy];
    }
    return panels;
}

- (void)recalculateVisiblePanels {
    PFBProbeNote(PFBProbeNewRecalculate, NO, 0);
    %orig;
}

- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(id)panelIDs {
    PFBProbeNote(PFBProbeNewRecalculate, NO, 0);
    if (pthread_main_np()) {
        gProbeUpdatedPanels = [panelIDs isKindOfClass:[NSArray class]] ? PFBProbePanelsText(panelIDs)
                                                                       : PFBProbeName([panelIDs class]);
    }
    %orig;
}

- (void)setCurrentPanel:(long long)panel animated:(BOOL)animated completion:(id)completion {
    PFBProbeNote(PFBProbeNewSetPanel, NO, 0);
    if (pthread_main_np()) {
        if (!gProbePanelsSet) {
            gProbePanelsSet = [NSMutableArray array];
        }
        [gProbePanelsSet addObject:@(panel)];
        if (gProbePanelsSet.count > 12) {
            [gProbePanelsSet removeObjectAtIndex:0];
        }
    }
    %orig;
}

%end

// MARK: The old navigation, where the options hook

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    PFBProbeNote(PFBProbeDashUpdate, NO, 0);
    BOOL outer = gProbeDashQuery;
    gProbeDashQuery = YES;
    %orig;
    gProbeDashQuery = outer;
}

%end

%hook T1TabNavigationController

// The last two are objects in Twitter's binary; passed on untouched.
- (void)_t1_main_updateNavigationItemForViewController:(id)controller
                                                isRoot:(BOOL)isRoot
                           providingLeftBarButtonItems:(__unsafe_unretained id)left
                                 rightBarButtonItems:(__unsafe_unretained id)right {
    PFBProbeNote(PFBProbeOldNavigationItems, NO, 0);
    %orig;
}

%end

%hook TFNNavigationBar

- (void)layoutSubviews {
    PFBProbeNote(PFBProbeOldNavigationBar, NO, 0);
    %orig;
}

%end

%hook TFNExpandingButtonItemView

- (void)_tfn_updateIcon {
    PFBProbeNote(PFBProbeOldComposeIcon, NO, 0);
    %orig;
}

%end

%hook TFNFloatingActionButton

- (void)layoutSubviews {
    PFBProbeNote(PFBProbeOldComposeButton, NO, 0);
    %orig;
}

%end

%hook _TtC14T1TwitterSwift28GuideContainerViewController

- (UIView*)tfn_navigationBarAccessoryView {
    PFBProbeNote(PFBProbeExploreAccessory, NO, 0);
    return %orig;
}

%end

%hook _TtC10TFNUISwift25LegacySegmentedTabBarView

- (void)layoutSubviews {
    PFBProbeNote(PFBProbeExploreTabs, NO, 0);
    %orig;
}

%end

%hook T1FleetLineView

- (void)layoutSubviews {
    PFBProbeNote(PFBProbeFleetLine, NO, 0);
    %orig;
}

%end

%hook T1ConversationFooterTextView

- (void)updateFooterTextView {
    PFBProbeNote(PFBProbeTweetFooter, NO, 0);
    %orig;
}

%end

// MARK: The old bar, which PrimeFreeBird's tab bar options hook

%hook T1TabView

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldTabIcon, NO, CACurrentMediaTime() - start);
}

- (void)_t1_layoutForTabBar {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldTabLayout, NO, CACurrentMediaTime() - start);
}

- (void)setSelected:(BOOL)selected {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldTabSelected, NO, CACurrentMediaTime() - start);
}

%end

%hook T1TabBarViewController

- (void)setTabBarCollapseRatio:(double)ratio {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldCollapse, NO, CACurrentMediaTime() - start);
}

- (void)_t1_layoutTabBar {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldBarLayout, NO, CACurrentMediaTime() - start);
}

- (void)_t1_updateTabBarHidden {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldBarHidden, NO, CACurrentMediaTime() - start);
}

%end

%hook T1TabBarHostView

- (void)layoutSubviews {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldHostLayout, NO, CACurrentMediaTime() - start);
}

%end

%hook TFNCustomTabBar

- (void)layoutSubviews {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldCustomBarLayout, NO, CACurrentMediaTime() - start);
}

%end

%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    CFTimeInterval start = CACurrentMediaTime();
    %orig;
    PFBProbeNote(PFBProbeOldTabEntries, NO, CACurrentMediaTime() - start);
}

- (NSArray*)_t1_tabEntriesLimitedToBottomCapacity:(NSArray*)entries {
    PFBProbeNote(PFBProbeOldTabCapacity, NO, 0);
    return %orig;
}

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    PFBProbeNote(PFBProbeOldPanelsAsked, NO, 0);
    return %orig;
}

%end

%end

// Every other file installs its hooks from its constructor. The main queue first runs
// once they all have, so these are installed last.
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
      PFBProbeStart();
      %init(PFBGlassProbe);
    });
}
