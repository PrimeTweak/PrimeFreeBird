//
//  ExploreTabs.x
//  PrimeFreeBird
//
//  Granular Explore tabs — data-source remap.
//
//  Steering a 5-page pager around hidden pages (gesture rewrites, deferred
//  animations) cannot be made artifact-free, so the page set itself is
//  reduced. The pager's own data source
//  (TFNUISwift.PagingViewController — its collectionView:numberOfItemsInSection:
//  and cellForItemAtIndexPath: are ObjC protocol methods, hookable) is
//  remapped so the collection REALLY contains only the kept pages:
//
//    numberOfItemsInSection  -> kept count (N)
//    cellForItemAtIndexPath  -> remapped item translated to the ABSOLUTE tab
//                               before %orig, so each visible page mounts the
//                               right content
//
//  Consequences, by construction:
//    - contentSize = N * pageWidth: hidden pages DO NOT EXIST. No white pages,
//      no mid-swipe bounce, nothing to steer.
//    - Swiping is 100% native: UIKit's own paging against a real N-item
//      collection. Ends are REAL content edges, so edge behaviour is exactly
//      stock Twitter's.
//    - The 33 ms page-mount hitch at a boundary is stock Twitter behaviour
//      (it happens with all 5 tabs visible too); with a native deceleration it
//      reads as native.
//
//  The BAR keeps its proven visual filter (hide cell by index, pack survivors,
//  centre the row, rescue an orphaned underline). Two bridges connect the
//  bar's ABSOLUTE world to the pager's REMAPPED world:
//
//    1. TAPS: the bar's cells carry absolute indices. The delegate callback
//       collectionView:didSelectItemAtIndexPath: is intercepted on the bar /
//       segmented controller (ObjC protocol method on a Swift class — same
//       mechanism as the pager's hookable delegate methods). The tweak drives the
//       pager ourselves to the REMAPPED offset and do not forward the Swift
//       navigation, so no absolute-index scroll is ever issued. If that
//       selector is not the live path on this build, a safety net below
//       translates absolute scrolls instead (and disables itself the moment
//       the primary path is seen working).
//    2. UNDERLINE: a pure function of the pager offset — position AND width
//       interpolated between the REAL packed cells of the two pages around
//       the current offset, set dead on every bar layout pass. Measured: the
//       native follow both targets and SIZES the underline for the
//       REMAPPED-index cell (the wrong absolute cell whenever remap differs),
//       so its animations on that one layer are squelched and never fight
//       back. Glides natively during flights and taps, exact at rest, no
//       late corrections.
//
//  Setting changes (a tab toggled while Search is open underneath): the bar's
//  layoutSubviews refires on return, the filter recentres the row, and a mask
//  change triggers ONE pager reloadData (+ offset clamp) so the page set
//  matches immediately.
//
//  Two failure modes are closed structurally: (1) STARTUP ORDER — the
//  pager's data source can be interrogated before the bar exists (scope
//  unknowable); the candidate is remembered on every pass, and the bar's
//  first filter run captures it, reloads, and re-expresses the current page
//  in remapped coordinates. (2) BAR OVERWRITE — the bar's INNER collection re-lays cells
//  to native positions on its own layout passes; the filter now re-applies
//  after every such pass (identity-guarded), so the packed row cannot be
//  overwritten for more than one pass.
//
//  Per-tab key <-> index: hide_tab_foryou(0) trending(1) news(2) sports(3)
//    entertainment(4). ON = HIDE. Keys default NO. Indices beyond the known
//    five are always kept (future-proof if Twitter adds a tab).
//

#import "HookHelpers.h"
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

static BOOL nfbAllTabsHidden(void) {
    for (NSInteger i = 0; i < kNFBTabCount; i++) {
        if (![BHTSettings boolForKey:kNFBTabKeys[i]]) { return NO; }
    }
    return YES;
}

BOOL nfbShouldHideAllTrends(void) {
    if (![BHTSettings boolForKey:@"hide_trends"]) { return NO; }
    if (!nfbAnyTabHidden()) { return YES; }
    if (nfbAllTabsHidden()) { return YES; }
    return NO;
}

