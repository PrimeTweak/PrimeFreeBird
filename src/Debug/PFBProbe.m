// The measurement probe; see PFBProbe.h.

#import "Debug/PFBProbe.h"
#import "Debug/PFBDebugger.h"
#import "Common/PFBCompatibility.h"
#import "Common/PFBSettings.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>

// The view model a timeline item wraps (HookHelpers.m).
extern id PFBUnwrapDataViewItem(id item);

static NSString* const kPFBProbeStoreKey = @"pfb_probe";
// Room for every question, and a bound if one of them turns out chatty.
static const NSUInteger kPFBProbeLineLimit = 400;

static NSObject* gPFBProbeLock;
static NSMutableSet<NSString*>* gPFBProbeKeys;
static NSMutableArray<NSString*>* gPFBProbeLines;
static NSString* gPFBProbeBuild;
static NSDateFormatter* gPFBProbeClock;
// Saves happen in order, outside the lock: the defaults are never written while it is held.
static dispatch_queue_t gPFBProbeWriter;

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

BOOL PFBProbeWants(NSString* key) {
    if (!PFBDebugIsRecording() || !key) {
        return NO;
    }
    probeLoad();
    @synchronized(gPFBProbeLock) {
        return gPFBProbeLines.count < kPFBProbeLineLimit && ![gPFBProbeKeys containsObject:key];
    }
}

void PFBProbeNote(NSString* key, NSString* format, ...) {
    if (!PFBDebugIsRecording() || !key || !format) {
        return;
    }
    probeLoad();
    va_list arguments;
    va_start(arguments, format);
    NSString* text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString* step = NSThread.isMainThread ? PFBProbeTourStep() : nil;
    NSString* stamp = [gPFBProbeClock stringFromDate:[NSDate date]];
    NSString* line = step.length ? [NSString stringWithFormat:@"%@  [%@] %@", stamp, step, text]
                                 : [NSString stringWithFormat:@"%@  %@", stamp, text];
    @synchronized(gPFBProbeLock) {
        if (gPFBProbeLines.count >= kPFBProbeLineLimit || [gPFBProbeKeys containsObject:key]) {
            return;
        }
        [gPFBProbeKeys addObject:key];
        [gPFBProbeLines addObject:line];
        NSDictionary* saved = @{
            @"build": gPFBProbeBuild ?: @"?",
            @"keys": gPFBProbeKeys.allObjects,
            @"lines": [gPFBProbeLines copy],
        };
        dispatch_async(gPFBProbeWriter, ^{
          [[NSUserDefaults standardUserDefaults] setObject:saved forKey:kPFBProbeStoreKey];
        });
    }
}

NSString* PFBProbeReportText(void) {
    if (!PFBDebugIsRecording()) {
        return @"PROBE  off: debug tools are off\n";
    }
    probeLoad();
    NSArray<NSString*>* lines;
    @synchronized(gPFBProbeLock) {
        lines = [gPFBProbeLines copy];
    }
    if (!lines.count) {
        return [NSString stringWithFormat:@"PROBE  build %@ · nothing noted yet\n", gPFBProbeBuild];
    }
    return [NSString stringWithFormat:@"PROBE  build %@ · %lu notes\n%@\n", gPFBProbeBuild, (unsigned long)lines.count,
                                      [lines componentsJoinedByString:@"\n"]];
}

// MARK: - Reading the app

// A getter's object, read only when its signature says it returns one.
static id probeGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

// The screen a controller belongs to: the topmost of its parents below a navigation stack.
static NSString* probeScreenName(UIViewController* controller) {
    UIViewController* screen = controller;
    while (screen.parentViewController && ![screen.parentViewController isKindOfClass:[UINavigationController class]]) {
        screen = screen.parentViewController;
    }
    return screen ? NSStringFromClass([screen class]) : @"no screen";
}

static UIViewController* probeControllerOfView(UIView* view) {
    for (UIResponder* responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
    }
    return nil;
}

