//
//  ExploreTabs.x
//  PrimeFreeBird
//
//  Granular Explore tabs.
//
//  The pager keeps every page and the bar keeps every cell, so a page index,
//  a cell index and a tab index are all the same number. The app's own
//  navigation, its selected-tab styling and its bookkeeping therefore stay
//  correct without translation, and a hidden tab is handled by two rules:
//
//    - the bar hides its cell, packs the survivors together and centres the
//      row, so nothing empty is left where the tab was;
//    - a gesture never comes to rest on a hidden page, and a programmatic
//      navigation aimed at one is redirected to the nearest visible tab.
//
//  The underline is placed here rather than left to the app: with cells packed
//  by hand, the native placement follows the layout's own frames instead of
//  theirs. Position and width are interpolated between the two cells around
//  the current offset and set without animation on every bar layout pass, and
//  native animations on that one layer are dropped so nothing fights back.
//
//  Two ordering hazards are handled: the pager's data source can be
//  interrogated before the bar exists, so the candidate collection is
//  remembered on every pass and adopted once the bar is provably live; and the
//  bar's inner collection re-lays its cells on its own layout passes, so the
//  packed row is re-applied after each of them.
//
//  Per-tab key <-> index: hide_tab_foryou(0) trending(1) news(2) sports(3)
//    entertainment(4). ON = HIDE. Keys default NO. Indices beyond the known
//    five are always kept (future-proof if Twitter adds a tab).
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"
#import <QuartzCore/QuartzCore.h>

static NSString* const kNFBTabKeys[] = {
    @"hide_tab_foryou",
    @"hide_tab_trending",
    @"hide_tab_news",
    @"hide_tab_sports",
    @"hide_tab_entertainment",
};
static const NSInteger kNFBTabCount = 5;

// MARK: - shared predicates (defined before use)

static BOOL nfbTabHidden(NSInteger idx) {
    if (idx < 0 || idx >= kNFBTabCount) { return NO; }
    return [BHTSettings boolForKey:kNFBTabKeys[idx]];
}

static BOOL nfbAnyTabHidden(void) {
    for (NSInteger i = 0; i < kNFBTabCount; i++) {
        if ([BHTSettings boolForKey:kNFBTabKeys[i]]) { return YES; }
    }
    return NO;
}

// The two modes are asked for, not inferred. The old pair read a single master
// and guessed: master ON with no tab chosen meant "hide everything", and master
// ON with every tab chosen meant the same - which made striking all five
// identical to striking none. Each mode now has its own switch, and the
// settings screen refuses to strike the last kept tab, so an empty bar cannot
// be reached at all.
BOOL nfbShouldHideAllTrends(void) {
    return [BHTSettings boolForKey:@"hide_explore_all"];
}

static BOOL nfbGranularActive(void) {
    return ![BHTSettings boolForKey:@"hide_explore_all"]
        && [BHTSettings boolForKey:@"choose_explore_tabs"]
        && nfbAnyTabHidden();
}

// MARK: - tab mask helpers (pure, defined before use)


// Nearest KEPT absolute index to `cur` (used only by the safety net).
static NSInteger nfbNearestKeptAbs(NSInteger cur, NSInteger total) {
    for (NSInteger d = 1; d < total + 1; d++) {
        if (cur - d >= 0 && !nfbTabHidden(cur - d)) { return cur - d; }
        if (cur + d < total && !nfbTabHidden(cur + d)) { return cur + d; }
    }
    return 0;
}

// Bitmask of the current hidden set — cheap change detection.
static NSUInteger nfbMaskBits(void) {
    NSUInteger bits = 0;
    for (NSInteger i = 0; i < kNFBTabCount; i++) {
        if (nfbTabHidden(i)) { bits |= (1u << i); }
    }
    return bits;
}

// MARK: - Explore-bar identity + pager state (defined before use)

