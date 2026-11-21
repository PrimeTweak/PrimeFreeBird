// Probe for Twitter 12.45, removed once read: every way Home's Tweets change at launch and on refresh, with the
// row shown on top before and after, what lies over the list, and the refreshes around them.

#import "Support/HookHelpers.h"

static NSString* const kPFBRefreshProbeTopic = @"probe refresh";
static const NSUInteger kPFBRefreshProbeCap = 400;
static const NSUInteger kPFBRefreshProbeLaunchCap = 130;
static NSInteger gPFBRefreshProbeLaunch;
static NSUInteger gPFBRefreshProbeLines;
static CFTimeInterval gPFBRefreshProbeStart;
static CFTimeInterval gPFBRefreshProbeBegan = -1000.0;
static const void* kPFBRefreshProbeListKey = &kPFBRefreshProbeListKey;

static void PFBRefreshProbeLine(NSString* event) {
    if (++gPFBRefreshProbeLines > kPFBRefreshProbeLaunchCap) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    NSString* since = gPFBRefreshProbeBegan > 0.0 ? [NSString stringWithFormat:@"+%.2fs", now - gPFBRefreshProbeBegan] : @"no begin";
    PFBCompatMeasure(kPFBRefreshProbeTopic,
                     [NSString stringWithFormat:@"L%ld %03lu %6.2fs (%@) %@", (long)gPFBRefreshProbeLaunch, (unsigned long)gPFBRefreshProbeLines,
                                                now - gPFBRefreshProbeStart, since, event],
                     kPFBRefreshProbeCap);
}

// The last four hex digits of an object's address, to tell objects apart in the lines.
static unsigned long PFBRefreshProbeTag(id object) {
    uintptr_t address = (uintptr_t)(__bridge void*)object;
    return (unsigned long)(address % 0x10000);
}

static BOOL PFBRefreshProbeIsHome(UIViewController* controller) {
    for (UIViewController* parent = controller; parent; parent = parent.parentViewController) {
        if ([NSStringFromClass(parent.class) isEqualToString:@"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController"]) {
            return YES;
        }
    }
    return NO;
}

static UIScrollView* PFBRefreshProbeList(UIViewController* controller) {
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

// The topmost row on screen and the first words it shows.
static NSString* PFBRefreshProbeTop(UIScrollView* list) {
    if (![list isKindOfClass:[UITableView class]]) {
        return @"no table";
    }
    UITableView* table = (UITableView*)list;
    NSArray<NSIndexPath*>* paths = [table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)];
    for (NSIndexPath* path in paths) {
        UITableViewCell* cell = [table cellForRowAtIndexPath:path];
        __block NSString* words = cell.accessibilityLabel;
        if (!words.length) {
            PFBWalkAllSubviews(cell.contentView, 5, ^(UIView* view) {
              if (!words.length && [view isKindOfClass:[UILabel class]]) {
                  words = ((UILabel*)view).text;
              }
            });
        }
        if (words.length) {
            words = [words stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            return [NSString stringWithFormat:@"top %ld.%ld '%@'", (long)path.section, (long)path.row,
                                              words.length > 20 ? [words substringToIndex:20] : words];
        }
    }
    return [NSString stringWithFormat:@"%lu rows, no words", (unsigned long)paths.count];
}

// A view laid over the whole list, as Smooth refresh's still picture is: its address and opacity on screen.
static NSString* PFBRefreshProbeOver(UIScrollView* list) {
    NSArray* siblings = list.superview.subviews;
    NSUInteger index = [siblings indexOfObject:list];
    UIView* above = nil;
    for (NSUInteger i = index == NSNotFound ? siblings.count : index + 1; i < siblings.count; i++) {
        UIView* view = siblings[i];
        if (CGRectEqualToRect(CGRectIntegral(view.frame), CGRectIntegral(list.frame))) {
            above = view;
        }
    }
    if (!above) {
        return @"nothing over";
    }
    CALayer* shown = above.layer.presentationLayer ?: above.layer;
    return [NSString stringWithFormat:@"still %04lx at %.2f", PFBRefreshProbeTag(above), shown.opacity];
}

static NSString* PFBRefreshProbeState(UIScrollView* list) {
    return [NSString stringWithFormat:@"window %d moving %d offset %.1f, %@, %@", list.window != nil,
                                      list.tracking || list.dragging || list.decelerating, list.contentOffset.y, PFBRefreshProbeTop(list),
                                      PFBRefreshProbeOver(list)];
}

// The same 0.05 s later: what the change put on screen.
static void PFBRefreshProbeAfter(UIScrollView* list, NSString* what) {
    __weak UIScrollView* weakList = list;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIScrollView* later = weakList;
      PFBRefreshProbeLine([NSString stringWithFormat:@"  after %@: %@", what, later ? PFBRefreshProbeState(later) : @"list gone"]);
    });
}

