// Path tour: opens Twitter's screens in turn so the report proves the paths they carry.

#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <stdatomic.h>
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Debug/PFBTourOverlayWindow.h"

// Long enough for a screen and its first page of content to arrive.
static const NSTimeInterval kPFBTourPause = 2.5;

// How long a step waits for the proofs its screen owes before it concludes.
static const NSTimeInterval kPFBTourProofWait = 6.0;

// The first look at a step, then one look per tick until it concludes.
static const NSTimeInterval kPFBTourFirstLook = 1.0;
static const NSTimeInterval kPFBTourPoll = 0.25;

// When a step's first way in has shown nothing, its second one is tried.
static const NSTimeInterval kPFBTourDoorRetry = 2.5;

// Left to the app after a step's setup and after its clean-up.
static const NSTimeInterval kPFBTourSettle = 0.4;

// How many screens down Home is searched for a view of a given class.
static const NSInteger kPFBTourScreensDown = 6;

// Well past the refresh threshold, released the way a finger lets go.
static const CGFloat kPFBTourPullDistance = 160.0;

// Long enough after launch for the first timeline to be on screen.
static const NSTimeInterval kPFBTourLaunchDelay = 4.0;

static NSString* const kPFBTourPendingKey = @"pfb_compat_tour_pending";

typedef BOOL (^PFBTourCheck)(UIViewController* before, UIViewController* after);

static BOOL gPFBTourRunning = NO;
// Bumped at each start and each cancel, so the callbacks of a stopped run do nothing.
static NSUInteger gPFBTourGeneration;
// The step whose screen is up; nil once it concludes, so its delayed parts stop with it.
static NSString* gPFBTourStepLive;
// Set by a step whose screen had nothing to open (an inbox with no conversation): the
// step then concludes on that, not as reached or not reached.
static NSString* gPFBTourStepEmpty;
static UIWindow* gPFBTourOverlay;
static UILabel* gPFBTourStepLabel;
static NSFileHandle* gPFBTourJournal;
// Twitter's palette in use before the dark mode step switched it.
static id gPFBTourPaletteBefore;

// MARK: - Journal

// The tour's journal is a file written line by line, so a crash cannot erase it: the
// report prints it, and the next launch reads where a tour stopped.
static NSString* tourJournalPath(void) {
    NSString* caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [caches ?: NSTemporaryDirectory() stringByAppendingPathComponent:@"pfb-path-tour.log"];
}

static void tourJournalWrite(NSString* line) {
    static NSDateFormatter* clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      clock = [NSDateFormatter new];
      clock.dateFormat = @"HH:mm:ss.SSS";
    });
    if (!gPFBTourJournal) {
        NSString* path = tourJournalPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        gPFBTourJournal = [NSFileHandle fileHandleForWritingAtPath:path];
        [gPFBTourJournal seekToEndReturningOffset:NULL error:nil];
    }
    NSString* stamped = [NSString stringWithFormat:@"%@  %@\n", [clock stringFromDate:[NSDate date]], line];
    [gPFBTourJournal writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding] error:nil];
}

static void tourJournalClose(void) {
    [gPFBTourJournal closeAndReturnError:nil];
    gPFBTourJournal = nil;
}

void PFBCompatTourLog(NSString* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString* line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    if (gPFBTourRunning) {
        tourJournalWrite(line);
    } else {
        PFBDebugLog(@"%@", line);
    }
}


NSString* PFBCompatTourJournalText(void) {
    NSString* text = [NSString stringWithContentsOfFile:tourJournalPath() encoding:NSUTF8StringEncoding error:nil];
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

// Twitter's main window: the debugger's own overlay is often the key one.
static UIWindow* tourWindow(void) {
    UIWindow* fallback = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            NSString* name = NSStringFromClass([window class]);
            if ([name isEqualToString:@"T1Window"]) {
                return window;
            }
            if (!fallback && !window.hidden && window.windowLevel == UIWindowLevelNormal &&
                window.rootViewController && ![name hasPrefix:@"PFB"]) {
                fallback = window;
            }
        }
    }
    return fallback;
}

// The view under the middle of Twitter's window: the side menu stays mounted behind
// the content and the tab bar sits below it, so neither is reached from there.
static UIView* tourFrontView(void) {
    UIWindow* window = tourWindow();
    if (!window) {
        return nil;
    }
    return [window hitTest:CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds)) withEvent:nil];
}

// The screen in front: the controller its navigation stack shows, or one presented alone.
static UIViewController* tourScreen(void) {
    UIViewController* screen = nil;
    for (UIResponder* responder = tourFrontView(); responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            screen = (UIViewController*)responder;
            break;
        }
    }
    while (screen.parentViewController &&
           ![screen.parentViewController isKindOfClass:[UINavigationController class]]) {
        screen = screen.parentViewController;
    }
    return screen;
}

static NSString* tourScreenName(UIViewController* screen) {
    return screen ? NSStringFromClass([screen class]) : @"?";
}

// The list under the middle of the screen, the one a finger would pull.
static UITableView* tourFrontList(void) {
    for (UIView* view = tourFrontView(); view; view = view.superview) {
        if ([view isKindOfClass:[UITableView class]]) {
            return (UITableView*)view;
        }
    }
    return nil;
}

// The controller that answers selectTabAtIndex:, the route the tab bar code uses.
static id tourTabSwitcher(void) {
    SEL select = NSSelectorFromString(@"selectTabAtIndex:");
    NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
    UIViewController* root = tourWindow().rootViewController;
    if (root) {
        [queue addObject:root];
    }
    for (NSUInteger i = 0; i < queue.count && i < 512; i++) {
        UIViewController* controller = queue[i];
        if ([controller respondsToSelector:select]) {
            return controller;
        }
        [queue addObjectsFromArray:controller.childViewControllers];
    }
    return nil;
}

static NSInteger tourIntegerGetter(id object, NSString* name);
static UIView* tourFindClass(UIView* root, NSString* className);
static id tourGetter(id object, NSString* name);

// Twitter's app navigation object, answered by its tabbed controller in either design.
static id tourAppNavigation(void) {
    NSMutableArray<UIViewController*>* queue = [NSMutableArray array];
    UIViewController* root = tourWindow().rootViewController;
    if (root) {
        [queue addObject:root];
    }
    for (NSUInteger i = 0; i < queue.count && i < 512; i++) {
        id navigation = tourGetter(queue[i], @"appNavigation");
        if (navigation) {
            return navigation;
        }
        [queue addObjectsFromArray:queue[i].childViewControllers];
    }
    return nil;
}

// Without a tab bar controller to ask, as under Twitter's own Liquid Glass, the app
// navigation takes a panel: the one recorded for the page at that place when the
// navigation lists it, otherwise the panel at that place in its own list.
static void tourSelectPanel(NSInteger index) {
    static NSUInteger toldGeneration;
    id navigation = tourAppNavigation();
    NSArray* panels = tourGetter(navigation, @"visiblePanelIDs");
    SEL set = NSSelectorFromString(@"setCurrentPanel:animated:completion:");
    NSArray<NSString*>* pages =
        [PFBCustomTabBarUtility visiblePageIDsInOrder] ?: [PFBCustomTabBarUtility defaultVisiblePageIDs];
    id recorded = index >= 0 && index < (NSInteger)pages.count
                      ? [PFBCustomTabBarUtility metadataForPage:pages[(NSUInteger)index]][PFBTabPanelIDKey]
                      : nil;
    id panel = nil;
    if ([panels isKindOfClass:[NSArray class]]) {
        if ([recorded isKindOfClass:[NSNumber class]] && [panels containsObject:recorded]) {
            panel = recorded;
        } else if (index >= 0 && index < (NSInteger)panels.count) {
            panel = panels[(NSUInteger)index];
        }
    }
    BOOL usable = [panel respondsToSelector:@selector(longLongValue)] && [navigation respondsToSelector:set];
    if (toldGeneration != gPFBTourGeneration) {
        toldGeneration = gPFBTourGeneration;
        PFBCompatTourLog(@"[tour] tabs: %@ through %@", usable ? @"panels" : @"no way to switch",
                         navigation ? NSStringFromClass([navigation class]) : @"no app navigation");
    }
    if (!usable) {
        return;
    }
    long long value = [panel longLongValue];
    if (tourIntegerGetter(navigation, @"currentPanelID") == value) {
        return;
    }
    ((void (*)(id, SEL, long long, BOOL, id))objc_msgSend)(navigation, set, value, NO, nil);
}

// Selecting the tab already in front would make Twitter scroll it back to the top.
static void tourSelectTab(NSInteger index) {
    id switcher = tourTabSwitcher();
    if (!switcher) {
        tourSelectPanel(index);
        return;
    }
    if (tourIntegerGetter(switcher, @"selectedTabIndex") == index) {
        return;
    }
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(switcher, NSSelectorFromString(@"selectTabAtIndex:"), index);
}

static void tourPopToRoot(void) {
    [tourScreen().navigationController popToRootViewControllerAnimated:NO];
}

static id tourGetter(id object, NSString* name) {
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

// A pull past the threshold commits a refresh before the finger lifts: status 1 marked
// as coming from scrolling, then the value-changed action. The control is read from the
// list's controller up the responder chain, since the list's delegate can be a relaying proxy.
static void tourCommitRefresh(UITableView* list) {
    id control = nil;
    for (UIResponder* responder = list.nextResponder; responder && !control;
         responder = responder.nextResponder) {
        control = tourGetter(responder, @"pullToLoadTopControl");
    }
    SEL status = NSSelectorFromString(@"_setStatus:fromScrolling:");
    if (![control isKindOfClass:[UIControl class]] || ![control respondsToSelector:status]) {
        PFBCompatTourLog(@"[tour] refresh: no usable control up the chain (%@)",
                         control ? NSStringFromClass([control class]) : @"none");
        return;
    }
    ((void (*)(id, SEL, unsigned long long, BOOL))objc_msgSend)(control, status, 1, YES);
    [(UIControl*)control sendActionsForControlEvents:UIControlEventValueChanged];
}

static void tourPull(void) {
    UITableView* list = tourFrontList();
    id<UITableViewDelegate> delegate = list.delegate;
    if (!list || !delegate) {
        return;
    }
    CGPoint rest = list.contentOffset;
    [list setContentOffset:CGPointMake(rest.x, -list.adjustedContentInset.top - kPFBTourPullDistance)
                  animated:NO];
    if ([delegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
        [delegate scrollViewDidScroll:list];
    }
    tourCommitRefresh(list);
    if ([delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [delegate scrollViewDidEndDragging:list willDecelerate:NO];
    }
    [list setContentOffset:rest animated:YES];
}

// The first Tweet row the list shows, selected the way a tap does; when none can be
// opened, the log says what was found instead.
static void tourOpenFirstTweet(void) {
    UITableView* list = tourFrontList();
    Class statusCell = NSClassFromString(@"T1StatusCell");
    id<UITableViewDelegate> delegate = list.delegate;
    if (!list || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        PFBCompatTourLog(@"[tour] first Tweet: %@", list ? @"the list takes no row selection"
                                                    : @"no list under the middle of the screen");
        return;
    }
    // A Tweet with a link card can open the link rather than its conversation.
    NSArray<NSIndexPath*>* rows = [list.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)];
    NSIndexPath* carded = nil;
    for (NSIndexPath* row in rows) {
        UITableViewCell* cell = [list cellForRowAtIndexPath:row];
        if (!statusCell || ![cell isKindOfClass:statusCell]) {
            continue;
        }
        if (tourFindClass(cell, @"T1UnifiedCardView")) {
            carded = carded ?: row;
            continue;
        }
        [delegate tableView:list didSelectRowAtIndexPath:row];
        return;
    }
    if (carded) {
        PFBCompatTourLog(@"[tour] first Tweet: every visible Tweet has a link card, row %ld opened", (long)carded.row);
        [delegate tableView:list didSelectRowAtIndexPath:carded];
        return;
    }
    PFBCompatTourLog(@"[tour] first Tweet: no Tweet among %lu visible row(s) of %@",
                (unsigned long)rows.count, NSStringFromClass([list class]));
}

// Through the app delegate, the way a link opened from outside arrives; YES when
// Twitter takes it.
static BOOL tourOpenLink(NSString* link) {
    UIApplication* app = UIApplication.sharedApplication;
    id<UIApplicationDelegate> delegate = app.delegate;
    NSURL* url = [NSURL URLWithString:link];
    if (url && [delegate respondsToSelector:@selector(application:openURL:options:)]) {
        return [delegate application:app openURL:url options:@{}];
    }
    return NO;
}

static void tourOpenOwnProfile(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    NSString* name = tourGetter(account, @"username");
    if (![name isKindOfClass:[NSString class]] || !name.length) {
        return;
    }
    NSString* encoded =
        [name stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    tourOpenLink([@"twitter://user?screen_name=" stringByAppendingString:encoded ?: name]);
}

// With Liquid Glass on, the box wears the reply bar's glass with its keyboard tint;
// otherwise the system material, whose corners need clipping.
static UIVisualEffect* tourBoxEffect(BOOL* glass) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    *glass = glassClass != nil && [PFBSettings boolForKey:@"enable_liquid_glass"];
    if (!*glass) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    UIVisualEffect* effect = [[glassClass alloc] init];
    if ([effect respondsToSelector:@selector(setTintColor:)]) {
        [(id)effect setTintColor:[UIColor.systemBackgroundColor colorWithAlphaComponent:PFBGlassTint]];
    }
    return effect;
}

// A tab's name as the app shows it, or its page id.
static NSString* tourTabTitle(NSString* page) {
    NSString* title = [PFBCustomTabBarUtility metadataForPage:page][PFBTabTitleKey];
    return [title isKindOfClass:[NSString class]] && title.length ? title : page;
}

// An integer a getter returns, read only when its signature says it returns one.
static NSInteger tourIntegerGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) {
        return NSNotFound;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, @encode(NSInteger)) != 0) {
        return NSNotFound;
    }
    return ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
}