static BOOL nfbGranularActive(void) {
    return [BHTSettings boolForKey:@"hide_trends"]
        && nfbAnyTabHidden() && !nfbAllTabsHidden();
}

// MARK: - absolute <-> remapped index mapping (pure, defined before use)

// Number of KEPT tabs among `total` absolute slots.
static NSInteger nfbKeptCount(NSInteger total) {
    NSInteger kept = 0;
    for (NSInteger i = 0; i < total; i++) {
        if (!nfbTabHidden(i)) { kept++; }
    }
    return kept;
}

// Absolute index of the r-th kept tab. Clamps to the last kept tab.
static NSInteger nfbAbsFromRemap(NSInteger r, NSInteger total) {
    NSInteger seen = -1, lastKept = 0;
    for (NSInteger i = 0; i < total; i++) {
        if (nfbTabHidden(i)) { continue; }
        lastKept = i;
        seen++;
        if (seen == r) { return i; }
    }
    return lastKept;
}

// Remapped position of an absolute index. -1 if that tab is hidden.
static NSInteger nfbRemapFromAbs(NSInteger absIdx, NSInteger total) {
    if (nfbTabHidden(absIdx)) { return -1; }
    NSInteger r = 0;
    for (NSInteger i = 0; i < absIdx && i < total; i++) {
        if (!nfbTabHidden(i)) { r++; }
    }
    return r;
}

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
// Startup-order fix (measured failure: numberOfItems ran BEFORE the bar was
// captured -> scope false -> 5 pages forever, and the pager was never
// captured so no catch-up reload could ever fire). The data source is now
// remembered as a CANDIDATE on every pass (paging, multi-item collection),
// and the bar's own filter performs the catch-up: capture + reload + offset
// realign, the first time it runs with a live bar.
static __weak UICollectionView* gNFBPagerCandidate = nil;
static NSInteger gNFBPagerCandidateTotal = 0;
static __weak UICollectionView* gNFBBarCV = nil;     // the bar's inner collection
static __weak CALayer* gNFBHighlightLayer = nil;     // underline layer (lockdown)
static BOOL gNFBSettingUnderline = NO;               // our own underline set
static BOOL gNFBInBarFilter = NO;                    // re-entrancy guard
static BOOL gNFBSelfNav = NO;          // our own pager navigation in progress
static BOOL gNFBBarTapHookSeen = NO;   // primary tap path proven live
static NSMutableString* gNFBBarPaths = nil;   // relevé : chemins vus, dans l'ordre
static BOOL gNFBBarSelfUpdate = NO;   // notre propre appel à la barre, à ne pas retraduire

static void nfbNoteBarPath(NSString* note) {
    if (!gNFBBarPaths) { gNFBBarPaths = [NSMutableString string]; }
    if ([gNFBBarPaths rangeOfString:note].location != NSNotFound) { return; }
    if (gNFBBarPaths.length > 60) { [gNFBBarPaths setString:@""]; }
    [gNFBBarPaths appendFormat:@"%@ ", note];
}
static NSUInteger gNFBAppliedMaskBits = 0xFFFF;   // last mask synced to the pager