// A Home controller event, with the state of its list before and 0.05 s after.
static void PFBRefreshProbeEvent(UIViewController* controller, NSString* how, NSArray* sections, BOOL counted) {
    if (!PFBRefreshProbeIsHome(controller)) {
        return;
    }
    UIScrollView* list = PFBRefreshProbeList(controller);
    objc_setAssociatedObject(list, kPFBRefreshProbeListKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray* had = [controller respondsToSelector:@selector(sections)] ? [(id)controller sections] : nil;
    NSString* items = counted ? [NSString stringWithFormat:@"%lu items (had %lu), ", (unsigned long)PFBRefreshProbeCount(sections),
                                                           (unsigned long)PFBRefreshProbeCount(had)]
                              : @"";
    PFBRefreshProbeLine([NSString stringWithFormat:@"%@ on %@ %04lx: %@before: %@", how, NSStringFromClass(controller.class),
                                                   PFBRefreshProbeTag(controller), items, PFBRefreshProbeState(list)]);
    PFBRefreshProbeAfter(list, how);
}

static void PFBRefreshProbeTable(UITableView* table, NSString* how) {
    if (!objc_getAssociatedObject(table, kPFBRefreshProbeListKey)) {
        return;
    }
    PFBRefreshProbeLine([NSString stringWithFormat:@"table %@, before: %@", how, PFBRefreshProbeState(table)]);
    PFBRefreshProbeAfter(table, [@"table " stringByAppendingString:how]);
}

%hook _TtC32TwitterHomeFeatureImplementation25HomeLogoRefreshController

- (void)pullToRefreshControl:(id)control didBeginRefreshingFromPull:(BOOL)fromPull {
    gPFBRefreshProbeBegan = CACurrentMediaTime();
    PFBRefreshProbeLine([NSString stringWithFormat:@"refresh begins, from pull %d", fromPull]);
    %orig;
}

- (void)pullToRefreshControlDidEndRefreshing:(id)control {
    PFBRefreshProbeLine(@"refresh ends");
    %orig;
}

%end

%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PFBRefreshProbeLine(@"Home appears");
}

%end

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections {
    PFBRefreshProbeEvent((UIViewController*)self, @"setSections:", sections, YES);
    %orig;
}

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    PFBRefreshProbeEvent((UIViewController*)self, restore ? @"setSections:restore YES" : @"setSections:restore NO", sections, YES);
    %orig;
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    PFBRefreshProbeEvent((UIViewController*)self, [NSString stringWithFormat:@"updateSections:reconfigure animation %lld", animation], sections, YES);
    %orig;
}

%end

// Home's own timeline controllers, below Twitter's data controller (both read in 12.45's binary).
%hook THFHomeTimelineItemsViewController

- (void)updateSections:(NSArray*)sections withRowAnimation:(long long)animation completion:(id)completion {
    PFBRefreshProbeEvent((UIViewController*)self, [NSString stringWithFormat:@"updateSections:withRowAnimation %lld", animation], sections, YES);
    %orig;
}