// Home's own tabs (For you, Following, pinned timelines): the first controller up the
// responder chain from its list that says how many tabs it has and which one shows.
static id tourHomeTabs(void) {
    for (UIResponder* responder = tourFrontList().nextResponder; responder;
         responder = responder.nextResponder) {
        if (tourIntegerGetter(responder, @"numberOfTabs") != NSNotFound &&
            tourIntegerGetter(responder, @"selectedIndex") != NSNotFound) {
            return responder;
        }
    }
    return nil;
}

// Shows one of Home's tabs through its tab controller, without animation.
static void tourShowHomeTab(id tabs, NSInteger index) {
    SEL select = NSSelectorFromString(@"setSelectedIndex:animated:");
    NSMethodSignature* signature =
        [tabs respondsToSelector:select] ? [tabs methodSignatureForSelector:select] : nil;
    if (signature.numberOfArguments != 4 ||
        strcmp([signature getArgumentTypeAtIndex:2], @encode(NSInteger)) != 0 ||
        strcmp([signature getArgumentTypeAtIndex:3], @encode(BOOL)) != 0) {
        return;
    }
    ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(tabs, select, index, NO);
}

// MARK: - Finding things on screen

static UIViewController* tourRootController(void) {
    return tourWindow().rootViewController;
}

static UIViewController* tourTopController(void) {
    UIViewController* top = tourRootController();
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

// Whatever a step presented over Twitter comes down without animation.
static void tourDismissPresented(void) {
    UIViewController* root = tourRootController();
    if (root.presentedViewController) {
        [root dismissViewControllerAnimated:NO completion:nil];
    }
}

// Home in front, on whichever of its tabs the user left: where most steps start.
static void tourHomeFront(void) {
    tourDismissPresented();
    tourPopToRoot();
    tourSelectTab(0);
}

// The first view under a root that matches, breadth first, within a bound.
static UIView* tourFindView(UIView* root, BOOL (^match)(UIView* view)) {
    if (!root) {
        return nil;
    }
    NSMutableArray<UIView*>* queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count && i < 6000; i++) {
        UIView* view = queue[i];
        if (match(view)) {
            return view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

// In a window, with neither the view nor any of its parents hidden or transparent.
static BOOL tourOnScreen(UIView* view) {
    for (UIView* level = view; level; level = level.superview) {
        if (level.hidden || level.alpha < 0.01) {
            return NO;
        }
    }
    return view.window != nil;
}

static UIView* tourFindClass(UIView* root, NSString* className) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        return nil;
    }
    return tourFindView(root, ^BOOL(UIView* view) {
      return [view isKindOfClass:cls] && !view.hidden;
    });
}

static UIView* tourAncestor(UIView* view, NSString* className) {
    Class cls = NSClassFromString(className);
    for (UIView* up = view; cls && up; up = up.superview) {
        if ([up isKindOfClass:cls]) {
            return up;
        }
    }
    return nil;
}

// A controller of the class under a root: its children, stacks and presented ones.
static UIViewController* tourFindController(UIViewController* root, NSString* className) {
    Class cls = NSClassFromString(className);
    if (!root || !cls) {
        return nil;
    }
    NSMutableArray<UIViewController*>* queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count && i < 256; i++) {
        UIViewController* controller = queue[i];
        if ([controller isKindOfClass:cls]) {
            return controller;
        }
        [queue addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) {
            [queue addObject:controller.presentedViewController];
        }
    }
    return nil;
}

static BOOL tourSend(id target, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) {
        return NO;
    }
    ((void (*)(id, SEL))objc_msgSend)(target, selector);
    return YES;
}

// A BOOL a getter returns, read only when its signature says it returns one.
static BOOL tourBoolGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) {
        return NO;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (signature.numberOfArguments != 2 || (type[0] != 'B' && type[0] != 'c')) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

// A view of one of the classes, the first preferred, in the Home list's visible Tweets,
// looking a screen further down each time none shows one. The list stays where it was found.
static UIView* tourHomeViewOfClasses(NSArray<NSString*>* classNames) {
    UITableView* list = tourFrontList();
    for (NSInteger screen = 0; list && screen <= kPFBTourScreensDown; screen++) {
        for (NSString* className in classNames) {
            for (UITableViewCell* cell in list.visibleCells) {
                UIView* found = tourFindClass(cell, className);
                if (found.window) {
                    return found;
                }
            }
        }
        CGPoint offset = list.contentOffset;
        [list setContentOffset:CGPointMake(offset.x, offset.y + list.bounds.size.height * 0.8) animated:NO];
        [list layoutIfNeeded];
    }
    PFBCompatTourLog(@"[tour] no %@ within %ld screens of Home", [classNames componentsJoinedByString:@" or "],
                     (long)kPFBTourScreensDown + 1);
    return nil;
}

static UIView* tourHomeViewOfClass(NSString* className) {
    return tourHomeViewOfClasses(@[ className ]);
}

static BOOL tourIsKind(UIView* view, NSString* className) {
    Class cls = NSClassFromString(className);
    return cls && [view isKindOfClass:cls];
}

// The first video on Home: its player, or the preview Twitter shows in its place until the
// player loads. The journal names which of the two was found.
static UIView* tourHomeVideo(NSString* step) {
    UIView* video = tourHomeViewOfClasses(@[ @"T1InlineVideoView", @"T1InlineVideoFacadeView" ]);
    if (video) {
        PFBCompatTourLog(@"[tour] %@: %@ found", step, tourIsKind(video, @"T1InlineVideoView") ? @"player" : @"preview");
    }
    return video;
}

static void tourScrollHomeToTop(void) {
    UITableView* list = tourFrontList();
    if (list) {
        [list setContentOffset:CGPointMake(list.contentOffset.x, -list.adjustedContentInset.top) animated:NO];
    }
}

// The list the tour is dragging. It says a finger holds it until the drag ends: Twitter
// folds its bars only under a finger, or while a list still glides.
static _Atomic(void*) gPFBTourFingerList;
static BOOL (*gPFBTourIsTracking)(id, SEL);
static BOOL (*gPFBTourIsDragging)(id, SEL);

static BOOL tourIsTracking(UIScrollView* list, SEL selector) {
    return (__bridge void*)list == atomic_load_explicit(&gPFBTourFingerList, memory_order_relaxed) ||
           gPFBTourIsTracking(list, selector);
}

static BOOL tourIsDragging(UIScrollView* list, SEL selector) {
    return (__bridge void*)list == atomic_load_explicit(&gPFBTourFingerList, memory_order_relaxed) ||
           gPFBTourIsDragging(list, selector);
}

// Set up at the tour's first drag; every other list still answers for itself.
static BOOL tourFingerReady(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Method tracking = class_getInstanceMethod([UIScrollView class], @selector(isTracking));
      Method dragging = class_getInstanceMethod([UIScrollView class], @selector(isDragging));
      if (tracking && dragging) {
          gPFBTourIsTracking = (BOOL (*)(id, SEL))method_getImplementation(tracking);
          gPFBTourIsDragging = (BOOL (*)(id, SEL))method_getImplementation(dragging);
          method_setImplementation(tracking, (IMP)tourIsTracking);
          method_setImplementation(dragging, (IMP)tourIsDragging);
      }
    });
    return gPFBTourIsTracking && gPFBTourIsDragging;
}

// A drag glides over this many frames, about 0.4 s: a step per frame, as under a finger.
static const NSInteger kPFBTourDragSteps = 24;
static const NSTimeInterval kPFBTourDragFrame = 1.0 / 60.0;
// Bumped at each drag, so a drag still gliding stops once another one starts.
static NSUInteger gPFBTourDragToken;

// One frame of a drag: the list moves a step from where it is and UIKit tells its
// delegate. After the last step, or once something else moved the list, the finger lets
// go and done runs; a stopped tour, a list gone or a newer drag ends it without done.
static void tourDragFrame(UITableView* list, CGFloat delta, NSInteger remaining, CGFloat last, NSUInteger token,
                          NSUInteger generation, dispatch_block_t done) {
    if (token != gPFBTourDragToken) {
        return;
    }
    BOOL live = generation == gPFBTourGeneration && list.window != nil;
    // A move of over a quarter screen the drag did not make, a step's clean-up for one, ends it.
    BOOL moving = live && fabs(list.contentOffset.y - last) < list.bounds.size.height / 4.0;
    CGPoint offset = list.contentOffset;
    @try {
        if (moving) {
            offset.y += delta;
            [list setContentOffset:offset animated:NO];
        }
        if (!moving || remaining == 1) {
            id<UITableViewDelegate> delegate = list.delegate;
            if ([delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
                [delegate scrollViewDidEndDragging:list willDecelerate:NO];
            }
        }
    } @catch (id exception) {
        PFBCompatTourLog(@"[tour] drag: exception with %ld steps left: %@", (long)remaining, exception);
        live = moving = NO;
    }
    if (moving && remaining > 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourDragFrame * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         tourDragFrame(list, delta, remaining - 1, offset.y, token, generation, done);
                       });
        return;
    }
    atomic_store_explicit(&gPFBTourFingerList, NULL, memory_order_relaxed);
    if (live && done) {
        done();
    }
}

// A finger's drag down the list, held by the finger until it lets go. The journal says
// once per tour whether the list took the finger.
static void tourDrag(UITableView* list, CGFloat distance, dispatch_block_t done) {
    static NSUInteger toldGeneration;
    if (!list) {
        return;
    }
    NSUInteger token = ++gPFBTourDragToken;
    if (tourFingerReady()) {
        atomic_store_explicit(&gPFBTourFingerList, (__bridge void*)list, memory_order_relaxed);
    }
    @try {
        if (toldGeneration != gPFBTourGeneration) {
            toldGeneration = gPFBTourGeneration;
            PFBCompatTourLog(@"[tour] drag: %@", list.isDragging ? @"the list says a finger holds it"
                                                                 : @"the list answers on its own");
        }
        id<UITableViewDelegate> delegate = list.delegate;
        if ([delegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
            [delegate scrollViewWillBeginDragging:list];
        }
    } @catch (id exception) {
        atomic_store_explicit(&gPFBTourFingerList, NULL, memory_order_relaxed);
        @throw;
    }
    tourDragFrame(list, distance / kPFBTourDragSteps, kPFBTourDragSteps, list.contentOffset.y, token,
                  gPFBTourGeneration, done);
}

// The action names a control sends on a tap, whatever its target.
static NSArray<NSString*>* tourControlActions(UIControl* control) {
    NSMutableOrderedSet<NSString*>* found = [NSMutableOrderedSet orderedSet];
    const UIControlEvents events[] = {UIControlEventTouchUpInside, UIControlEventPrimaryActionTriggered,
                                      UIControlEventTouchDown};
    for (id target in control.allTargets) {
        id receiver = target == [NSNull null] ? nil : target;
        for (size_t i = 0; i < sizeof(events) / sizeof(events[0]); i++) {
            [found addObjectsFromArray:[control actionsForTarget:receiver forControlEvent:events[i]] ?: @[]];
        }
    }
    return found.array;
}

// Whether a control under the root sends the action; what the controls send goes to
// the log, so a rewired button shows how.
static BOOL tourWired(UIView* root, NSString* action, NSMutableArray<NSString*>* seen) {
    __block BOOL wired = NO;
    tourFindView(root, ^BOOL(UIView* view) {
      if ([view isKindOfClass:[UIControl class]]) {
          NSArray<NSString*>* actions = tourControlActions((UIControl*)view);
          if (actions.count) {
              [seen addObject:[NSString stringWithFormat:@"%@ %@", NSStringFromClass([view class]),
                                                         [actions componentsJoinedByString:@" "]]];
          }
          wired = [actions containsObject:action];
      }
      return wired;
    });
    return wired;
}

// A gesture recognizer under the root whose target action has the name; the
// recognizer's own description lists its targets.
static UIGestureRecognizer* tourGesture(UIView* root, NSString* action) {
    NSString* mark = [@"action=" stringByAppendingString:action];
    __block UIGestureRecognizer* found = nil;
    tourFindView(root, ^BOOL(UIView* view) {
      for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
          if ([recognizer.description containsString:mark]) {
              found = recognizer;
              return YES;
          }
      }
      return NO;
    });
    return found;
}

// MARK: - Step checks