static __weak UIView* gNFBExploreBar = nil;          // the Explore accessory view
static __weak UICollectionView* gNFBPagerCV = nil;   // the Explore pager collection
static NSInteger gNFBPagerTotal = 0;                 // absolute page count (%orig)
// The data source can be interrogated before the bar exists, which leaves the
// scope check with nothing to answer. Any paging, multi-item collection served
// by that controller is therefore remembered as a candidate on every pass, and
// the bar's own filter adopts it the first time it runs with a live bar.
static __weak UICollectionView* gNFBPagerCandidate = nil;
static NSInteger gNFBPagerCandidateTotal = 0;
static __weak UICollectionView* gNFBBarCV = nil;     // the bar's inner collection
static __weak CALayer* gNFBHighlightLayer = nil;     // underline layer (lockdown)
static BOOL gNFBSettingUnderline = NO;               // our own underline set
static BOOL gNFBInBarFilter = NO;                    // re-entrancy guard
static BOOL gNFBSelfNav = NO;          // our own pager navigation in progress
static NSUInteger gNFBAppliedMaskBits = 0xFFFF;   // last mask synced to the pager

void nfbNoteExploreAccessoryView(UIView* v) {
    // TEMPORARY probe for 12.21: is the accessory still handed to us, and what
    // is it made of now.
    static NSInteger probeCalls = 0;
    if (probeCalls < 3) {
        probeCalls++;
        NSMutableArray* names = [NSMutableArray array];
        for (UIView* sub in v.subviews) {
            [names addObject:NSStringFromClass([sub class])];
            if (names.count >= 8) {
                break;
            }
        }
        NFBDebugLog(@"[p21] explore accessory #%ld | class=%@ | subviews: %@",
                    (long)probeCalls, v ? NSStringFromClass([v class]) : @"nil",
                    names.count ? [names componentsJoinedByString:@", "] : @"(none)");
    }
    gNFBExploreBar = v;
    // 12.21 hands the accessory over AFTER the segmented bar has laid itself
    // out, and the bar only adopts its collection from layoutSubviews. Nothing
    // asks it to lay out again, so it never adopts. Measured: the bar's layout
    // fired at 53.4 s with the accessory unknown, the accessory arrived at 55.6 s,
    // and the collection was then recognised but never adopted. Asking for a
    // layout pass here makes the order irrelevant.
    if (v) {
        Class legacyBar = NSClassFromString(@"_TtC10TFNUISwift25LegacySegmentedTabBarView");
        Class oldBar = NSClassFromString(@"_TtC10TFNUISwift19SegmentedTabBarView");
        EnumerateSubviewsRecursively(v, ^(UIView* sub) {
          if ((legacyBar && [sub isKindOfClass:legacyBar]) ||
              (oldBar && [sub isKindOfClass:oldBar])) {
              [sub setNeedsLayout];
              NFBDebugLog(@"[p21] explore: bar %@ asked to lay out again",
                          NSStringFromClass([sub class]));
          }
        });
        if ([v isKindOfClass:legacyBar] || [v isKindOfClass:oldBar]) {
            [v setNeedsLayout];
        }
    }
}

static BOOL nfbIsExploreBar(UIView* bar) {
    UIView* root = gNFBExploreBar;
    if (!root || !bar) { return NO; }
    return (bar == root) || [bar isDescendantOfView:root];
}

// MARK: - view helpers (defined before use)

static UICollectionView* nfbFindCollection(UIView* v, int depth) {
    if (!v || depth > 6) { return nil; }
    if ([v isKindOfClass:[UICollectionView class]]) {
        return (UICollectionView*)v;
    }
    for (UIView* s in v.subviews) {
        UICollectionView* found = nfbFindCollection(s, depth + 1);
        if (found) { return found; }
    }
    return nil;
}

static UIView* nfbFindHighlightBar(UIView* v, int depth) {
    if (!v || depth > 6) { return nil; }
    NSString* cls = NSStringFromClass([v class]);
    if ([cls rangeOfString:@"SegmentedHighlightBarView"].location != NSNotFound) {
        return v;
    }
    for (UIView* s in v.subviews) {
        UIView* found = nfbFindHighlightBar(s, depth + 1);
        if (found) { return found; }
    }
    return nil;
}

// Scope: is the Explore bar currently ON SCREEN in the same window as this
// scroll view? The accessory bar lives in the navigation chrome, NOT inside the
// SegmentedViewController's view. Off-screen tabs have window == nil, so when
// Home's pager (same generic class) is used, the guard is false. Only Explore
// passes.
static BOOL nfbPagerScopeOK(UIScrollView* sv) {
    UIView* root = gNFBExploreBar;
    if (!root || !sv) { return NO; }
    return root.window != nil && root.window == sv.window;
}