- (void)_performIncrementalUpdate:(id)update animated:(BOOL)animated {
    PFBRefreshProbeEvent((UIViewController*)self, [NSString stringWithFormat:@"_performIncrementalUpdate animated %d", animated], nil, NO);
    %orig;
}

- (id)itemsAnimatorSectionsToAnimateFrom:(id)sections {
    id from = %orig;
    PFBRefreshProbeEvent((UIViewController*)self,
                         [NSString stringWithFormat:@"itemsAnimatorSectionsToAnimateFrom gives %lu items", (unsigned long)PFBRefreshProbeCount(from)],
                         nil, NO);
    return from;
}

- (void)_streamDidUpdate {
    PFBRefreshProbeEvent((UIViewController*)self, @"_streamDidUpdate", nil, NO);
    %orig;
}

- (void)_streamApplicationLaunchInitialRequestDidComplete:(id)notification {
    PFBRefreshProbeEvent((UIViewController*)self, @"_streamApplicationLaunchInitialRequestDidComplete", nil, NO);
    %orig;
}

- (void)_topLoadDidComplete {
    PFBRefreshProbeEvent((UIViewController*)self, @"_topLoadDidComplete", nil, NO);
    %orig;
}

- (void)pullToRefreshDidLand {
    PFBRefreshProbeEvent((UIViewController*)self, @"pullToRefreshDidLand", nil, NO);
    %orig;
}

- (void)_scrollToFirstItemAtIndexPath {
    PFBRefreshProbeEvent((UIViewController*)self, @"_scrollToFirstItemAtIndexPath", nil, NO);
    %orig;
}

%end

%hook _TtC32TwitterHomeFeatureImplementation28TimelineEngineViewController

- (void)updateSections:(NSArray*)sections withRowAnimation:(long long)animation completion:(id)completion {
    PFBRefreshProbeEvent((UIViewController*)self, [NSString stringWithFormat:@"updateSections:withRowAnimation %lld", animation], sections, YES);
    %orig;
}

%end

// Home's table changed directly, below the data controller.
%hook UITableView

- (void)reloadData {
    PFBRefreshProbeTable(self, @"reloadData");
    %orig;
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

- (void)insertSections:(NSIndexSet*)sections withRowAnimation:(UITableViewRowAnimation)animation {
    PFBRefreshProbeTable(self, [NSString stringWithFormat:@"insertSections %lu animation %ld", (unsigned long)sections.count, (long)animation]);
    %orig;
}

- (void)deleteSections:(NSIndexSet*)sections withRowAnimation:(UITableViewRowAnimation)animation {
    PFBRefreshProbeTable(self, [NSString stringWithFormat:@"deleteSections %lu animation %ld", (unsigned long)sections.count, (long)animation]);
    %orig;
}

- (void)reloadSections:(NSIndexSet*)sections withRowAnimation:(UITableViewRowAnimation)animation {
    PFBRefreshProbeTable(self, [NSString stringWithFormat:@"reloadSections %lu animation %ld", (unsigned long)sections.count, (long)animation]);
    %orig;
}

%end

// Animated moves of Home's list that go somewhere, as the Home tab or a refresh sends it to the top.
%hook UIScrollView

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if (animated && fabs(offset.y - self.contentOffset.y) > 0.5 && objc_getAssociatedObject(self, kPFBRefreshProbeListKey)) {
        PFBRefreshProbeLine([NSString stringWithFormat:@"list moves to %.1f animated, from %.1f", offset.y, self.contentOffset.y]);
    }
    %orig;
}

%end

%ctor {
    gPFBRefreshProbeStart = CACurrentMediaTime();
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    gPFBRefreshProbeLaunch = [defaults integerForKey:@"PFBRefreshProbeLaunch"] + 1;
    [defaults setInteger:gPFBRefreshProbeLaunch forKey:@"PFBRefreshProbeLaunch"];
    %init;
}