// MARK: - 1. Timelines and the reading marker

static const void* kPFBProbeTimelineKey = &kPFBProbeTimelineKey;

BOOL PFBProbeTimelineWanted(UIViewController* timeline) {
    return PFBDebugIsRecording() && timeline && !objc_getAssociatedObject(timeline, kPFBProbeTimelineKey);
}

void PFBProbeTimeline(UIViewController* timeline, BOOL inHome, BOOL followingSection) {
    if (!PFBProbeTimelineWanted(timeline)) {
        return;
    }
    // Read once the controller is placed, when its screen can be named.
    if (!timeline.parentViewController && !timeline.navigationController) {
        return;
    }
    objc_setAssociatedObject(timeline, kPFBProbeTimelineKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Lists that name no scribe section, settings pages among them, are not timelines.
    if (![timeline respondsToSelector:NSSelectorFromString(@"scribeSection")]) {
        return;
    }
    id section = probeGetter(timeline, @"scribeSection");
    NSString* sectionName = [section isKindOfClass:[NSString class]] ? section : @"none";
    NSString* name = NSStringFromClass([timeline class]);
    NSString* key = [NSString stringWithFormat:@"timeline %@ %@ %d", name, sectionName, inHome];
    if (!PFBProbeWants(key)) {
        return;
    }
    PFBProbeNote(key, @"#1 timeline %@ · section “%@” · %@ · screen %@ · the reading marker %@", name, sectionName,
                 inHome ? @"inside Home" : @"outside Home", probeScreenName(timeline),
                 inHome && followingSection ? @"can show here" : @"never shows here");
}

// MARK: - 2. Chronological replies

static NSString* const kPFBProbeReplySortingKey = @"pfb_probe_reply_sorting";

void PFBProbeSwitchReplySorting(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kPFBProbeReplySortingKey]) {
        return;
    }
    id stored = [defaults objectForKey:@"reply_sorting"];
    BOOL current = [PFBSettings boolForKey:@"reply_sorting"];
    [defaults setObject:@{@"had": @(stored != nil), @"value": stored ?: @NO} forKey:kPFBProbeReplySortingKey];
    [defaults setBool:!current forKey:@"reply_sorting"];
    PFBCompatTourLog(@"[tour] replies: Chronological replies switched %@ for this conversation", current ? @"off" : @"on");
}

void PFBProbeRestoreReplySorting(NSString* when) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* saved = [defaults dictionaryForKey:kPFBProbeReplySortingKey];
    if (!saved) {
        return;
    }
    if ([saved[@"had"] boolValue] && saved[@"value"]) {
        [defaults setObject:saved[@"value"] forKey:@"reply_sorting"];
    } else {
        [defaults removeObjectForKey:@"reply_sorting"];
    }
    [defaults removeObjectForKey:kPFBProbeReplySortingKey];
    BOOL now = [PFBSettings boolForKey:@"reply_sorting"];
    PFBCompatTourLog(@"[tour] replies: Chronological replies put back %@, %@", now ? @"on" : @"off", when);
    PFBProbeNote([@"replies restored " stringByAppendingString:when], @"#2 replies: Chronological replies put back %@, %@",
                 now ? @"on" : @"off", when);
}

void PFBProbeRestoreAtLaunch(void) {
    PFBProbeRestoreReplySorting(@"at launch, after a tour Twitter closed");
}

void PFBProbeReplySortingRead(BOOL answer) {
    static atomic_bool seen[2];
    if (!PFBDebugIsRecording() || atomic_exchange_explicit(&seen[answer ? 1 : 0], true, memory_order_relaxed)) {
        return;
    }
    PFBProbeNote(answer ? @"replies flag YES" : @"replies flag NO", @"#2 replies: Twitter read reply_sorting_enabled and got %@",
                 answer ? @"YES" : @"NO");
}

// MARK: - 3. Explore and search