// The underline is placed here. The native placement follows the layout's own
// cell frames, which are not the packed ones this filter installs, so position
// AND width are interpolated between the real packed cells of the two pages
// around the current offset, and set without animation on every bar layout
// pass — a native-looking glide during flights, exact at rest. Native
// animations are squelched (CALayer hook below), so nothing fights back.
static void nfbPositionUnderline(UIView* root, UICollectionView* cv) {
    UICollectionView* pager = gNFBPagerCV;
    if (!root || !cv || !pager) { return; }
    UIView* hl = nfbFindHighlightBar(root, 0);
    if (!hl) { return; }
    gNFBHighlightLayer = hl.layer;
    CGFloat pw = pager.bounds.size.width;
    if (pw < 1.0) { return; }
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    if (total < 1) { return; }
    // The page index is the tab's own index, so the offset points straight at
    // a cell. Mid-swipe it can point at a hidden one; the underline then rides
    // the nearest tab that is on screen.
    CGFloat f = pager.contentOffset.x / pw;
    if (f < 0) { f = 0; }
    if (f > total - 1) { f = total - 1; }
    NSInteger i0 = (NSInteger)floor(f);
    NSInteger i1 = (i0 + 1 <= total - 1) ? i0 + 1 : total - 1;
    CGFloat t = f - i0;
    NSInteger abs0 = nfbTabHidden(i0) ? nfbNearestKeptAbs(i0, total) : i0;
    NSInteger abs1 = nfbTabHidden(i1) ? nfbNearestKeptAbs(i1, total) : i1;
    // At rest, the bar itself knows which tab is selected, and that is what the
    // reader is looking at. Deriving the answer from the pager is only needed
    // while a swipe is in flight, between two tabs.
    if (fabs(f - (CGFloat)llround(f)) < 0.02) {
        NSArray<NSIndexPath*>* picked = cv.indexPathsForSelectedItems;
        NSIndexPath* chosen = picked.count == 1 ? picked.firstObject : nil;
        if (chosen && !nfbTabHidden(chosen.item)) {
            abs0 = chosen.item;
            abs1 = chosen.item;
            t = 0.0;
        }
    }

    CGRect f0 = CGRectZero, f1 = CGRectZero;
    BOOL have0 = NO, have1 = NO;
    for (UICollectionViewCell* cell in cv.visibleCells) {
        NSIndexPath* ip = [cv indexPathForCell:cell];
        if (!ip) { continue; }
        if (ip.item == abs0) {
            f0 = [root convertRect:cell.frame fromView:cell.superview];
            have0 = YES;
        }
        if (ip.item == abs1) {
            f1 = [root convertRect:cell.frame fromView:cell.superview];
            have1 = YES;
        }
    }
    if (!have0 && !have1) { return; }
    if (!have0) { f0 = f1; }
    if (!have1) { f1 = f0; }
    CGFloat c0 = f0.origin.x + f0.size.width / 2.0;
    CGFloat c1 = f1.origin.x + f1.size.width / 2.0;
    CGFloat centreInRoot = c0 + (c1 - c0) * t;
    CGFloat width = f0.size.width + (f1.size.width - f0.size.width) * t;
    if (width < 40.0) { width = 40.0; }
    CGRect local = hl.frame;
    CGPoint centreInSuper =
        [hl.superview convertPoint:CGPointMake(centreInRoot, 0) fromView:root];
    local.origin.x = centreInSuper.x - width / 2.0;
    local.size.width = width;
    gNFBSettingUnderline = YES;
    [UIView performWithoutAnimation:^{ hl.frame = local; }];
    gNFBSettingUnderline = NO;

}

// MARK: - pager <-> mask sync (defined before use)

// One reloadData when the hidden set changes, so the page set matches the
// toggles immediately (requirement: toggling a tab recentres the bar AND
// updates the pages on return to Search). Idempotent: gNFBAppliedMaskBits is
// updated first, so the filter's delayed re-assertions do not re-trigger it.
static void nfbSyncPagerToMask(void) {
    UICollectionView* cv = gNFBPagerCV;
    if (!cv || !nfbPagerScopeOK(cv)) { return; }
    CGFloat pw = cv.bounds.size.width;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    if (pw >= 1.0 && total >= 1) {
        NSInteger page = (NSInteger)llround(cv.contentOffset.x / pw);
        if (page >= 0 && page <= total - 1 && nfbTabHidden(page)) {
            NSInteger kept = nfbNearestKeptAbs(page, total);
            if (kept >= 0 && kept <= total - 1) {
                gNFBSelfNav = YES;
                [cv setContentOffset:CGPointMake(kept * pw, 0) animated:NO];
                gNFBSelfNav = NO;
            }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [gNFBBarCV setNeedsLayout];
    });
}