// A Tweet's buttons, read without a tap: like and reply relay to the hooked inline
// actions, the share button's long press to the hooked handler. Where a relay cannot
// be read, the hooked class on screen is the proof, named as such.
static BOOL tourCheckTweetButtons(void) {
    UIView* actions = tourHomeViewOfClass(@"TTAStatusInlineActionsView");
    if (!actions) {
        return NO;
    }
    BOOL relays = [actions respondsToSelector:NSSelectorFromString(@"didTapInlineActionButton:")];
    NSMutableArray<NSString*>* seen = [NSMutableArray array];
    UIView* like = tourFindClass(actions, @"TTAStatusInlineFavoriteButton");
    if (like && relays) {
        PFBCompatObserve(PFBCompat_like_confirm, tourWired(like, @"didTap", seen) ? @"like button wired"
                                                                                   : @"inline actions shown");
    }
    UIView* reply = tourFindClass(actions, @"TTAStatusInlineReplyButton");
    if (reply && relays) {
        PFBCompatObserve(PFBCompat_reply_in_webview, tourWired(reply, @"didTap", seen) ? @"reply button wired"
                                                                                       : @"inline actions shown");
    }
    UIView* share = tourFindClass(actions, @"TTAStatusInlineShareButton");
    if (share) {
        PFBCompatObserve(PFBCompat_tweet_to_image, tourGesture(share, @"didLongPressActionButton:")
                                                       ? @"share long press wired"
                                                       : @"share button shown");
    }
    return YES;
}

// The caret of the first Tweet, tapped through its own handler: the menu it arms or
// opens goes through the hook Hide conversations uses. Returns the caret to close.
static UIControl* tourOpenTweetMenu(void) {
    UIView* author = tourHomeViewOfClass(@"TTAStatusAuthorView");
    id caret = tourGetter(author, @"caretButton");
    tourSend(author, @"_didTapCaret");
    return [caret isKindOfClass:[UIControl class]] ? caret : nil;
}

// The media view around a Tweet's video or photos, tapped at its first item: the route
// a tap on the media takes.
static void tourTapMedia(UIView* media, NSString* step) {
    UIView* forward = tourAncestor(media, @"T1StatusPhotoVideoForwardView");
    SEL open = NSSelectorFromString(@"_t1_mediaTapActionAtIndex:");
    if (![forward respondsToSelector:open]) {
        PFBCompatTourLog(@"[tour] %@: %@", step, media ? @"no media view around it" : @"nothing to tap");
        return;
    }
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(forward, open, 0);
}

// The first video on Home, opened full screen: a player through its own tap handler, with
// the tap recognizer it expects; a preview through the media view around it. Returns the
// video, for the second way in.
static UIView* tourOpenVideo(void) {
    UIView* video = tourHomeVideo(@"video full screen");
    if (video && !tourIsKind(video, @"T1InlineVideoView")) {
        tourTapMedia(video, @"video full screen");
        return video;
    }
    UIGestureRecognizer* tap = tourGesture(video, @"handleTapWithTapRecognizer:");
    for (UIGestureRecognizer* recognizer in video.gestureRecognizers) {
        if (!tap && [recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
            tap = recognizer;
        }
    }
    SEL open = NSSelectorFromString(@"handleTapWithTapRecognizer:");
    if (!tap || ![video respondsToSelector:open]) {
        PFBCompatTourLog(@"[tour] video full screen: %@", video ? @"no tap recognizer on the video" : @"no video found");
        return video;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(video, open, tap);
    return video;
}

// The full-screen player's double tap is the like Confirm likes guards there.
static BOOL tourCheckDoubleTapLike(void) {
    UIView* root = tourRootController().presentedViewController.view ?: tourWindow();
    UIView* plugin = tourFindClass(root, @"_TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView");
    if (plugin) {
        PFBCompatObserve(PFBCompat_like_confirm, tourGesture(plugin, @"handleDoubleTap:") ? @"double tap like wired"
                                                                                          : @"double tap like shown");
    }
    return plugin != nil;
}

// A long press on a Tweet's media is the timeline table's context menu: UIKit asks the
// list's delegate for it at the point pressed. Asked here at the video's center, its
// entries are built without the menu showing, through the same hooks; YES when it has entries.
static BOOL tourTableMenuDoor(UIView* video, NSString* pass) {
    UITableView* list = (UITableView*)tourAncestor(video, @"UITableView");
    UITableViewCell* cell = (UITableViewCell*)tourAncestor(video, @"UITableViewCell");
    NSIndexPath* row = cell ? [list indexPathForCell:cell] : nil;
    id<UITableViewDelegate> delegate = list.delegate;
    SEL build = @selector(tableView:contextMenuConfigurationForRowAtIndexPath:point:);
    if (!row || ![delegate respondsToSelector:build]) {
        PFBCompatTourLog(@"[tour] video long press: %@", !row ? @"no row under the video" : @"the list builds no context menu");
        return NO;
    }
    CGPoint point = [video convertPoint:CGPointMake(CGRectGetMidX(video.bounds), CGRectGetMidY(video.bounds))
                                 toView:list];
    UIContextMenuConfiguration* configuration =
        [delegate tableView:list contextMenuConfigurationForRowAtIndexPath:row point:point];
    UIMenu* (^provider)(NSArray<UIMenuElement*>*) = nil;
    @try {
        provider = (UIMenu * (^)(NSArray<UIMenuElement*>*))[configuration valueForKey:@"actionProvider"];
    } @catch (__unused NSException* exception) {
        provider = nil;
    }
    UIMenu* menu = provider ? provider(@[]) : nil;
    return menu.children.count > 0;
}

// Among the Tweets of Home's first screens, the author with the longest bio, so the
// profile opened has one long enough to clip; nil when no author can be read.
static id tourLongestBioAuthor(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    NSString* own = tourGetter(account, @"username");
    id best = nil;
    NSUInteger longest = 0;
    UITableView* list = tourFrontList();
    for (NSInteger screen = 0; list && screen < 3; screen++) {
        for (UITableViewCell* cell in list.visibleCells) {
            id user = tourGetter(tourGetter(tourFindClass(cell, @"T1StandardStatusView"), @"viewModel"), @"fromUser");
            NSString* handle = tourGetter(user, @"username");
            NSString* bio = tourGetter(user, @"bio");
            if (![handle isKindOfClass:[NSString class]] ||
                [handle caseInsensitiveCompare:[own isKindOfClass:[NSString class]] ? own : @""] == NSOrderedSame) {
                continue;
            }
            NSUInteger length = [bio isKindOfClass:[NSString class]] ? bio.length : 0;
            if (!best || length > longest) {
                best = user;
                longest = length;
            }
        }
        [list setContentOffset:CGPointMake(list.contentOffset.x, list.contentOffset.y + list.bounds.size.height * 0.8)
                      animated:NO];
        [list layoutIfNeeded];
    }
    tourScrollHomeToTop();
    return best;
}

// A 64-bit integer a getter returns, read only when its signature says it returns one.
static long long tourLongLongGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) {
        return 0;
    }
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    if (signature.numberOfArguments != 2 || (type[0] != 'q' && type[0] != 'Q')) {
        return 0;
    }
    return ((long long (*)(id, SEL))objc_msgSend)(object, selector);
}

// Twitter's own profile command, with the account ID when known, as its own callers
// send it: no panel, no source.
static void tourShowProfile(NSString* handle, long long userID) {
    id navigation = tourAppNavigation();
    SEL show = NSSelectorFromString(@"showProfileForUsername:orUserID:fromPanel:source:sourceNavigationMetadata:completion:");
    if (![navigation respondsToSelector:show]) {
        PFBCompatTourLog(@"[tour] other profile: no profile command (%@)",
                         navigation ? NSStringFromClass([navigation class]) : @"no navigation");
        return;
    }
    ((void (*)(id, SEL, NSString*, long long, long long, long long, id, id))objc_msgSend)(navigation, show, handle,
                                                                                          userID, 0, 0, nil, nil);
}

// A profile's "…" menu, built the way its button builds it, without showing it.
static void tourBuildProfileMenu(UIViewController* profile) {
    UIViewController* header = tourFindController(profile, @"T1ProfileHeaderViewController");
    SEL build = NSSelectorFromString(@"profileMoreActionsBaseActionItemsWithSender:");
    if (![header respondsToSelector:build]) {
        PFBCompatTourLog(@"[tour] other profile: no profile menu (%@)",
                         header ? NSStringFromClass([header class]) : @"no header");
        return;
    }
    ((NSArray* (*)(id, SEL, id))objc_msgSend)(header, build, header.view);
}

// Twitter's settings opened the way the side menu's "Settings and privacy" row does,
// in the current tab.
static void tourShowTwitterSettings(void) {
    UIViewController* tabs = tourFindController(tourRootController(), @"T1TabbedAppNavigationViewController");
    id presenter = tourGetter(tourGetter(tabs, @"dashContentController"), @"presenter");
    if (!tourSend(presenter, @"showSettings")) {
        PFBCompatTourLog(@"[tour] Twitter settings: no side menu action (%@)",
                         presenter ? NSStringFromClass([presenter class]) : @"no presenter");
    }
}

// The full-screen player's card swipe, asked the question UIKit asks as a swipe starts.
static void tourAskCardSwipe(void) {
    UIViewController* player = tourFindController(tourRootController(), @"T1ImmersiveViewController");
    Class cls = [player class];
    Ivar ivar = cls ? class_getInstanceVariable(cls, "$__lazy_storage_$_panRecognizer") : NULL;
    id pan = ivar ? object_getIvar(player, ivar) : nil;
    if (![pan isKindOfClass:[UIGestureRecognizer class]] ||
        ![player respondsToSelector:@selector(gestureRecognizerShouldBegin:)]) {
        PFBCompatTourLog(@"[tour] video full screen: card swipe %@", player ? @"not found" : @"no full-screen player");
        return;
    }
    [(id<UIGestureRecognizerDelegate>)player gestureRecognizerShouldBegin:pan];
}

// Whether the full-screen video may shrink into the bottom player, asked the way
// closing it would; the question has no side effect.
static void tourAskDocking(void) {
    UIViewController* player = tourFindController(tourRootController(), @"T1ImmersiveFullScreenViewController");
    SEL question = NSSelectorFromString(@"_canDockCurrentVideoToBottomSegment");
    if (![player respondsToSelector:question]) {
        PFBCompatTourLog(@"[tour] video full screen: docking not asked, %@",
                         player ? @"question absent" : @"no full-screen player");
        return;
    }
    ((BOOL (*)(id, SEL))objc_msgSend)(player, question);
}

// The handle of the first author on Home who is not the account itself.
static NSString* tourAuthorHandle(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    NSString* own = tourGetter(account, @"username");
    NSCharacterSet* allowed = [NSCharacterSet
        characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    for (UITableViewCell* cell in tourFrontList().visibleCells) {
        UIView* author = tourFindClass(cell, @"TTAStatusAuthorView");
        __block NSString* handle = nil;
        tourFindView(author, ^BOOL(UIView* view) {
          NSString* text = [view isKindOfClass:[UILabel class]] ? ((UILabel*)view).text : nil;
          NSRange at = [text rangeOfString:@"@"];
          if (at.location == NSNotFound) {
              return NO;
          }
          NSMutableString* name = [NSMutableString string];
          for (NSUInteger i = NSMaxRange(at); i < text.length && [allowed characterIsMember:[text characterAtIndex:i]]; i++) {
              [name appendFormat:@"%C", [text characterAtIndex:i]];
          }
          handle = name.length ? name : nil;
          return handle != nil;
        });
        if (handle && [handle caseInsensitiveCompare:([own isKindOfClass:[NSString class]] ? own : @"")] != NSOrderedSame) {
            return handle;
        }
    }
    return nil;
}

// The Follow button of a profile: wired to the handler Confirm follows hooks, or at
// least of the hooked class.
static BOOL tourCheckFollowButton(UIViewController* profile) {
    UIView* button = tourFindClass(profile.viewIfLoaded, @"TUIFollowButtonV2");
    if (!button) {
        return NO;
    }
    NSMutableArray<NSString*>* seen = [NSMutableArray array];
    BOOL wired = tourWired(button, @"buttonTapped", seen);
    PFBCompatObserve(PFBCompat_follow_confirm, wired ? @"Follow button wired" : @"Follow button of the hooked class shown");
    return YES;
}

// The reply bar under an opened Tweet: its taps reach the controller Reply in web view
// hooks, and its send button the handler Confirm Tweets hooks.
static BOOL tourCheckReplyBar(void) {
    UIViewController* bar = tourFindController(tourScreen(), @"T1PersistentComposeViewController");
    if (!bar) {
        return NO;
    }
    UIView* view = bar.viewIfLoaded;
    UIView* relay = tourFindView(view, ^BOOL(UIView* candidate) {
      return tourGetter(candidate, @"delegate") == bar;
    });
    if (relay && [bar respondsToSelector:NSSelectorFromString(@"persistentComposeViewDidTap:")]) {
        PFBCompatObserve(PFBCompat_reply_in_webview, @"reply bar wired");
    }
    id send = tourGetter(bar, @"sendReplyButton") ?: tourGetter(bar, @"sendButton");
    NSArray<NSString*>* actions = [send isKindOfClass:[UIControl class]] ? tourControlActions(send) : @[];
    BOOL wired = [actions containsObject:@"_t1_didTapReply:"] || [actions containsObject:@"_t1_sendReply"];
    if ([bar respondsToSelector:NSSelectorFromString(@"_t1_sendReply")] && (wired || send)) {
        PFBCompatObserve(PFBCompat_tweet_confirm, wired ? @"reply send button wired" : @"reply bar of the hooked class shown");
    }
    return YES;
}

// The composer's send button, wired to the handler Confirm Tweets hooks.
static void tourCheckSendButton(UIViewController* composer) {
    SEL send = NSSelectorFromString(@"_t1_didTapSendButton:");
    NSMutableArray<NSString*>* seen = [NSMutableArray array];
    BOOL wired = tourWired(composer.navigationController.viewIfLoaded ?: composer.viewIfLoaded, @"_t1_didTapSendButton:", seen);
    NSMutableArray<UIBarButtonItem*>* items = [NSMutableArray array];
    [items addObjectsFromArray:composer.navigationItem.rightBarButtonItems ?: @[]];
    [items addObjectsFromArray:composer.navigationItem.leftBarButtonItems ?: @[]];
    for (UIBarButtonItem* item in items) {
        wired = wired || item.action == send;
    }
    if ([composer respondsToSelector:send]) {
        PFBCompatObserve(PFBCompat_tweet_confirm, wired ? @"send button wired" : @"composer of the hooked class shown");
    }
}

// The Tweet the first Tweet step opens, the first the front list shows without a link
// card or else the first one: its ID and its author's, read from its status view.
static BOOL tourFirstTweetIDs(NSInteger* statusID, NSInteger* authorID) {
    UITableView* list = tourFrontList();
    Class statusCell = NSClassFromString(@"T1StatusCell");
    UITableViewCell* tweet = nil;
    for (NSIndexPath* row in [list.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)]) {
        UITableViewCell* cell = [list cellForRowAtIndexPath:row];
        if (!statusCell || ![cell isKindOfClass:statusCell]) {
            continue;
        }
        if (!tourFindClass(cell, @"T1UnifiedCardView")) {
            tweet = cell;
            break;
        }
        tweet = tweet ?: cell;
    }
    id model = tourGetter(tourFindClass(tweet, @"T1StandardStatusView"), @"viewModel");
    *statusID = tourIntegerGetter(model, @"statusID");
    *authorID = tourIntegerGetter(model, @"fromUserID");
    return *statusID != NSNotFound && *authorID != NSNotFound;
}