static const void* kPFBProbeAreaKey = &kPFBProbeAreaKey;
static const void* kPFBProbeSeenKey = &kPFBProbeSeenKey;

// "Explore" or "search" for a list shown under either, or nil.
static NSString* probeArea(UIViewController* controller) {
    UIViewController* current = controller;
    for (NSUInteger depth = 0; current && depth < 64; depth++) {
        NSString* name = NSStringFromClass([current class]);
        if ([name containsString:@"GuideContainer"]) {
            return @"Explore";
        }
        if ([name containsString:@"Search"]) {
            return @"search";
        }
        if (current.parentViewController) {
            current = current.parentViewController;
        } else if (current.navigationController) {
            current = current.navigationController;
        } else {
            current = current.presentingViewController;
        }
    }
    return nil;
}

void PFBProbeExploreSections(UIViewController* timeline, NSArray* sections, NSString* location) {
    if (!PFBDebugIsRecording() || !timeline || ![sections isKindOfClass:[NSArray class]]) {
        return;
    }
    id area = objc_getAssociatedObject(timeline, kPFBProbeAreaKey);
    if (!area) {
        // Judged once the controller is placed; until then its place is unknown.
        if (!timeline.parentViewController && !timeline.navigationController) {
            return;
        }
        area = probeArea(timeline) ?: (id)[NSNull null];
        objc_setAssociatedObject(timeline, kPFBProbeAreaKey, area, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![area isKindOfClass:[NSString class]]) {
        return;
    }
    NSMutableSet<NSString*>* seen = objc_getAssociatedObject(timeline, kPFBProbeSeenKey);
    if (!seen) {
        seen = [NSMutableSet set];
        objc_setAssociatedObject(timeline, kPFBProbeSeenKey, seen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString* place = [location isKindOfClass:[NSString class]] && location.length ? location : @"none";
    for (NSUInteger section = 0; section < sections.count; section++) {
        NSArray* items = sections[section];
        if (![items isKindOfClass:[NSArray class]]) {
            continue;
        }
        NSUInteger headers = 0;
        for (NSUInteger row = 0; row < items.count; row++) {
            id item = PFBUnwrapDataViewItem(items[row]);
            NSString* name = NSStringFromClass([item classForCoder]);
            if ([name hasSuffix:@"ModuleHeaderViewModel"]) {
                headers++;
            }
            if (!name || [seen containsObject:name]) {
                continue;
            }
            [seen addObject:name];
            NSString* key = [NSString stringWithFormat:@"explore %@ %@ %@", area, place, name];
            if (!PFBProbeWants(key)) {
                continue;
            }
            id entry = probeGetter(item, @"entryID");
            PFBProbeNote(key, @"#3 %@: item %@ · ad location %@ · list %@ · section %lu row %lu, %lu module header(s) "
                              @"from the top · entry %@",
                         area, name, place, NSStringFromClass([timeline class]), (unsigned long)section,
                         (unsigned long)row, (unsigned long)headers,
                         [entry isKindOfClass:[NSString class]] ? entry : @"not readable");
        }
    }
}

// MARK: - 4. Voice notes

static atomic_int gPFBProbeAssets;

// Where a media file comes from, without the identifiers that change per file.
static NSString* probeURLShape(NSURL* url) {
    NSString* place;
    if (url.isFileURL) {
        place = url.path.stringByDeletingLastPathComponent.lastPathComponent ?: @"?";
    } else {
        NSArray<NSString*>* parts = url.pathComponents;
        place = [NSString stringWithFormat:@"%@/%@", url.host ?: @"?", parts.count > 1 ? parts[1] : @""];
    }
    NSString* shape = [NSString stringWithFormat:@"%@ %@ .%@", url.scheme ?: @"?", place,
                                                 url.pathExtension.length ? url.pathExtension : @"-"];
    return [shape stringByReplacingOccurrencesOfString:@"[0-9A-Fa-f-]{8,}"
                                            withString:@"*"
                                               options:NSRegularExpressionSearch
                                                 range:NSMakeRange(0, shape.length)];
}

void PFBProbeAsset(NSURL* url, BOOL keptAsVoiceNote) {
    if (!PFBDebugIsRecording() || !url || atomic_load_explicit(&gPFBProbeAssets, memory_order_relaxed) >= 12) {
        return;
    }
    NSString* shape = probeURLShape(url);
    NSString* key = [NSString stringWithFormat:@"asset %@ %d", shape, keptAsVoiceNote];
    if (!PFBProbeWants(key)) {
        return;
    }
    atomic_fetch_add_explicit(&gPFBProbeAssets, 1, memory_order_relaxed);
    PFBProbeNote(key, @"#4 voice: media opened from %@%@", shape, keptAsVoiceNote ? @" · kept as the voice note to save" : @"");
}

void PFBProbeVoiceView(BOOL voiceFileKnown) {
    static atomic_bool seen[2];
    if (!PFBDebugIsRecording() || atomic_exchange_explicit(&seen[voiceFileKnown ? 1 : 0], true, memory_order_relaxed)) {
        return;
    }
    PFBProbeNote(voiceFileKnown ? @"voice view known" : @"voice view unknown", @"#4 voice: a voice note on screen, %@",
                 voiceFileKnown ? @"a voice file already kept to save" : @"no voice file kept yet");
}

void PFBProbeVoiceMenu(BOOL offered) {
    PFBProbeNote(offered ? @"voice menu offered" : @"voice menu refused", @"#4 voice: long press on a voice note, %@",
                 offered ? @"Download offered" : @"no menu, since no voice file was kept");
}

// MARK: - 5. Follow button

static const void* kPFBProbeFollowKey = &kPFBProbeFollowKey;

void PFBProbeFollowControl(UIView* authorRow, BOOL hidden) {
    if (hidden || !authorRow || !PFBDebugIsRecording() || objc_getAssociatedObject(authorRow, kPFBProbeFollowKey)) {
        return;
    }
    objc_setAssociatedObject(authorRow, kPFBProbeFollowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Read on the next turn, once the row sits in its cell and screen.
    __weak UIView* weakRow = authorRow;
    dispatch_async(dispatch_get_main_queue(), ^{
      UIView* row = weakRow;
      if (!row) {
          return;
      }
      UIViewController* controller = probeControllerOfView(row);
      NSString* screen = controller ? probeScreenName(controller) : @"no screen yet";
      UIView* cell = row;
      while (cell && ![cell isKindOfClass:[UITableViewCell class]] && ![cell isKindOfClass:[UICollectionViewCell class]]) {
          cell = cell.superview;
      }
      NSString* place = cell ? NSStringFromClass([cell class])
                             : (row.superview ? NSStringFromClass([row.superview class]) : @"no parent");
      NSString* key = [NSString stringWithFormat:@"follow %@ %@", screen, place];
      if (PFBProbeWants(key)) {
          PFBProbeNote(key, @"#5 follow: Twitter shows an author row's Follow button in %@ on %@%@", place, screen,
                       [PFBSettings boolForKey:@"hide_follow_button"] ? @" (the option hides it)" : @"");
      }
    });
}

// MARK: - 7. Video feed

void PFBProbeVideoFeed(long long listCount, long long navigatorCount, long long loadedEnd, long long firstPromoted,
                       BOOL enabled) {
    static atomic_bool counted;
    static atomic_bool mismatched;
    static atomic_bool promoted;
    if (!PFBDebugIsRecording()) {
        return;
    }
    if (!atomic_exchange_explicit(&counted, true, memory_order_relaxed)) {
        PFBProbeNote(@"videofeed counts", @"#7 video feed: %lld cards in the list, %lld for the navigator, pages loaded up to %lld",
                     listCount, navigatorCount, loadedEnd);
    }
    if (navigatorCount != listCount && !atomic_exchange_explicit(&mismatched, true, memory_order_relaxed)) {
        PFBProbeNote(@"videofeed mismatch",
                     @"#7 video feed: the navigator counts %lld cards while the list holds %lld, pages loaded up to %lld",
                     navigatorCount, listCount, loadedEnd);
    }
    if (firstPromoted < listCount && !atomic_exchange_explicit(&promoted, true, memory_order_relaxed)) {
        PFBProbeNote(@"videofeed promoted",
                     @"#7 video feed: a promoted card at %lld of %lld, past the pages loaded up to %lld, Hide ads %@",
                     firstPromoted, listCount, loadedEnd, enabled ? @"on" : @"off");
    }
}

void PFBProbeVideoFeedEdited(long long listBefore, long long listAfter, long long navigatorBefore, long long navigatorAfter) {
    static atomic_bool edited;
    static atomic_bool diverged;
    if (!PFBDebugIsRecording()) {
        return;
    }
    if (!atomic_exchange_explicit(&edited, true, memory_order_relaxed)) {
        PFBProbeNote(@"videofeed edited", @"#7 video feed: %lld promoted card(s) removed · list %lld → %lld · navigator %lld → %lld",
                     listBefore - listAfter, listBefore, listAfter, navigatorBefore, navigatorAfter);
    }
    if (navigatorAfter != listAfter && !atomic_exchange_explicit(&diverged, true, memory_order_relaxed)) {
        PFBProbeNote(@"videofeed diverged", @"#7 video feed: after a removal the navigator counts %lld cards and the list %lld",
                     navigatorAfter, listAfter);
    }
}

// MARK: - 8. Bar icons

// A glyph's vector name when the app's loader recorded it, and its size.
static NSString* probeImageName(UIImage* image) {
    if (!image) {
        return @"no image";
    }
    id name = objc_getAssociatedObject(image, (const void*)NSSelectorFromString(@"tfn_vectorImageNamed:fitsSize:fillColor:"));
    NSString* size = [NSString stringWithFormat:@"%.0fx%.0f", image.size.width, image.size.height];
    return [name isKindOfClass:[NSString class]] ? [NSString stringWithFormat:@"“%@” %@", name, size] : size;
}

void PFBProbeBarIcon(UIView* view, UIImage* original, UIImage* incoming) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    UIViewController* owner = probeControllerOfView(view);
    if ([owner isKindOfClass:[UINavigationController class]]) {
        owner = ((UINavigationController*)owner).topViewController ?: owner;
    }
    NSString* ownerName = owner ? NSStringFromClass([owner class]) : @"no screen";
    NSString* incomingName = probeImageName(incoming);
    NSString* key = [NSString stringWithFormat:@"baricon %@ %@", ownerName, incomingName];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"#8 bar icon: Twitter set %@ on a repainted icon of %@ whose first image is %@; the first image "
                          @"was repainted in its place",
                     incomingName, ownerName, probeImageName(original));
    }
}

void PFBProbeBarItem(UIImage* incoming) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    NSString* incomingName = probeImageName(incoming);
    NSString* key = [@"baritem " stringByAppendingString:incomingName];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"#8 bar icon: Twitter set %@ on a repainted bar button; the new image was repainted", incomingName);
    }
}