// Adopts the pager once the bar is provably live, and steps off a page whose
// tab is hidden so the reader never starts on one.
static void nfbCapturePagerAndRemap(UICollectionView* candidate) {
    if (!candidate) { return; }
    NSInteger total = gNFBPagerCandidateTotal ?: kNFBTabCount;
    gNFBPagerCV = candidate;
    gNFBPagerTotal = total;
    CGFloat pw = candidate.bounds.size.width;
    if (pw >= 1.0) {
        NSInteger page = (NSInteger)llround(candidate.contentOffset.x / pw);
        if (page < 0) { page = 0; }
        if (page > total - 1) { page = total - 1; }
        if (nfbTabHidden(page)) {
            NSInteger kept = nfbNearestKeptAbs(page, total);
            if (kept >= 0 && kept <= total - 1) {
                gNFBSelfNav = YES;
                [candidate setContentOffset:CGPointMake(kept * pw, 0) animated:NO];
                gNFBSelfNav = NO;
            }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [gNFBBarCV setNeedsLayout];
    });
}

// MARK: - bar filter (proven; unchanged behaviour) + mask-change detection

static void nfbApplyTabFilter(UIView* bar, UICollectionView* cv) {
    NSArray* cells = [cv.visibleCells sortedArrayUsingComparator:
        ^NSComparisonResult(UICollectionViewCell* a, UICollectionViewCell* b) {
            return [@([cv indexPathForCell:a].item)
                    compare:@([cv indexPathForCell:b].item)];
        }];
    if (cells.count == 0) { return; }

    CGFloat leading = CGFLOAT_MAX;
    CGFloat spacing = 0.0;
    UICollectionViewCell* prevAny = nil;
    for (UICollectionViewCell* c in cells) {
        leading = MIN(leading, c.frame.origin.x);
        if (prevAny && spacing == 0.0) {
            CGFloat gap = c.frame.origin.x
                        - (prevAny.frame.origin.x + prevAny.frame.size.width);
            if (gap > 0.0 && gap < 40.0) { spacing = gap; }
        }
        prevAny = c;
    }
    if (leading == CGFLOAT_MAX) { leading = 0.0; }

    CGFloat keptWidth = 0.0;
    NSInteger keptCount = 0;
    for (UICollectionViewCell* cell in cells) {
        NSIndexPath* ip = [cv indexPathForCell:cell];
        if (!nfbTabHidden(ip ? ip.item : -1)) {
            keptWidth += cell.frame.size.width;
            keptCount++;
        }
    }
    if (keptCount > 1) { keptWidth += spacing * (keptCount - 1); }

    CGFloat cursor = (cv.bounds.size.width - keptWidth) / 2.0;
    if (cursor < leading) { cursor = leading; }

    for (UICollectionViewCell* cell in cells) {
        NSIndexPath* ip = [cv indexPathForCell:cell];
        NSInteger idx = ip ? ip.item : -1;
        if (nfbTabHidden(idx)) {
            CGRect f = cell.frame;
            f.origin.x = cursor;
            f.size.width = 0.0;
            cell.frame = f;
            cell.hidden = YES;
        } else {
            CGRect f = cell.frame;
            f.origin.x = cursor;
            cell.frame = f;
            cell.hidden = NO;
            cursor += f.size.width + spacing;
        }
    }

    // Underline: pure function of the pager offset — position AND width —
    // applied on every layout pass (replaces the old orphan-only rescue,
    // which never fired when the natively-placed underline happened to
    // overlap the WRONG kept cell).
    nfbPositionUnderline(bar, cv);

    // The bar's inner collection is the anchor for the persistent filter hook.
    gNFBBarCV = cv;

    // The bar is provably live right here, so a candidate remembered before it
    // existed can now be adopted.
    if (!gNFBPagerCV) {
        UICollectionView* cand = gNFBPagerCandidate;
        if (cand && cand != cv && bar.window != nil
            && cand.window == bar.window) {
            nfbCapturePagerAndRemap(cand);
            gNFBAppliedMaskBits = nfbMaskBits();
        }
    }

    // Mask changed since the pager last matched it -> one reload, recorded
    // FIRST so the delayed re-assertions of this same filter stay no-ops.
    NSUInteger bits = nfbMaskBits();
    if (bits != gNFBAppliedMaskBits) {
        gNFBAppliedMaskBits = bits;
        nfbSyncPagerToMask();
    }
}