// Twitter's screen of that Tweet's quotes, retweets and likes, built through its class
// factory on the Quotes tab (1) and pushed on the stack in front.
static void tourShowTweetInteractions(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    Class screenClass = NSClassFromString(@"T1PostInteractionsViewController");
    SEL build = NSSelectorFromString(@"viewControllerWithAccount:statusID:statusUserID:initialTab:");
    NSMethodSignature* signature =
        [screenClass respondsToSelector:build] ? [screenClass methodSignatureForSelector:build] : nil;
    BOOL buildable = signature.numberOfArguments == 6 && signature.methodReturnType[0] == '@' &&
                     [signature getArgumentTypeAtIndex:2][0] == '@';
    for (NSUInteger i = 3; buildable && i < 6; i++) {
        buildable = strcmp([signature getArgumentTypeAtIndex:i], @encode(long long)) == 0;
    }
    NSInteger statusID = NSNotFound;
    NSInteger authorID = NSNotFound;
    BOOL found = tourFirstTweetIDs(&statusID, &authorID);
    UINavigationController* stack = tourScreen().navigationController;
    if (!buildable || !found || !stack || ![account isKindOfClass:NSClassFromString(@"TFNTwitterAccount")]) {
        PFBCompatTourLog(@"[tour] Tweet interactions: factory %@, Tweet %@, stack %@, account %@",
                         buildable ? @"usable" : @"not usable", found ? @"read" : @"not found",
                         stack ? @"found" : @"none", account ? NSStringFromClass([account class]) : @"none");
        return;
    }
    UIViewController* screen = ((id (*)(id, SEL, id, long long, long long, long long))objc_msgSend)(
        screenClass, build, account, statusID, authorID, 1);
    [stack pushViewController:screen animated:NO];
}

// The first Tweet's edit history, built by the factory its "Last edited" link uses,
// without showing it.
static void tourBuildEditHistory(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    Class factory = NSClassFromString(@"T1EditHistoryViewControllerFactory");
    SEL build = NSSelectorFromString(@"viewControllerWithAccount:tweetID:scribeContext:");
    NSMethodSignature* signature = [factory respondsToSelector:build] ? [factory methodSignatureForSelector:build] : nil;
    BOOL buildable = signature.numberOfArguments == 5 && signature.methodReturnType[0] == '@' &&
                     [signature getArgumentTypeAtIndex:2][0] == '@' &&
                     strcmp([signature getArgumentTypeAtIndex:3], @encode(unsigned long long)) == 0 &&
                     [signature getArgumentTypeAtIndex:4][0] == '@';
    Class scribeClass = NSClassFromString(@"TFSTwitterScribeContext");
    SEL makeScribe = NSSelectorFromString(@"scribeContextWithPage:");
    id scribe = [scribeClass respondsToSelector:makeScribe]
                    ? ((id (*)(id, SEL, id))objc_msgSend)(scribeClass, makeScribe, @"tweet")
                    : nil;
    NSInteger statusID = NSNotFound;
    NSInteger authorID = NSNotFound;
    BOOL found = tourFirstTweetIDs(&statusID, &authorID);
    if (!buildable || !scribe || !found || ![account isKindOfClass:NSClassFromString(@"TFNTwitterAccount")]) {
        PFBCompatTourLog(@"[tour] edit history: factory %@, scribe %@, Tweet %@, account %@",
                         buildable ? @"usable" : @"not usable", scribe ? @"made" : @"not made",
                         found ? @"read" : @"not found", account ? NSStringFromClass([account class]) : @"none");
        return;
    }
    ((id (*)(id, SEL, id, unsigned long long, id))objc_msgSend)(factory, build, account,
                                                                (unsigned long long)statusID, scribe);
}

// Why a conversation row may be unread, or nil when it reads as read. Opening an
// unread one would send a read receipt, so a row that says nothing is left alone too.
static NSString* tourUnreadMark(UIView* cell) {
    NSMutableString* text = [NSMutableString stringWithString:cell.accessibilityLabel ?: @""];
    [text appendString:cell.accessibilityValue ?: @""];
    tourFindView(cell, ^BOOL(UIView* view) {
      if ([view isKindOfClass:[UILabel class]]) {
          [text appendString:((UILabel*)view).text ?: @""];
      }
      return NO;
    });
    if (text.length == 0) {
        return @"nothing readable";
    }
    // The English word, then Twitter's own word for the inbox's unread filter.
    NSString* lower = text.lowercaseString;
    NSString* key = @"DM_INBOX_PILL_UNREAD_TITLE";
    NSString* word = [[PFBBundle sharedBundle] localizedTwitterStringForKey:key].lowercaseString;
    if ([lower containsString:@"unread"] || (![word isEqualToString:key.lowercaseString] && [lower containsString:word])) {
        return @"marked unread";
    }
    // A small round dot of any vivid color: the accent can repaint Twitter's blue.
    UIView* dot = tourFindView(cell, ^BOOL(UIView* view) {
      CGSize size = view.bounds.size;
      CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
      return !view.hidden && size.width >= 4 && size.width <= 14 && fabs(size.width - size.height) < 1.0 &&
             [view.backgroundColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha] &&
             alpha > 0.5 && saturation > 0.4 && brightness > 0.4;
    });
    return dot ? @"unread dot" : nil;
}

// What an inbox row is, or nil for a conversation. Twitter shows its suggested accounts
// in conversation rows too, each with a "Chat" button; a conversation row has a button
// only for a call to join. A button with no readable title leaves its row unknown.
static NSString* tourInboxRowKind(UIView* cell) {
    Class conversation = NSClassFromString(@"_TtC20ChatConversationList24ConversationListItemCell");
    if (!conversation) {
        return nil;
    }
    if (![cell isKindOfClass:conversation]) {
        return [NSStringFromClass([cell class]) componentsSeparatedByString:@"."].lastObject;
    }
    UIView* content = tourFindClass(cell, @"_TtC20ChatConversationList31ConversationListItemContentView");
    Ivar ivar = content ? class_getInstanceVariable([content class], "accessoryButton") : NULL;
    UIView* button = ivar ? object_getIvar(content, ivar) : nil;
    if (![button isKindOfClass:[UIView class]] || !tourOnScreen(button)) {
        return nil;
    }
    NSMutableString* title = [NSMutableString stringWithString:button.accessibilityLabel ?: @""];
    tourFindView(button, ^BOOL(UIView* view) {
      if ([view isKindOfClass:[UILabel class]]) {
          [title appendString:((UILabel*)view).text ?: @""];
      }
      return NO;
    });
    NSString* chat = [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"CHAT_COLD_INBOX_CHAT_BUTTON_TITLE"];
    if (chat.length && [title containsString:chat]) {
        return @"suggested account";
    }
    return title.length ? nil : @"untitled button";
}

// Each kind once, with its count when it repeats, in the order first seen.
static NSString* tourCounted(NSArray<NSString*>* kinds) {
    NSCountedSet* counts = [[NSCountedSet alloc] initWithArray:kinds];
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* kind in [NSOrderedSet orderedSetWithArray:kinds]) {
        NSUInteger count = [counts countForObject:kind];
        [parts addObject:count > 1 ? [NSString stringWithFormat:@"%lu %@", (unsigned long)count, kind] : kind];
    }
    return parts.count ? [parts componentsJoinedByString:@", "] : @"none";
}

