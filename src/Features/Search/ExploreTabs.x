// Granular Explore tabs: hides the chosen tabs from the segmented bar, packs the
// survivors, places the underline itself and keeps the pager off hidden pages.
// Keys hide_tab_* map to indices 0-4; ON hides; unknown indices are kept.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import <QuartzCore/QuartzCore.h>

static NSString* const kPFBTabKeys[] = {
    @"hide_tab_foryou",
    @"hide_tab_trending",
    @"hide_tab_news",
    @"hide_tab_sports",
    @"hide_tab_entertainment",
};
static const NSInteger kPFBTabCount = 5;

// MARK: - shared predicates

static BOOL pfbTabHidden(NSInteger idx) {
    if (idx < 0 || idx >= kPFBTabCount) { return NO; }
    return [PFBSettings boolForKey:kPFBTabKeys[idx]];
}

static BOOL pfbAnyTabHidden(void) {
    for (NSInteger i = 0; i < kPFBTabCount; i++) {
        if ([PFBSettings boolForKey:kPFBTabKeys[i]]) { return YES; }
    }
    return NO;
}

// The two modes are asked for, not inferred: each has its own switch, and the
// settings screen refuses to strike the last kept tab, so an empty bar cannot be
// reached.
BOOL pfbShouldHideAllTrends(void) {
    return [PFBSettings boolForKey:@"hide_explore_all"];
}

static BOOL pfbGranularActive(void) {
    return ![PFBSettings boolForKey:@"hide_explore_all"]
        && [PFBSettings boolForKey:@"choose_explore_tabs"]
        && pfbAnyTabHidden();
}

// MARK: - tab mask helpers

// Nearest kept absolute index to `cur`, the lower one first at equal distance;
// 0 when no other tab is kept.
static NSInteger pfbNearestKeptAbs(NSInteger cur, NSInteger total) {
    for (NSInteger d = 1; d < total + 1; d++) {
        if (cur - d >= 0 && !pfbTabHidden(cur - d)) { return cur - d; }
        if (cur + d < total && !pfbTabHidden(cur + d)) { return cur + d; }
    }
    return 0;
}

// Bitmask of the current hidden set — cheap change detection.
static NSUInteger pfbMaskBits(void) {
    NSUInteger bits = 0;
    for (NSInteger i = 0; i < kPFBTabCount; i++) {
        if (pfbTabHidden(i)) { bits |= (1u << i); }
    }
    return bits;
}

// MARK: - Explore-bar identity + pager state

static __weak UIView* gPFBExploreBar = nil;          // the Explore accessory view
static __weak UICollectionView* gPFBPagerCV = nil;   // the Explore pager collection
static NSInteger gPFBPagerTotal = 0;                 // absolute page count (%orig)
// The data source can be interrogated before the bar exists, leaving the scope
// check with nothing to answer. Any paging, multi-item collection is remembered as
// a candidate, and the bar's filter adopts it once it runs with a live bar.
static __weak UICollectionView* gPFBPagerCandidate = nil;
static NSInteger gPFBPagerCandidateTotal = 0;
static __weak UICollectionView* gPFBBarCV = nil;     // the bar's inner collection
static __weak CALayer* gPFBHighlightLayer = nil;     // underline layer (lockdown)
static BOOL gPFBSettingUnderline = NO;               // the tweak is setting the underline
static BOOL gPFBInBarFilter = NO;                    // re-entrancy guard
static BOOL gPFBSelfNav = NO;          // a pager move started by the tweak
static NSUInteger gPFBAppliedMaskBits = 0xFFFF;   // last mask synced to the pager

void pfbNoteExploreAccessoryView(UIView* v) {
    gPFBExploreBar = v;
    // The accessory can arrive after the segmented bar has laid itself out, and
    // the bar only adopts its collection from layoutSubviews. Asking for a layout
    // pass here makes the order irrelevant.
    if (v) {
        Class legacyBar = NSClassFromString(@"_TtC10TFNUISwift25LegacySegmentedTabBarView");
        PFBEnumerateSubviewsRecursively(v, ^(UIView* sub) {
          if (legacyBar && [sub isKindOfClass:legacyBar]) {
              [sub setNeedsLayout];
          }
        });
        if (legacyBar && [v isKindOfClass:legacyBar]) {
            [v setNeedsLayout];
        }
    }
}