// MARK: - 9. Pull-to-refresh sound

// The last release near the top, judged once Twitter has had time to start its refresh.
// Main thread only, as scrolling is.
static CFTimeInterval gPFBProbeReleaseAt = -1.0;
static CFTimeInterval gPFBProbeRefreshAt = -1.0;
static BOOL gPFBProbeReleaseJudged = YES;
static BOOL gPFBProbeReleasePsst;
static BOOL gPFBProbeReleaseTour;
static CGFloat gPFBProbeReleaseOffset;
static CGFloat gPFBProbeReleaseInset;

static void probeJudgeRelease(BOOL refreshed) {
    gPFBProbeReleaseJudged = YES;
    if (!gPFBProbeReleasePsst && !refreshed) {
        return;
    }
    NSString* verdict = gPFBProbeReleasePsst ? (refreshed ? @"psst and a refresh" : @"psst without a refresh")
                                             : @"a refresh without psst";
    NSString* key = [NSString stringWithFormat:@"psst %@%@", verdict, gPFBProbeReleaseTour ? @" tour" : @""];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"#9 psst: %@%@ · released at offset %.0f with a top inset of %.0f, %.0f pt below the top", verdict,
                     gPFBProbeReleaseTour ? @" (tour)" : @"", gPFBProbeReleaseOffset, gPFBProbeReleaseInset,
                     -(gPFBProbeReleaseOffset + gPFBProbeReleaseInset));
    }
}

