// Hides promoted posts, the premium offer and trend videos from the lists the
// app builds (hide_promoted, hide_premium_offer, hide_trend_videos).

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <mach/mach_time.h>

// Timeline items are removed from the section data before it reaches the data view
// controller, so no empty cells are left behind. This covers every timeline surface,
// table view and diffable collection view alike.

// The promoted state of a status item is only reachable through its Swift-side
// `status` stored property, which is still registered as an ObjC ivar.
static BOOL StatusItemIsPromoted(id item) {
    Ivar statusIvar = class_getInstanceVariable([item class], "status");
    if (!statusIvar) {
        return NO;
    }

    TFNTwitterStatus* status = object_getIvar(item, statusIvar);
    return [status respondsToSelector:@selector(isPromoted)] && status.isPromoted;
}

// Event summary heroes (the image ads at the top of explore) carry their promotion
// in the Swift-side `promotedContent` stored property, not always reflected in the
// scribe item. Trends have no such property: the scribe item's promoted_id decides.
static BOOL ItemHasPromotedContent(id item) {
    Ivar promotedIvar =
        class_getInstanceVariable([item class], "promotedContent");
    return promotedIvar && object_getIvar(item, promotedIvar) != nil;
}

static BOOL ScribeItemIsPromoted(id item) {
    if (![item respondsToSelector:@selector(scribeItem)]) {
        return NO;
    }

    NSDictionary* scribeItem = [item performSelector:@selector(scribeItem)];
    return [scribeItem isKindOfClass:[NSDictionary class]] &&
           scribeItem[@"promoted_id"] != nil;
}

// Probe 14a#F005: the kinds of message Hide Twitter Blue prompts removes, by entry, component
// and the offer words their texts hold, at most 5 kinds; no text is noted. A filter call that
// notes one is left out of 09#F055's timing.
static BOOL gPFBProbeAdsNoted;
static BOOL gPFBProbePromptDone;
static NSUInteger gPFBProbePromptLooks;
static NSUInteger gPFBProbePromptNoted;
static NSMutableSet<NSString*>* gPFBProbePromptEntries;

