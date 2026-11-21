// Probe for Twitter 12.45, removed once read: frame by frame around each change of Home's Tweets, what is laid
// over the list and how it fades, what removes it, and how the list and Twitter's launch screen look meanwhile.

#import <QuartzCore/QuartzCore.h>
#import "Support/HookHelpers.h"

static NSString* const kPFBRefreshProbeTopic = @"probe refresh";
static const NSUInteger kPFBRefreshProbeCap = 200;
static const NSUInteger kPFBRefreshProbeLaunchCap = 400;
static const NSUInteger kPFBRefreshProbeChunk = 30;
static const CFTimeInterval kPFBRefreshProbeWatch = 1.5;
static const CFTimeInterval kPFBRefreshProbeFollowLimit = 3.0;
static const void* kPFBRefreshProbeListKey = &kPFBRefreshProbeListKey;

static NSInteger gPFBRefreshProbeLaunch;
static NSUInteger gPFBRefreshProbeLines;
static NSUInteger gPFBRefreshProbeFlushes;
static NSInteger gPFBRefreshProbeHandOvers;
static CFTimeInterval gPFBRefreshProbeStart;
static CFTimeInterval gPFBRefreshProbeBegan = -1000.0;
static CFTimeInterval gPFBRefreshProbeWatchUntil;
static CFTimeInterval gPFBRefreshProbeLastTick;
static NSMutableArray<NSString*>* gPFBRefreshProbePending;
static NSMapTable<UIView*, NSNumber*>* gPFBRefreshProbeFollowed;
static NSHashTable<UIView*>* gPFBRefreshProbeKnown;
static NSMutableDictionary<NSString*, NSString*>* gPFBRefreshProbeShown;
static __weak UIScrollView* gPFBRefreshProbeList;
static __weak UIView* gPFBRefreshProbeSplash;
static CADisplayLink* gPFBRefreshProbeLink;

static void PFBRefreshProbeFlushLater(void);

static void PFBRefreshProbeLine(NSString* event) {
    if (++gPFBRefreshProbeLines > kPFBRefreshProbeLaunchCap) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    NSString* since = gPFBRefreshProbeBegan > 0.0 ? [NSString stringWithFormat:@"+%.3fs", now - gPFBRefreshProbeBegan] : @"no begin";
    [gPFBRefreshProbePending addObject:[NSString stringWithFormat:@"L%ld %03lu %7.3fs (%@) %@", (long)gPFBRefreshProbeLaunch,
                                                                 (unsigned long)gPFBRefreshProbeLines, now - gPFBRefreshProbeStart, since,
                                                                 event]];
    PFBRefreshProbeFlushLater();
}

// Lines wait in memory while Home changes, so that writing them never slows Twitter down, and are written in
// blocks once all is quiet or the app leaves the screen.
static void PFBRefreshProbeFlush(void) {
    NSArray<NSString*>* lines = [gPFBRefreshProbePending copy];
    [gPFBRefreshProbePending removeAllObjects];
    for (NSUInteger i = 0; i < lines.count; i += kPFBRefreshProbeChunk) {
        NSArray<NSString*>* chunk = [lines subarrayWithRange:NSMakeRange(i, MIN(kPFBRefreshProbeChunk, lines.count - i))];
        PFBCompatMeasure(kPFBRefreshProbeTopic, [chunk componentsJoinedByString:@"\n"], kPFBRefreshProbeCap);
    }
}

static void PFBRefreshProbeFlushLater(void) {
    NSUInteger flush = ++gPFBRefreshProbeFlushes;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (flush == gPFBRefreshProbeFlushes && !gPFBRefreshProbeLink) {
          PFBRefreshProbeFlush();
      }
    });
}

// The last four hex digits of an object's address, to tell objects apart in the lines.
static unsigned long PFBRefreshProbeTag(id object) {
    uintptr_t address = (uintptr_t)(__bridge void*)object;
    return (unsigned long)(address % 0x10000);
}