// The first conversation of the inbox known to be read, opened the way a tap does. On
// the last look, an inbox done loading that shows no conversation ends the step on that.
static void tourOpenReadConversation(BOOL lastLook) {
    UIScrollView* list = nil;
    for (UIView* view = tourFrontView(); view && !list; view = view.superview) {
        if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) {
            list = (UIScrollView*)view;
        }
    }
    UITableView* table = [list isKindOfClass:[UITableView class]] ? (UITableView*)list : nil;
    UICollectionView* grid = [list isKindOfClass:[UICollectionView class]] ? (UICollectionView*)list : nil;
    NSArray<UIView*>* cells = table ? (NSArray<UIView*>*)table.visibleCells : (NSArray<UIView*>*)grid.visibleCells;
    cells = [cells sortedArrayUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
      return a.frame.origin.y < b.frame.origin.y ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSString*>* skipped = [NSMutableArray array];
    NSMutableArray<NSString*>* others = [NSMutableArray array];
    NSUInteger conversations = 0;
    for (UIView* cell in cells) {
        NSString* kind = tourInboxRowKind(cell);
        if (kind) {
            [skipped addObject:kind];
            [others addObject:kind];
            conversations += [kind isEqualToString:@"untitled button"] ? 1 : 0;
            continue;
        }
        conversations++;
        NSString* unread = tourUnreadMark(cell);
        if (unread) {
            [skipped addObject:unread];
            continue;
        }
        NSIndexPath* row = table ? [table indexPathForCell:(UITableViewCell*)cell]
                                 : [grid indexPathForCell:(UICollectionViewCell*)cell];
        if (!row) {
            continue;
        }
        if (table && [table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
            [table.delegate tableView:table didSelectRowAtIndexPath:row];
        } else if (grid && [grid.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
            [grid.delegate collectionView:grid didSelectItemAtIndexPath:row];
        } else {
            PFBCompatTourLog(@"[tour] conversation: %@ takes no selection", NSStringFromClass([list class]));
            return;
        }
        return;
    }
    UIView* screen = tourScreen().view;
    BOOL (^shown)(NSString*) = ^BOOL(NSString* part) {
      return tourFindView(screen, ^BOOL(UIView* view) {
               return [NSStringFromClass([view class]) containsString:part] && tourOnScreen(view);
             }) != nil;
    };
    BOOL loading = [others containsObject:@"ConversationListLoadingCell"] || shown(@"ConversationListShimmerView");
    BOOL emptyState = shown(@"EmptyState");
    if (lastLook && conversations == 0 && !loading && (list || emptyState)) {
        gPFBTourStepEmpty = @"none in the inbox";
        PFBCompatTourLog(@"[tour] conversation: no conversation in the inbox (rows: %@%@)", tourCounted(others),
                         emptyState ? @", empty state shown" : @"");
        return;
    }
    PFBCompatTourLog(@"[tour] conversation: no conversation known to be read in %@ (%@%@)",
                list ? NSStringFromClass([list class]) : @"no list",
                cells.count ? tourCounted(skipped) : @"no rows", loading ? @", still loading" : @"");
}

// The controller that shows the side menu.
static id tourSideMenuOwner(void) {
    UIViewController* split = tourFindController(tourRootController(), @"T1AppSplitViewController");
    return [split respondsToSelector:NSSelectorFromString(@"presentDashFromViewController:animated:completion:")] ? split
                                                                                                                  : nil;
}

static void tourOpenSideMenu(void) {
    id owner = tourSideMenuOwner();
    if (!owner) {
        PFBCompatTourLog(@"[tour] side menu: no controller opens it");
        return;
    }
    ((void (*)(id, SEL, id, BOOL, dispatch_block_t))objc_msgSend)(
        owner, NSSelectorFromString(@"presentDashFromViewController:animated:completion:"), tourScreen(), NO, ^{
        });
}

static void tourCloseSideMenu(void) {
    id owner = tourSideMenuOwner();
    SEL close = NSSelectorFromString(@"private_dashShowContentViewControllerAnimated:completion:");
    if (tourBoolGetter(owner, @"isDashOpen") && [owner respondsToSelector:close]) {
        ((void (*)(id, SEL, BOOL, dispatch_block_t))objc_msgSend)(owner, close, NO, ^{
        });
    }
}

// Apple's in-app browser on a neutral page, as Twitter shows help pages and some links;
// Twitter's own browser traps the initializer a plain URL would need.
static void tourOpenWebLink(void) {
    NSURL* url = [NSURL URLWithString:@"https://example.com"];
    SFSafariViewController* browser = [[SFSafariViewController alloc] initWithURL:url];
    [tourTopController() presentViewController:browser animated:NO completion:nil];
}

// Whether a class method's code lives in this library: the hook installed here is the
// one Twitter reaches.
static BOOL tourHookedHere(Class cls, SEL selector) {
    Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    Dl_info here = {0};
    Dl_info there = {0};
    return method && dladdr((const void*)&tourHookedHere, &here) &&
           dladdr((const void*)method_getImplementation(method), &there) && here.dli_fbase == there.dli_fbase;
}

// Twitter's t.co click count, safety check and click ID, asked for a t.co link the way
// Twitter asks them, only while the hooks installed here answer them: nothing is sent.
static void tourAskTcoRequests(void) {
    NSURL* link = [NSURL URLWithString:@"https://t.co/pfbtour"];
    Class clickIDs = NSClassFromString(@"T1TwitterClickIDHandler");
    SEL append = NSSelectorFromString(@"URLByAppendingTwitterClickIDIfNecessary:status:account:scribePage:scribeComponent:");
    if (tourHookedHere(clickIDs, append)) {
        ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(clickIDs, append, link, nil, nil, nil, nil);
    } else {
        PFBCompatTourLog(@"[tour] t.co check: click ID not asked, not hooked");
    }
    Class talon = NSClassFromString(@"TNUTalonUtilities");
    SEL count = NSSelectorFromString(@"sendTalonRequestForAnalytics:");
    SEL check = NSSelectorFromString(@"verifyTalonURL:completion:");
    BOOL countHooked = tourHookedHere(talon, count);
    BOOL checkHooked = tourHookedHere(talon, check);
    if (!countHooked || !checkHooked) {
        PFBCompatTourLog(@"[tour] t.co check: not asked, click count %@, safety check %@",
                         countHooked ? @"hooked" : @"not hooked", checkHooked ? @"hooked" : @"not hooked");
        return;
    }
    ((BOOL (*)(id, SEL, id))objc_msgSend)(talon, count, link);
    ((id (*)(id, SEL, id, id))objc_msgSend)(talon, check, link, nil);
}

// Twitter's own color settings: its palette decides dark mode, not the window's style.
static id tourColorSettings(void) {
    Class settings = NSClassFromString(@"TAEColorSettings");
    SEL shared = NSSelectorFromString(@"sharedSettings");
    return [settings respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(settings, shared) : nil;
}

static id tourPalette(void) {
    return tourGetter(tourColorSettings(), @"currentColorPalette");
}

static NSString* tourPaletteName(id palette) {
    id name = tourGetter(palette, @"name");
    return [name isKindOfClass:[NSString class]] ? name : @"?";
}

static void tourSetPalette(id palette) {
    id settings = tourColorSettings();
    SEL set = NSSelectorFromString(@"setCurrentColorPalette:");
    if (!palette || ![settings respondsToSelector:set]) {
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(settings, set, palette);
    tourSend(settings, @"applyCurrentColorPalette");
}

// The first dark palette Twitter offers. The journal names the palette in use first,
// so a tour stopped midway gives it back at the next launch.
static void tourSwitchToDarkPalette(void) {
    id current = tourPalette();
    id available = tourGetter(tourColorSettings(), @"availableColorPalettes");
    for (id palette in [available isKindOfClass:[NSArray class]] ? available : @[]) {
        if (tourBoolGetter(palette, @"isDark")) {
            tourJournalWrite([@"palette: switched from " stringByAppendingString:tourPaletteName(current)]);
            gPFBTourPaletteBefore = current;
            tourSetPalette(palette);
            PFBCompatTourLog(@"[tour] dark mode: Twitter's palette switched to %@", tourPaletteName(palette));
            return;
        }
    }
    PFBCompatTourLog(@"[tour] dark mode: no dark palette among %lu offered", (unsigned long)[available count]);
}

static void tourRestorePalette(void) {
    if (!gPFBTourPaletteBefore) {
        return;
    }
    tourSetPalette(gPFBTourPaletteBefore);
    gPFBTourPaletteBefore = nil;
    tourJournalWrite(@"palette: restored");
}

static void tourRestorePaletteNamed(NSString* name) {
    id settings = tourColorSettings();
    SEL match = NSSelectorFromString(@"colorPaletteMatchingName:");
    if ([settings respondsToSelector:match]) {
        tourSetPalette(((id (*)(id, SEL, id))objc_msgSend)(settings, match, name));
    }
}

static UIView* tourFirstResponder(void) {
    return tourFindView(tourWindow(), ^BOOL(UIView* view) {
      return view.isFirstResponder;
    });
}

// The search screen's bar, tapped through its own handler: its field only takes the
// keyboard that way. Twitter then lists recent searches, the list Disable search
// history empties.
static BOOL tourFocusSearchField(void) {
    Class barClass = NSClassFromString(@"_TtC15TwitterSearchV29SearchBar");
    UIView* root = tourScreen().navigationController.viewIfLoaded ?: tourWindow();
    UIView* bar = barClass ? tourFindView(root, ^BOOL(UIView* view) {
      return [view isKindOfClass:barClass] && !view.hidden && view.window;
    })
                           : nil;
    UITextField* field = (UITextField*)tourFindView(bar, ^BOOL(UIView* view) {
      return [view isKindOfClass:[UITextField class]];
    });
    if (!bar) {
        return NO;
    }
    BOOL tapped = tourSend(bar, @"handleFocusTap");
    if (!tapped) {
        [field becomeFirstResponder];
    }
    return YES;
}

// One of PrimeFreeBird's pages with switches, shown over Twitter.
static void tourShowSettings(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    PFBModernSettingsPageViewController* page = [[PFBModernSettingsPageViewController alloc] initWithAccount:account
                                                                                                pageKey:@"general"];
    UINavigationController* stack = [[UINavigationController alloc] initWithRootViewController:page];
    [tourTopController() presentViewController:stack animated:NO completion:nil];
}

// Runs one part of a step. An exception there goes to the journal and leaves the step
// unreached, instead of closing Twitter.
static BOOL tourAttempt(NSString* step, NSString* part, dispatch_block_t body) {
    if (!body) {
        return YES;
    }
    @try {
        body();
        return YES;
    } @catch (NSException* exception) {
        PFBCompatTourLog(@"[tour] %@: exception during %@: %@: %@", step, part, exception.name, exception.reason);
        return NO;
    }
}

// MARK: - Options switched for one step

// A step can switch an option for its own screen. What the person had stays on disk
// until it is put back, so a tour Twitter closed gives it back at the next launch.
static NSString* const kPFBTourSwitchedKey = @"pfb_compat_tour_switched";

static void tourSwitchOption(NSString* key, BOOL value) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* stored = [defaults dictionaryForKey:kPFBTourSwitchedKey];
    NSMutableDictionary* saved = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (!saved[key]) {
        id had = [defaults objectForKey:key];
        saved[key] = had ? @{@"value": had} : @{};
        [defaults setObject:saved forKey:kPFBTourSwitchedKey];
    }
    [defaults setBool:value forKey:key];
    PFBCompatTourLog(@"[tour] %@ switched %@ for this step", key, value ? @"on" : @"off");
}

// Every option a step switched goes back to what the person had; one never set stays unset.
static void tourRestoreOptions(NSString* when) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* saved = [defaults dictionaryForKey:kPFBTourSwitchedKey];
    for (NSString* key in saved) {
        NSDictionary* entry = [saved[key] isKindOfClass:[NSDictionary class]] ? saved[key] : nil;
        if (entry[@"value"]) {
            [defaults setObject:entry[@"value"] forKey:key];
        } else {
            [defaults removeObjectForKey:key];
        }
        PFBCompatTourLog(@"[tour] %@ put back %@, %@", key, [PFBSettings boolForKey:key] ? @"on" : @"off", when);
    }
    [defaults removeObjectForKey:kPFBTourSwitchedKey];
}

// MARK: - Replies in date order

// Home's Tweet with the most replies, read from its first three screens, then the list
// back at its top. Left out: the Tweet the first Tweet step opens, and Tweets with a link
// card, which a tap can open instead. 0 when no Tweet shows a count.
static long long tourMostRepliedTweet(void) {
    NSInteger first = NSNotFound;
    NSInteger firstAuthor = NSNotFound;
    tourFirstTweetIDs(&first, &firstAuthor);
    long long best = 0;
    NSInteger bestCount = -1;
    tourScrollHomeToTop();
    UITableView* list = tourFrontList();
    [list layoutIfNeeded];
    for (NSInteger screen = 0; list && screen < 3; screen++) {
        for (UITableViewCell* cell in list.visibleCells) {
            if (tourFindClass(cell, @"T1UnifiedCardView")) {
                continue;
            }
            id model = tourGetter(tourFindClass(cell, @"T1StandardStatusView"), @"viewModel");
            NSInteger statusID = tourIntegerGetter(model, @"statusID");
            NSInteger count = tourIntegerGetter(model, @"displayReplyCount");
            if (count == NSNotFound) {
                count = tourIntegerGetter(model, @"replyCount");
            }
            if (statusID == NSNotFound || statusID <= 0 || statusID == first || count == NSNotFound) {
                continue;
            }
            if (count > bestCount) {
                best = statusID;
                bestCount = count;
            }
        }
        [list setContentOffset:CGPointMake(list.contentOffset.x, list.contentOffset.y + list.bounds.size.height * 0.8)
                      animated:NO];
        [list layoutIfNeeded];
    }
    tourScrollHomeToTop();
    if (best) {
        PFBCompatTourLog(@"[tour] replies: Tweet %lld picked on Home, %ld replies", best, (long)bestCount);
    } else {
        PFBCompatTourLog(@"[tour] replies: no Tweet with a reply count on Home's first screens");
    }
    return best;
}

// A Tweet of Home opened the way a tap does, as the first Tweet step opens its own: its
// row is looked for from the top, a screen at a time.
static BOOL tourOpenHomeTweet(long long statusID) {
    tourScrollHomeToTop();
    UITableView* list = tourFrontList();
    [list layoutIfNeeded];
    id<UITableViewDelegate> delegate = list.delegate;
    if (![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        PFBCompatTourLog(@"[tour] replies: %@", list ? @"Home's list takes no row selection" : @"no list in front");
        return NO;
    }
    for (NSInteger screen = 0; screen < 4; screen++) {
        for (NSIndexPath* row in [list.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)]) {
            id model = tourGetter(tourFindClass([list cellForRowAtIndexPath:row], @"T1StandardStatusView"), @"viewModel");
            if (tourIntegerGetter(model, @"statusID") == statusID) {
                [delegate tableView:list didSelectRowAtIndexPath:row];
                return YES;
            }
        }
        [list setContentOffset:CGPointMake(list.contentOffset.x, list.contentOffset.y + list.bounds.size.height * 0.8)
                      animated:NO];
        [list layoutIfNeeded];
    }
    PFBCompatTourLog(@"[tour] replies: Tweet %lld not found again on Home's first screens", statusID);
    return NO;
}

// The view model of the Tweet a cell shows: the first view under it whose model has a
// status ID, the focal Tweet's own view included.
static id tourStatusModel(UIView* cell) {
    __block id found = nil;
    tourFindView(cell, ^BOOL(UIView* view) {
      id model = tourGetter(view, @"viewModel");
      if (model && tourIntegerGetter(model, @"statusID") != NSNotFound) {
          found = model;
          return YES;
      }
      return NO;
    });
    return found;
}

// The direct replies to the focal Tweet now on screen, in their order, added after
// those already read. The focal author's own replies are left out: Twitter lists them
// first whatever the order.
static void tourReadReplies(long long focalID, NSInteger* focalAuthor, NSMutableArray<NSNumber*>* order) {
    UITableView* list = tourFrontList();
    for (NSIndexPath* row in [list.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)]) {
        id model = tourStatusModel([list cellForRowAtIndexPath:row]);
        NSInteger statusID = tourIntegerGetter(model, @"statusID");
        if (statusID == NSNotFound) {
            continue;
        }
        NSInteger author = tourIntegerGetter(model, @"fromUserID");
        if (statusID == focalID) {
            *focalAuthor = author;
            continue;
        }
        if (author != NSNotFound && author == *focalAuthor) {
            continue;
        }
        if (tourIntegerGetter(model, @"inReplyToStatusID") == focalID && ![order containsObject:@(statusID)]) {
            [order addObject:@(statusID)];
        }
    }
}

// A Tweet ID grows with its creation time, so the replies read are in date order when
// nearly every one is older than the one above it, or nearly every one newer. That
// order proves the option; the counts go to the journal either way.
static void tourJudgeReplies(long long focalID, NSArray<NSNumber*>* order) {
    NSInteger later = 0;
    NSInteger earlier = 0;
    for (NSUInteger i = 1; i < order.count; i++) {
        if (order[i].longLongValue > order[i - 1].longLongValue) {
            later++;
        } else {
            earlier++;
        }
    }
    NSInteger pairs = later + earlier;
    NSString* verdict = @"too few to tell";
    if (pairs >= 5) {
        verdict = earlier * 10 >= pairs * 9 ? @"newest first"
                                            : (later * 10 >= pairs * 9 ? @"oldest first" : @"not in date order");
    }
    if ([verdict hasSuffix:@"first"]) {
        PFBCompatReach(PFBCompatPath_replies_by_date);
    }
    PFBCompatTourLog(@"[tour] replies: Tweet %lld, %lu direct replies read, %ld newer than the one above, %ld older: %@",
                     focalID, (unsigned long)order.count, (long)later, (long)earlier, verdict);
}

// More of the front list, dragged a screen and a half at a time: each drag makes Twitter
// load and file the next items, which is where content-bound proofs come from.
static void tourDeepScroll(NSString* step, NSInteger drags) {
    NSUInteger generation = gPFBTourGeneration;
    for (NSInteger drag = 1; drag <= drags; drag++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * drag * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         if (generation != gPFBTourGeneration || ![gPFBTourStepLive isEqualToString:step]) {
                             return;
                         }
                         tourAttempt(step, @"scrolling further", ^{
                           UITableView* list = tourFrontList();
                           tourDrag(list, list.bounds.size.height * 1.5, nil);
                         });
                       });
    }
}

