// Hides promoted posts, the premium offer and trend videos from the lists the
// app builds (hide_promoted, hide_premium_offer, hide_trend_videos).

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"

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

// Promoted trends and event summary heroes (the image ads at the top of
// explore) carry their promotion in the Swift-side `promotedContent` stored
// property, which isn't always reflected in the scribe item.
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
        if ([className
                isEqualToString:@"TwitterURT.URTTimelineMessageItemViewModel"]) {
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