// The libraries a call came through, nearest first, repeats folded: the tweak's own code, Twitter's or UIKit's.
static NSString* PFBRefreshProbeCallers(void) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (NSNumber* address in [NSThread callStackReturnAddresses]) {
        Dl_info info;
        if (names.count == 10 || !dladdr((const void*)address.unsignedLongValue, &info) || !info.dli_fname) {
            continue;
        }
        NSString* name = [@(info.dli_fname) lastPathComponent];
        if (![names.lastObject isEqualToString:name]) {
            [names addObject:name];
        }
    }
    return [names componentsJoinedByString:@" < "];
}

static BOOL PFBRefreshProbeIsHome(UIViewController* controller) {
    for (UIViewController* parent = controller; parent; parent = parent.parentViewController) {
        if ([NSStringFromClass(parent.class) isEqualToString:@"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController"]) {
            return YES;
        }
    }
    return NO;
}

static UIScrollView* PFBRefreshProbeListOf(UIViewController* controller) {
    if ([controller.view isKindOfClass:[UIScrollView class]]) {
        return (UIScrollView*)controller.view;
    }
    __block UIScrollView* found = nil;
    PFBWalkAllSubviews(controller.view, 3, ^(UIView* view) {
      if (!found && [view isKindOfClass:[UITableView class]]) {
          found = (UIScrollView*)view;
      }
    });
    return found;
}

static NSUInteger PFBRefreshProbeCount(NSArray* sections) {
    NSUInteger count = 0;
    for (id section in sections) {
        count += [section isKindOfClass:[NSArray class]] ? ((NSArray*)section).count : 1;
    }
    return count;
}

// The first words a row shows, from accessibility, a label or a text view at any depth.
static NSString* PFBRefreshProbeWords(UIView* row) {
    __block NSString* words = row.accessibilityLabel;
    if (!words.length) {
        PFBWalkAllSubviews(row, 8, ^(UIView* view) {
          if (words.length) {
              return;
          }
          if ([view isKindOfClass:[UILabel class]]) {
              words = ((UILabel*)view).text;
          } else if ([view isKindOfClass:[UITextView class]]) {
              words = ((UITextView*)view).text;
          }
          if (!words.length) {
              words = view.accessibilityLabel;
          }
        });
    }
    words = [words stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return words.length > 24 ? [words substringToIndex:24] : words;
}

// The topmost row with words, and the rows above it that have none, by kind and height.
static NSString* PFBRefreshProbeTop(UIScrollView* list) {
    if (![list isKindOfClass:[UITableView class]]) {
        return @"no table";
    }
    UITableView* table = (UITableView*)list;
    NSArray<NSIndexPath*>* paths = [table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString*>* silent = [NSMutableArray array];
    for (NSIndexPath* path in paths) {
        UITableViewCell* cell = [table cellForRowAtIndexPath:path];
        NSString* words = PFBRefreshProbeWords(cell);
        if (words.length) {
            NSString* above = silent.count ? [NSString stringWithFormat:@" under %@", [silent componentsJoinedByString:@", "]] : @"";
            return [NSString stringWithFormat:@"%lu rows, row %ld.%ld '%@'%@", (unsigned long)paths.count, (long)path.section,
                                              (long)path.row, words, above];
        }
        if (silent.count < 3) {
            [silent addObject:[NSString stringWithFormat:@"%@ %.0f pt", NSStringFromClass(cell.class), cell.bounds.size.height]];
        }
    }
    return [NSString stringWithFormat:@"%lu rows, no words: %@", (unsigned long)paths.count, [silent componentsJoinedByString:@", "]];
}

// The first row on screen, cheaply: which cell and a hash of its words, to notice when it changes.
static NSString* PFBRefreshProbeTopKey(UIScrollView* list) {
    if (![list isKindOfClass:[UITableView class]]) {
        return @"";
    }
    UITableView* table = (UITableView*)list;
    NSIndexPath* first = [table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)].firstObject;
    UITableViewCell* cell = first ? [table cellForRowAtIndexPath:first] : nil;
    return [NSString stringWithFormat:@"%04lx %lu", PFBRefreshProbeTag(cell), (unsigned long)cell.accessibilityLabel.hash];
}

// Where a view shows on screen, as drawn this frame.
static CGRect PFBRefreshProbeOnScreen(UIView* view) {
    if (!view.window) {
        return CGRectNull;
    }
    CALayer* layer = view.layer.presentationLayer ?: view.layer;
    return [layer convertRect:layer.bounds toLayer:nil];
}

// How visible a view is this frame: its opacity times that of every view holding it.
static float PFBRefreshProbeSeen(UIView* view) {
    float seen = 1.0f;
    for (UIView* holder = view; holder; holder = holder.superview) {
        CALayer* layer = holder.layer.presentationLayer ?: holder.layer;
        seen *= holder.hidden ? 0.0f : layer.opacity;
    }
    return seen;
}

// Animations running on the list or on any view holding it, and masks laid on them.
static NSString* PFBRefreshProbeMotion(UIView* list) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (UIView* holder = list; holder; holder = holder.superview) {
        NSArray<NSString*>* keys = holder.layer.animationKeys;
        if (keys.count || holder.layer.mask) {
            [parts addObject:[NSString stringWithFormat:@"%@ %04lx%@%@", NSStringFromClass(holder.class), PFBRefreshProbeTag(holder),
                                                        keys.count ? [@" animating " stringByAppendingString:[keys componentsJoinedByString:@","]] : @"",
                                                        holder.layer.mask ? @" masked" : @""]];
        }
    }
    return parts.count ? [parts componentsJoinedByString:@" / "] : @"none";
}