// MARK: - The steps

// A step: its name in the report, its label on screen, where it brings the app first,
// what it does there, how it knows its screen came up, a second way in when the first
// showed nothing, and how it leaves the app for the next step.
static NSDictionary* tourStep(NSString* name, NSString* label, dispatch_block_t setup, dispatch_block_t action,
                              PFBTourCheck check, dispatch_block_t door, dispatch_block_t after) {
    NSMutableDictionary* step = [@{
        @"name": name,
        @"label": label,
        @"setup": [setup copy],
        @"action": [action copy],
        @"check": [check copy]
    } mutableCopy];
    if (door) {
        step[@"door"] = [door copy];
    }
    if (after) {
        step[@"after"] = [after copy];
    }
    return step;
}

// A step whose check does a reading of its own: it ends when the check passes, or after
// its wait, whatever proofs it owes.
static NSDictionary* tourStepWaiting(NSTimeInterval wait, NSDictionary* step) {
    NSMutableDictionary* waiting = [step mutableCopy];
    waiting[@"wait"] = @(wait);
    return waiting;
}

// Every step in order. Each brings the app where it needs it, so any subset runs on
// its own.
static NSArray<NSDictionary*>* tourAllSteps(void) {
    dispatch_block_t home = ^{
      tourHomeFront();
    };
    dispatch_block_t root = ^{
      tourDismissPresented();
      tourPopToRoot();
    };
    PFBTourCheck changed = ^BOOL(UIViewController* before, UIViewController* after) {
      return after && after != before;
    };
    PFBTourCheck presented = ^BOOL(UIViewController* before, UIViewController* after) {
      return tourRootController().presentedViewController != nil;
    };
    NSMutableArray<NSDictionary*>* steps = [NSMutableArray array];
    NSArray<NSString*>* pages =
        [PFBCustomTabBarUtility visiblePageIDsInOrder] ?: [PFBCustomTabBarUtility defaultVisiblePageIDs];
    for (NSUInteger i = 1; i < pages.count; i++) {
        NSString* name = [@"tab " stringByAppendingString:pages[i]];
        BOOL explore = [pages[i] isEqualToString:@"guide"];
        [steps addObject:tourStep(name, tourTabTitle(pages[i]), root, ^{
                 tourSelectTab((NSInteger)i);
                 if (explore) {
                     tourDeepScroll(name, 3);
                 }
               }, changed, nil, nil)];
    }
    if (pages.count > 1) {
        [steps addObject:tourStep([@"tab " stringByAppendingString:pages[0]], tourTabTitle(pages[0]), root, ^{
                 tourSelectTab(0);
               }, ^BOOL(UIViewController* before, UIViewController* after) {
                 return tourHomeTabs() != nil;
               }, nil, nil)];
    }
    [steps addObject:tourStep(@"pull", @"Pull to refresh", home, ^{
             tourPull();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return PFBCompatPathReached(PFBCompatPath_pull_sound);
           }, nil, nil)];
    __block NSInteger tweetLooks = 0;
    __block BOOL replyBarRead = NO;
    [steps addObject:tourStep(@"first Tweet", @"First Tweet", home, ^{
             tweetLooks = 0;
             replyBarRead = NO;
             tourOpenFirstTweet();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             BOOL opened = after && after != before;
             // The second look scrolls the conversation down by 40% of the list's height, toward the replies.
             if (opened && ++tweetLooks == 2) {
                 UITableView* list = tourFrontList();
                 [list setContentOffset:CGPointMake(list.contentOffset.x,
                                                    list.contentOffset.y + list.bounds.size.height * 0.4)
                               animated:NO];
             }
             if (opened && !replyBarRead && tweetLooks >= 3) {
                 replyBarRead = tourCheckReplyBar();
             }
             return opened;
           }, nil, nil)];
    [steps addObject:tourStep(@"Tweet interactions", @"Tweet interactions", home, ^{
             tourShowTweetInteractions();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourFindController(after, @"T1PostInteractionsViewController") != nil;
           }, nil, ^{
             tourPopToRoot();
           })];
    [steps addObject:tourStep(@"edit history", @"Edit history", home, ^{
             tourAttempt(@"edit history", @"building it", ^{
               tourBuildEditHistory();
             });
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return PFBCompatPathReached(PFBCompatPath_verified_edit_history);
           }, nil, nil)];
    [steps addObject:tourStep(@"own profile", @"Your profile", root, ^{
             tourOpenOwnProfile();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return [tourScreenName(after) containsString:@"Profile"];
           }, nil, nil)];
    [steps addObject:tourStep(@"search", @"Search", root, ^{
             tourOpenLink(@"twitter://search?query=twitter");
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return [tourScreenName(after) containsString:@"Search"];
           }, nil, nil)];
    __block BOOL barTapped = NO;
    // Runs on the screen the search step leaves open: a search link opened later in the tour,
    // after the composer, goes nowhere.
    [steps addObject:tourStep(@"search field", @"Search field", ^{
           }, ^{
             barTapped = NO;
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             if (!barTapped && [tourScreenName(after) containsString:@"Search"]) {
                 barTapped = tourFocusSearchField();
             }
             return [tourFirstResponder() isKindOfClass:[UITextField class]];
           }, ^{
             if (![tourScreenName(tourScreen()) containsString:@"Search"]) {
                 tourOpenLink(@"twitter://search?query=news");
             }
           }, ^{
             [tourWindow() endEditing:YES];
             tourDismissPresented();
             tourPopToRoot();
             tourSelectTab(0);
           })];
    // Advanced search switched off for one search, whatever the setting says: Twitter's own
    // filter button must be back in the search bar. Before the composer, after which a
    // search link goes nowhere.
    [steps addObject:tourStep(@"search off", @"Search, Advanced search off", ^{
             root();
             tourSwitchOption(@"advanced_search", NO);
           }, ^{
             tourOpenLink(@"twitter://search?query=twitter");
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return [tourScreenName(after) containsString:@"Search"];
           }, nil, ^{
             tourRestoreOptions(@"after the step");
             tourDismissPresented();
             tourPopToRoot();
             tourSelectTab(0);
           })];
    [steps addObject:tourStep(@"refresh end", @"Refresh end", home, ^{
             // Posts that arrive while the list is away from its top come with the pill.
             UITableView* list = tourFrontList();
             tourDrag(list, list.bounds.size.height * 1.5, ^{
               if ([gPFBTourStepLive isEqualToString:@"refresh end"]) {
                   tourAttempt(@"refresh end", @"pulling", ^{
                     tourPull();
                   });
               }
             });
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return PFBCompatPathReached(PFBCompatPath_refresh_end_sound);
           }, nil, ^{
             tourScrollHomeToTop();
           })];
    __block __weak id homeTabs = nil;
    __block NSInteger homeTabShown = NSNotFound;
    [steps addObject:tourStep(@"following timeline", @"Following", home, ^{
             homeTabs = tourHomeTabs();
             homeTabShown = tourIntegerGetter(homeTabs, @"selectedIndex");
             NSInteger count = tourIntegerGetter(homeTabs, @"numberOfTabs");
             if (count != NSNotFound && count > 1) {
                 tourShowHomeTab(homeTabs, 1);
                 // Following shows placeholders until it is refreshed.
                 NSUInteger generation = gPFBTourGeneration;
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                   if (generation == gPFBTourGeneration && [gPFBTourStepLive isEqualToString:@"following timeline"]) {
                       tourAttempt(@"following timeline", @"refreshing", ^{
                         tourPull();
                       });
                   }
                 });
                 tourDeepScroll(@"following timeline", 3);
             }
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourIntegerGetter(homeTabs, @"selectedIndex") == 1;
           }, nil, ^{
             NSInteger shown = tourIntegerGetter(homeTabs, @"selectedIndex");
             if (homeTabShown != NSNotFound && homeTabShown != shown) {
                 tourShowHomeTab(homeTabs, homeTabShown);
             }
           })];
    __block CGFloat scrollStart = 0.0;
    [steps addObject:tourStep(@"scroll", @"Scroll", home, ^{
             UITableView* list = tourFrontList();
             scrollStart = list.contentOffset.y;
             tourDrag(list, list.bounds.size.height * 1.5, nil);
             tourDeepScroll(@"scroll", 3);
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             UITableView* list = tourFrontList();
             return list && list.contentOffset.y > scrollStart + 10.0;
           }, nil, ^{
             tourScrollHomeToTop();
           })];
    __block BOOL buttonsRead = NO;
    [steps addObject:tourStep(@"Tweet buttons", @"Tweet buttons", home, ^{
             buttonsRead = tourCheckTweetButtons();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return buttonsRead;
           }, nil, ^{
             tourScrollHomeToTop();
           })];
    __block __weak UIControl* caret = nil;
    [steps addObject:tourStep(@"Tweet menu", @"Tweet menu", home, ^{
             caret = tourOpenTweetMenu();
           }, presented, nil, ^{
             tourDismissPresented();
             [caret.contextMenuInteraction dismissMenu];
             tourScrollHomeToTop();
           })];
    __block __weak UIView* video = nil;
    __block BOOL doubleTapRead = NO;
    __block NSInteger playerLooks = 0;
    [steps addObject:tourStep(@"video full screen", @"Video full screen", home, ^{
             doubleTapRead = NO;
             playerLooks = 0;
             video = tourOpenVideo();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             BOOL open = tourRootController().presentedViewController != nil ||
                         [tourScreenName(after) containsString:@"Immersive"];
             if (open && !doubleTapRead) {
                 doubleTapRead = tourCheckDoubleTapLike();
             }
             if (open && ++playerLooks == 5) {
                 tourAttempt(@"video full screen", @"asking the card swipe", ^{
                   tourAskCardSwipe();
                 });
                 tourAttempt(@"video full screen", @"asking about docking", ^{
                   tourAskDocking();
                 });
             }
             return open;
           }, ^{
             tourTapMedia(video, @"video full screen");
           }, ^{
             tourDismissPresented();
             tourScrollHomeToTop();
           })];
    __block BOOL menuBuilt = NO;
    [steps addObject:tourStep(@"video long press", @"Video menu", home, ^{
             menuBuilt = NO;
             UIView* pressed = tourHomeVideo(@"video long press");
             menuBuilt = tourTableMenuDoor(pressed, @"first");
             // Twitter's share sheet names the Tweet a moment after an ask; the asks that
             // follow find it, as the menu of a real long press does, on the video the row
             // shows then, a preview having become its player.
             __weak UIView* weakPressed = pressed;
             __weak UITableViewCell* weakRow = (UITableViewCell*)tourAncestor(pressed, @"UITableViewCell");
             NSUInteger generation = gPFBTourGeneration;
             for (NSInteger ask = 1; ask <= 2; ask++) {
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * ask * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{
                                  if (generation == gPFBTourGeneration &&
                                      [gPFBTourStepLive isEqualToString:@"video long press"]) {
                                      tourAttempt(@"video long press", @"asking the menu again", ^{
                                        UIView* shown = tourFindClass(weakRow, @"T1InlineVideoView")
                                                            ?: tourFindClass(weakRow, @"T1InlineVideoFacadeView")
                                                            ?: weakPressed;
                                        menuBuilt = tourTableMenuDoor(shown, ask == 1 ? @"again" : @"a third time") || menuBuilt;
                                      });
                                  }
                                });
             }
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return menuBuilt;
           }, nil, ^{
             tourDismissPresented();
             tourScrollHomeToTop();
           })];
    __block __weak UIView* photos = nil;
    [steps addObject:tourStep(@"photo full screen", @"Photo full screen", home, ^{
             photos = tourHomeViewOfClass(@"_TtC21TweetMediaAttachments14MultiMediaView");
             tourTapMedia(photos, @"photo full screen");
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourRootController().presentedViewController != nil || (after && after != before);
           }, ^{
             BOOL sent = tourSend(tourAncestor(photos, @"T1StatusPhotoVideoForwardView"), @"_t1_imageTapAction");
             PFBCompatTourLog(@"[tour] photo full screen: image tap %@", sent ? @"sent" : @"not possible");
           }, ^{
             tourDismissPresented();
             tourPopToRoot();
             tourScrollHomeToTop();
           })];
    __block BOOL followRead = NO;
    __block BOOL profileMenuBuilt = NO;
    __block NSInteger profileLooks = 0;
    __block NSString* profileHandle = nil;
    __block long long profileUserID = 0;
    [steps addObject:tourStep(@"other profile", @"Another profile", home, ^{
             followRead = NO;
             profileMenuBuilt = NO;
             profileLooks = 0;
             id author = tourLongestBioAuthor();
             profileHandle = tourGetter(author, @"username") ?: tourAuthorHandle() ?: @"X";
             profileUserID = tourLongLongGetter(author, @"userID");
             BOOL taken = tourOpenLink([@"twitter://user?screen_name=" stringByAppendingString:profileHandle]);
             PFBCompatTourLog(@"[tour] other profile: link %@", taken ? @"taken by Twitter" : @"refused by Twitter");
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             BOOL profile = [tourScreenName(after) containsString:@"Profile"];
             if (profile && !followRead) {
                 followRead = tourCheckFollowButton(after);
             }
             if (profile && !profileMenuBuilt) {
                 profileMenuBuilt = YES;
                 tourAttempt(@"other profile", @"profile menu", ^{
                   tourBuildProfileMenu(after);
                 });
             }
             // Folded under the bar, the header shows the post count.
             if (profile && ++profileLooks == 6) {
                 tourAttempt(@"other profile", @"folding the header", ^{
                   UITableView* list = tourFrontList();
                   tourDrag(list, list.bounds.size.height * 0.8, nil);
                 });
             }
             return profile;
           }, ^{
             tourShowProfile(profileHandle, profileUserID);
           }, ^{
             tourPopToRoot();
           })];
    __block BOOL sendRead = NO;
    [steps addObject:tourStep(@"composer", @"Composer", root, ^{
             sendRead = NO;
             tourOpenLink(@"twitter://post");
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             UIViewController* composer =
                 tourFindController(tourRootController().presentedViewController, @"T1TweetComposeViewController");
             if (composer && !sendRead) {
                 sendRead = YES;
                 tourCheckSendButton(composer);
             }
             return composer != nil;
           }, ^{
             tourOpenLink(@"twitter://compose");
           }, ^{
             tourDismissPresented();
           })];
    NSUInteger messages = [pages indexOfObject:@"messages"];
    if (messages != NSNotFound) {
        __block NSString* inbox = nil;
        [steps addObject:tourStep(@"conversation", @"Conversation", root, ^{
                 inbox = nil;
                 tourSelectTab((NSInteger)messages);
                 NSUInteger generation = gPFBTourGeneration;
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{
                                  if (generation == gPFBTourGeneration) {
                                      tourAttempt(@"conversation", @"opening a row", ^{
                                        inbox = tourScreenName(tourScreen());
                                        tourOpenReadConversation(NO);
                                      });
                                  }
                                });
               }, ^BOOL(UIViewController* before, UIViewController* after) {
                 NSString* name = tourScreenName(after);
                 BOOL opened = inbox && ![name isEqualToString:inbox] &&
                               ([name containsString:@"Conversation"] || [name containsString:@"Chat"]);
                 gPFBTourStepEmpty = opened ? nil : gPFBTourStepEmpty;
                 return opened;
               }, ^{
                 // Chat may still be loading its conversations after the first look; with
                 // none by then, the step ends on an inbox with no conversation.
                 inbox = tourScreenName(tourScreen());
                 tourOpenReadConversation(YES);
               }, ^{
                 tourPopToRoot();
                 tourSelectTab(0);
               })];
    }
    // Sort replies on Most recent for one conversation, whatever the setting says (on reads
    // as Most recent): Home's Tweet with the most replies is opened, read at its top, then
    // three times a little further down, and its replies judged by their IDs.
    __block long long replyFocal = 0;
    __block NSInteger replyAuthor = NSNotFound;
    __block NSInteger replyLooks = 0;
    __block BOOL repliesRead = NO;
    NSMutableArray<NSNumber*>* replyOrder = [NSMutableArray array];
    [steps addObject:tourStepWaiting(8.0, tourStep(@"replies", @"Replies by date", ^{
                                                     tourHomeFront();
                                                     tourSwitchOption(@"reply_sorting", YES);
                                                   }, ^{
                                                     replyLooks = 0;
                                                     replyAuthor = NSNotFound;
                                                     repliesRead = NO;
                                                     [replyOrder removeAllObjects];
                                                     replyFocal = tourMostRepliedTweet();
                                                     if (replyFocal) {
                                                         tourOpenHomeTweet(replyFocal);
                                                     }
                                                   }, ^BOOL(UIViewController* before, UIViewController* after) {
                                                     if (repliesRead || !replyFocal ||
                                                         ![tourScreenName(after) containsString:@"Conversation"]) {
                                                         return repliesRead;
                                                     }
                                                     replyLooks++;
                                                     if (replyLooks == 5 || replyLooks == 8 || replyLooks == 11 ||
                                                         replyLooks == 14) {
                                                         tourReadReplies(replyFocal, &replyAuthor, replyOrder);
                                                         UITableView* list = tourFrontList();
                                                         [list setContentOffset:CGPointMake(list.contentOffset.x,
                                                                                            list.contentOffset.y +
                                                                                                list.bounds.size.height * 0.7)
                                                                       animated:NO];
                                                         [list layoutIfNeeded];
                                                     }
                                                     if (replyLooks >= 15) {
                                                         tourJudgeReplies(replyFocal, replyOrder);
                                                         repliesRead = YES;
                                                     }
                                                     return repliesRead;
                                                   }, nil, ^{
                                                     tourRestoreOptions(@"after the step");
                                                     if (replyFocal && !repliesRead) {
                                                         PFBCompatTourLog(@"[tour] replies: Tweet %lld, %lu direct "
                                                                          @"replies read when the step ended, not judged",
                                                                          replyFocal, (unsigned long)replyOrder.count);
                                                     }
                                                     tourPopToRoot();
                                                   }))];
    [steps addObject:tourStep(@"side menu", @"Side menu", home, ^{
             tourOpenSideMenu();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourBoolGetter(tourSideMenuOwner(), @"isDashOpen");
           }, nil, ^{
             tourCloseSideMenu();
           })];
    __block UIUserInterfaceStyle styleBefore = UIUserInterfaceStyleUnspecified;
    [steps addObject:tourStep(@"dark mode", @"Dark mode", ^{
             home();
             styleBefore = tourWindow().overrideUserInterfaceStyle;
           }, ^{
             UIWindow* window = tourWindow();
             window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
             PFBCompatTourLog(@"[tour] dark mode: window forced dark, Twitter's palette %@", tourPaletteName(tourPalette()));
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourBoolGetter(tourPalette(), @"isDark");
           }, ^{
             tourSwitchToDarkPalette();
           }, ^{
             tourWindow().overrideUserInterfaceStyle = styleBefore;
             tourRestorePalette();
           })];
    [steps addObject:tourStep(@"web link", @"Web link", home, ^{
             tourOpenWebLink();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourFindController(tourRootController().presentedViewController, @"SFSafariViewController") != nil;
           }, nil, ^{
             tourDismissPresented();
           })];
    [steps addObject:tourStep(@"t.co check", @"t.co block", root, ^{
             tourAttempt(@"t.co check", @"asking", ^{
               tourAskTcoRequests();
             });
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return PFBCompatPathReached(PFBCompatPath_tco_requests) || PFBCompatPathReached(PFBCompatPath_click_ids);
           }, nil, nil)];
    // Given the proof wait even when nothing is owed, so a slow opening still shows.
    [steps addObject:tourStepWaiting(kPFBTourProofWait, tourStep(@"Twitter settings", @"Twitter settings", root, ^{
             tourShowTwitterSettings();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return [after isKindOfClass:NSClassFromString(@"T1GenericSettingsViewController")];
           }, nil, ^{
             tourPopToRoot();
           }))];
    [steps addObject:tourStep(@"PFB settings", @"PrimeFreeBird settings", root, ^{
             tourShowSettings();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourFindController(tourRootController().presentedViewController,
                                       @"PFBModernSettingsPageViewController") != nil;
           }, nil, ^{
             tourDismissPresented();
           })];
    return steps;
}