// Probe: a text field of the message as a plain string, or nil.
static NSString* pfbProbePromptText(id value) {
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSAttributedString class]]) {
        value = PFBProbeGetter(value, @"text");
    }
    if ([value isKindOfClass:[NSAttributedString class]]) {
        return ((NSAttributedString*)value).string;
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static void pfbProbePromptRemoved(id item) {
    if (gPFBProbePromptDone || !NSThread.isMainThread) {
        return;
    }
    if (!PFBDebugIsRecording() || gPFBProbePromptNoted >= 5 || ++gPFBProbePromptLooks > 2000) {
        gPFBProbePromptDone = YES;
        gPFBProbePromptEntries = nil;
        return;
    }
    id entryValue = PFBProbeGetter(item, @"entryID");
    NSString* entryID = [entryValue isKindOfClass:[NSString class]] ? entryValue : @"";
    if ([gPFBProbePromptEntries containsObject:entryID]) {
        return;
    }
    if (!gPFBProbePromptEntries) {
        gPFBProbePromptEntries = [NSMutableSet set];
    }
    [gPFBProbePromptEntries addObject:entryID];

    NSRange digit = [entryID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet];
    NSString* entryKind =
        [entryID substringToIndex:MIN(digit.location == NSNotFound ? entryID.length : digit.location, (NSUInteger)40)];
    id componentValue = PFBProbeGetter(item, @"scribeComponent");
    NSString* component = [componentValue isKindOfClass:[NSString class]] ? componentValue : @"none";
    NSString* header = pfbProbePromptText(PFBProbeGetter(item, @"headerRichText"));
    NSString* body = pfbProbePromptText(PFBProbeGetter(item, @"bodyRichText"));
    NSString* banner = pfbProbePromptText(PFBProbeGetter(item, @"bannerText"));
    NSString* texts =
        [NSString stringWithFormat:@"%@ %@ %@", header ?: @"", body ?: @"", banner ?: @""].lowercaseString;
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    for (NSString* word in @[ @"premium", @"verified", @"verification", @"subscribe", @"subscription", @"upgrade",
                              @"blue", @"checkmark", @"contacts", @"notifications", @"topics", @"follow" ]) {
        if ([texts containsString:word]) {
            [words addObject:word];
        }
    }
    NSString* kind = [NSString stringWithFormat:@"entry %@ · component %@ · offer words %@",
                                                entryKind.length ? entryKind : @"none", component,
                                                words.count ? [words componentsJoinedByString:@"+"] : @"none"];
    NSString* key = [@"14a#F005 " stringByAppendingString:kind];
    if (PFBProbeWants(key)) {
        gPFBProbePromptNoted++;
        gPFBProbeAdsNoted = YES;
        PFBProbeNote(key, @"14a#F005 Blue prompt removed: %@ · header %lu chars, body %lu, banner %lu", kind,
                     (unsigned long)header.length, (unsigned long)body.length, (unsigned long)banner.length);
    }
}

static BOOL ShouldHideItem(id item, NSString* location) {
    item = PFBUnwrapDataViewItem(item);
    NSString* className = NSStringFromClass([item classForCoder]);

    if ([PFBSettings boolForKey:@"hide_promoted"]) {
        if ([item
                isKindOfClass:objc_getClass("T1URTTimelineStatusItemViewModel")] &&
            StatusItemIsPromoted(item)) {
            PFBCOMPAT_ACTION(PFBCompat_hide_promoted, @"promoted tweet");
            return YES;
        }

        if ([className
                isEqualToString:@"TwitterURT.URTTimelineGoogleNativeAdViewModel"]) {
            return YES;
        }

        if (([className isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"] ||
             [className
                 isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) &&
            (ScribeItemIsPromoted(item) || ItemHasPromotedContent(item))) {
            return YES;
        }
    }

    if ([PFBSettings boolForKey:@"hide_premium_offer"]) {
        if ([className isEqualToString:@"T1URTTimelineMessageItemViewModel"]) {
            // Probe: notes the kind of message removed, for 14a#F005.
            pfbProbePromptRemoved(item);
            PFBCOMPAT_ACTION(PFBCompat_hide_premium_offer, @"premium message hidden");
            return YES;
        }
    }

    if (PFBCompatNeedsObservation(PFBCompat_hide_trend_videos) &&
        ![PFBSettings boolForKey:@"hide_trend_videos"] && [location isEqualToString:@"OTHER"] &&
        [className isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_trend_videos, @"trending videos found");
    }
    if ([PFBSettings boolForKey:@"hide_trend_videos"] &&
        [location isEqualToString:@"OTHER"]) {
        if ([className
                isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_trend_videos, @"trending videos hidden");
            return YES;
        }
    }

    return NO;
}

// Probe: milliseconds from mach_absolute_time ticks.
static double pfbProbeMs(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) {
        mach_timebase_info(&timebase);
    }
    return (double)ticks * (double)timebase.numer / (double)timebase.denom / 1e6;
}

// Probe: the end of a tour closes this file's tour measurements (defined below them).
static void pfbProbeObserveTour(void);

// Probe 14b#F013: each list's ad location and screen during tours, and the carousels delivered,
// until a full tour runs to its end; at most 30 lists and 12 carousels.
static int gPFBProbeListState;   // 0 not read yet, 1 open, 2 closed
static NSUInteger gPFBProbeListCalls;
static NSUInteger gPFBProbeListNoted;
static NSUInteger gPFBProbeListCarousels;
static NSHashTable* gPFBProbeListControllers;
static NSMutableSet* gPFBProbeListPlainClasses;
static NSMutableSet<NSString*>* gPFBProbeListCarouselKinds;

static void pfbProbeListTourEnded(void) {
    if (gPFBProbeListState != 1 || ![PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
        return;
    }
    gPFBProbeListState = 2;
    PFBProbeNote(@"14b#F013 end", @"14b#F013 end of the first tour: %lu deliveries read, %lu carousel items met",
                 (unsigned long)gPFBProbeListCalls, (unsigned long)gPFBProbeListCarousels);
    gPFBProbeListControllers = nil;
    gPFBProbeListPlainClasses = nil;
    gPFBProbeListCarouselKinds = nil;
}

static void pfbProbeListLocation(TFNItemsDataViewController* dataViewController, NSArray* sections) {
    if (gPFBProbeListState == 2 || !NSThread.isMainThread) {
        return;
    }
    if (gPFBProbeListState == 0) {
        if (!PFBProbeWants(@"14b#F013 end")) {
            gPFBProbeListState = 2;
            return;
        }
        gPFBProbeListState = 1;
        gPFBProbeListControllers = [NSHashTable weakObjectsHashTable];
        gPFBProbeListPlainClasses = [NSMutableSet set];
        gPFBProbeListCarouselKinds = [NSMutableSet set];
        pfbProbeObserveTour();
    }
    if (++gPFBProbeListCalls > 20000) {
        gPFBProbeListState = 2;
        return;
    }
    NSString* location = [dataViewController respondsToSelector:@selector(adDisplayLocation)]
                             ? dataViewController.adDisplayLocation
                             : nil;
    // A list is read once it sits in a screen during the tour, so its screen is the one it shows in.
    if (PFBCompatTourIsRunning() && ![gPFBProbeListControllers containsObject:dataViewController] &&
        (dataViewController.parentViewController || dataViewController.navigationController)) {
        [gPFBProbeListControllers addObject:dataViewController];
        NSString* list = [NSString stringWithFormat:@"%@ location %@ on %@", PFBProbeClassName(dataViewController),
                                                    location ?: @"none", PFBProbeScreenName(dataViewController)];
        NSString* key = [@"14b#F013 list " stringByAppendingString:list];
        if (gPFBProbeListNoted < 30 && PFBProbeWants(key)) {
            gPFBProbeListNoted++;
            PFBProbeNote(key, @"14b#F013 list %@", list);
        }
    }
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (id item in (NSArray*)section) {
            Class itemClass = [PFBUnwrapDataViewItem(item) classForCoder];
            if (!itemClass || [gPFBProbeListPlainClasses containsObject:itemClass]) {
                continue;
            }
            NSString* name = NSStringFromClass(itemClass);
            if (![name containsString:@"Carousel"]) {
                [gPFBProbeListPlainClasses addObject:itemClass];
                continue;
            }
            gPFBProbeListCarousels++;
            if (gPFBProbeListCarouselKinds.count >= 12) {
                continue;
            }
            NSString* carousel =
                [NSString stringWithFormat:@"%@ in %@ on %@ (location %@)", name, PFBProbeClassName(dataViewController),
                                           PFBProbeScreenName(dataViewController), location ?: @"none"];
            if ([gPFBProbeListCarouselKinds containsObject:carousel]) {
                continue;
            }
            [gPFBProbeListCarouselKinds addObject:carousel];
            NSString* key = [@"14b#F013 carousel " stringByAppendingString:carousel];
            if (PFBProbeWants(key)) {
                PFBProbeNote(key, @"14b#F013 carousel %@", carousel);
            }
        }
    }
}

// Probe 09#F055: the time this filter takes during the first full tour run to its end, noted then.
static int gPFBProbeAdsState;   // 0 not read yet, 1 open, 2 closed
static struct {
    NSUInteger calls, itemsMax;
    uint64_t start, ticks, longest;
} gPFBProbeAds;

static void pfbProbeAdsTourEnded(void) {
    if (gPFBProbeAdsState != 1 || !gPFBProbeAds.start) {
        return;
    }
    // A tour stopped early or not full is left out; the next one is measured afresh.
    if (![PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
        memset(&gPFBProbeAds, 0, sizeof(gPFBProbeAds));
        return;
    }
    gPFBProbeAdsState = 2;
    double tour = pfbProbeMs(mach_absolute_time() - gPFBProbeAds.start) / 1000.0;
    double total = pfbProbeMs(gPFBProbeAds.ticks);
    PFBProbeNote(@"09#F055 list filter",
                 @"09#F055 Ads list filter during the tour (%.0f s): %lu calls, %.1f ms (%.2f%%), longest %.2f ms, "
                 @"items up to %lu",
                 tour, (unsigned long)gPFBProbeAds.calls, total, tour > 0 ? total / (tour * 10.0) : 0.0,
                 pfbProbeMs(gPFBProbeAds.longest), (unsigned long)gPFBProbeAds.itemsMax);
}

static uint64_t pfbProbeAdsClock(void) {
    if (gPFBProbeAdsState == 2) {
        return 0;
    }
    if (gPFBProbeAdsState == 0) {
        if (!PFBProbeWants(@"09#F055 list filter")) {
            gPFBProbeAdsState = 2;
            return 0;
        }
        gPFBProbeAdsState = 1;
        pfbProbeObserveTour();
    }
    if (!PFBCompatTourIsRunning() || !NSThread.isMainThread) {
        return 0;
    }
    if (!gPFBProbeAds.start) {
        gPFBProbeAds.start = mach_absolute_time();
    }
    gPFBProbeAdsNoted = NO;
    return mach_absolute_time();
}

static void pfbProbeAdsCall(uint64_t start, NSArray* sections) {
    if (!start) {
        return;
    }
    uint64_t ticks = mach_absolute_time() - start;
    gPFBProbeAds.calls++;
    if (gPFBProbeAdsNoted) {
        return;
    }
    gPFBProbeAds.ticks += ticks;
    gPFBProbeAds.longest = MAX(gPFBProbeAds.longest, ticks);
    NSUInteger items = 0;
    for (id section in sections) {
        if ([section isKindOfClass:[NSArray class]]) {
            items += ((NSArray*)section).count;
        }
    }
    gPFBProbeAds.itemsMax = MAX(gPFBProbeAds.itemsMax, items);
}

static NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                                 NSArray* sections) {
    // Probe: notes the list's location and carousels for 14b#F013, then times the call for 09#F055.
    pfbProbeListLocation(dataViewController, sections);
    uint64_t probeStart = pfbProbeAdsClock();
    if (!([PFBSettings boolForKey:@"hide_promoted"] ||
          [PFBSettings boolForKey:@"hide_premium_offer"] ||
          [PFBSettings boolForKey:@"hide_trend_videos"])) {
        pfbProbeAdsCall(probeStart, sections);
        return sections;
    }

    NSString* location =
        [dataViewController respondsToSelector:@selector(adDisplayLocation)]
            ? dataViewController.adDisplayLocation
            : nil;

    BOOL modified = NO;
    NSMutableArray* filteredSections =
        [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSUInteger count = items.count;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < count; i++) {
            if (ShouldHideItem(items[i], location)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        PFBMarkEmptiedModuleChrome(items, removed);

        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        modified = YES;

        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    pfbProbeAdsCall(probeStart, sections);
    return modified ? filteredSections : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections
    restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredSections(self, sections), identifiers, animation,
              completion);
}

%end

%hook TFNTwitterStatus

- (_Bool)isCardHidden {
    if ([PFBSettings boolForKey:@"hide_promoted"] && [self isPromoted]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_promoted, @"promoted card hidden");
        return true;
    }
    return %orig;
}

%end

// MARK: - Immersive video feed

// The vertical video feed keeps its own card list and never goes through
// TFNItemsDataViewController, so promoted cards are dropped from that list
// before they become pages.

// A Swift stored property that holds a class reference, read as an object.
static id ObjectIvar(id object, const char* name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return ivar ? object_getIvar(object, ivar) : nil;
}

static BOOL ImmersiveCardIsPromoted(id card) {
    if (object_getClass(card) == objc_getClass("_TtC14T1TwitterSwift36ImmersiveGoogleNativeAdCardViewModel")) {
        return YES;
    }

    id statusItem = ObjectIvar(card, "statusItemViewModel");
    return statusItem && StatusItemIsPromoted(statusItem);
}

// The card list is only edited when its storage is a native Swift array of
// ImmersiveCardViewModelProtocol, told by the storage class name: any other
// storage has a layout this code does not know.
static BOOL ImmersiveCardBufferIsKnown(uint8_t* buffer) {
    static Class known;
    static BOOL reported;
    if (!buffer || ((uintptr_t)buffer & 0xFF0000000000000FULL)) {
        return NO;
    }

    Class storage = object_getClass((__bridge id)(void*)buffer);
    if (storage == known) {
        return YES;
    }

    const char* name = class_getName(storage);
    if (name && strstr(name, "ContiguousArrayStorage") && strstr(name, "ImmersiveCardViewModelProtocol")) {
        known = storage;
        return YES;
    }
    if (!reported && PFBDebugIsRecording() && !(name && strstr(name, "EmptyArrayStorage"))) {
        reported = YES;
        PFBDebugLog(@"[ads] video feed: list storage not recognised (%s)", name ?: "no name");
    }
    return NO;
}

// Probe 09#F063: the time each scan of the video feed takes during the first full tour run to its
// end, noted then, with no call if the tour never showed the feed. A call that notes a probe line
// is counted, not timed.
static int gPFBProbeFeedState;   // 0 not read yet, 1 open, 2 closed
static BOOL gPFBProbeFeedNoted;
static struct {
    NSUInteger calls, timed;
    uint64_t ticks, longest;
} gPFBProbeFeed;

static void pfbProbeFeedTourEnded(void) {
    if (gPFBProbeFeedState == 2) {
        return;
    }
    // A tour stopped early or not full is left out; the next one is measured afresh.
    if (![PFBCompatTourLastRun() hasPrefix:@"Full tour"]) {
        memset(&gPFBProbeFeed, 0, sizeof(gPFBProbeFeed));
        return;
    }
    gPFBProbeFeedState = 2;
    if (PFBProbeWants(@"09#F063 video feed")) {
        PFBProbeNote(@"09#F063 video feed",
                     @"09#F063 video feed scan during the tour: %lu calls, %.2f ms over %lu timed, longest %.0f µs",
                     (unsigned long)gPFBProbeFeed.calls, pfbProbeMs(gPFBProbeFeed.ticks),
                     (unsigned long)gPFBProbeFeed.timed, pfbProbeMs(gPFBProbeFeed.longest) * 1000.0);
    }
}

static uint64_t pfbProbeFeedBegin(void) {
    if (gPFBProbeFeedState == 2) {
        return 0;
    }
    if (gPFBProbeFeedState == 0) {
        if (!PFBProbeWants(@"09#F063 video feed")) {
            gPFBProbeFeedState = 2;
            return 0;
        }
        gPFBProbeFeedState = 1;
        pfbProbeObserveTour();
    }
    if (!PFBCompatTourIsRunning() || !NSThread.isMainThread) {
        return 0;
    }
    gPFBProbeFeedNoted = NO;
    return mach_absolute_time();
}

static void pfbProbeFeedEnd(uint64_t* start) {
    if (!*start) {
        return;
    }
    uint64_t ticks = mach_absolute_time() - *start;
    gPFBProbeFeed.calls++;
    if (gPFBProbeFeedNoted) {
        return;
    }
    gPFBProbeFeed.timed++;
    gPFBProbeFeed.ticks += ticks;
    gPFBProbeFeed.longest = MAX(gPFBProbeFeed.longest, ticks);
}

// Probe 09#F036: the navigator's count against the list's, read before promoted cards are
// removed; once when they agree, once when they differ.
static BOOL gPFBProbeFeedCountsDone;

static void pfbProbeFeedCounts(id navigator, Ivar countIvar, int64_t total, int64_t loadedEnd, int64_t first) {
    if (gPFBProbeFeedCountsDone) {
        return;
    }
    if (!PFBDebugIsRecording()) {
        gPFBProbeFeedCountsDone = YES;
        return;
    }
    int64_t navigatorCount = *(int64_t*)((uint8_t*)(__bridge void*)navigator + ivar_getOffset(countIvar));
    BOOL agree = navigatorCount == total;
    NSString* key = agree ? @"09#F036 agree" : @"09#F036 differ";
    if (PFBProbeWants(key)) {
        gPFBProbeFeedNoted = YES;
        PFBProbeNote(key, @"09#F036 video feed: list %lld, navigator %lld, loaded up to %lld, first promoted %lld: %@",
                     (long long)total, (long long)navigatorCount, (long long)loadedEnd, (long long)first,
                     agree ? @"counts agree" : @"COUNTS DIFFER");
    }
    gPFBProbeFeedCountsDone = !PFBProbeWants(@"09#F036 agree") && !PFBProbeWants(@"09#F036 differ");
}

static void pfbProbeObserveTour(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      [[NSNotificationCenter defaultCenter] addObserverForName:PFBProbeTourEndedNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(__unused NSNotification* note) {
                                                      pfbProbeListTourEnded();
                                                      pfbProbeAdsTourEnded();
                                                      pfbProbeFeedTourEnded();
                                                    }];
    });
}