// Views animating inside the rows on screen, as Twitter's own fades would.
static NSString* PFBRefreshProbeRowMotion(UIScrollView* list) {
    if (![list isKindOfClass:[UITableView class]]) {
        return @"no table";
    }
    __block NSUInteger moving = 0;
    NSMutableSet<NSString*>* kinds = [NSMutableSet set];
    for (UITableViewCell* cell in ((UITableView*)list).visibleCells) {
        PFBWalkAllSubviews(cell, 8, ^(UIView* view) {
          NSArray<NSString*>* keys = view.layer.animationKeys;
          if (keys.count) {
              moving++;
              [kinds addObject:[NSString stringWithFormat:@"%@ %@", NSStringFromClass(view.class), [keys componentsJoinedByString:@","]]];
          }
        });
    }
    if (!moving) {
        return @"none";
    }
    NSArray<NSString*>* sorted = [kinds.allObjects sortedArrayUsingSelector:@selector(compare:)];
    return [NSString stringWithFormat:@"%lu views (%@)", (unsigned long)moving,
                                      [[sorted subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)3, sorted.count))] componentsJoinedByString:@"; "]];
}

// Twitter's launch screen: on screen or not, how visible, and how much of its fill is left.
static NSString* PFBRefreshProbeSplashState(UIView* splash) {
    if (!splash.window) {
        return @"off screen";
    }
    CGFloat fill = 0.0;
    for (UIView* part in splash.subviews) {
        CALayer* layer = part.layer.presentationLayer ?: part.layer;
        if (layer.backgroundColor) {
            fill = MAX(fill, CGColorGetAlpha(layer.backgroundColor));
        }
    }
    return [NSString stringWithFormat:@"seen %.1f, fill %.1f", PFBRefreshProbeSeen(splash), fill];
}

// Each field is written only when it changes; opacities are compared by steps of 0.1.
static void PFBRefreshProbeNote(NSMutableArray<NSString*>* changes, NSString* field, NSString* value, NSString* shown) {
    if ([gPFBRefreshProbeShown[field] isEqualToString:value]) {
        return;
    }
    gPFBRefreshProbeShown[field] = value;
    [changes addObject:[NSString stringWithFormat:@"%@ %@", field, shown ?: value]];
}

static NSString* PFBRefreshProbePlace(CGRect rect, CGRect listRect) {
    if (CGRectIsNull(rect)) {
        return @"off screen";
    }
    if (CGRectEqualToRect(CGRectIntegral(rect), CGRectIntegral(listRect))) {
        return @"on the list";
    }
    return [NSString stringWithFormat:@"y %.1f h %.1f, list y %.1f h %.1f", rect.origin.y, rect.size.height, listRect.origin.y,
                                      listRect.size.height];
}

