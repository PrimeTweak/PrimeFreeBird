// Probe for Twitter 12.45, removed once read: every Home refresh as Smooth refresh sees it, pulled or from
// the Home tab, each hand-over of Tweets with its timing, how the list moves around it and what fades.

#import "Support/HookHelpers.h"

static NSString* const kPFBRefreshProbeTopic = @"probe refresh";
static const NSUInteger kPFBRefreshProbeCap = 400;
static const NSUInteger kPFBRefreshProbeLaunchCap = 80;
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
    NSString* since = gPFBRefreshProbeBegan > 0.0 ? [NSString stringWithFormat:@"%.2fs after begin", now - gPFBRefreshProbeBegan] : @"no begin yet";
    PFBCompatMeasure(kPFBRefreshProbeTopic,
                     [NSString stringWithFormat:@"L%ld %02lu %7.2fs (%@) %@", (long)gPFBRefreshProbeLaunch, (unsigned long)gPFBRefreshProbeLines,
                                                now - gPFBRefreshProbeStart, since, event],
                     kPFBRefreshProbeCap);
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

static NSString* PFBRefreshProbeState(UIScrollView* list) {
    return [NSString stringWithFormat:@"list window %d superview %d tracking %d dragging %d decelerating %d offset %.1f top inset %.1f", list.window != nil,
                                      list.superview != nil, list.tracking, list.dragging, list.decelerating, list.contentOffset.y,
                                      list.adjustedContentInset.top];
}

// What sits over the list 0.05 s after a hand-over: the fade's still picture, or nothing; and how far the
// list moved meanwhile.
static void PFBRefreshProbeAfter(UIScrollView* list, NSString* what) {
    CGFloat before = list.contentOffset.y;
    __weak UIScrollView* weakList = list;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      UIScrollView* later = weakList;
      UIView* above = nil;
      NSArray* siblings = later.superview.subviews;
      NSUInteger index = later ? [siblings indexOfObject:later] : NSNotFound;
      for (NSUInteger i = index == NSNotFound ? siblings.count : index + 1; i < siblings.count; i++) {
          UIView* view = siblings[i];
          if (CGRectEqualToRect(CGRectIntegral(view.frame), CGRectIntegral(later.frame))) {
              above = view;
          }
      }
      CALayer* shown = above.layer.presentationLayer ?: above.layer;
      PFBRefreshProbeLine([NSString stringWithFormat:@"after %@: %@, list moved %.1f, now %@", what,
                                                     above ? [NSString stringWithFormat:@"%@ over the list, alpha %.2f", NSStringFromClass(above.class), shown.opacity]
                                                           : @"nothing over the list",
                                                     later.contentOffset.y - before, later ? PFBRefreshProbeState(later) : @"list gone"]);
    });
}

static void PFBRefreshProbeHandOver(UIViewController* controller, NSString* how, NSArray* sections) {
    if (!PFBRefreshProbeIsHome(controller)) {
        return;
    }
    UIScrollView* list = PFBRefreshProbeList(controller);
    objc_setAssociatedObject(list, kPFBRefreshProbeListKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PFBRefreshProbeLine([NSString stringWithFormat:@"%@ %lu items (had %lu), Smooth refresh %d, %@", how, (unsigned long)PFBRefreshProbeCount(sections),
                                                   (unsigned long)PFBRefreshProbeCount([controller respondsToSelector:@selector(sections)] ? [(id)controller sections] : nil),
                                                   [PFBSettings boolForKey:@"refresh_fade"], PFBRefreshProbeState(list)]);
    PFBRefreshProbeAfter(list, how);
}

%hook _TtC32TwitterHomeFeatureImplementation25HomeLogoRefreshController

- (void)pullToRefreshControl:(id)control didBeginRefreshingFromPull:(BOOL)fromPull {
    gPFBRefreshProbeBegan = CACurrentMediaTime();
    PFBRefreshProbeLine([NSString stringWithFormat:@"refresh begins, from pull %d, control %@", fromPull, NSStringFromClass([control class])]);
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
    PFBRefreshProbeHandOver((UIViewController*)self, @"setSections:", sections);
    %orig;
}

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restore {
    PFBRefreshProbeHandOver((UIViewController*)self, restore ? @"setSections:restore YES" : @"setSections:restore NO", sections);
    %orig;
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    PFBRefreshProbeHandOver((UIViewController*)self, [NSString stringWithFormat:@"updateSections: animation %lld", animation], sections);
    %orig;
}

%end

// Animated moves of Home's list, as the Home tab sends it to the top.
%hook UIScrollView

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if (animated && objc_getAssociatedObject(self, kPFBRefreshProbeListKey)) {
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