static BOOL pfbIsExploreBar(UIView* bar) {
    UIView* root = gPFBExploreBar;
    if (!root || !bar) { return NO; }
    return (bar == root) || [bar isDescendantOfView:root];
}

// MARK: - view helpers

static UICollectionView* pfbFindCollection(UIView* v, int depth) {
    if (!v || depth > 6) { return nil; }
    if ([v isKindOfClass:[UICollectionView class]]) {
        return (UICollectionView*)v;
    }
    for (UIView* s in v.subviews) {
        UICollectionView* found = pfbFindCollection(s, depth + 1);
        if (found) { return found; }
    }
    return nil;
}

static UIView* pfbFindHighlightBar(UIView* v, int depth) {
    if (!v || depth > 6) { return nil; }
    NSString* cls = NSStringFromClass([v class]);
    if ([cls rangeOfString:@"SegmentedHighlightBarView"].location != NSNotFound) {
        return v;
    }
    for (UIView* s in v.subviews) {
        UIView* found = pfbFindHighlightBar(s, depth + 1);
        if (found) { return found; }
    }
    return nil;
}

// Whether the Explore bar is on screen in the same window as this scroll view.
// The accessory bar lives in the navigation chrome, and off-screen tabs have a
// nil window, so Home's pager of the same class does not pass.
static BOOL pfbPagerScopeOK(UIScrollView* sv) {
    UIView* root = gPFBExploreBar;
    if (!root || !sv) { return NO; }
    return root.window != nil && root.window == sv.window;
}