static void PFBRefreshProbeWatch(void);

// A view that appears over Home's list, followed frame by frame until it goes or for 3 s.
static void PFBRefreshProbeFollow(UIView* view, UIScrollView* list, BOOL added) {
    if ([gPFBRefreshProbeKnown containsObject:view]) {
        return;
    }
    [gPFBRefreshProbeKnown addObject:view];
    [gPFBRefreshProbeFollowed setObject:@(CACurrentMediaTime()) forKey:view];
    NSArray<UIView*>* siblings = list.superview.subviews;
    NSUInteger rank = [siblings indexOfObjectIdenticalTo:view] - [siblings indexOfObjectIdenticalTo:list];
    PFBRefreshProbeLine([NSString stringWithFormat:@"+ %04lx %@ %@ at rank %lu above the list, %@, %@%@", PFBRefreshProbeTag(view),
                                                   NSStringFromClass(view.class), added ? @"added" : @"found", (unsigned long)rank,
                                                   PFBRefreshProbePlace(PFBRefreshProbeOnScreen(view), PFBRefreshProbeOnScreen(list)),
                                                   gPFBRefreshProbeHandOvers > 0 ? @"during a hand-over" : @"outside hand-overs",
                                                   added ? [@", through " stringByAppendingString:PFBRefreshProbeCallers()] : @""]);
    PFBRefreshProbeWatch();
}

static void PFBRefreshProbeRemoving(UIView* view) {
    CFTimeInterval since = CACurrentMediaTime() - [[gPFBRefreshProbeFollowed objectForKey:view] doubleValue];
    CALayer* layer = view.layer.presentationLayer ?: view.layer;
    PFBRefreshProbeLine([NSString stringWithFormat:@"- %04lx removed %.0f ms after it appeared, seen at %.2f (alpha %.2f, %@), %@, "
                                                   @"through %@",
                                                   PFBRefreshProbeTag(view), since * 1000.0, layer.opacity, view.alpha,
                                                   view.layer.animationKeys.count ? @"animating" : @"not animating",
                                                   gPFBRefreshProbeHandOvers > 0 ? @"during a hand-over" : @"outside hand-overs",
                                                   PFBRefreshProbeCallers()]);
    [gPFBRefreshProbeFollowed removeObjectForKey:view];
    [gPFBRefreshProbeShown removeObjectForKey:[NSString stringWithFormat:@"%04lx", PFBRefreshProbeTag(view)]];
}