// MARK: - hooks: the bar (visual filter, unchanged)

%hook _TtC10TFNUISwift19SegmentedTabBarView

- (void)layoutSubviews {
    %orig;
    static BOOL probeOnce = NO;
    if (!probeOnce) {
        probeOnce = YES;
        NFBDebugLog(@"[p21] OLD segmented bar layoutSubviews FIRED | granular=%d | isExploreBar=%d",
                    nfbGranularActive(), nfbIsExploreBar((UIView*)self));
    }

    if (!nfbGranularActive()) { return; }
    if (!nfbIsExploreBar((UIView*)self)) { return; }

    UICollectionView* cv = nfbFindCollection((UIView*)self, 0);
    if (!cv) { return; }

    nfbApplyTabFilter((UIView*)self, cv);

    __weak UIView* wself = (UIView*)self;
    __weak UICollectionView* wcv = cv;
    for (NSNumber* ms in @[ @16, @50, @120, @250 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(ms.intValue * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (wself && wcv && nfbGranularActive()) {
                nfbApplyTabFilter(wself, wcv);
            }
        });
    }
}

// A tap on a tab. The callback is an ObjC protocol method, so it is
// interceptable on this Swift class; it is guarded to the Explore bar's own
// collection and everything else passes through untouched.
- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    UIView* root = gNFBExploreBar;
    UICollectionView* barCV = root ? nfbFindCollection(root, 0) : nil;
    UICollectionView* pager = gNFBPagerCV;
    if (!nfbGranularActive() || !barCV || collectionView != barCV || !pager) {
        %orig;
        return;
    }
    // The cell's index is the page's index, so the app's own navigation lands
    // on the right page and carries the bar's bookkeeping with it — which is
    // what puts the bold label and its icon on the tab that was tapped.
    %orig;
}

%end

// Same bridge on the segmented controller, in case the bar collection's
// delegate is the controller rather than the bar view on this build. Only one
// of the two receives the live callback; the other stays a silent no-op.
%hook _TtC10TFNUISwift23SegmentedViewController

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    UIView* root = gNFBExploreBar;
    UICollectionView* barCV = root ? nfbFindCollection(root, 0) : nil;
    UICollectionView* pager = gNFBPagerCV;
    if (!nfbGranularActive() || !barCV || collectionView != barCV || !pager) {
        %orig;
        return;
    }
    // Cell index and page index are the same number, so the app's own
    // navigation lands on the right page and carries the bar's own styling
    // with it.
    %orig;
}

%end

// MARK: - hooks: the pager

%hook _TtC10TFNUISwift20PagingViewController

// The collection asks its data source how many pages exist. The answer is left
// alone; this is where the pager collection and its page count are captured,
// the argument being the pager's collection view.
- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
    NSInteger n = %orig;
    if (!nfbGranularActive()) { return n; }
    if (![collectionView isKindOfClass:[UICollectionView class]]) { return n; }
    // Remember the candidate on EVERY pass (startup-order fix): a paging,
    // multi-item collection served by this controller IS a tab pager. The
    // bar's filter performs the capture once the bar is provably live.
    if (collectionView.pagingEnabled && n >= 2) {
        gNFBPagerCandidate = collectionView;
        gNFBPagerCandidateTotal = n;
    }
    // Once captured, the pager keeps that identity for its whole life: the
    // bar's window is never re-tested, so a transient weak-nil there cannot
    // change what this collection is taken to be mid-session.
    if (collectionView != gNFBPagerCV) {
        if (!nfbPagerScopeOK(collectionView)) { return n; }
        gNFBPagerCV = collectionView;
    }
    gNFBPagerTotal = n;
    // The pager keeps ALL its pages. Handing it the kept count is what put its
    // page indices in a different space from the bar's cell indices, and every
    // misplacement since — the underline, the bold label — came from bridging
    // those two spaces. With the counts equal, page index IS cell index IS
    // absolute index, and Twitter's own bar styles the right tab with no help.
    // Hidden pages are simply never landed on: see the drag handler below.
    return n;
}