// The steps a tour takes: all, or those whose screen still owes a proof.
// A step that closed Twitter is left out until a new build.
static NSArray<NSDictionary*>* tourSteps(BOOL full) {
    NSArray<NSDictionary*>* steps = tourAllSteps();
    NSIndexSet* kept = [steps indexesOfObjectsPassingTest:^BOOL(NSDictionary* step, NSUInteger index, BOOL* stop) {
      return !PFBCompatStationCrashed(step[@"name"]) && (full || PFBCompatStationLeft(step[@"name"]));
    }];
    return [steps objectsAtIndexes:kept];
}

// MARK: - Running the tour

static void tourHideOverlay(void) {
    gPFBTourOverlay.hidden = YES;
    gPFBTourOverlay = nil;
    gPFBTourStepLabel = nil;
}

// Records the outcome for the report: each step's result in order, and why the tour
// stopped early, if it did.
static void tourConclude(NSMutableArray<NSString*>* results, BOOL full, NSString* stop) {
    tourRestoreOptions(@"at the end of the tour");
    PFBCompatTourRecord(full, stop, results);
    tourJournalWrite([@"end: " stringByAppendingString:stop ?: @"completed"]);
    tourJournalClose();
    gPFBTourRunning = NO;
    tourHideOverlay();
    PFBDebuggerSetTriggerHidden(NO);
}

// Stops where the app stands: the steps already judged keep their result and the
// paths they proved stay proven; the step in progress puts the app back and goes
// unjudged, like the rest.
static void tourCancel(NSArray<NSDictionary*>* steps, NSMutableArray<NSString*>* results, BOOL full) {
    if (!gPFBTourRunning) {
        return;
    }
    gPFBTourGeneration++;
    NSDictionary* current = steps[MIN(results.count, steps.count - 1)];
    // Between two steps nothing is set up, so nothing is cleaned.
    if (gPFBTourStepLive) {
        tourAttempt(current[@"name"], @"clean-up", current[@"after"]);
    }
    gPFBTourStepLive = nil;
    PFBCompatTourLog(@"[tour] canceled at %@", current[@"name"]);
    tourConclude(results, full, [@"canceled at " stringByAppendingString:current[@"name"]]);
}

// A box over the app while the tour runs, in its own window: it says what is
// happening and has a Cancel button; touches outside the box reach the app.
static void tourShowOverlay(NSArray<NSDictionary*>* steps, NSMutableArray<NSString*>* results, BOOL full) {
    UIWindowScene* scene = tourWindow().windowScene;
    if (!scene || gPFBTourOverlay) {
        return;
    }
    UIWindow* overlay = [[PFBTourOverlayWindow alloc] initWithWindowScene:scene];
    overlay.windowLevel = UIWindowLevelAlert + 1;
    overlay.backgroundColor = UIColor.clearColor;
    BOOL glass = NO;
    UIVisualEffectView* box = [[UIVisualEffectView alloc] initWithEffect:tourBoxEffect(&glass)];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.layer.cornerRadius = 22.0;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = !glass;
    UIActivityIndicatorView* spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    UILabel* title = [UILabel new];
    title.text = @"Check every option";
    title.font = [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17.0];
    title.textColor = UIColor.labelColor;
    UILabel* step = [UILabel new];
    step.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:14.0];
    step.textColor = UIColor.secondaryLabelColor;
    step.textAlignment = NSTextAlignmentCenter;
    UIButtonConfiguration* style = [UIButtonConfiguration grayButtonConfiguration];
    style.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    style.baseForegroundColor = UIColor.labelColor;
    style.attributedTitle = [[NSAttributedString alloc]
        initWithString:@"Cancel"
            attributes:@{NSFontAttributeName : [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15.0]}];
    UIButton* cancel = [UIButton buttonWithConfiguration:style
                                           primaryAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
                                             tourCancel(steps, results, full);
                                           }]];
    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[ spinner, title, step, cancel ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8.0;
    [stack setCustomSpacing:16.0 afterView:step];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box.contentView addSubview:stack];
    [overlay addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [box.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [box.widthAnchor constraintEqualToConstant:260.0],
        [stack.topAnchor constraintEqualToAnchor:box.contentView.topAnchor constant:22.0],
        [stack.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor constant:-16.0],
        [stack.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor constant:-16.0],
        [cancel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [cancel.heightAnchor constraintEqualToConstant:40.0],
    ]];
    overlay.hidden = NO;
    gPFBTourOverlay = overlay;
    gPFBTourStepLabel = step;
}