static void PFBRefreshProbeTick(void) {
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval gap = now - gPFBRefreshProbeLastTick;
    gPFBRefreshProbeLastTick = now;
    NSMutableArray<NSString*>* changes = [NSMutableArray array];
    if (gap > 0.025) {
        [changes addObject:[NSString stringWithFormat:@"main thread held %.0f ms", gap * 1000.0]];
    }
    UIScrollView* list = gPFBRefreshProbeList;
    CGRect listRect = PFBRefreshProbeOnScreen(list);
    if (list) {
        NSArray<UIView*>* siblings = list.superview.subviews;
        NSUInteger index = [siblings indexOfObjectIdenticalTo:list];
        for (NSUInteger i = index == NSNotFound ? siblings.count : index + 1; i < siblings.count; i++) {
            PFBRefreshProbeFollow(siblings[i], list, NO);
        }
        float seen = PFBRefreshProbeSeen(list);
        BOOL finger = list.tracking || list.dragging || list.decelerating;
        PFBRefreshProbeNote(changes, @"finger", finger ? @"moves the list" : @"off the list", nil);
        PFBRefreshProbeNote(changes, @"list",
                            finger ? @"moved by the finger"
                                   : [NSString stringWithFormat:@"%.0f %.0f %.0f %.1f %04lx", listRect.origin.y, listRect.size.height,
                                                                list.contentOffset.y, seen, PFBRefreshProbeTag(list.superview)],
                            finger ? @"moved by the finger"
                                   : [NSString stringWithFormat:@"y %.1f h %.1f offset %.1f seen %.2f in %@ %04lx", listRect.origin.y,
                                                                listRect.size.height, list.contentOffset.y, seen,
                                                                NSStringFromClass(list.superview.class), PFBRefreshProbeTag(list.superview)]);
        PFBRefreshProbeNote(changes, @"list motion", PFBRefreshProbeMotion(list), nil);
        PFBRefreshProbeNote(changes, @"inside rows", PFBRefreshProbeRowMotion(list), nil);
        NSString* topKey = PFBRefreshProbeTopKey(list);
        if (![gPFBRefreshProbeShown[@"top key"] isEqualToString:topKey]) {
            gPFBRefreshProbeShown[@"top key"] = topKey;
            PFBRefreshProbeNote(changes, @"top", PFBRefreshProbeTop(list), nil);
        }
    }
    for (UIView* view in [[gPFBRefreshProbeFollowed keyEnumerator] allObjects]) {
        NSString* name = [NSString stringWithFormat:@"%04lx", PFBRefreshProbeTag(view)];
        CFTimeInterval since = now - [[gPFBRefreshProbeFollowed objectForKey:view] doubleValue];
        if (!view.window || since > kPFBRefreshProbeFollowLimit) {
            [changes addObject:[NSString stringWithFormat:@"%@ %@", name, view.window ? @"still there after 3 s, no longer followed" : @"left the screen"]];
            [gPFBRefreshProbeFollowed removeObjectForKey:view];
            [gPFBRefreshProbeShown removeObjectForKey:name];
            continue;
        }
        CALayer* layer = view.layer.presentationLayer ?: view.layer;
        NSString* place = PFBRefreshProbePlace(PFBRefreshProbeOnScreen(view), listRect);
        BOOL animating = view.layer.animationKeys.count > 0;
        PFBRefreshProbeNote(changes, name, [NSString stringWithFormat:@"%.1f %.0f %d %@", layer.opacity, view.alpha, animating, place],
                            [NSString stringWithFormat:@"seen at %.2f (alpha %.2f, %@), %@", layer.opacity, view.alpha,
                                                       animating ? @"animating" : @"not animating", place]);
    }
    UIView* splash = gPFBRefreshProbeSplash;
    if (splash) {
        PFBRefreshProbeNote(changes, @"launch screen", PFBRefreshProbeSplashState(splash), nil);
    }
    if (changes.count) {
        PFBRefreshProbeLine([@"frame: " stringByAppendingString:[changes componentsJoinedByString:@"; "]]);
    }
    if (now > gPFBRefreshProbeWatchUntil && ![gPFBRefreshProbeFollowed keyEnumerator].allObjects.count && !splash.window) {
        [gPFBRefreshProbeLink invalidate];
        gPFBRefreshProbeLink = nil;
        PFBRefreshProbeFlush();
    }
}

@interface PFBRefreshProbeTicker : NSObject
@end

@implementation PFBRefreshProbeTicker

- (void)tick:(CADisplayLink*)link {
    PFBRefreshProbeTick();
}

@end

// The views already over the list when watching starts, or when another list is watched, are listed once and
// not followed.
static void PFBRefreshProbeNoteAbove(UIScrollView* list) {
    NSArray<UIView*>* siblings = list.superview.subviews;
    NSUInteger index = [siblings indexOfObjectIdenticalTo:list];
    if (index == NSNotFound) {
        return;
    }
    NSMutableArray<NSString*>* above = [NSMutableArray array];
    for (NSUInteger i = index + 1; i < siblings.count; i++) {
        [gPFBRefreshProbeKnown addObject:siblings[i]];
        [above addObject:[NSString stringWithFormat:@"%@ %04lx", NSStringFromClass(siblings[i].class), PFBRefreshProbeTag(siblings[i])]];
    }
    NSMutableArray<NSString*>* changes = [NSMutableArray array];
    PFBRefreshProbeNote(changes, @"already over the list:", above.count ? [above componentsJoinedByString:@", "] : @"nothing", nil);
    if (changes.count) {
        PFBRefreshProbeLine(changes.firstObject);
    }
}

