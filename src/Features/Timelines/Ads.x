// Hides promoted posts, the premium offer and trend videos from the lists the
// app builds (hide_promoted, hide_premium_offer, hide_trend_videos).

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

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

static NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                                 NSArray* sections) {
    if (!([PFBSettings boolForKey:@"hide_promoted"] ||
          [PFBSettings boolForKey:@"hide_premium_offer"] ||
          [PFBSettings boolForKey:@"hide_trend_videos"])) {
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
    return ([PFBSettings boolForKey:@"hide_promoted"] && [self isPromoted])
               ? true
               : %orig;
}

%end

// MARK: - Immersive video feed

// The vertical video feed keeps its own card list and never goes through
// TFNItemsDataViewController, so promoted cards are dropped from that list
// before they become pages.

static const void* kLoadedPromotedCardsKey = &kLoadedPromotedCardsKey;

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

// Pages up to the end of the navigator's loaded range already have their views, so
// only the cards past it are removed: taking a loaded one out would leave its view
// in place and shift every card after it.
static void RemovePromotedImmersiveCards(id controller) {
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

    if (PFBDebugIsRecording()) {
        long long loaded = 0;
        for (int64_t i = 0; i < MIN(loadedEnd, total); i++) {
            loaded += ImmersiveCardIsPromoted((__bridge id)elements[i * 2]) ? 1 : 0;
        }
        NSNumber* last = objc_getAssociatedObject(coordinator, kLoadedPromotedCardsKey);
        if (loaded != last.longLongValue) {
            objc_setAssociatedObject(coordinator, kLoadedPromotedCardsKey, @(loaded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PFBDebugLog(@"[ads] video feed: %lld promoted card(s) already loaded as pages - left in place", loaded);
        }
    }
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
    PFBDebugLog(@"[ads] video feed: %lld promoted card(s) removed past page %lld (%lld -> %lld cards)",
                (long long)droppedCount, (long long)loadedEnd - 1, (long long)total, (long long)kept);
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