static void tourShowStep(NSString* label, NSUInteger index, NSUInteger total) {
    gPFBTourStepLabel.text = [NSString stringWithFormat:@"%@ \u00b7 %lu of %lu", label, (unsigned long)(index + 1),
                                                        (unsigned long)total];
}

// The start's own proofs are judged last, so the late ones still count; then Home
// comes back to front and the report opens.
static void tourFinish(NSMutableArray<NSString*>* results, BOOL full) {
    tourAttempt(@"finish", @"return to Home", ^{
      tourHomeFront();
    });
    NSSet<NSString*>* launch = PFBCompatStationPending(@"launch");
    PFBCompatStationRecord(@"launch", YES, launch);
    if (launch.count) {
        PFBCompatTourLog(@"[tour] launch: not seen: %@",
                         [[launch.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]);
    }
    tourConclude(results, full, nil);
    if (PFBDebugIsRecording()) {
        PFBDebuggerCaptureAndPresent();
    } else {
        PFBDebuggerPresent();
    }
}

static void tourRun(NSArray<NSDictionary*>* steps, NSUInteger index, NSMutableArray<NSString*>* results, BOOL full);

// Records a step's outcome, lets it put the app back, then moves on.
static void tourConcludeStep(NSArray<NSDictionary*>* steps, NSUInteger index, NSMutableArray<NSString*>* results,
                             BOOL full, BOOL reached, NSSet<NSString*>* pending, NSString* detail) {
    NSDictionary* step = steps[index];
    NSString* name = step[@"name"];
    gPFBTourStepLive = nil;
    // Only a step that ran to its end (one with a pending set) ends on an empty screen.
    NSString* empty = pending ? gPFBTourStepEmpty : nil;
    gPFBTourStepEmpty = nil;
    reached = reached && !empty;
    // A screen reached with options still unproven says how many did not see their situation.
    NSArray<NSString*>* missed = [pending.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSString* outcome = empty ?: (!reached ? @"not reached"
                                           : (missed.count ? [NSString stringWithFormat:@"reached (%lu not seen)",
                                                                                        (unsigned long)missed.count]
                                                           : @"ok"));
    [results addObject:[NSString stringWithFormat:@"%@ %@", name, outcome]];
    if (empty) {
        PFBCompatStationRecordEmpty(name, empty);
    } else {
        PFBCompatStationRecord(name, reached, pending);
    }
    PFBCompatTourLog(@"[tour] %@: %@ \u00b7 %@%@", name, outcome, detail,
                     reached && missed.count ? [@" \u00b7 not seen: " stringByAppendingString:[missed componentsJoinedByString:@", "]]
                                             : @"");
    tourJournalWrite([NSString stringWithFormat:@"result: %@ \u00b7 %@", name, outcome]);
    tourAttempt(name, @"clean-up", step[@"after"]);
    NSUInteger generation = gPFBTourGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourSettle * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (generation == gPFBTourGeneration) {
                         tourRun(steps, index + 1, results, full);
                     }
                   });
}

// One look at a step: done once its screen shows and it owes nothing, or when time is up.
// Shown means the check passed or an owed proof arrived, counted after the check, which
// can bring one. A second way in, tried at doorAt (negative until then), gets its own time.
static void tourWatch(NSArray<NSDictionary*>* steps, NSUInteger index, NSMutableArray<NSString*>* results, BOOL full,
                      UIViewController* before, NSSet<NSString*>* owed, NSDate* start, NSTimeInterval doorAt) {
    NSDictionary* step = steps[index];
    NSString* name = step[@"name"];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    UIViewController* after = tourScreen();
    PFBTourCheck check = step[@"check"];
    __block BOOL shown = NO;
    if (!tourAttempt(name, @"check", ^{
          shown = check(before, after);
        })) {
        tourConcludeStep(steps, index, results, full, NO, nil, @"stopped by an exception");
        return;
    }
    NSSet<NSString*>* pending = PFBCompatStationPending(name);
    BOOL reached = shown || pending.count < owed.count;
    dispatch_block_t door = step[@"door"];
    if (!reached && doorAt < 0 && door && elapsed >= kPFBTourDoorRetry) {
        tourJournalWrite([NSString stringWithFormat:@"step %@ \u00b7 second way in", name]);
        if (!tourAttempt(name, @"second way in", door)) {
            tourConcludeStep(steps, index, results, full, NO, nil, @"stopped by an exception");
            return;
        }
        doorAt = elapsed;
    }
    BOOL owes = owed.count > 0;
    NSTimeInterval limit = MAX(owes ? kPFBTourProofWait : kPFBTourPause, doorAt < 0 ? 0 : doorAt + kPFBTourPause);
    NSNumber* wait = step[@"wait"];
    BOOL done = wait ? (shown || elapsed >= MAX(limit, wait.doubleValue))
                     : (elapsed >= limit || (owes && reached && pending.count == 0));
    NSUInteger generation = gPFBTourGeneration;
    if (!done) {
        NSTimeInterval tried = doorAt;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourPoll * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         if (generation == gPFBTourGeneration) {
                             tourWatch(steps, index, results, full, before, owed, start, tried);
                         }
                       });
        return;
    }
    tourConcludeStep(steps, index, results, full, reached, pending,
                     [NSString stringWithFormat:@"%@ -> %@ in %.1f s", tourScreenName(before), tourScreenName(after),
                                                elapsed]);
}

// A step brings the app where it needs it, lets it settle, notes the screen in front,
// then acts: the check compares against that screen, not the previous step's. The
// journal names each part before it runs, so a crash still says where it happened.
static void tourRun(NSArray<NSDictionary*>* steps, NSUInteger index, NSMutableArray<NSString*>* results, BOOL full) {
    if (index >= steps.count) {
        tourFinish(results, full);
        return;
    }
    NSUInteger generation = gPFBTourGeneration;
    NSDictionary* step = steps[index];
    NSString* name = step[@"name"];
    gPFBTourStepLive = name;
    gPFBTourStepEmpty = nil;
    tourShowStep(step[@"label"], index, steps.count);
    NSSet<NSString*>* owed = PFBCompatStationPending(name);
    tourJournalWrite([NSString stringWithFormat:@"step %@ \u00b7 setup", name]);
    if (!tourAttempt(name, @"setup", step[@"setup"])) {
        tourConcludeStep(steps, index, results, full, NO, nil, @"stopped by an exception");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourSettle * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (generation != gPFBTourGeneration) {
                         return;
                     }
                     UIViewController* before = tourScreen();
                     tourJournalWrite([NSString stringWithFormat:@"step %@ \u00b7 action", name]);
                     if (!tourAttempt(name, @"action", step[@"action"])) {
                         tourConcludeStep(steps, index, results, full, NO, nil, @"stopped by an exception");
                         return;
                     }
                     NSDate* start = [NSDate date];
                     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourFirstLook * NSEC_PER_SEC)),
                                    dispatch_get_main_queue(), ^{
                                      if (generation == gPFBTourGeneration) {
                                          tourWatch(steps, index, results, full, before, owed, start, -1.0);
                                      }
                                    });
                   });
}

static void tourStart(BOOL full) {
    if (gPFBTourRunning) {
        return;
    }
    NSArray<NSDictionary*>* steps = tourSteps(full);
    if (steps.count == 0) {
        PFBDebugLog(@"[tour] nothing left to prove");
        return;
    }
    gPFBTourRunning = YES;
    NSUInteger generation = ++gPFBTourGeneration;
    PFBDebuggerSetTriggerHidden(YES);
    tourJournalClose();
    [[NSFileManager defaultManager] removeItemAtPath:tourJournalPath() error:nil];
    tourJournalWrite([NSString stringWithFormat:@"start: %@ \u00b7 %lu steps \u00b7 build %@", full ? @"full" : @"what is left",
                                                (unsigned long)steps.count, PFBCompatBuildID()]);
    for (NSDictionary* step in tourAllSteps()) {
        if (PFBCompatStationCrashed(step[@"name"])) {
            PFBCompatTourLog(@"[tour] %@ skipped: it closed Twitter on a previous tour of this build", step[@"name"]);
        }
    }
    NSMutableArray<NSString*>* results = [NSMutableArray array];
    void (^start)(void) = ^{
      tourShowOverlay(steps, results, full);
      tourAttempt(@"start", @"return to Home", ^{
        tourHomeFront();
      });
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourPause * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       if (generation == gPFBTourGeneration) {
                           tourRun(steps, 0, results, full);
                       }
                     });
    };
    UIViewController* root = tourRootController();
    if (root.presentedViewController) {
        [root dismissViewControllerAnimated:YES completion:start];
    } else {
        start();
    }
}

void PFBCompatRunTour(void) {
    tourStart(YES);
}

void PFBCompatRunTourLeft(void) {
    tourStart(NO);
}

BOOL PFBCompatTourIsRunning(void) {
    return gPFBTourRunning;
}

// MARK: - Planning a tour

// The screens a tour would show: all of them, or those with proofs still owed.
NSUInteger PFBCompatTourScreens(BOOL full) {
    return tourSteps(full).count;
}

// MARK: - At launch

void PFBCompatScheduleTourAtLaunch(void) {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPFBTourPendingKey];
}

// A journal without its end line means Twitter closed during the tour. On the same
// build, the step then running is recorded as having closed Twitter; a palette it
// switched comes back either way.
static void tourRecoverStop(void) {
    NSString* text = PFBCompatTourJournalText();
    if (!text) {
        return;
    }
    BOOL full = NO;
    BOOL ended = NO;
    NSString* build = nil;
    NSString* step = nil;
    NSString* palette = nil;
    NSMutableArray<NSString*>* results = [NSMutableArray array];
    for (NSString* stamped in [text componentsSeparatedByString:@"\n"]) {
        NSRange gap = [stamped rangeOfString:@"  "];
        NSString* line = gap.location == NSNotFound ? stamped : [stamped substringFromIndex:NSMaxRange(gap)];
        NSRange dot = [line rangeOfString:@" \u00b7 " options:NSBackwardsSearch];
        if ([line hasPrefix:@"start: "]) {
            full = [line hasPrefix:@"start: full"];
            NSRange mark = [line rangeOfString:@" \u00b7 build "];
            build = mark.location == NSNotFound ? nil : [line substringFromIndex:NSMaxRange(mark)];
        } else if ([line hasPrefix:@"end: "]) {
            ended = YES;
        } else if ([line hasPrefix:@"step "] && dot.location != NSNotFound && dot.location > 5) {
            step = [line substringWithRange:NSMakeRange(5, dot.location - 5)];
        } else if ([line hasPrefix:@"result: "] && dot.location != NSNotFound && dot.location > 8) {
            NSString* name = [line substringWithRange:NSMakeRange(8, dot.location - 8)];
            [results addObject:[NSString stringWithFormat:@"%@ %@", name, [line substringFromIndex:NSMaxRange(dot)]]];
            step = [step isEqualToString:name] ? nil : step;
        } else if ([line hasPrefix:@"palette: switched from "]) {
            palette = [line substringFromIndex:23];
        } else if ([line isEqualToString:@"palette: restored"]) {
            palette = nil;
        }
    }
    if (ended) {
        return;
    }
    if (palette) {
        tourRestorePaletteNamed(palette);
        tourJournalWrite(@"palette: restored");
    }
    NSString* stop = step ? [@"Twitter closed during " stringByAppendingString:step] : @"Twitter closed during the tour";
    if ([build isEqualToString:PFBCompatBuildID()]) {
        if (step) {
            PFBCompatStationRecordCrash(step);
        }
        PFBCompatTourRecord(full, stop, results);
    } else {
        stop = [stop stringByAppendingString:@", on an earlier build"];
    }
    tourJournalWrite([@"end: " stringByAppendingString:stop]);
    tourJournalClose();
}

// Once the app is active after launch: a tour Twitter closed is recorded, then a tour
// asked for before quitting runs. The options a step had switched are put back first,
// before Twitter reads them.
void PFBCompatTourResumeAtLaunch(void) {
    tourRestoreOptions(@"at launch, after a tour Twitter closed");
    __block id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification* note) {
                  [[NSNotificationCenter defaultCenter] removeObserver:observer];
                  observer = nil;
                  tourRecoverStop();
                  BOOL scheduled = [[NSUserDefaults standardUserDefaults] boolForKey:kPFBTourPendingKey];
                  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPFBTourPendingKey];
                  if (!scheduled) {
                      return;
                  }
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourLaunchDelay * NSEC_PER_SEC)),
                                 dispatch_get_main_queue(), ^{
                                   PFBCompatRunTour();
                                 });
                }];
}