// The underline is placed here: position and width are interpolated between the
// packed cells of the two pages around the current offset, without animation, on
// every bar layout pass. Native animations are dropped by the CALayer hook below.
static void pfbPositionUnderline(UIView* root, UICollectionView* cv) {
    UICollectionView* pager = gPFBPagerCV;
    if (!root || !cv || !pager) { return; }
    UIView* hl = pfbFindHighlightBar(root, 0);
    if (!hl) { return; }
    gPFBHighlightLayer = hl.layer;
    CGFloat pw = pager.bounds.size.width;
    if (pw < 1.0) { return; }
    NSInteger total = gPFBPagerTotal ?: kPFBTabCount;
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
    NSInteger abs0 = pfbTabHidden(i0) ? pfbNearestKeptAbs(i0, total) : i0;
    NSInteger abs1 = pfbTabHidden(i1) ? pfbNearestKeptAbs(i1, total) : i1;
    // At rest, the bar itself knows which tab is selected, and that is what the
    // reader is looking at. Deriving the answer from the pager is only needed
    // while a swipe is in flight, between two tabs.
    if (fabs(f - (CGFloat)llround(f)) < 0.02) {
        NSArray<NSIndexPath*>* picked = cv.indexPathsForSelectedItems;
        NSIndexPath* chosen = picked.count == 1 ? picked.firstObject : nil;
        if (chosen && !pfbTabHidden(chosen.item)) {
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
    gPFBSettingUnderline = YES;
    [UIView performWithoutAnimation:^{ hl.frame = local; }];
    gPFBSettingUnderline = NO;

}

// MARK: - pager <-> mask sync

// Runs when the hidden set differs from the last one synced: a pager showing a page
// now hidden moves to the nearest kept page, and the bar is laid out again 50 ms later.
static void pfbSyncPagerToMask(void) {
    UICollectionView* cv = gPFBPagerCV;
    if (!cv || !pfbPagerScopeOK(cv)) { return; }
    CGFloat pw = cv.bounds.size.width;
    NSInteger total = gPFBPagerTotal ?: kPFBTabCount;
    if (pw >= 1.0 && total >= 1) {
        NSInteger page = (NSInteger)llround(cv.contentOffset.x / pw);
        if (page >= 0 && page <= total - 1 && pfbTabHidden(page)) {
            NSInteger kept = pfbNearestKeptAbs(page, total);
            if (kept >= 0 && kept <= total - 1) {
                gPFBSelfNav = YES;
                [cv setContentOffset:CGPointMake(kept * pw, 0) animated:NO];
                gPFBSelfNav = NO;
            }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [gPFBBarCV setNeedsLayout];
    });
}

// Adopts the pager once the bar is provably live, and steps off a page whose
// tab is hidden so a session never starts on one.
static void pfbCapturePagerAndRemap(UICollectionView* candidate) {
    if (!candidate) { return; }
    NSInteger total = gPFBPagerCandidateTotal ?: kPFBTabCount;
    gPFBPagerCV = candidate;
    gPFBPagerTotal = total;
    CGFloat pw = candidate.bounds.size.width;
    if (pw >= 1.0) {
        NSInteger page = (NSInteger)llround(candidate.contentOffset.x / pw);
        if (page < 0) { page = 0; }
        if (page > total - 1) { page = total - 1; }
        if (pfbTabHidden(page)) {
            NSInteger kept = pfbNearestKeptAbs(page, total);
            if (kept >= 0 && kept <= total - 1) {
                gPFBSelfNav = YES;
                [candidate setContentOffset:CGPointMake(kept * pw, 0) animated:NO];
                gPFBSelfNav = NO;
            }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [gPFBBarCV setNeedsLayout];
    });
}

// MARK: - bar filter + mask-change detection

static void pfbApplyTabFilter(UIView* bar, UICollectionView* cv) {
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
        if (!pfbTabHidden(ip ? ip.item : -1)) {
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
        if (pfbTabHidden(idx)) {
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

    // Underline: placed from the pager offset, or from the bar's selection at rest,
    // on every layout pass.
    pfbPositionUnderline(bar, cv);

    // The bar's inner collection is the anchor for the persistent filter hook.
    gPFBBarCV = cv;

    // The bar is provably live right here, so a candidate remembered before it
    // existed can now be adopted.
    if (!gPFBPagerCV) {
        UICollectionView* cand = gPFBPagerCandidate;
        if (cand && cand != cv && bar.window != nil
            && cand.window == bar.window) {
            pfbCapturePagerAndRemap(cand);
            gPFBAppliedMaskBits = pfbMaskBits();
        }
    }

    // Mask changed since the pager last matched it: one sync, recorded first so
    // the delayed re-runs of this filter do not repeat it.
    NSUInteger bits = pfbMaskBits();
    if (bits != gPFBAppliedMaskBits) {
        gPFBAppliedMaskBits = bits;
        pfbSyncPagerToMask();
    }
}

// MARK: - hooks: the bar, its controller and the pager

// These two classes carry a Legacy prefix; the hooks bind to those names.

%hook _TtC10TFNUISwift25LegacySegmentedTabBarView

- (void)layoutSubviews {
    %orig;

    if (!pfbGranularActive()) {
        if (PFBCompatNeedsObservation(PFBCompat_choose_explore_tabs) &&
            pfbIsExploreBar((UIView*)self)) {
            PFBCOMPAT_OBSERVE(PFBCompat_choose_explore_tabs, @"Explore tabs found");
        }
        return;
    }
    if (!pfbIsExploreBar((UIView*)self)) { return; }

    UICollectionView* cv = pfbFindCollection((UIView*)self, 0);
    if (!cv) { return; }

    pfbApplyTabFilter((UIView*)self, cv);
    PFBCOMPAT_ACTION(PFBCompat_choose_explore_tabs, @"chosen tabs kept");

    __weak UIView* wself = (UIView*)self;
    __weak UICollectionView* wcv = cv;
    for (NSNumber* ms in @[ @16, @50, @120, @250 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(ms.intValue * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (wself && wcv && pfbGranularActive()) {
                pfbApplyTabFilter(wself, wcv);
            }
        });
    }
}

%end

// The first two view controllers up the responder chain of a view, by class name.
static NSString* pfbOwners(UIView* view) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (UIResponder* responder = view; responder && names.count < 2; responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            [names addObject:NSStringFromClass([responder class])];
        }
    }
    return names.count ? [names componentsJoinedByString:@" in "] : @"none";
}

// Once per launch and per owner, while the journal records: a second pager taken for
// Explore's, with the screens that own it and the tab bar.
static void pfbProbePagerSwap(UICollectionView* pager, NSInteger pages) {
    static NSMutableSet<NSString*>* said;
    if (!PFBDebugIsRecording()) { return; }
    NSString* owners = pfbOwners(pager);
    said = said ?: [NSMutableSet set];
    if ([said containsObject:owners]) { return; }
    [said addObject:owners];
    PFBDebugLog(@"[explore] another pager taken as Explore's: %ld pages, owned by %@; the tab bar by %@",
                (long)pages, owners, pfbOwners(gPFBExploreBar));
}

%hook _TtC10TFNUISwift26LegacyPagingViewController

// The collection asks its data source how many pages exist. The answer is left
// alone; this is where the pager collection and its page count are captured,
// the argument being the pager's collection view.
- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
    NSInteger n = %orig;
    if (!pfbGranularActive()) { return n; }
    if (![collectionView isKindOfClass:[UICollectionView class]]) { return n; }
    // The candidate is remembered on every pass: a paging, multi-item collection
    // served by this controller is a tab pager. The bar's filter performs the
    // capture once the bar is provably live.
    if (collectionView.pagingEnabled && n >= 2) {
        gPFBPagerCandidate = collectionView;
        gPFBPagerCandidateTotal = n;
    }
    // Once captured, the pager keeps that identity for its whole life: the
    // bar's window is never re-tested, so a transient weak-nil there cannot
    // change what this collection is taken to be mid-session.
    if (collectionView != gPFBPagerCV) {
        if (!pfbPagerScopeOK(collectionView)) { return n; }
        if (gPFBPagerCV) {
            pfbProbePagerSwap(collectionView, n);
        }
        gPFBPagerCV = collectionView;
    }
    gPFBPagerTotal = n;
    // The pager keeps all its pages: handing it the kept count puts its page
    // indices in a different space from the bar's cell indices. With the counts
    // equal, page index is cell index; hidden pages are never landed on.
    return n;
}

// Underline ticks. Bar layout passes stop before the fine end of a deceleration,
// which parks the glide short of the target, so it is placed again on every offset
// change and once more when a gesture or animation ends.
- (void)scrollViewDidScroll:(id)scrollView {
    %orig;
    if (!pfbGranularActive()
        || (UICollectionView*)scrollView != gPFBPagerCV) { return; }
    pfbPositionUnderline(gPFBExploreBar, gPFBBarCV);
}

// A swipe never comes to rest on a hidden tab. UIKit asks the delegate where the
// gesture should land, and that answer is moved to the nearest kept page in the
// direction the finger was going.
- (void)scrollViewWillEndDragging:(id)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(CGPoint*)target {
    %orig;
    if (!pfbGranularActive() || (UICollectionView*)scrollView != gPFBPagerCV) {
        return;
    }
    UICollectionView* pager = gPFBPagerCV;
    CGFloat pw = pager.bounds.size.width;
    NSInteger total = gPFBPagerTotal ?: kPFBTabCount;
    if (pw < 1.0 || !target) {
        return;
    }
    NSInteger wanted = (NSInteger)llround(target->x / pw);
    if (wanted < 0) { wanted = 0; }
    if (wanted > total - 1) { wanted = total - 1; }
    if (!pfbTabHidden(wanted)) {
        return;
    }
    NSInteger step = (velocity.x < 0) ? -1 : 1;
    NSInteger probe = wanted;
    while (probe >= 0 && probe <= total - 1 && pfbTabHidden(probe)) {
        probe += step;
    }
    if (probe < 0 || probe > total - 1) {
        probe = pfbNearestKeptAbs(wanted, total);
    }
    if (probe >= 0 && probe <= total - 1) {
        target->x = probe * pw;
    }
}

- (void)scrollViewDidEndDecelerating:(id)scrollView {
    %orig;
    if (!pfbGranularActive()
        || (UICollectionView*)scrollView != gPFBPagerCV) { return; }
    pfbPositionUnderline(gPFBExploreBar, gPFBBarCV);
}

- (void)scrollViewDidEndScrollingAnimation:(id)scrollView {
    %orig;
    if (!pfbGranularActive()
        || (UICollectionView*)scrollView != gPFBPagerCV) { return; }
    pfbPositionUnderline(gPFBExploreBar, gPFBBarCV);
}

%end

// MARK: - hidden pages are never a destination

// A programmatic navigation can aim at a hidden tab, from a deep link, a restored
// state or the app's own bookkeeping. The two guards below redirect to the nearest
// visible tab, at one pointer comparison for every other scroll view.

%hook UICollectionView

// The bar's inner collection re-lays its cells to their native positions on its
// own layout passes, when the outer bar view's layoutSubviews does not fire, so
// the packed row is re-applied here. The identity guard comes first.
- (void)layoutSubviews {
    %orig;
    if ((UICollectionView*)self != gPFBBarCV || gPFBInBarFilter
        || !pfbGranularActive()) {
        return;
    }
    UIView* root = gPFBExploreBar;
    if (!root) { return; }
    gPFBInBarFilter = YES;
    pfbApplyTabFilter(root, (UICollectionView*)self);
    gPFBInBarFilter = NO;
}

// A programmatic jump to a hidden tab lands on the nearest visible one
// instead. Indices are absolute on both sides, so nothing else is touched.
- (void)scrollToItemAtIndexPath:(NSIndexPath*)indexPath
               atScrollPosition:(NSUInteger)scrollPosition
                       animated:(BOOL)animated {
    if ((UICollectionView*)self != gPFBPagerCV || gPFBSelfNav
        || !pfbGranularActive() || gPFBPagerTotal < 1
        || !pfbTabHidden(indexPath.item)) {
        %orig;
        return;
    }
    NSInteger kept = pfbNearestKeptAbs(indexPath.item, gPFBPagerTotal);
    if (kept < 0 || kept > gPFBPagerTotal - 1) {
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
    if ((UIScrollView*)self != (UIScrollView*)gPFBPagerCV || gPFBSelfNav
        || !animated || !pfbGranularActive() || gPFBPagerTotal < 1) {
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
    if (!exact || !pfbTabHidden(page)) {
        %orig;
        return;
    }
    NSInteger kept = pfbNearestKeptAbs(page, gPFBPagerTotal);
    if (kept < 0 || kept > gPFBPagerTotal - 1) {
        %orig;
        return;
    }
    %orig(CGPointMake(kept * pw, contentOffset.y), animated);
}

%end

// MARK: - underline animation squelch

// The bar animates the underline toward the cell frames of its own layout, not the
// packed ones installed here, so those animations are dropped. The placement above
// is a dead set inside performWithoutAnimation and never enters here.
%hook CALayer

- (void)addAnimation:(id)anim forKey:(id)key {
    if ((CALayer*)self == gPFBHighlightLayer && pfbGranularActive()) {
        return;
    }
    %orig;
}

// A write with no animation escapes the drop above and can leave the underline
// between tabs, with no later layout pass to repair it. Foreign writes on this one
// layer are dropped and the flagged ones pass through.
- (void)setPosition:(CGPoint)position {
    if ((CALayer*)self == gPFBHighlightLayer && pfbGranularActive()
        && !gPFBSettingUnderline) {
        return;
    }
    %orig;
}

- (void)setBounds:(CGRect)bounds {
    if ((CALayer*)self == gPFBHighlightLayer && pfbGranularActive()
        && !gPFBSettingUnderline) {
        return;
    }
    %orig;
}

%end