// Frames are read for 1.5 s after each event, longer while a followed view or the launch screen is on screen.
static void PFBRefreshProbeWatch(void) {
    gPFBRefreshProbeWatchUntil = CACurrentMediaTime() + kPFBRefreshProbeWatch;
    if (gPFBRefreshProbeLink) {
        return;
    }
    PFBRefreshProbeNoteAbove(gPFBRefreshProbeList);
    gPFBRefreshProbeLastTick = CACurrentMediaTime();
    gPFBRefreshProbeLink = [CADisplayLink displayLinkWithTarget:[PFBRefreshProbeTicker new] selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) {
        gPFBRefreshProbeLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0f, 120.0f, 120.0f);
    }
    [gPFBRefreshProbeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// Home's list on screen becomes the one watched, marked for the table hooks below.
static void PFBRefreshProbeAdopt(UIScrollView* list) {
    UIScrollView* current = gPFBRefreshProbeList;
    if (!list || (current.window && !list.window)) {
        return;
    }
    if (list != current) {
        gPFBRefreshProbeList = list;
        objc_setAssociatedObject(list, kPFBRefreshProbeListKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PFBRefreshProbeNoteAbove(list);
    }
}

// A change of Home's Tweets: the call, the items handed over and the rows on screen before it.
static void PFBRefreshProbeEvent(UIViewController* controller, NSString* how, NSArray* sections) {
    if (!PFBRefreshProbeIsHome(controller)) {
        return;
    }
    UIScrollView* list = PFBRefreshProbeListOf(controller);
    PFBRefreshProbeAdopt(list);
    NSArray* had = [controller respondsToSelector:@selector(sections)] ? [(id)controller sections] : nil;
    PFBRefreshProbeLine([NSString stringWithFormat:@"%@ on %@ %04lx: %lu items (had %lu), before: %@", how,
                                                   NSStringFromClass(controller.class), PFBRefreshProbeTag(controller),
                                                   (unsigned long)PFBRefreshProbeCount(sections), (unsigned long)PFBRefreshProbeCount(had),
                                                   PFBRefreshProbeTop(list)]);
    PFBRefreshProbeWatch();
}

static void PFBRefreshProbeTable(UITableView* table, NSString* how) {
    if (!objc_getAssociatedObject(table, kPFBRefreshProbeListKey)) {
        return;
    }
    PFBRefreshProbeLine([NSString stringWithFormat:@"table %@, before: %@", how, PFBRefreshProbeTop(table)]);
    PFBRefreshProbeWatch();
}

%hook T1AnimatedLaunchScreenView

- (void)animateRevealWithCompletion:(id)completion {
    gPFBRefreshProbeSplash = (UIView*)self;
    PFBRefreshProbeLine(@"launch screen starts its reveal");
    PFBRefreshProbeWatch();
    if (!completion) {
        %orig;
        return;
    }
    void (^done)(void) = completion;
    %orig(^{
      PFBRefreshProbeLine(@"launch screen reveal done");
      done();
    });
}

%end

%hook _TtC32TwitterHomeFeatureImplementation25HomeLogoRefreshController

- (void)pullToRefreshControl:(id)control didBeginRefreshingFromPull:(BOOL)fromPull {
    gPFBRefreshProbeBegan = CACurrentMediaTime();
    PFBRefreshProbeLine([NSString stringWithFormat:@"refresh begins, from pull %d", fromPull]);
    PFBRefreshProbeWatch();
    %orig;
}

- (void)pullToRefreshControlDidEndRefreshing:(id)control {
    PFBRefreshProbeLine(@"refresh ends");
    PFBRefreshProbeWatch();
    %orig;
}

%end

%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PFBRefreshProbeLine([NSString stringWithFormat:@"Home appears, Smooth refresh %@", [PFBSettings boolForKey:@"refresh_fade"] ? @"on" : @"off"]);
    PFBRefreshProbeWatch();
}

%end

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections {
    PFBRefreshProbeEvent((UIViewController*)self, @"setSections:", sections);
    gPFBRefreshProbeHandOvers++;
    %orig;
    gPFBRefreshProbeHandOvers--;
}

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    PFBRefreshProbeEvent((UIViewController*)self, restore ? @"setSections:restore YES" : @"setSections:restore NO", sections);
    gPFBRefreshProbeHandOvers++;
    %orig;
    gPFBRefreshProbeHandOvers--;
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    PFBRefreshProbeEvent((UIViewController*)self, [NSString stringWithFormat:@"updateSections:reconfigure animation %lld", animation], sections);
    gPFBRefreshProbeHandOvers++;
    %orig;
    gPFBRefreshProbeHandOvers--;
}

