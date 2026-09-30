// Toggles that remove interface elements: the verified checkmark, search history,
// trending on Explore, the Subscribe and Follow buttons, and inline action buttons.

#import "Support/HookHelpers.h"

// MARK: - Hide Blue verified checkmark

// A verified flag Twitter reads is the option's proof, whatever the toggle; the flag
// is hidden when the option is on.
static BOOL PFBHidesVerifiedFlag(BOOL verified) {
    BOOL hide = [PFBSettings boolForKey:@"hide_blue_verified"];
    if (verified && hide) {
        PFBCOMPAT_ACTION(PFBCompat_hide_blue_verified, @"checkmark hidden");
    } else if (verified) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_blue_verified, @"verified user read");
    }
    return hide;
}

// isBlueVerified answers with an object: a number, or nil when unknown.
static BOOL PFBVerifiedValue(id value) {
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : value != nil;
}

// The author-row badge builds from the merged verified flag plus identityType and
// ignores isBlueVerified, so both getters are silenced; brand and government badges
// survive through identityType.

%hook TFSTwitterUser

- (id)isBlueVerified {
    id verified = %orig;
    return PFBHidesVerifiedFlag(PFBVerifiedValue(verified)) ? nil : verified;
}

- (BOOL)verified {
    BOOL verified = %orig;
    return PFBHidesVerifiedFlag(verified) ? NO : verified;
}

%end

// Reaches into the wrapped user's storage directly instead of through its
// getter.
%hook TFSTwitterUserSource

- (id)isBlueVerified {
    id verified = %orig;
    return PFBHidesVerifiedFlag(PFBVerifiedValue(verified)) ? nil : verified;
}

- (BOOL)verified {
    BOOL verified = %orig;
    return PFBHidesVerifiedFlag(verified) ? NO : verified;
}

%end

%hook TFSTwitterTypeaheadUser

- (id)isBlueVerified {
    id verified = %orig;
    return PFBHidesVerifiedFlag(PFBVerifiedValue(verified)) ? nil : verified;
}

- (BOOL)verified {
    BOOL verified = %orig;
    return PFBHidesVerifiedFlag(verified) ? NO : verified;
}

%end

%hook TFSDirectMessageUser

- (id)isBlueVerified {
    id verified = %orig;
    return PFBHidesVerifiedFlag(PFBVerifiedValue(verified)) ? nil : verified;
}

- (BOOL)verified {
    BOOL verified = %orig;
    return PFBHidesVerifiedFlag(verified) ? NO : verified;
}

%end

// Status view models cache these flags at init, beyond the user model hooks;
// the author row badge reads isFromUserVerified, and other view models forward
// here.
%hook T1TwitterCoreStatusViewModelAdapter

- (BOOL)isFromUserBlueVerified {
    BOOL verified = %orig;
    if (![PFBSettings boolForKey:@"hide_blue_verified"]) {
        if (verified) {
            PFBCOMPAT_OBSERVE(PFBCompat_hide_blue_verified, @"verified author seen");
        }
        return verified;
    }
    if (verified) {
        PFBCOMPAT_ACTION(PFBCompat_hide_blue_verified, @"checkmark hidden");
    }
    return NO;
}

- (BOOL)isFromUserVerified {
    BOOL verified = %orig;
    if (![PFBSettings boolForKey:@"hide_blue_verified"]) {
        if (verified) {
            PFBCOMPAT_OBSERVE(PFBCompat_hide_blue_verified, @"verified author seen");
        }
        return verified;
    }
    if (verified) {
        PFBCOMPAT_ACTION(PFBCompat_hide_blue_verified, @"checkmark hidden");
    }
    return NO;
}

%end

// MARK: - No search history

// Every recent-search write funnels through _tse_setRecentSearch: and every
// read through recentSearches, recentQueriesAndUserIDs included (it starts
// there); the separate saved-searches feature stays untouched.

%hook TTSRecentSearchesDatastore

- (void)_tse_setRecentSearch:(__unsafe_unretained id)item {
    if (![PFBSettings boolForKey:@"no_history"]) {
        %orig;
    } else {
        PFBCOMPAT_ACTION(PFBCompat_no_history, @"search not saved");
    }
}

- (NSArray*)recentSearches {
    if ([PFBSettings boolForKey:@"no_history"]) {
        PFBCOMPAT_ACTION(PFBCompat_no_history, @"history hidden");
        return @[];
    }
    PFBCOMPAT_OBSERVE(PFBCompat_no_history, @"read by Twitter");
    return %orig;
}

%end

// MARK: - Hide trending content on the Explore tab

// Defined in ExploreTabs.x. YES only for the hide_explore_all switch, which takes
// the whole Explore chrome. Choosing which tabs to keep is a separate switch that
// leaves the bar in place.
extern BOOL pfbShouldHideAllTrends(void);
// Defined in ExploreTabs.x. Records the accessory view this guide vends, so the
// tab filter only touches this bar (the segmented bar class is shared with
// Notifications and search results).
extern void pfbNoteExploreAccessoryView(UIView* v);

// Trending content lives in the child URT chrome view controller, whose property
// has no ObjC getter, so it is found among the children. The page tab strip
// arrives separately through tfn_navigationBarAccessoryView.

%hook _TtC14T1TwitterSwift28GuideContainerViewController