void nfbNoteExploreAccessoryView(UIView* v) {
    gNFBExploreBar = v;
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

// THE UNDERLINE IS the tweak's — a pure function of the pager's offset (measured:
// the native follow both TARGETS and SIZES the underline for the cell at the
// REMAPPED index — e.g. selection remap-2 highlights the hidden News cell —
// so at rest the width stayed wrong (sized for the wrong cell) and every
// settle needed a late correction). Position AND width are now interpolated
// between the REAL packed cells of the two pages around the current offset,
// and set dead (no animation) on every bar layout pass — a native-looking
// glide during flights, exact at rest, no late corrections. Native underline
// animations are squelched (CALayer hook below), so nothing fights back.
// Temporary instrumentation: the numbers this placement rests on, written on
// screen so a screenshot settles what is guesswork today — which space the
// pager is in, whether the bar marks a cell as selected, and which tab the
// calculation picked.
static void nfbUnderlineDiag(UIView* root, NSString* text) {
    UIWindow* window = root.window;
    if (!window) {
        return;
    }
    static const void* kNFBTabDiagKey = &kNFBTabDiagKey;
    UILabel* hud = objc_getAssociatedObject(window, kNFBTabDiagKey);
    if (!hud) {
        hud = [[UILabel alloc] init];
        hud.numberOfLines = 0;
        hud.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
        hud.textColor = [UIColor whiteColor];
        hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
        hud.layer.cornerRadius = 5;
        hud.clipsToBounds = YES;
        hud.userInteractionEnabled = NO;
        objc_setAssociatedObject(window, kNFBTabDiagKey, hud,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hud.superview != window) {
        [window addSubview:hud];
    }
    hud.text = text;
    CGSize fit = [hud sizeThatFits:CGSizeMake(300, 200)];
    hud.frame = CGRectMake(10, window.bounds.size.height - fit.height - 130,
                           fit.width + 12, fit.height + 8);
    [window bringSubviewToFront:hud];
}

static void nfbPositionUnderline(UIView* root, UICollectionView* cv) {
    UICollectionView* pager = gNFBPagerCV;
    if (!root || !cv || !pager) { return; }
    UIView* hl = nfbFindHighlightBar(root, 0);
    if (!hl) { return; }
    gNFBHighlightLayer = hl.layer;
    CGFloat pw = pager.bounds.size.width;
    if (pw < 1.0) { return; }
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger kept = nfbKeptCount(total);
    if (kept < 1) { return; }
    // Which space the offset is in cannot be asked of the data source: this
    // tweak answers that question itself, and always says "kept". The pages
    // actually laid out are the only honest witness — content width over page
    // width — and they still read absolute until a reload has happened.
    NSInteger laidOut = (NSInteger)llround(pager.contentSize.width / pw);
    BOOL pagerRemapped = (laidOut < 1) || (laidOut <= kept);
    NSInteger span = pagerRemapped ? kept : total;
    CGFloat f = pager.contentOffset.x / pw;
    if (f < 0) { f = 0; }
    if (f > span - 1) { f = span - 1; }
    NSInteger i0 = (NSInteger)floor(f);
    NSInteger i1 = (i0 + 1 <= span - 1) ? i0 + 1 : span - 1;
    CGFloat t = f - i0;
    NSInteger abs0 = pagerRemapped ? nfbAbsFromRemap(i0, total) : i0;
    NSInteger abs1 = pagerRemapped ? nfbAbsFromRemap(i1, total) : i1;
    // An absolute page can be one of the hidden ones mid-swipe; the underline
    // then rides the nearest tab that is actually on screen.
    if (!pagerRemapped) {
        if (nfbTabHidden(abs0)) { abs0 = nfbNearestKeptAbs(abs0, total); }
        if (nfbTabHidden(abs1)) { abs1 = nfbNearestKeptAbs(abs1, total); }
    }
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

    NSArray<NSIndexPath*>* sel = cv.indexPathsForSelectedItems;
    NSMutableString* items = [NSMutableString string];
    for (UICollectionViewCell* cell in cv.visibleCells) {
        NSIndexPath* ip = [cv indexPathForCell:cell];
        if (ip && !cell.hidden) {
            [items appendFormat:@"%ld@%.0f ", (long)ip.item,
                                CGRectGetMidX([root convertRect:cell.frame
                                                       fromView:cell.superview])];
        }
    }
    nfbUnderlineDiag(
        root,
        [NSString stringWithFormat:
                      @"pages %ld posees / %ld gardees / %ld total\noffset %.2f  espace %@\n"
                      @"selection %@  choix abs %ld\nbarre %@\ntrait %.0f l%.0f\ncellules %@",
                      (long)laidOut, (long)kept, (long)total, f,
                      pagerRemapped ? @"remappe" : @"absolu",
                      sel.count ? [NSString stringWithFormat:@"%ld", (long)sel.firstObject.item]
                                : @"aucune",
                      (long)abs0, gNFBBarPaths.length ? gNFBBarPaths : @"aucun",
                      centreInRoot, width, items]);
}

// MARK: - pager <-> mask sync (defined before use)

// One reloadData when the hidden set changes, so the page set matches the
// toggles immediately (requirement: toggling a tab recentres the bar AND
// updates the pages on return to Search). Idempotent: gNFBAppliedMaskBits is
// updated first, so the filter's delayed re-assertions do not re-trigger it.
static void nfbSyncPagerToMask(void) {
    UICollectionView* cv = gNFBPagerCV;
    if (!cv) { return; }
    if (!nfbPagerScopeOK(cv)) { return; }
    [cv reloadData];
    CGFloat pw = cv.bounds.size.width;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger kept = nfbKeptCount(total);
    if (pw >= 1.0 && kept >= 1) {
        CGFloat maxX = (kept - 1) * pw;
        if (cv.contentOffset.x > maxX + 1.0) {
            gNFBSelfNav = YES;
            [cv setContentOffset:CGPointMake(0, 0) animated:NO];
            gNFBSelfNav = NO;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        [gNFBBarCV setNeedsLayout];
    });
}

// CATCH-UP (startup-order fix): the pager was interrogated before the bar
// existed, so it still runs UNREMAPPED with all absolute pages. Capture the
// candidate now, reload so numberOfItems is asked again (and answers the kept
// count), and re-express the CURRENT absolute page as its remapped position so
// the user stays on the same content (nearest kept if that tab is hidden).
static void nfbCapturePagerAndRemap(UICollectionView* candidate) {
    if (!candidate) { return; }
    CGFloat pw = candidate.bounds.size.width;
    NSInteger total = gNFBPagerCandidateTotal ?: kNFBTabCount;
    NSInteger absBefore = 0;
    if (pw >= 1.0) {
        absBefore = (NSInteger)llround(candidate.contentOffset.x / pw);
        if (absBefore < 0) { absBefore = 0; }
        if (absBefore > total - 1) { absBefore = total - 1; }
    }
    gNFBPagerCV = candidate;
    gNFBPagerTotal = total;
    [candidate reloadData];
    if (pw >= 1.0) {
        NSInteger absTarget = nfbTabHidden(absBefore)
            ? nfbNearestKeptAbs(absBefore, total) : absBefore;
        NSInteger r = nfbRemapFromAbs(absTarget, total);
        if (r < 0) { r = 0; }
        gNFBSelfNav = YES;
        [candidate setContentOffset:CGPointMake(r * pw, 0) animated:NO];
        gNFBSelfNav = NO;
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

    // CATCH-UP (startup order, measured): the pager was interrogated before
    // the bar existed and still serves all absolute pages. The bar is provably
    // live right here — capture the candidate, reload, realign the offset.
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

// MARK: - the bar's own selection (measured: it styles the wrong tab)
//
// The relevé settled it: the pager is remapped (3 pages laid out for 3 kept),
// the bar marks no cell as selected, and at kept page 2 the underline sits on
// Sports — with the content on Sports too. What is wrong is the bold label:
// Twitter hands this bar the pager's page index and the bar uses it as a CELL
// index, so kept page 2 styles cell 2 (News) instead of cell 3 (Sports).
// Translating on the way in puts the styling back on the tab the reader is
// actually looking at.

static NSInteger nfbBarIndexIn(NSInteger index) {
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger kept = nfbKeptCount(total);
    if (!nfbGranularActive() || kept < 1 || index < 0 || index > kept - 1) {
        return index;
    }
    NSInteger abs = nfbAbsFromRemap(index, total);
    return (abs >= 0 && abs <= total - 1) ? abs : index;
}

%hook _TtC10TFNUISwift19SegmentedTabBarView

- (void)layoutSubviews {
    %orig;

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

// PRIMARY TAP BRIDGE. The bar's cells carry ABSOLUTE indices; its delegate
// callback is an ObjC protocol method, interceptable on the Swift class. When
// granular is active the tweak navigates the REMAPPED pager ourselves and swallow the
// Swift navigation (no absolute-index scroll is ever issued). Guarded to the
// Explore bar's own collection; everything else passes through untouched. If
// this selector is not implemented on this class, Logos simply installs
// nothing and the safety net below covers taps instead.
- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    UIView* root = gNFBExploreBar;
    UICollectionView* barCV = root ? nfbFindCollection(root, 0) : nil;
    UICollectionView* pager = gNFBPagerCV;
    if (!nfbGranularActive() || !barCV || collectionView != barCV || !pager) {
        %orig;
        return;
    }
    NSInteger absIdx = indexPath.item;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger r = nfbRemapFromAbs(absIdx, total);
    if (r < 0) {   // hidden cell: not tappable in practice; be safe
        %orig;
        return;
    }
    gNFBBarTapHookSeen = YES;
    CGFloat pw = pager.bounds.size.width;
    if (pw >= 1.0) {
        gNFBSelfNav = YES;
        [pager setContentOffset:CGPointMake(r * pw, 0) animated:YES];
        gNFBSelfNav = NO;
    }
    // NO %orig: the Swift absolute navigation must not run. The underline
    // glides on its own — it follows the animating offset at every layout.
}


- (void)setSelectedIndex:(NSInteger)index {
    if (gNFBBarSelfUpdate) {
        %orig;
        return;
    }
    NSInteger t = nfbBarIndexIn(index);
    nfbNoteBarPath([NSString stringWithFormat:@"sel%ld>%ld", (long)index, (long)t]);
    %orig(t);
}

- (void)selectTabAt:(NSInteger)index animated:(BOOL)animated {
    NSInteger t = nfbBarIndexIn(index);
    nfbNoteBarPath([NSString stringWithFormat:@"tab%ld>%ld", (long)index, (long)t]);
    %orig(t, animated);
}

- (void)finalizePagingToIndex:(NSInteger)index {
    NSInteger t = nfbBarIndexIn(index);
    nfbNoteBarPath([NSString stringWithFormat:@"fin%ld>%ld", (long)index, (long)t]);
    %orig(t);
}

// Swift calling its own methods does not go through objc_msgSend, so hooking
// this class's API catches nothing of what Twitter does internally — the relevé
// proved it, every one of those hooks stayed silent. What UIKit calls, though,
// is dispatched: the bar is the pager's scroll delegate, and this is where it
// restyles its labels from the offset. The offset is in the kept space and the
// labels are indexed absolutely, which is the whole misalignment. So after the
// app has had its pass, the bar is told the position again — translated, and
// through a real message send, which its Swift side does answer.
- (void)scrollViewDidScroll:(id)scrollView {
    %orig;

    UIView* bar = (UIView*)self;
    UICollectionView* pager = gNFBPagerCV;
    if (!nfbGranularActive() || !nfbIsExploreBar(bar) || !pager) {
        return;
    }
    nfbNoteBarPath(scrollView == pager ? @"scroll=pager" : @"scroll=autre");
    CGFloat pw = pager.bounds.size.width;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger kept = nfbKeptCount(total);
    if (pw < 1.0 || kept < 1) {
        return;
    }
    CGFloat f = pager.contentOffset.x / pw;
    if (f < 0) { f = 0; }
    if (f > kept - 1) { f = kept - 1; }
    NSInteger i0 = (NSInteger)floor(f);
    NSInteger i1 = (i0 + 1 <= kept - 1) ? i0 + 1 : i0;
    CGFloat t = f - i0;
    CGFloat a0 = (CGFloat)nfbAbsFromRemap(i0, total);
    CGFloat a1 = (CGFloat)nfbAbsFromRemap(i1, total);
    CGFloat absF = a0 + (a1 - a0) * t;

    gNFBBarSelfUpdate = YES;
    ((void (*)(id, SEL, double))objc_msgSend)(
        self, @selector(updateForFractionalIndex:), (double)absF);
    NSInteger settled = (NSInteger)llround(absF);
    if (fabs(absF - (CGFloat)settled) < 0.02) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(
            self, @selector(setSelectedIndex:), settled);
    }
    gNFBBarSelfUpdate = NO;
}

// The label that turns bold and grows an icon changes here, by index — the one
// path none of the others covered.
- (void)animateTabContentChangeAt:(NSInteger)index {
    NSInteger t = nfbBarIndexIn(index);
    nfbNoteBarPath([NSString stringWithFormat:@"anim%ld>%ld", (long)index, (long)t]);
    %orig(t);
}

// Takes the scroll view, not an index: nothing to translate here, only to
// record — if this is the live path, the styling is computed inside it and the
// answer lies further in.
- (void)updateForScrollOffset:(id)offset {
    nfbNoteBarPath(@"offs");
    %orig;
}

// The fractional index drives the styling mid-swipe: the two ends are
// translated and the position between them is kept.
- (void)updateForFractionalIndex:(CGFloat)index {
    if (gNFBBarSelfUpdate) {
        %orig;
        return;
    }
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger kept = nfbKeptCount(total);
    if (!nfbGranularActive() || kept < 1) {
        %orig;
        return;
    }
    CGFloat clamped = index < 0 ? 0 : (index > kept - 1 ? kept - 1 : index);
    NSInteger i0 = (NSInteger)floor(clamped);
    NSInteger i1 = (i0 + 1 <= kept - 1) ? i0 + 1 : i0;
    CGFloat t = clamped - i0;
    CGFloat a0 = (CGFloat)nfbAbsFromRemap(i0, total);
    CGFloat a1 = (CGFloat)nfbAbsFromRemap(i1, total);
    %orig(a0 + (a1 - a0) * t);
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
    NSInteger absIdx = indexPath.item;
    NSInteger total = gNFBPagerTotal ?: kNFBTabCount;
    NSInteger r = nfbRemapFromAbs(absIdx, total);
    if (r < 0) {
        %orig;
        return;
    }
    gNFBBarTapHookSeen = YES;
    CGFloat pw = pager.bounds.size.width;
    if (pw >= 1.0) {
        gNFBSelfNav = YES;
        [pager setContentOffset:CGPointMake(r * pw, 0) animated:YES];
        gNFBSelfNav = NO;
    }
    // NO %orig. Underline follows the animating offset at every layout.
}

%end

// MARK: - hooks: the pager (data-source remap + settle realign)

%hook _TtC10TFNUISwift20PagingViewController

// The collection asks its data source how many pages exist. Under granular
// filtering the Explore pager REALLY has only the kept pages. This is also
// where the pager collection and the absolute total are captured (the
// argument IS the pager's collection view).
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
    // Once captured, the pager stays remapped for its whole life — never
    // re-test the bar's window (a transient weak-nil there must not flip the
    // page count mid-session).
    if (collectionView != gNFBPagerCV) {
        if (!nfbPagerScopeOK(collectionView)) { return n; }
        gNFBPagerCV = collectionView;
    }
    gNFBPagerTotal = n;
    NSInteger kept = nfbKeptCount(n);
    return (kept >= 1) ? kept : n;
}

// Translate the remapped item to the ABSOLUTE tab before %orig, so the
// visible page mounts the right content.
- (id)collectionView:(UICollectionView*)collectionView
    cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    // Translate ONLY for the officially remapped pager: the invariant is
    // "translation active ⟺ numberOfItems answered the kept count for this
    // very collection". Anything else (including an Explore pager that raced
    // ahead of the bar and still runs unremapped) passes through untouched.
    if (!nfbGranularActive()
        || collectionView != gNFBPagerCV
        || gNFBPagerTotal < 1) {
        return %orig;
    }
    NSInteger absIdx = nfbAbsFromRemap(indexPath.item, gNFBPagerTotal);
    if (absIdx == indexPath.item) {
        return %orig;
    }
    NSIndexPath* absPath = [NSIndexPath indexPathForItem:absIdx
                                               inSection:indexPath.section];
    return %orig(collectionView, absPath);
}

// Underline ticks. Bar layout passes stop before the fine end of a
// deceleration, which parks the glide short of the target. If this class implements
// scrollViewDidScroll: the tweak gets a tick on EVERY offset change (perfect 60fps
// glide + exact landing); if it does not, Logos installs nothing and the two
// settle callbacks below still give an immediate exact
// placement the moment any gesture or animation ends.
- (void)scrollViewDidScroll:(id)scrollView {
    %orig;
    if (!nfbGranularActive()
        || (UICollectionView*)scrollView != gNFBPagerCV) { return; }
    nfbPositionUnderline(gNFBExploreBar, gNFBBarCV);
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

// MARK: - safety net (auto-disabling absolute->remap translation)
//
// Only relevant if the primary tap bridge above is NOT the live path on this
// build (its selector absent from both classes). Then the Swift tap issues an
// ABSOLUTE navigation at the pager; these guards translate it. Both hooks are
// one pointer-compare for every other scroll view in the app, and both stand
// down permanently (gNFBBarTapHookSeen) the moment the primary bridge fires.


%hook UICollectionView

// PERSISTENT BAR FILTER (measured failure: the bar's INNER collection re-lays
// its cells to their native positions on its own layout passes, overwriting
// the packed/centred row for most of the session — the outer bar view's
// layoutSubviews does not fire then). Re-apply the filter after EVERY layout
// pass of that one collection. Identity guard first: one pointer compare for
// every other collection in the app.
- (void)layoutSubviews {
    %orig;
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

- (void)scrollToItemAtIndexPath:(NSIndexPath*)indexPath
               atScrollPosition:(NSUInteger)scrollPosition
                       animated:(BOOL)animated {
    if ((UICollectionView*)self != gNFBPagerCV || gNFBSelfNav
        || gNFBBarTapHookSeen || !nfbGranularActive() || gNFBPagerTotal < 1) {
        %orig;
        return;
    }
    NSInteger kept = nfbKeptCount(gNFBPagerTotal);
    NSInteger item = indexPath.item;
    if (item > kept - 1 || nfbTabHidden(item)) {   // unmistakably ABSOLUTE
        NSInteger absIdx = nfbTabHidden(item)
            ? nfbNearestKeptAbs(item, gNFBPagerTotal) : item;
        NSInteger r = nfbRemapFromAbs(absIdx, gNFBPagerTotal);
        if (r < 0) { r = 0; }
        if (r > kept - 1) { r = kept - 1; }
        NSIndexPath* rp = [NSIndexPath indexPathForItem:r
                                              inSection:indexPath.section];
        %orig(rp, scrollPosition, animated);
        return;
    }
    %orig;
}

%end

%hook UIScrollView

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if ((UIScrollView*)self != (UIScrollView*)gNFBPagerCV || gNFBSelfNav
        || gNFBBarTapHookSeen || !animated || !nfbGranularActive()
        || gNFBPagerTotal < 1) {
        %orig;
        return;
    }
    CGFloat pw = self.bounds.size.width;
    if (pw < 1.0) {
        %orig;
        return;
    }
    NSInteger k = (NSInteger)llround(contentOffset.x / pw);
    BOOL pageExact = fabs(contentOffset.x - k * pw) < 1.0 && k >= 0;
    NSInteger kept = nfbKeptCount(gNFBPagerTotal);
    // Translate ONLY unmistakably absolute targets: a hidden tab's slot, or a
    // page beyond the remapped bounds. Ambiguous values pass through (and the
    // net stands down entirely once the primary bridge is proven live).
    if (pageExact && (nfbTabHidden(k) || k > kept - 1)) {
        NSInteger absIdx = nfbTabHidden(k)
            ? nfbNearestKeptAbs(k, gNFBPagerTotal) : k;
        NSInteger r = nfbRemapFromAbs(absIdx, gNFBPagerTotal);
        if (r < 0) { r = 0; }
        if (r > kept - 1) { r = kept - 1; }
        %orig(CGPointMake(r * pw, contentOffset.y), animated);
        return;
    }
    %orig;
}

%end

// MARK: - underline animation squelch
//
// The bar's native follow ANIMATES the underline toward — and SIZES it for —
// the cell at the REMAPPED index (measured: at rest the width stayed sized
// for the wrong cell, and every settle needed a late correction while the
// native animation finished). The tweak's placement is a dead set inside
// performWithoutAnimation, so it never enters here; everything the native
// side tries to animate on that one layer is dropped. Identity-guarded: one
// pointer compare for every other layer in the app (same proven pattern as
// the reply-compose bounce squelch).
%hook CALayer

- (void)addAnimation:(id)anim forKey:(id)key {
    if ((CALayer*)self == gNFBHighlightLayer && nfbGranularActive()) {
        return;
    }
    %orig;
}

// Measured (3-hidden video): ~230ms after a clean landing, a NATIVE DEAD SET
// (no animation — invisible to the squelch above) teleported the underline to
// a phantom position between tabs, and with no further layout pass at rest,
// nothing repaired it until the next gesture. Every position/bounds write on
// this one layer now belongs to the tweak: foreign dead sets are dropped, the tweak's own
// (flagged) pass through. Identity first — one pointer compare per call for
// the rest of the app.
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