// Underline ticks. Bar layout passes stop before the fine end of a
// deceleration, which parks the glide short of the target, so the underline is
// placed again on every offset change and once more when any gesture or
// animation ends.
- (void)scrollViewDidScroll:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
}

// The only thing left to enforce: a swipe never comes to rest on a hidden tab.
// UIKit asks the delegate where the gesture should land, and that answer is
// moved to the nearest kept page — in the direction the finger was going, so a
// flick past a hidden tab carries on instead of bouncing back.
- (void)scrollViewWillEndDragging:(id)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(CGPoint*)target {
    %orig;
    if (!nfbGranularActive() || (UICollectionView*)scrollView != gNFBPagerCV) {
        return;
    }
    UICollectionView* pager = gNFBPagerCV;
    CGFloat pw = pager.bounds.size.width;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    if (pw < 1.0 || !target) {
        return;
    }
    NSInteger wanted = (NSInteger)llround(target->x / pw);
    if (wanted < 0) { wanted = 0; }
    if (wanted > total - 1) { wanted = total - 1; }
    if (!nfbTabHidden(wanted)) {
        return;
    }
    NSInteger step = (velocity.x < 0) ? -1 : 1;
    NSInteger probe = wanted;
    while (probe >= 0 && probe <= total - 1 && nfbTabHidden(probe)) {
        probe += step;
    }
    if (probe < 0 || probe > total - 1) {
        probe = nfbNearestKeptAbs(wanted, total);
    }
    if (probe >= 0 && probe <= total - 1) {
        target->x = probe * pw;
    }
}

- (void)scrollViewDidEndDecelerating:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
}

- (void)scrollViewDidEndScrollingAnimation:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
}

%end

// MARK: - 12.21: the same three classes, renamed with a Legacy prefix
//
// Twitter 12.21 renamed SegmentedTabBarView, SegmentedViewController and
// PagingViewController with a Legacy prefix and shipped no ObjC successor: the
// new Explore bar is most likely SwiftUI. The blocks below are the same bodies
// bound to the new names, so whatever screen still uses the legacy bar keeps
// working. A hook on a class that is absent from the running build attaches to
// nothing, which is why both sets can coexist.

%hook _TtC10TFNUISwift25LegacySegmentedTabBarView

- (void)layoutSubviews {
    %orig;
    static BOOL probeOnce = NO;
    if (!probeOnce) {
        probeOnce = YES;
        NFBDebugLog(@"[p21] LEGACY segmented bar layoutSubviews FIRED | granular=%d | isExploreBar=%d",
                    nfbGranularActive(), nfbIsExploreBar((UIView*)self));
    }

    if (!nfbGranularActive()) { return; }
    if (!nfbIsExploreBar((UIView*)self)) { return; }

    UICollectionView* cv = nfbFindCollection((UIView*)self, 0);
    if (!cv) { return; }

    nfbApplyTabFilter((UIView*)self, cv);

    __weak UIView* wself = (UIView*)self;
    __weak UICollectionView* wcv = cv;
    for (NSNumber* ms in @[ @16, @50, @120, @250 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(ms.intValue * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (wself && wcv && nfbGranularActive()) {
                nfbApplyTabFilter(wself, wcv);
            }
        });
    }
}

// A tap on a tab. The callback is an ObjC protocol method, so it is
// interceptable on this Swift class; it is guarded to the Explore bar's own
// collection and everything else passes through untouched.
- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    UIView* root = gNFBExploreBar;
    UICollectionView* barCV = root ? nfbFindCollection(root, 0) : nil;
    UICollectionView* pager = gNFBPagerCV;
    if (!nfbGranularActive() || !barCV || collectionView != barCV || !pager) {
        %orig;
        return;
    }
    // The cell's index is the page's index, so the app's own navigation lands
    // on the right page and carries the bar's bookkeeping with it — which is
    // what puts the bold label and its icon on the tab that was tapped.
    %orig;
}

%end