void PFBProbePullReleased(UIScrollView* list, BOOL psst) {
    if (!PFBDebugIsRecording() || !list) {
        return;
    }
    CGFloat offset = list.contentOffset.y;
    // A release away from the top neither sounds nor refreshes.
    if (!psst && offset > 0.0) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    gPFBProbeReleaseAt = now;
    gPFBProbeReleasePsst = psst;
    gPFBProbeReleaseTour = PFBCompatTourIsRunning();
    gPFBProbeReleaseOffset = offset;
    gPFBProbeReleaseInset = list.adjustedContentInset.top;
    gPFBProbeReleaseJudged = NO;
    // Twitter may have started its refresh while the release was handled.
    if (gPFBProbeRefreshAt >= 0.0 && now - gPFBProbeRefreshAt < 0.5) {
        probeJudgeRelease(YES);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (gPFBProbeReleaseAt == now && !gPFBProbeReleaseJudged) {
          probeJudgeRelease(gPFBProbeRefreshAt >= now);
      }
    });
}

void PFBProbeRefreshStarted(void) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    gPFBProbeRefreshAt = CACurrentMediaTime();
    if (!gPFBProbeReleaseJudged && gPFBProbeRefreshAt - gPFBProbeReleaseAt < 0.8) {
        probeJudgeRelease(YES);
    }
}