%end

// Home's table changed directly, below the data controller.
%hook UITableView

- (void)reloadData {
    PFBRefreshProbeTable(self, @"reloadData");
    gPFBRefreshProbeHandOvers++;
    %orig;
    gPFBRefreshProbeHandOvers--;
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion {
    PFBRefreshProbeTable(self, @"performBatchUpdates");
    %orig;
}

- (void)insertRowsAtIndexPaths:(NSArray*)paths withRowAnimation:(UITableViewRowAnimation)animation {
    PFBRefreshProbeTable(self, [NSString stringWithFormat:@"insertRows %lu animation %ld", (unsigned long)paths.count, (long)animation]);
    %orig;
}

- (void)deleteRowsAtIndexPaths:(NSArray*)paths withRowAnimation:(UITableViewRowAnimation)animation {
    PFBRefreshProbeTable(self, [NSString stringWithFormat:@"deleteRows %lu animation %ld", (unsigned long)paths.count, (long)animation]);
    %orig;
}

- (void)reloadRowsAtIndexPaths:(NSArray*)paths withRowAnimation:(UITableViewRowAnimation)animation {
    PFBRefreshProbeTable(self, [NSString stringWithFormat:@"reloadRows %lu animation %ld", (unsigned long)paths.count, (long)animation]);
    %orig;
}

%end

// Animated moves of Home's list that go somewhere, as the Home tab or a refresh sends it to the top.
%hook UIScrollView

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if (animated && fabs(offset.y - self.contentOffset.y) > 0.5 && objc_getAssociatedObject(self, kPFBRefreshProbeListKey)) {
        PFBRefreshProbeLine([NSString stringWithFormat:@"list moves to %.1f animated, from %.1f", offset.y, self.contentOffset.y]);
        PFBRefreshProbeWatch();
    }
    %orig;
}

%end

// Views put over Home's list or taken off it, with the code that did it.
%hook UIView

- (void)didAddSubview:(UIView*)subview {
    %orig;
    UIScrollView* list = gPFBRefreshProbeList;
    if (list && self == list.superview && subview != list &&
        [self.subviews indexOfObjectIdenticalTo:subview] > [self.subviews indexOfObjectIdenticalTo:list]) {
        PFBRefreshProbeFollow(subview, list, YES);
    }
}

- (void)willRemoveSubview:(UIView*)subview {
    if ([gPFBRefreshProbeFollowed objectForKey:subview]) {
        PFBRefreshProbeRemoving(subview);
    }
    %orig;
}

%end

%ctor {
    gPFBRefreshProbeStart = CACurrentMediaTime();
    gPFBRefreshProbePending = [NSMutableArray array];
    NSPointerFunctionsOptions weakIdentity = NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality;
    gPFBRefreshProbeFollowed = [[NSMapTable alloc] initWithKeyOptions:weakIdentity valueOptions:NSPointerFunctionsStrongMemory capacity:4];
    gPFBRefreshProbeKnown = [NSHashTable hashTableWithOptions:weakIdentity];
    gPFBRefreshProbeShown = [NSMutableDictionary dictionary];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    gPFBRefreshProbeLaunch = [defaults integerForKey:@"PFBRefreshProbeLaunch"] + 1;
    [defaults setInteger:gPFBRefreshProbeLaunch forKey:@"PFBRefreshProbeLaunch"];
    NSDateFormatter* clock = [[NSDateFormatter alloc] init];
    clock.dateFormat = @"HH:mm:ss.SSS";
    PFBRefreshProbeLine([@"Twitter starts, clock at " stringByAppendingString:[clock stringFromDate:[NSDate date]]]);
    for (NSNotificationName name in @[ UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification ]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification* note) {
                                                        PFBRefreshProbeFlush();
                                                      }];
    }
    %init;
}