// Pages up to the end of the navigator's loaded range already have their views, so
// only the cards past it are removed: taking a loaded one out would leave its view
// in place and shift every card after it.
static void RemovePromotedImmersiveCards(id controller) {
    // Probe: times this call for 09#F063; the cleanup runs on every return.
    uint64_t probeStart __attribute__((cleanup(pfbProbeFeedEnd))) = pfbProbeFeedBegin();
    BOOL enabled = [PFBSettings boolForKey:@"hide_promoted"];
    if (!controller || (!enabled && PFBCompatPathReached(PFBCompatPath_promoted_video_feed))) {
        return;
    }

    id coordinator = ObjectIvar(controller, "timelineCoordinator");
    id navigator = ObjectIvar(controller, "cardNavigator");
    Ivar itemsIvar = coordinator ? class_getInstanceVariable(object_getClass(coordinator), "items") : NULL;
    Ivar rangeIvar = navigator ? class_getInstanceVariable(object_getClass(navigator), "loadedPageRange") : NULL;
    Ivar countIvar = navigator ? class_getInstanceVariable(object_getClass(navigator), "itemCount") : NULL;
    if (!itemsIvar || !rangeIvar || !countIvar) {
        return;
    }

    // The buffer of a Swift array has its count at +16 and its elements from +32,
    // two words each here: the card and its protocol witness table.
    uint8_t* buffer = *(uint8_t**)((uint8_t*)(__bridge void*)coordinator + ivar_getOffset(itemsIvar));
    if (!ImmersiveCardBufferIsKnown(buffer)) {
        return;
    }
    int64_t* count = (int64_t*)(buffer + 16);
    void** elements = (void**)(buffer + 32);
    int64_t total = *count;
    if (total <= 0) {
        return;
    }

    // loadedPageRange is a Swift Range<Int>: lower bound, then upper bound.
    int64_t loadedEnd = ((int64_t*)((uint8_t*)(__bridge void*)navigator + ivar_getOffset(rangeIvar)))[1];
    int64_t first = MAX(loadedEnd, 0);
    while (first < total && !ImmersiveCardIsPromoted((__bridge id)elements[first * 2])) {
        first++;
    }
    PFBCompatReach(PFBCompatPath_promoted_video_feed);

    if (!enabled || first == total) {
        return;
    }

    static bool (*isUniquelyReferenced)(const void*);
    static void (*unknownObjectRelease)(void*);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        isUniquelyReferenced = dlsym(RTLD_DEFAULT, "swift_isUniquelyReferenced_nonNull_native");
        unknownObjectRelease = dlsym(RTLD_DEFAULT, "swift_unknownObjectRelease");
    });

    // Editing a buffer that another array still shares would change that array too.
    void** dropped = malloc((size_t)(total - first) * sizeof(void*));
    if (!isUniquelyReferenced || !unknownObjectRelease || !dropped || !isUniquelyReferenced(buffer)) {
        static BOOL reported;
        if (!reported && PFBDebugIsRecording()) {
            reported = YES;
            PFBDebugLog(@"[ads] video feed: card list shared or runtime call missing - removal skipped");
        }
        free(dropped);
        return;
    }

    // Probe: notes the two counts before the removal, for 09#F036.
    pfbProbeFeedCounts(navigator, countIvar, total, loadedEnd, first);
    int64_t kept = first;
    int64_t droppedCount = 0;
    for (int64_t i = first; i < total; i++) {
        void* card = elements[i * 2];
        if (ImmersiveCardIsPromoted((__bridge id)card)) {
            dropped[droppedCount++] = card;
            PFBCOMPAT_ACTION(PFBCompat_hide_promoted, @"promoted video card removed");
            continue;
        }

        elements[kept * 2] = card;
        elements[kept * 2 + 1] = elements[i * 2 + 1];
        kept++;
    }
    *count = kept;

    // The navigator holds its own count: left as it was, it would allow empty pages
    // past the last card.
    int64_t* navigatorCount = (int64_t*)((uint8_t*)(__bridge void*)navigator + ivar_getOffset(countIvar));
    if (*navigatorCount == total) {
        *navigatorCount = kept;
    }

    // The cards are released once the list is consistent again.
    for (int64_t i = 0; i < droppedCount; i++) {
        unknownObjectRelease(dropped[i]);
    }
    free(dropped);
}

%hook T1ImmersiveViewController

- (void)viewWillLayoutSubviews {
    RemovePromotedImmersiveCards(self);
    %orig;
}

%end

// The host lays out each time a page is created: the first moment to reach cards
// that have just arrived.
%hook _TtC14T1TwitterSwift21ImmersiveCardHostView

- (void)layoutSubviews {
    Class controllerClass = objc_getClass("T1ImmersiveViewController");
    UIResponder* responder = [(UIView*)self nextResponder];
    while (responder && ![responder isKindOfClass:controllerClass]) {
        responder = responder.nextResponder;
    }
    RemovePromotedImmersiveCards(responder);
    %orig;
}

%end