%hook _TtC10TFNUISwift29LegacySegmentedViewController

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    UIView* root = gNFBExploreBar;
    UICollectionView* barCV = root ? nfbFindCollection(root, 0) : nil;
    UICollectionView* pager = gNFBPagerCV;
    if (!nfbGranularActive() || !barCV || collectionView != barCV || !pager) {
        %orig;
        return;
    }
    // Cell index and page index are the same number, so the app's own
    // navigation lands on the right page and carries the bar's own styling
    // with it.
    %orig;
}

%end

%hook _TtC10TFNUISwift26LegacyPagingViewController

// The collection asks its data source how many pages exist. The answer is left
// alone; this is where the pager collection and its page count are captured,
// the argument being the pager's collection view.
- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
    NSInteger n = %orig;
    if (!nfbGranularActive()) { return n; }
    if (![collectionView isKindOfClass:[UICollectionView class]]) { return n; }
    // Remember the candidate on EVERY pass (startup-order fix): a paging,
    // multi-item collection served by this controller IS a tab pager. The
    // bar's filter performs the capture once the bar is provably live.
    if (collectionView.pagingEnabled && n >= 2) {
        gNFBPagerCandidate = collectionView;
        gNFBPagerCandidateTotal = n;
    }
    // Once captured, the pager keeps that identity for its whole life: the
    // bar's window is never re-tested, so a transient weak-nil there cannot
    // change what this collection is taken to be mid-session.
    if (collectionView != gNFBPagerCV) {
        if (!nfbPagerScopeOK(collectionView)) { return n; }
        gNFBPagerCV = collectionView;
    }
    gNFBPagerTotal = n;
    // The pager keeps ALL its pages. Handing it the kept count is what put its
    // page indices in a different space from the bar's cell indices, and every
    // misplacement since — the underline, the bold label — came from bridging
    // those two spaces. With the counts equal, page index IS cell index IS
    // absolute index, and Twitter's own bar styles the right tab with no help.
    // Hidden pages are simply never landed on: see the drag handler below.
    return n;
}

// Underline ticks. Bar layout passes stop before the fine end of a
// deceleration, which parks the glide short of the target, so the underline is
// placed again on every offset change and once more when any gesture or
// animation ends.
- (void)scrollViewDidScroll:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
}

// The only thing left to enforce: a swipe never comes to rest on a hidden tab.
// UIKit asks the delegate where the gesture should land, and that answer is
// moved to the nearest kept page — in the direction the finger was going, so a
// flick past a hidden tab carries on instead of bouncing back.
- (void)scrollViewWillEndDragging:(id)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(CGPoint*)target {
    %orig;
    if (!nfbGranularActive() || (UICollectionView*)scrollView != gNFBPagerCV) {
        return;
    }
    UICollectionView* pager = gNFBPagerCV;
    CGFloat pw = pager.bounds.size.width;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    if (pw < 1.0 || !target) {
        return;
    }
    NSInteger wanted = (NSInteger)llround(target->x / pw);
    if (wanted < 0) { wanted = 0; }
    if (wanted > total - 1) { wanted = total - 1; }
    if (!nfbTabHidden(wanted)) {
        return;
    }
    NSInteger step = (velocity.x < 0) ? -1 : 1;
    NSInteger probe = wanted;
    while (probe >= 0 && probe <= total - 1 && nfbTabHidden(probe)) {
        probe += step;
    }
    if (probe < 0 || probe > total - 1) {
        probe = nfbNearestKeptAbs(wanted, total);
    }
    if (probe >= 0 && probe <= total - 1) {
        target->x = probe * pw;
    }
}

- (void)scrollViewDidEndDecelerating:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
}

- (void)scrollViewDidEndScrollingAnimation:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
}

%end

// MARK: - hidden pages are never a destination
//
// A programmatic navigation can still aim at a tab the reader has hidden —
// from a deep link, a restored state, or the app's own bookkeeping. The two
// guards below redirect such a target to the nearest visible tab. Both cost
// one pointer comparison for every other scroll view in the app.


%hook UICollectionView