- (void)viewDidLoad {
    %orig;

    if (!pfbShouldHideAllTrends()) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_explore_all, @"Explore content found");
    }
    if (pfbShouldHideAllTrends()) {
        for (UIViewController* child in
             [(UIViewController*)self childViewControllers]) {
            if ([child isKindOfClass:
                           %c(_TtC14T1TwitterSwift23URTChromeViewController)]) {
                child.view.hidden = YES;
                PFBCOMPAT_ACTION(PFBCompat_hide_explore_all, @"Explore content hidden");
            }
        }
    }
}

- (UIView*)tfn_navigationBarAccessoryView {
    if (pfbShouldHideAllTrends()) {
        PFBCOMPAT_ACTION(PFBCompat_hide_explore_all, @"Explore tabs removed");
        return nil;
    }
    UIView* accessory = %orig;
    pfbNoteExploreAccessoryView(accessory);
    return accessory;
}

%end

// MARK: - No Subscribe button

// Every Subscribe surface shows only when the relationship's eligible state is 1,
// so reporting 2 keeps the plain Follow button everywhere. An actively
// super-following relationship is left genuine.

%hook TFSTwitterRelationship

- (NSInteger)superFollowEligibleState {
    NSInteger state = %orig;
    if (state == 1 && ![PFBSettings boolForKey:@"restore_follow_button"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_restore_follow_button, @"Subscribe button offered");
    }
    if ([PFBSettings boolForKey:@"restore_follow_button"] &&
        self.superFollowingState != 1) {
        if (state == 1) {
            PFBCOMPAT_ACTION(PFBCompat_restore_follow_button, @"Subscribe swapped for Follow");
        }
        return 2;
    }
    return state;
}

%end

// MARK: - Hide Follow button on Tweets

// The conversation focal tweet and the immersive player both render their
// author row through TTAStatusAuthorView, so forcing the flag here covers every
// surface.

%hook TTAStatusAuthorView

- (void)setFollowControlHidden:(BOOL)hidden {
    if (![PFBSettings boolForKey:@"hide_follow_button"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_follow_button, @"Follow button found");
        %orig(hidden);
        return;
    }
    if (!hidden) {
        PFBCOMPAT_ACTION(PFBCompat_hide_follow_button, @"Follow button hidden");
    }
    %orig(YES);
}

// The Message button beside the author, hidden again on every layout since the row
// is reconfigured in place.
- (void)layoutSubviews {
    %orig;
    UIView* row = (UIView*)self;
    SEL buttonSelector = NSSelectorFromString(@"messageButton");
    UIView* button = [row respondsToSelector:buttonSelector]
                         ? ((id (*)(id, SEL))objc_msgSend)(row, buttonSelector)
                         : nil;
    if (![button isKindOfClass:[UIView class]]) {
        return;
    }
    if (![PFBSettings boolForKey:@"hide_message_button"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_message_button, @"Message button found");
        return;
    }
    if (button.hidden) {
        return;
    }
    button.hidden = YES;
    button.userInteractionEnabled = NO;
    PFBCOMPAT_ACTION(PFBCompat_hide_message_button, @"Message button hidden");
}
%end

// MARK: - Hide inline action buttons

%hook TTAStatusInlineActionsView

+ (NSArray*)_t1_inlineActionViewClassesForViewModel:(id)arg1
                                            options:(NSUInteger)arg2
                                        displayType:(NSUInteger)arg3
                                            account:(id)arg4 {
    NSArray* origClasses = %orig;
    if (![origClasses isKindOfClass:NSArray.class]) {
        return origClasses;
    }

    NSMutableArray* newClasses = [origClasses mutableCopy];

    Class analyticsButtonClass = %c(TTAStatusInlineAnalyticsButton);
    if (analyticsButtonClass && [PFBSettings boolForKey:@"hide_view_count"] &&
        [newClasses containsObject:analyticsButtonClass]) {
        [newClasses removeObject:analyticsButtonClass];
        PFBCOMPAT_ACTION(PFBCompat_hide_view_count, @"views count removed");
    } else if (analyticsButtonClass && [newClasses containsObject:analyticsButtonClass]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_view_count, @"views count found");
    }

    Class bookmarkButtonClass = %c(TTAStatusInlineBookmarkButton);
    if (bookmarkButtonClass && [PFBSettings boolForKey:@"hide_bookmark_button"] &&
        [newClasses containsObject:bookmarkButtonClass]) {
        [newClasses removeObject:bookmarkButtonClass];
        PFBCOMPAT_ACTION(PFBCompat_hide_bookmark_button, @"bookmark button removed");
    } else if (bookmarkButtonClass && [newClasses containsObject:bookmarkButtonClass]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_bookmark_button, @"bookmark button found");
    }

    Class downvoteButtonClass = %c(TTAStatusInlineDownvoteButton);
    if (downvoteButtonClass && [PFBSettings boolForKey:@"hide_downvote_button"] &&
        [newClasses containsObject:downvoteButtonClass]) {
        [newClasses removeObject:downvoteButtonClass];
        PFBCOMPAT_ACTION(PFBCompat_hide_downvote_button, @"downvote button removed");
    } else if (downvoteButtonClass && [newClasses containsObject:downvoteButtonClass]) {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_downvote_button, @"downvote button found");
    }

    return [newClasses copy];
}

%end