// MARK: - 10. Advanced search

// The controller whose bar shows a navigation item: one held in a navigation stack.
static UIViewController* probeItemHolder(UINavigationItem* item) {
    NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.rootViewController) {
                [queue addObject:window.rootViewController];
            }
        }
    }
    for (NSUInteger i = 0; i < queue.count && i < 512; i++) {
        UIViewController* controller = queue[i];
        if ([controller isKindOfClass:[UINavigationController class]]) {
            for (UIViewController* stacked in ((UINavigationController*)controller).viewControllers) {
                if (stacked.navigationItem == item) {
                    return stacked;
                }
            }
        }
        [queue addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) {
            [queue addObject:controller.presentedViewController];
        }
    }
    return nil;
}

static const void* kPFBProbeItemKey = &kPFBProbeItemKey;

void PFBProbeAdvancedSearch(UIViewController* owner, UINavigationItem* item, BOOL searchScreen,
                            NSString* (^match)(void)) {
    if (!PFBDebugIsRecording() || !item || objc_getAssociatedObject(item, kPFBProbeItemKey)) {
        return;
    }
    objc_setAssociatedObject(item, kPFBProbeItemKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController* holder = item == owner.navigationItem ? owner : probeItemHolder(item);
    NSString* ownerName = owner ? NSStringFromClass([owner class]) : @"no screen";
    NSString* holderName = holder ? NSStringFromClass([holder class]) : @"a bar no stacked screen holds";
    NSString* key = [NSString stringWithFormat:@"advsearch %@ %@", ownerName, holderName];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"#10 advanced search: a Filters button replaced on the bar of %@ while %@ was in front (%@) · "
                          @"matched by %@",
                     holderName, ownerName, searchScreen ? @"a search screen" : @"not a search screen",
                     match ? match() : @"?");
    }
}