// The bar's inner collection re-lays its cells to their native positions on
// its own layout passes, and the outer bar view's layoutSubviews does not fire
// then, so the packed row is re-applied after every layout pass of that one
// collection. The identity guard comes first: one pointer comparison for every
// other collection in the app.
- (void)layoutSubviews {
    %orig;
    // TEMPORARY probe for 12.21: the first three collections seen while a bar
    // is known, with the chain above them, so a SwiftUI host shows its name.
    static NSInteger probeCalls = 0;
    if (probeCalls < 3 && gNFBExploreBar && nfbGranularActive()) {
        probeCalls++;
        NSMutableArray* chain = [NSMutableArray array];
        UIView* up = ((UIView*)self).superview;
        while (up && chain.count < 5) {
            [chain addObject:NSStringFromClass([up class])];
            up = up.superview;
        }
        NFBDebugLog(@"[p21] collection #%ld | isBarCV=%d isExploreBar=%d | above: %@",
                    (long)probeCalls, (UICollectionView*)self == gNFBBarCV,
                    nfbIsExploreBar((UIView*)self), [chain componentsJoinedByString:@" < "]);
    }
    if ((UICollectionView*)self != gNFBBarCV || gNFBInBarFilter
        || !nfbGranularActive()) {
        return;
    }
    UIView* root = gNFBExploreBar;
    if (!root) { return; }
    gNFBInBarFilter = YES;
    nfbApplyTabFilter(root, (UICollectionView*)self);
    gNFBInBarFilter = NO;
}

// A programmatic jump to a hidden tab lands on the nearest visible one
// instead. Indices are absolute on both sides, so nothing else is touched.
- (void)scrollToItemAtIndexPath:(NSIndexPath*)indexPath
               atScrollPosition:(NSUInteger)scrollPosition
                       animated:(BOOL)animated {
    if ((UICollectionView*)self != gNFBPagerCV || gNFBSelfNav
        || !nfbGranularActive() || gNFBPagerTotal < 1
        || !nfbTabHidden(indexPath.item)) {
        %orig;
        return;
    }
    NSInteger kept = nfbNearestKeptAbs(indexPath.item, gNFBPagerTotal);
    if (kept < 0 || kept > gNFBPagerTotal - 1) {
        %orig;
        return;
    }
    %orig([NSIndexPath indexPathForItem:kept inSection:indexPath.section],
          scrollPosition, animated);
}

%end

%hook UIScrollView

// The same redirection for an animated scroll expressed as an offset: a page
// that resolves to a hidden tab is replaced by the nearest visible one.
- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if ((UIScrollView*)self != (UIScrollView*)gNFBPagerCV || gNFBSelfNav
        || !animated || !nfbGranularActive() || gNFBPagerTotal < 1) {
        %orig;
        return;
    }
    CGFloat pw = self.bounds.size.width;
    if (pw < 1.0) {
        %orig;
        return;
    }
    NSInteger page = (NSInteger)llround(contentOffset.x / pw);
    BOOL exact = fabs(contentOffset.x - page * pw) < 1.0 && page >= 0;
    if (!exact || !nfbTabHidden(page)) {
        %orig;
        return;
    }
    NSInteger kept = nfbNearestKeptAbs(page, gNFBPagerTotal);
    if (kept < 0 || kept > gNFBPagerTotal - 1) {
        %orig;
        return;
    }
    %orig(CGPointMake(kept * pw, contentOffset.y), animated);
}

%end

// MARK: - underline animation squelch
//
// The bar animates the underline toward the cell frames of its own layout,
// which are not the packed ones installed here, so those animations are
// dropped. The placement above is a dead set inside performWithoutAnimation
// and never enters here. Identity-guarded: one pointer comparison for every
// other layer in the app.
%hook CALayer

- (void)addAnimation:(id)anim forKey:(id)key {
    if ((CALayer*)self == gNFBHighlightLayer && nfbGranularActive()) {
        return;
    }
    %orig;
}

// A write with no animation escapes the drop above and can teleport the
// underline to a position between tabs, with no further layout pass at rest to
// repair it. Every position and bounds write on this one layer is therefore
// accounted for: foreign ones are dropped, the flagged ones from the placement
// above pass through. Identity first — one pointer comparison per call for the
// rest of the app.
- (void)setPosition:(CGPoint)position {
    if ((CALayer*)self == gNFBHighlightLayer && nfbGranularActive()
        && !gNFBSettingUnderline) {
        return;
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
    if ((CALayer*)self == gNFBHighlightLayer && nfbGranularActive()
        && !gNFBSettingUnderline) {
        return;
    }
    %orig;
}

%end
