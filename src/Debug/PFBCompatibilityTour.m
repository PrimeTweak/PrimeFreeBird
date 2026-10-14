// Path tour: shows Twitter's own screens one after another so the report proves the
// paths they carry, whatever the toggles say. Each step waits for the proofs its
// screen owes, then notes whether the screen came up and what it still missed.

#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#import <objc/message.h>
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Settings/PFBModernSettingsPageViewController.h"
#import "Debug/PFBTourOverlayWindow.h"
#import "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.h"
#import "Features/Appearance/ThemeColor/PFBPalette.h"

// Long enough for a screen and its first page of content to arrive.
static const NSTimeInterval kPFBTourPause = 2.5;

// How long a step waits for the proofs its screen owes before it concludes.
static const NSTimeInterval kPFBTourProofWait = 6.0;

// The first look at a step, then one look per tick until it concludes.
static const NSTimeInterval kPFBTourFirstLook = 1.0;
static const NSTimeInterval kPFBTourPoll = 0.25;

// When a step's first way in has shown nothing, its second one is tried.
static const NSTimeInterval kPFBTourDoorRetry = 2.5;

// Left to the app between a step's clean-up and the next step.
static const NSTimeInterval kPFBTourSettle = 0.4;

// Average duration of one step, for the duration the launch alert announces.
static const NSTimeInterval kPFBTourSecondsPerStep = 3.6;

// How far down Home is searched for a Tweet carrying a video or photos.
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
    PFBDebugLog(@"%@", line);
    if (gPFBTourRunning) {
        tourJournalWrite(line);
    }
}


NSString* PFBCompatTourJournalText(void) {
    NSString* text = [NSString stringWithContentsOfFile:tourJournalPath() encoding:NSUTF8StringEncoding error:nil];
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

NSString* PFBProbeTourStep(void) {
    return gPFBTourRunning ? gPFBTourStepLive : nil;
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

// Selecting the tab already in front would make Twitter scroll it back to the top.
static void tourSelectTab(NSInteger index) {
    id switcher = tourTabSwitcher();
    if (!switcher || tourIntegerGetter(switcher, @"selectedTabIndex") == index) {
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

// A finger's release commits a refresh: status 1 marked as coming from scrolling,
// then the value-changed action. The control is read from the list's controller up
// the responder chain, since the list's delegate can be a relaying proxy.
static void tourCommitRefresh(UITableView* list) {
    id delegate = list.delegate;
    NSString* delegateName = delegate ? NSStringFromClass(object_getClass(delegate)) : @"none";
    NSString* delegateGives = tourGetter(delegate, @"pullToLoadTopControl") ? @"gives" : @"hides";
    UIResponder* owner = nil;
    id control = nil;
    for (UIResponder* responder = list.nextResponder; responder && !control;
         responder = responder.nextResponder) {
        control = tourGetter(responder, @"pullToLoadTopControl");
        owner = responder;
    }
    SEL status = NSSelectorFromString(@"_setStatus:fromScrolling:");
    if (![control isKindOfClass:[UIControl class]] || ![control respondsToSelector:status]) {
        PFBCompatTourLog(@"[tour] refresh: delegate %@ %@ the control; none usable up the chain (%@)",
                    delegateName, delegateGives,
                    control ? NSStringFromClass([control class]) : @"none");
        return;
    }
    ((void (*)(id, SEL, unsigned long long, BOOL))objc_msgSend)(control, status, 1, YES);
    [(UIControl*)control sendActionsForControlEvents:UIControlEventValueChanged];
    PFBCompatTourLog(@"[tour] refresh: delegate %@ %@ the control; %@ holds %@, set to status 1 "
                @"(pull), value changed sent",
                delegateName, delegateGives, NSStringFromClass([owner class]),
                NSStringFromClass([control class]));
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
    if ([delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [delegate scrollViewDidEndDragging:list willDecelerate:NO];
    }
    [list setContentOffset:rest animated:YES];
    tourCommitRefresh(list);
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
    NSUInteger passed = 0;
    for (NSIndexPath* row in rows) {
        UITableViewCell* cell = [list cellForRowAtIndexPath:row];
        if (!statusCell || ![cell isKindOfClass:statusCell]) {
            continue;
        }
        if (tourFindClass(cell, @"T1UnifiedCardView")) {
            carded = carded ?: row;
            passed++;
            continue;
        }
        PFBCompatTourLog(@"[tour] first Tweet: row %ld opened, %lu with a link card passed", (long)row.row,
                         (unsigned long)passed);
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

// Through the app delegate, the way a link opened from outside arrives.
static void tourOpenLink(NSString* link) {
    UIApplication* app = UIApplication.sharedApplication;
    id<UIApplicationDelegate> delegate = app.delegate;
    NSURL* url = [NSURL URLWithString:link];
    if (url && [delegate respondsToSelector:@selector(application:openURL:options:)]) {
        [delegate application:app openURL:url options:@{}];
    }
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

static NSString* tourIndexText(NSInteger index) {
    return index == NSNotFound ? @"?" : [NSString stringWithFormat:@"%ld", (long)index];
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

// A view of the class in the Home list's visible Tweets, looking a screen further down
// each time none shows one. The list stays where the view was found.
static UIView* tourHomeViewOfClass(NSString* className) {
    UITableView* list = tourFrontList();
    for (NSInteger screen = 0; list && screen <= kPFBTourScreensDown; screen++) {
        for (UITableViewCell* cell in list.visibleCells) {
            UIView* found = tourFindClass(cell, className);
            if (found.window) {
                return found;
            }
        }
        CGPoint offset = list.contentOffset;
        [list setContentOffset:CGPointMake(offset.x, offset.y + list.bounds.size.height * 0.8) animated:NO];
        [list layoutIfNeeded];
    }
    PFBCompatTourLog(@"[tour] no %@ within %ld screens of Home", className, (long)kPFBTourScreensDown + 1);
    return nil;
}

static void tourScrollHomeToTop(void) {
    UITableView* list = tourFrontList();
    if (list) {
        [list setContentOffset:CGPointMake(list.contentOffset.x, -list.adjustedContentInset.top) animated:NO];
    }
}

// A finger's drag down the list, in steps, as its delegate would hear it.
static void tourDrag(UITableView* list, CGFloat distance) {
    id<UITableViewDelegate> delegate = list.delegate;
    if ([delegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
        [delegate scrollViewWillBeginDragging:list];
    }
    CGPoint start = list.contentOffset;
    for (NSInteger i = 1; i <= 6; i++) {
        [list setContentOffset:CGPointMake(start.x, start.y + distance * i / 6.0) animated:NO];
        if ([delegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
            [delegate scrollViewDidScroll:list];
        }
    }
    if ([delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [delegate scrollViewDidEndDragging:list willDecelerate:NO];
    }
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

// "about 25 s" or "about 1 min 30" for a number of steps.
static NSString* tourDuration(NSUInteger steps) {
    NSUInteger seconds = (NSUInteger)(steps * kPFBTourSecondsPerStep / 5.0 + 0.5) * 5;
    if (seconds < 60) {
        return [NSString stringWithFormat:@"about %lu s", (unsigned long)MAX(seconds, (NSUInteger)5)];
    }
    NSUInteger rest = seconds % 60;
    return rest ? [NSString stringWithFormat:@"about %lu min %lu", (unsigned long)(seconds / 60), (unsigned long)rest]
                : [NSString stringWithFormat:@"about %lu min", (unsigned long)(seconds / 60)];
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
    PFBCompatTourLog(@"[tour] Tweet buttons: like %@, reply %@, share %@, relay %@ \u00b7 controls: %@", like ? @"found" : @"none",
                reply ? @"found" : @"none", share ? @"found" : @"none", relays ? @"present" : @"missing",
                seen.count ? [seen componentsJoinedByString:@"; "] : @"none readable");
    return YES;
}

// The caret of the first Tweet, tapped through its own handler: the menu it arms or
// opens goes through the hook Hide conversations uses. Returns the caret to close.
static UIControl* tourOpenTweetMenu(void) {
    UIView* author = tourHomeViewOfClass(@"TTAStatusAuthorView");
    id caret = tourGetter(author, @"caretButton");
    BOOL armed = [caret isKindOfClass:[UIButton class]] && ((UIButton*)caret).menu != nil;
    BOOL tapped = tourSend(author, @"_didTapCaret");
    PFBCompatTourLog(@"[tour] Tweet menu: author row %@, caret %@, menu before the tap %@, tap %@",
                author ? @"found" : @"none", caret ? NSStringFromClass([caret class]) : @"none",
                armed ? @"armed" : @"none", tapped ? @"sent" : @"not possible");
    return [caret isKindOfClass:[UIControl class]] ? caret : nil;
}

// The first video on Home, opened full screen through its own tap handler, with the
// tap recognizer it expects. Returns the video, for the second way in.
static UIView* tourOpenVideo(void) {
    UIView* video = tourHomeViewOfClass(@"T1InlineVideoView");
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
    PFBCompatTourLog(@"[tour] video full screen: tap sent to %@", NSStringFromClass([video class]));
    return video;
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
    PFBCompatTourLog(@"[tour] %@: first item tapped through %@", step, NSStringFromClass([forward class]));
}

// Probe: the full-screen player's looks that found no double-tap plugin, in this step.
static NSUInteger gPFBTourProbeDoubleTapMisses;
static BOOL gPFBTourProbeDoubleTapFound;

// Probe: notes the first look that finds the double-tap plugin, with its handler wired or
// not, and counts the looks that miss it.
static void tourProbeDoubleTapLike(UIView* plugin) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    if (!plugin) {
        gPFBTourProbeDoubleTapMisses++;
        return;
    }
    gPFBTourProbeDoubleTapFound = YES;
    if (PFBProbeWants(@"02#F028 double tap found")) {
        PFBProbeNote(@"02#F028 double tap found",
                     @"02#F028 double tap like: plugin found · handleDoubleTap: %@ (%lu looks without it before)",
                     tourGesture(plugin, @"handleDoubleTap:") ? @"wired" : @"not wired",
                     (unsigned long)gPFBTourProbeDoubleTapMisses);
    }
}

// Probe: an action view's or its control's accessibility label, shortened.
static NSString* tourProbeLabel(UIView* view) {
    NSString* label = view.accessibilityLabel;
    if (!label.length) {
        UIView* control = tourFindView(view, ^BOOL(UIView* candidate) {
          return [candidate isKindOfClass:[UIControl class]] && candidate.accessibilityLabel.length;
        });
        label = control.accessibilityLabel;
    }
    return label.length > 24 ? [label substringToIndex:24] : (label ?: @"");
}

// Probe: notes the full-screen player's action views by label, its heart button with the
// view holding it, and what the inline favorite button reports its tap to.
static void tourProbePlayerLike(void) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"10b#F018 player like")) {
        return;
    }
    UIView* root = tourRootController().presentedViewController.viewIfLoaded;
    if (!root.window) {
        return;
    }
    NSMutableArray<NSString*>* labels = [NSMutableArray array];
    __block UIView* heart = nil;
    tourFindView(root, ^BOOL(UIView* view) {
      NSString* name = NSStringFromClass([view class]);
      BOOL button = [name hasSuffix:@".ImmersiveActionButton"];
      if ((button || [name hasSuffix:@".ImmersiveActionView"]) && labels.count < 8) {
          [labels addObject:[NSString stringWithFormat:@"%@ '%@'", button ? @"button" : @"view", tourProbeLabel(view)]];
      }
      if (!heart && [name isEqualToString:@"TTAStatusInlineFavoriteButton"]) {
          heart = view;
      }
      return NO;
    });
    NSString* holder = @"other";
    for (UIView* up = heart.superview; up; up = up.superview) {
        NSString* name = NSStringFromClass([up class]);
        if ([name hasSuffix:@".ImmersiveActionButton"] || [name hasSuffix:@".ImmersiveActionView"]) {
            holder = name;
            break;
        }
    }
    PFBProbeNote(@"10b#F018 player like",
                 @"10b#F018 player like: %lu action views (%@), heart %@ inside %@, inline favorite button %@",
                 (unsigned long)labels.count, labels.count ? [labels componentsJoinedByString:@", "] : @"none",
                 heart ? NSStringFromClass([heart class]) : @"none", heart ? holder : @"-",
                 heart ? [@"present, delegate " stringByAppendingString:PFBProbeClassName(PFBProbeGetter(heart, @"delegate"))]
                       : @"absent");
}

// Probe: as the full-screen video step ends, notes a double-tap plugin never found, then
// the player's like control while the player is still up.
static void tourProbeVideoStepEnd(void) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    if (!gPFBTourProbeDoubleTapFound && gPFBTourProbeDoubleTapMisses &&
        PFBProbeWants(@"02#F028 double tap not found")) {
        PFBProbeNote(@"02#F028 double tap not found", @"02#F028 double tap like: plugin not found in %lu looks",
                     (unsigned long)gPFBTourProbeDoubleTapMisses);
    }
    gPFBTourProbeDoubleTapFound = NO;
    gPFBTourProbeDoubleTapMisses = 0;
    tourProbePlayerLike();
}

// The full-screen player's double tap is the like Confirm likes guards there.
static BOOL tourCheckDoubleTapLike(void) {
    UIView* root = tourRootController().presentedViewController.view ?: tourWindow();
    UIView* plugin = tourFindClass(root, @"_TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView");
    if (plugin) {
        PFBCompatObserve(PFBCompat_like_confirm, tourGesture(plugin, @"handleDoubleTap:") ? @"double tap like wired"
                                                                                          : @"double tap like shown");
    }
    tourProbeDoubleTapLike(plugin);
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
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    for (UIMenuElement* element in menu.children) {
        [titles addObject:element.title.length ? element.title : @"?"];
    }
    PFBCompatTourLog(@"[tour] video long press: %@ %@ from %@, %lu entries: %@",
                     configuration ? @"menu built" : @"no menu", pass, NSStringFromClass([delegate class]),
                     (unsigned long)menu.children.count, [titles componentsJoinedByString:@" | "]);
    return menu.children.count > 0;
}

// Among the Tweets of Home's first screens, the author with the longest bio, so the
// profile opened has one long enough to clip; nil when no author can be read.
static NSString* tourLongestBioHandle(void) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    NSString* own = tourGetter(account, @"username");
    NSString* best = nil;
    NSUInteger longest = 0;
    NSUInteger read = 0;
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
            read++;
            NSUInteger length = [bio isKindOfClass:[NSString class]] ? bio.length : 0;
            if (!best || length > longest) {
                best = handle;
                longest = length;
            }
        }
        [list setContentOffset:CGPointMake(list.contentOffset.x, list.contentOffset.y + list.bounds.size.height * 0.8)
                      animated:NO];
        [list layoutIfNeeded];
    }
    tourScrollHomeToTop();
    PFBCompatTourLog(@"[tour] other profile: %lu authors read, longest bio %lu characters", (unsigned long)read,
                     (unsigned long)longest);
    return best;
}

// The full-screen player's card swipe, asked the question UIKit asks as a swipe starts.
static void tourAskCardSwipe(void) {
    UIViewController* player = tourFindController(tourRootController(), @"T1ImmersiveViewController");
    Class cls = [player class];
    Ivar ivar = cls ? (class_getInstanceVariable(cls, "panRecognizer")
                           ?: class_getInstanceVariable(cls, "$__lazy_storage_$_panRecognizer"))
                    : NULL;
    id pan = ivar ? object_getIvar(player, ivar) : nil;
    if (![pan isKindOfClass:[UIGestureRecognizer class]] ||
        ![player respondsToSelector:@selector(gestureRecognizerShouldBegin:)]) {
        PFBCompatTourLog(@"[tour] video full screen: card swipe %@", player ? @"not found" : @"no full-screen player");
        return;
    }
    BOOL allowed = [(id<UIGestureRecognizerDelegate>)player gestureRecognizerShouldBegin:pan];
    PFBCompatTourLog(@"[tour] video full screen: card swipe %@", allowed ? @"allowed" : @"blocked");
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
    BOOL allowed = ((BOOL (*)(id, SEL))objc_msgSend)(player, question);
    PFBCompatTourLog(@"[tour] video full screen: docking %@", allowed ? @"allowed" : @"refused");
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
    PFBCompatTourLog(@"[tour] other profile: Follow button %@ \u00b7 controls: %@", wired ? @"wired" : @"not read",
                seen.count ? [seen componentsJoinedByString:@"; "] : @"none readable");
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
    PFBCompatTourLog(@"[tour] first Tweet: reply bar relay %@, send button %@ (%@)", relay ? NSStringFromClass([relay class]) : @"none",
                send ? NSStringFromClass([send class]) : @"none", actions.count ? [actions componentsJoinedByString:@" "] : @"no actions read");
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
    PFBCompatTourLog(@"[tour] composer: send button %@ \u00b7 controls: %@", wired ? @"wired" : @"not read",
                seen.count ? [seen componentsJoinedByString:@"; "] : @"none readable");
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
    PFBCompatTourLog(@"[tour] Tweet interactions: Tweet %ld on its Quotes tab, pushed on %@", (long)statusID,
                     NSStringFromClass([stack class]));
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

// Probe: what the unread test reads in a conversation row, as counts and flags only; flags
// gets the four yes/no signals as digits.
static NSString* tourProbeRowSignals(UIView* cell, NSString** flags) {
    NSMutableString* text = [NSMutableString stringWithString:cell.accessibilityLabel ?: @""];
    [text appendString:cell.accessibilityValue ?: @""];
    tourFindView(cell, ^BOOL(UIView* view) {
      if ([view isKindOfClass:[UILabel class]]) {
          [text appendString:((UILabel*)view).text ?: @""];
      }
      return NO;
    });
    NSString* lower = text.lowercaseString;
    NSString* key = @"DM_INBOX_PILL_UNREAD_TITLE";
    NSString* word = [[PFBBundle sharedBundle] localizedTwitterStringForKey:key];
    BOOL wordFound = word.length && ![word isEqualToString:key] && [lower containsString:word.lowercaseString];
    __block CGFloat hue = 0, saturation = 0, brightness = 0;
    UIView* dot = tourFindView(cell, ^BOOL(UIView* view) {
      CGSize size = view.bounds.size;
      CGFloat alpha = 0;
      return !view.hidden && size.width >= 4 && size.width <= 14 && fabs(size.width - size.height) < 1.0 &&
             [view.backgroundColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha] &&
             alpha > 0.5;
    });
    NSUInteger value = cell.accessibilityValue.length;
    *flags = [NSString stringWithFormat:@"%d%d%d%d", [lower containsString:@"unread"], wordFound, value > 0, dot != nil];
    return [NSString
        stringWithFormat:@"%@: %lu characters, 'unread' %@, Twitter word '%@' %@, accessibilityValue %@, dot %@",
                         NSStringFromClass([cell class]), (unsigned long)text.length,
                         [lower containsString:@"unread"] ? @"yes" : @"no", word, wordFound ? @"yes" : @"no",
                         value ? [NSString stringWithFormat:@"%lu characters", (unsigned long)value] : @"empty",
                         dot ? [NSString stringWithFormat:@"%.0fx%.0f hue %.2f saturation %.2f brightness %.2f",
                                                          dot.bounds.size.width, dot.bounds.size.height, hue,
                                                          saturation, brightness]
                             : @"none"];
}

// Probe: notes each visible conversation row with what the unread test reads and what the
// tour does with it; a row is noted again when its outcome or one of its signals changes.
static void tourProbeConversationRows(NSArray<UIView*>* cells, UITableView* table, UICollectionView* grid) {
    static NSUInteger noted;
    if (!PFBDebugIsRecording() || noted >= 16) {
        return;
    }
    BOOL chosen = NO;
    for (NSUInteger i = 0; i < cells.count && i < 12 && noted < 16; i++) {
        UIView* cell = cells[i];
        NSString* mark = tourUnreadMark(cell);
        NSIndexPath* row = table ? [table indexPathForCell:(UITableViewCell*)cell]
                                 : [grid indexPathForCell:(UICollectionViewCell*)cell];
        NSString* outcome = chosen ? @"after the opened row"
                                   : (mark ? [@"skipped: " stringByAppendingString:mark]
                                           : (row ? @"opened" : @"skipped: no index path"));
        chosen = chosen || (!mark && row);
        NSString* flags = @"";
        NSString* signals = tourProbeRowSignals(cell, &flags);
        NSString* key = [NSString stringWithFormat:@"02#F018 row %lu %@ %@", (unsigned long)i, outcome, flags];
        if (PFBProbeWants(key)) {
            noted++;
            PFBProbeNote(key, @"02#F018 row %lu %@ → %@", (unsigned long)i, signals, outcome);
        }
    }
}

// The first conversation of the inbox known to be read, opened the way a tap does.
static void tourOpenReadConversation(void) {
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
    PFBCompatTourLog(@"[tour] conversation: front view %@, list %@ with %lu visible rows",
                     NSStringFromClass([tourFrontView() class]), list ? NSStringFromClass([list class]) : @"none",
                     (unsigned long)cells.count);
    tourProbeConversationRows(cells, table, grid);
    NSMutableArray<NSString*>* skipped = [NSMutableArray array];
    for (UIView* cell in cells) {
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
        PFBCompatTourLog(@"[tour] conversation: opened row %lu (skipped: %@)", (unsigned long)skipped.count,
                    skipped.count ? [skipped componentsJoinedByString:@", "] : @"none");
        return;
    }
    PFBCompatTourLog(@"[tour] conversation: no conversation known to be read in %@ (%@)",
                list ? NSStringFromClass([list class]) : @"no list",
                skipped.count ? [skipped componentsJoinedByString:@", "] : @"no rows");
}

// The controller that shows the side menu, and whether it is open.
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
    PFBCompatTourLog(@"[tour] web link: in-app browser presented over %@", tourScreenName(tourScreen()));
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

// The action names a gesture recognizer's description lists for its targets.
static NSString* tourActionNames(UIGestureRecognizer* recognizer) {
    NSString* text = recognizer.description;
    NSCharacterSet* stops = [NSCharacterSet characterSetWithCharactersInString:@", )>"];
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    NSRange rest = NSMakeRange(0, text.length);
    for (;;) {
        NSRange mark = [text rangeOfString:@"action=" options:0 range:rest];
        if (mark.location == NSNotFound) {
            break;
        }
        NSUInteger start = NSMaxRange(mark);
        NSRange stop = [text rangeOfCharacterFromSet:stops options:0 range:NSMakeRange(start, text.length - start)];
        NSUInteger end = stop.location == NSNotFound ? text.length : stop.location;
        [names addObject:[text substringWithRange:NSMakeRange(start, end - start)]];
        rest = NSMakeRange(end, text.length - end);
    }
    return names.count ? [names componentsJoinedByString:@" "] : @"no action";
}

// What each view from a media view up to its cell carries: interactions and gestures.
static void tourDescribeChain(NSString* step, UIView* from, UIView* upTo) {
    for (UIView* view = from; view && view != upTo.superview; view = view.superview) {
        NSMutableArray<NSString*>* parts = [NSMutableArray array];
        for (id<UIInteraction> interaction in view.interactions) {
            [parts addObject:NSStringFromClass([interaction class])];
        }
        for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
            [parts addObject:[NSString stringWithFormat:@"%@ (%@)", NSStringFromClass([recognizer class]),
                                                        tourActionNames(recognizer)]];
        }
        if (parts.count) {
            PFBCompatTourLog(@"[tour] %@: %@ carries %@", step, NSStringFromClass([view class]),
                             [parts componentsJoinedByString:@", "]);
        }
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
    Class barClass = NSClassFromString(@"_TtC15TwitterSearchV211SearchBarV2");
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
    PFBCompatTourLog(@"[tour] search field: bar found, focus tap %@, field %@, keyboard %@",
                     tapped ? @"sent" : @"not possible", field ? NSStringFromClass([field class]) : @"none",
                     field.isFirstResponder ? @"up" : @"not up yet");
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

// Probe: an option holding a number, set for one probe step. What the person had is kept the
// same way, so tourRestoreOptions puts it back, at the next launch too should Twitter close.
static void tourSwitchInteger(NSString* key, NSInteger value) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* stored = [defaults dictionaryForKey:kPFBTourSwitchedKey];
    NSMutableDictionary* saved = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (!saved[key]) {
        id had = [defaults objectForKey:key];
        saved[key] = had ? @{@"value": had} : @{};
        [defaults setObject:saved forKey:kPFBTourSwitchedKey];
    }
    [defaults setInteger:value forKey:key];
    PFBCompatTourLog(@"[tour] %@ set to %ld for this step", key, (long)value);
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
                           tourDrag(list, list.bounds.size.height * 1.5);
                         });
                       });
    }
}

// MARK: - Probe passages

// How long a probe passage may hold its step up past the step's own end.
static const NSTimeInterval kPFBTourHoldLimit = 12.0;

// The Twitter classes whose own factories build the screens some probe passages show.
static NSString* const kPFBTourSettingsFactory = @"T1SettingsViewControllers";
static NSString* const kPFBTourSettingsContainer = @"T1SettingsContainerController";
static NSString* const kPFBTourListsPage = @"_TtC33TwitterListsFeatureImplementation37ListManagementContainerViewController";
static NSString* const kPFBTourBookmarksFactory = @"T1BookmarkTimelineFactory";

// Twitter's settings container, declared so its initializer is called as one.
@interface NSObject (PFBTourSettingsContainer)
- (instancetype)initWithSettingsControllers:(NSArray*)controllers account:(id)account;
@end

// Probe readings of other files, made while a passage has their screen up.
extern void PFBProbeFontLoading(void);
extern void PFBProbeCustomFontsFile(void);
extern void PFBProbeTwitterStrings(void);
// The full-screen player's "sound allowed" state (ImmersivePlayer.x), which the video sound
// passage's tap sets: read before it and put back after it.
extern BOOL pfbProbeSoundAllowed(void);
extern void pfbProbeRestoreSoundAllowed(BOOL allowed);

// Whether an object's class or one of its superclasses has the name, read from the class.
static BOOL tourIsNamed(id object, NSString* name) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        if ([NSStringFromClass(cls) isEqualToString:name]) {
            return YES;
        }
    }
    return NO;
}

// The first controller under the window's root, presented ones included, that answers the
// selector.
static UIViewController* tourControllerAnswering(NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    UIViewController* root = tourRootController();
    NSMutableArray<UIViewController*>* queue = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
    for (NSUInteger i = 0; i < queue.count && i < 512; i++) {
        UIViewController* controller = queue[i];
        if ([controller respondsToSelector:selector]) {
            return controller;
        }
        [queue addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) {
            [queue addObject:controller.presentedViewController];
        }
    }
    return nil;
}

// A controller of the class under a root, compared by name: its children, stacks and
// presented ones.
static UIViewController* tourControllerNamed(UIViewController* root, NSString* name) {
    NSMutableArray<UIViewController*>* queue = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
    for (NSUInteger i = 0; i < queue.count && i < 256; i++) {
        UIViewController* controller = queue[i];
        if (tourIsNamed(controller, name)) {
            return controller;
        }
        [queue addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) {
            [queue addObject:controller.presentedViewController];
        }
    }
    return nil;
}

// Twitter's navigation object, held by its tab controller.
static id tourAppNavigation(void) {
    return tourGetter(tourControllerAnswering(@"tabbedAppNavigation"), @"appNavigation");
}

// The tab in front tapped again, the way a finger does: Twitter takes its stack back to its
// root. The tab bar's own selection is what is tapped, so the index cannot be out of range.
static void tourTapTabAgain(NSInteger expected) {
    id switcher = tourTabSwitcher();
    NSInteger current = tourIntegerGetter(switcher, @"selectedTabIndex");
    if (!switcher || current == NSNotFound) {
        PFBCompatTourLog(@"[tour] %@: no tab bar to tap", gPFBTourStepLive);
        return;
    }
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(switcher, NSSelectorFromString(@"selectTabAtIndex:"), current);
    PFBCompatTourLog(@"[tour] %@: tab %ld tapped again%@", gPFBTourStepLive, (long)current,
                     current == expected ? @"" : @", not the tab expected");
}

// Twitter's settings, built the way its navigation builds them: the root page from its
// factory, in its settings container, handed to the navigation's modal presenter. Returns
// the container, or nil when a piece is missing, which the journal names.
static UIViewController* tourPresentTwitterSettings(void) {
    id navigation = tourAppNavigation();
    id account = tourGetter(navigation, @"account");
    Class factory = NSClassFromString(kPFBTourSettingsFactory);
    Class containerClass = NSClassFromString(kPFBTourSettingsContainer);
    SEL build = NSSelectorFromString(@"rootViewControllerForAccount:");
    NSMethodSignature* signature = [factory respondsToSelector:build] ? [factory methodSignatureForSelector:build] : nil;
    BOOL buildable = signature.numberOfArguments == 3 && signature.methodReturnType[0] == '@' &&
                     [signature getArgumentTypeAtIndex:2][0] == '@' &&
                     [containerClass instancesRespondToSelector:@selector(initWithSettingsControllers:account:)];
    UIViewController* page = buildable && account ? ((id (*)(id, SEL, id))objc_msgSend)(factory, build, account) : nil;
    UIViewController* container = [page isKindOfClass:[UIViewController class]]
                                      ? [[containerClass alloc] initWithSettingsControllers:@[ page ] account:account]
                                      : nil;
    if (![container isKindOfClass:[UIViewController class]]) {
        PFBCompatTourLog(@"[tour] probe settings: navigation %@, account %@, factory %@, root page %@",
                         navigation ? NSStringFromClass([navigation class]) : @"none", account ? @"read" : @"none",
                         buildable ? @"usable" : @"not usable", page ? NSStringFromClass([page class]) : @"not built");
        return nil;
    }
    SEL present = NSSelectorFromString(
        @"_presentModalViewController:fromViewController:needsPreparationForModalPresentation:source:completion:");
    UIViewController* from = tourGetter(navigation, @"presentationViewController");
    NSMethodSignature* presenting =
        [navigation respondsToSelector:present] ? [navigation methodSignatureForSelector:present] : nil;
    BOOL presenter = [from isKindOfClass:[UIViewController class]] && presenting.numberOfArguments == 7 &&
                     [presenting getArgumentTypeAtIndex:2][0] == '@' && [presenting getArgumentTypeAtIndex:3][0] == '@' &&
                     strcmp([presenting getArgumentTypeAtIndex:4], @encode(BOOL)) == 0 &&
                     strcmp([presenting getArgumentTypeAtIndex:5], @encode(long long)) == 0 &&
                     strncmp([presenting getArgumentTypeAtIndex:6], "@?", 2) == 0;
    if (presenter) {
        ((void (*)(id, SEL, id, id, BOOL, long long, dispatch_block_t))objc_msgSend)(navigation, present, container, from,
                                                                                     NO, 0, ^{
                                                                                     });
    } else {
        [tourTopController() presentViewController:container animated:YES completion:nil];
    }
    PFBCompatTourLog(@"[tour] probe settings: %@ with root page %@ presented by %@",
                     NSStringFromClass([container class]), NSStringFromClass([page class]),
                     presenter ? [@"Twitter's presenter from " stringByAppendingString:NSStringFromClass([from class])]
                               : @"UIKit from the screen in front");
    return container;
}

// Twitter's settings asked of its navigation object, as its settings links do.
static void tourAskNavigationForSettings(void) {
    id navigation = tourAppNavigation();
    SEL show = NSSelectorFromString(@"showSettingsWithSource:completion:");
    NSMethodSignature* signature = [navigation respondsToSelector:show] ? [navigation methodSignatureForSelector:show] : nil;
    BOOL usable = signature.numberOfArguments == 4 && strcmp([signature getArgumentTypeAtIndex:2], @encode(long long)) == 0 &&
                  strncmp([signature getArgumentTypeAtIndex:3], "@?", 2) == 0;
    if (usable) {
        ((void (*)(id, SEL, long long, dispatch_block_t))objc_msgSend)(navigation, show, 0, ^{
        });
    }
    PFBCompatTourLog(@"[tour] probe settings: Twitter's navigation %@", usable ? @"asked for its settings" : @"cannot be asked");
}

// The root page of Twitter's settings while it is on screen: the first page of the
// container's stack, or of any settings stack up.
static UIViewController* tourSettingsRootPage(UIViewController* container) {
    UINavigationController* stack = tourGetter(container, @"settingsNavigationController");
    UIViewController* page = [stack isKindOfClass:[UINavigationController class]] ? stack.viewControllers.firstObject : nil;
    if (!page) {
        UIViewController* found = tourControllerNamed(tourRootController(), @"T1GenericSettingsViewController");
        page = found.navigationController.viewControllers.firstObject ?: found;
    }
    return page.viewIfLoaded.window ? page : nil;
}

// A row of a Twitter settings page selected the way a tap does: PrimeFreeBird's own, or
// the first of Twitter's that opens a page. Returns whether one was selected.
static BOOL tourSelectSettingsRow(UIViewController* page, BOOL ours) {
    NSArray* sections = tourGetter(page, @"sections");
    NSIndexPath* path = nil;
    NSString* kind = @"none";
    for (NSUInteger s = 0; !path && [sections isKindOfClass:[NSArray class]] && s < sections.count; s++) {
        NSArray* items = [sections[s] isKindOfClass:[NSArray class]] ? sections[s] : @[];
        for (NSUInteger r = 0; r < items.count; r++) {
            id title = tourGetter(items[r], @"title");
            BOOL pfb = [title isKindOfClass:[NSString class]] && [title isEqualToString:@PFB_PRODUCT_NAME];
            BOOL opensPage = [NSStringFromClass([items[r] class]) containsString:@"NavigationItem"];
            if (ours ? pfb : (!pfb && opensPage)) {
                path = [NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
                kind = NSStringFromClass([items[r] class]);
                break;
            }
        }
    }
    UIScrollView* list = (UIScrollView*)tourFindView(page.viewIfLoaded, ^BOOL(UIView* view) {
      return [view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]];
    });
    UITableView* table = [list isKindOfClass:[UITableView class]] ? (UITableView*)list : nil;
    UICollectionView* grid = [list isKindOfClass:[UICollectionView class]] ? (UICollectionView*)list : nil;
    BOOL listed = path && (table ? path.section < table.numberOfSections &&
                                       path.row < [table numberOfRowsInSection:path.section]
                                 : grid && path.section < grid.numberOfSections &&
                                       path.row < [grid numberOfItemsInSection:path.section]);
    NSString* row = ours ? @"its PrimeFreeBird row" : @"its first row that opens a page";
    BOOL selected = NO;
    if (listed && table && [table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [table.delegate tableView:table didSelectRowAtIndexPath:path];
        selected = YES;
    } else if (listed && grid && [grid.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        [grid.delegate collectionView:grid didSelectItemAtIndexPath:path];
        selected = YES;
    }
    PFBCompatTourLog(@"[tour] probe settings: %@ (%@) %@ in %@", row, kind,
                     selected ? [NSString stringWithFormat:@"selected at row %ld of section %ld", (long)path.row,
                                                           (long)path.section]
                              : (path ? @"not selectable" : @"not found"),
                     list ? NSStringFromClass([list class]) : @"no list");
    return selected;
}

// Twitter's settings closed the way their close button closes them: the sheet holding them
// goes down, or the stack goes back to its root when they were pushed.
static void tourCloseTwitterSettings(UIViewController* page) {
    if (!page) {
        PFBCompatTourLog(@"[tour] probe settings: no settings page left to close");
        return;
    }
    UIViewController* presenter = page.navigationController.presentingViewController ?: page.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:YES completion:nil];
    } else {
        [page.navigationController popToRootViewControllerAnimated:YES];
    }
    PFBCompatTourLog(@"[tour] probe settings: closed, %@", presenter ? @"sheet dismissed" : @"stack popped");
}

// A row of the Notifications list opened the way a tap does: its first Tweet, or else its
// first notification. Returns whether one was opened.
static BOOL tourOpenNotificationsRow(void) {
    UITableView* list = tourFrontList();
    id<UITableViewDelegate> delegate = list.delegate;
    NSIndexPath* tweet = nil;
    NSIndexPath* notification = nil;
    for (NSIndexPath* row in [list.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)]) {
        UITableViewCell* cell = [list cellForRowAtIndexPath:row];
        if (cell.hidden || cell.alpha < 0.5 || cell.bounds.size.height < 20.0) {
            continue;
        }
        NSString* name = NSStringFromClass([cell class]);
        tweet = tweet ?: ([name isEqualToString:@"T1StatusCell"] ? row : nil);
        notification = notification ?: ([name isEqualToString:@"T1URTTimelineNotificationCell"] ? row : nil);
    }
    NSIndexPath* pick = tweet ?: notification;
    if (!pick || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        PFBCompatTourLog(@"[tour] probe notifications: nothing to open in %@ (%lu visible rows)",
                         list ? NSStringFromClass([list class]) : @"no list", (unsigned long)list.visibleCells.count);
        return NO;
    }
    PFBCompatTourLog(@"[tour] probe notifications: %@ at row %ld opened", tweet ? @"Tweet" : @"notification",
                     (long)pick.row);
    [delegate tableView:list didSelectRowAtIndexPath:pick];
    return YES;
}

// The first trend Explore's list shows, opened the way a tap does. Returns whether one was.
static BOOL tourOpenTrend(void) {
    UITableView* list = tourFrontList();
    [list layoutIfNeeded];
    id<UITableViewDelegate> delegate = list.delegate;
    if (![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        return NO;
    }
    for (NSIndexPath* row in [list.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)]) {
        UITableViewCell* cell = [list cellForRowAtIndexPath:row];
        if (!cell.hidden && [NSStringFromClass([cell class]) hasSuffix:@".URTTimelineTrendCell"]) {
            PFBCompatTourLog(@"[tour] probe explore: trend at row %ld of section %ld opened", (long)row.row,
                             (long)row.section);
            [delegate tableView:list didSelectRowAtIndexPath:row];
            return YES;
        }
    }
    return NO;
}

// The segmented controller of a screen: the first one under it that names and shows tabs.
static id tourSegmentedUnder(UIViewController* screen) {
    NSMutableArray<UIViewController*>* queue = screen ? [NSMutableArray arrayWithObject:screen] : [NSMutableArray array];
    for (NSUInteger i = 0; i < queue.count && i < 128; i++) {
        UIViewController* controller = queue[i];
        if ([NSStringFromClass([controller class]) containsString:@"SegmentedViewController"] &&
            tourIntegerGetter(controller, @"numberOfTabs") != NSNotFound &&
            [controller respondsToSelector:NSSelectorFromString(@"tabBarView:descriptorAtIndex:")]) {
            return controller;
        }
        [queue addObjectsFromArray:controller.childViewControllers];
    }
    return nil;
}

// The trend's Latest tab, found by its title among the tabs of the screen's segmented
// controller, then shown the way Home's tabs are.
static void tourShowLatestTab(UIViewController* screen) {
    id segmented = tourSegmentedUnder(screen);
    id bar = tourGetter(segmented, @"tabBarView");
    NSInteger count = tourIntegerGetter(segmented, @"numberOfTabs");
    SEL describe = NSSelectorFromString(@"tabBarView:descriptorAtIndex:");
    NSMethodSignature* signature = [segmented respondsToSelector:describe] ? [segmented methodSignatureForSelector:describe] : nil;
    BOOL readable = bar && count != NSNotFound && signature.numberOfArguments == 4 && signature.methodReturnType[0] == '@' &&
                    [signature getArgumentTypeAtIndex:2][0] == '@' &&
                    strcmp([signature getArgumentTypeAtIndex:3], @encode(NSInteger)) == 0;
    NSString* latest = [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"SEARCH_FILTER_LATEST_LABEL"];
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    NSInteger found = NSNotFound;
    for (NSInteger i = 0; readable && i < count && i < 12; i++) {
        id descriptor = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(segmented, describe, bar, i);
        id title = tourGetter(descriptor, @"firstLabelText") ?: tourGetter(descriptor, @"tabAccessibilityLabel");
        NSString* text = [title isKindOfClass:[NSString class]] ? title : @"?";
        [titles addObject:text];
        if (found == NSNotFound && ([text caseInsensitiveCompare:latest] == NSOrderedSame ||
                                    [text caseInsensitiveCompare:@"Latest"] == NSOrderedSame)) {
            found = i;
        }
    }
    if (found != NSNotFound) {
        tourShowHomeTab(segmented, found);
    }
    PFBCompatTourLog(@"[tour] probe explore: %@ on %@, tabs %@ (%@)",
                     found != NSNotFound ? [NSString stringWithFormat:@"Latest tab %ld shown", (long)found] : @"no Latest tab",
                     tourScreenName(screen), segmented ? NSStringFromClass([segmented class]) : @"none",
                     titles.count ? [titles componentsJoinedByString:@" | "] : @"not read");
}

// One of Twitter's side-menu screens built by its own class factory taking the account, and
// pushed on the stack in front, as the Tweet interactions screen is. Returns whether it was.
static BOOL tourPushFactoryScreen(NSString* className, NSString* factoryName, NSString* step) {
    Class factory = NSClassFromString(className);
    SEL build = NSSelectorFromString(factoryName);
    NSMethodSignature* signature = [factory respondsToSelector:build] ? [factory methodSignatureForSelector:build] : nil;
    BOOL buildable = signature.numberOfArguments == 3 && signature.methodReturnType[0] == '@' &&
                     [signature getArgumentTypeAtIndex:2][0] == '@';
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    UINavigationController* stack = tourScreen().navigationController;
    UIViewController* screen =
        buildable && account && stack ? ((id (*)(id, SEL, id))objc_msgSend)(factory, build, account) : nil;
    if (![screen isKindOfClass:[UIViewController class]]) {
        PFBCompatTourLog(@"[tour] %@: factory %@, account %@, stack %@, screen %@", step, buildable ? @"usable" : @"not usable",
                         account ? @"read" : @"none", stack ? @"found" : @"none",
                         screen ? NSStringFromClass([screen class]) : @"not built");
        return NO;
    }
    [stack pushViewController:screen animated:NO];
    PFBCompatTourLog(@"[tour] %@: %@ pushed on %@", step, NSStringFromClass([screen class]), NSStringFromClass([stack class]));
    return YES;
}

// One of Twitter's side-menu screens opened by its tab controller's own panel command, the
// one a keyboard shortcut sends. Returns whether the command was sent.
static BOOL tourSendPanelCommand(NSString* command, NSString* step) {
    UIViewController* tabs = tourControllerAnswering(command);
    BOOL sent = tourSend(tabs, command);
    PFBCompatTourLog(@"[tour] %@: %@ %@", step, command,
                     sent ? [@"sent to " stringByAppendingString:NSStringFromClass([tabs class])] : @"not possible");
    return sent;
}

// Twitter's Tweet button, hidden or not.
static UIView* tourTweetButton(void) {
    return tourFindView(tourWindow(), ^BOOL(UIView* view) {
      return [NSStringFromClass([view class]) isEqualToString:@"TFNFloatingActionButton"];
    });
}

// Explore, then Notifications, each for 1.5 s, then Home, while the dark mode step holds the
// window dark; done runs once Home is back.
static void tourShowTabsInDark(NSInteger explore, NSInteger notifications, dispatch_block_t done) {
    NSUInteger generation = gPFBTourGeneration;
    NSArray<NSNumber*>* tabs = @[ @(explore), @(notifications), @0 ];
    NSTimeInterval at = 0;
    for (NSUInteger i = 0; i < tabs.count; i++) {
        NSInteger tab = tabs[i].integerValue;
        if (tab == NSNotFound) {
            continue;
        }
        BOOL last = i + 1 == tabs.count;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          if (generation != gPFBTourGeneration || ![gPFBTourStepLive isEqualToString:@"dark mode"]) {
              return;
          }
          tourAttempt(@"dark mode", @"showing a tab in dark", ^{
            tourSelectTab(tab);
          });
          if (last) {
              dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), done);
          }
        });
        at += 1.5;
    }
    PFBCompatTourLog(@"[tour] dark mode: %@%@then Home, shown in dark", explore != NSNotFound ? @"Explore, " : @"",
                     notifications != NSNotFound ? @"Notifications, " : @"");
}

// The author row of the first Tweet on screen by another account, promoted ones passed,
// tapped through its own handler: the route a tap on a name takes to the profile. Returns
// whether a row was tapped.
static BOOL tourTapAuthorRow(NSString* step) {
    id account = tourGetter(UIApplication.sharedApplication.delegate, @"_t1_currentAccount");
    NSString* own = tourGetter(account, @"username");
    NSUInteger promoted = 0;
    for (UITableViewCell* cell in tourFrontList().visibleCells) {
        id model = tourGetter(tourFindClass(cell, @"T1StandardStatusView"), @"viewModel");
        NSString* handle = tourGetter(tourGetter(model, @"fromUser"), @"username");
        UIView* author = tourFindClass(cell, @"TTAStatusAuthorView");
        if (!author.window || ![handle isKindOfClass:[NSString class]] ||
            [handle caseInsensitiveCompare:[own isKindOfClass:[NSString class]] ? own : @""] == NSOrderedSame) {
            continue;
        }
        if (tourBoolGetter(model, @"isPromoted") || tourGetter(model, @"promotedContent")) {
            promoted++;
            continue;
        }
        if (tourSend(author, @"_t1_didTapAuthorView")) {
            PFBCompatTourLog(@"[tour] %@: author row tapped through %@, %lu promoted passed", step,
                             NSStringFromClass([author class]), (unsigned long)promoted);
            return YES;
        }
    }
    PFBCompatTourLog(@"[tour] %@: no author row to tap, %lu promoted passed", step, (unsigned long)promoted);
    return NO;
}

// The tab a screen's segmented controller shows, with the title its descriptor gives.
static NSString* tourShownTab(UIViewController* screen) {
    id segmented = tourGetter(screen, @"segmentedViewController") ?: tourSegmentedUnder(screen);
    id bar = tourGetter(segmented, @"tabBarView");
    NSInteger shown = tourIntegerGetter(segmented, @"selectedIndex");
    NSInteger count = tourIntegerGetter(segmented, @"numberOfTabs");
    SEL describe = NSSelectorFromString(@"tabBarView:descriptorAtIndex:");
    NSMethodSignature* signature = [segmented respondsToSelector:describe] ? [segmented methodSignatureForSelector:describe] : nil;
    BOOL readable = bar && shown != NSNotFound && count != NSNotFound && shown >= 0 && shown < count &&
                    signature.numberOfArguments == 4 && signature.methodReturnType[0] == '@' &&
                    [signature getArgumentTypeAtIndex:2][0] == '@' &&
                    strcmp([signature getArgumentTypeAtIndex:3], @encode(NSInteger)) == 0;
    id descriptor = readable ? ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(segmented, describe, bar, shown) : nil;
    id title = tourGetter(descriptor, @"firstLabelText") ?: tourGetter(descriptor, @"tabAccessibilityLabel");
    return [NSString stringWithFormat:@"tab %@ of %@ shown (%@)", tourIndexText(shown), tourIndexText(count),
                                      [title isKindOfClass:[NSString class]] ? title : @"title not read"];
}

// MARK: - Probe readings

// Whether two colors match within 2/255 per channel once resolved with the traits.
static BOOL tourSameColor(UIColor* first, UIColor* second, UITraitCollection* traits) {
    UIColor* a = [first resolvedColorWithTraitCollection:traits];
    UIColor* b = [second resolvedColorWithTraitCollection:traits];
    CGFloat ra = 0, ga = 0, ba = 0, aa = 0, rb = 0, gb = 0, bb = 0, ab = 0;
    if (![a getRed:&ra green:&ga blue:&ba alpha:&aa] || ![b getRed:&rb green:&gb blue:&bb alpha:&ab]) {
        return [a isEqual:b];
    }
    CGFloat limit = 2.0 / 255.0 + 0.0001;
    return fabs(ra - rb) <= limit && fabs(ga - gb) <= limit && fabs(ba - bb) <= limit && fabs(aa - ab) <= limit;
}

// Probe: in forced dark with Twitter's dark palette, notes the tab editor's screen color
// against its Restore pill and border, and the palette's background against the system's.
static void tourProbeDarkColors(void) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    UITraitCollection* traits = tourWindow().traitCollection;
    NSString* palette = tourPaletteName(tourPalette());
    if (PFBProbeWants(@"07#F038 tab editor in dark")) {
        PFBProbeNote(@"07#F038 tab editor in dark",
                     @"07#F038 tab editor in dark: screen rgba(%@) · Restore pill rgba(%@) · border rgba(%@) · palette %@",
                     PFBProbeColor(PFBCustomTabBarScreenBackgroundColor(), traits),
                     PFBProbeColor(UIColor.systemBackgroundColor, traits), PFBProbeColor(UIColor.systemGray4Color, traits),
                     palette);
    }
    if (PFBProbeWants(@"09#F015 dark backgrounds")) {
        BOOL found = NO;
        long long darker = PFBProbeIntegerGetter(tourColorSettings(), @"isDarkerPaletteSelected", &found);
        PFBProbeNote(@"09#F015 dark backgrounds",
                     @"09#F015 08#F019 dark backgrounds: Twitter palette %@ rgba(%@), system rgba(%@), darker palette %@",
                     palette, PFBProbeColor([PFBPalette currentBackgroundColor], traits),
                     PFBProbeColor(UIColor.systemBackgroundColor, traits), found ? (darker ? @"yes" : @"no") : @"unreadable");
    }
}

// Probe: notes the text size, and the height the tab editor's header text and a tile's title
// need at it against the 60 pt and 19 pt they get.
static void tourProbeTextSize(void) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"07#F039 text size")) {
        return;
    }
    UIFont* regular = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13]);
    UIFont* bold = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:13]);
    NSString* text = [[PFBBundle sharedBundle] localizedStringForKey:@"CUSTOM_TAB_BAR_GRID_DETAIL"];
    CGFloat width = CGRectGetWidth(tourWindow().bounds) - 8.0;
    CGRect box = regular ? [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:@{NSFontAttributeName : regular}
                                              context:nil]
                         : CGRectZero;
    PFBProbeNote(@"07#F039 text size",
                 @"07#F039 text size %@: editor header needs %.1f of 60 pt (width %.0f), tile title needs %.1f of 19 pt",
                 UIApplication.sharedApplication.preferredContentSizeCategory, ceil(CGRectGetHeight(box)), width,
                 bold.lineHeight);
}

// Probe: notes the Home Screen icons this build declares, counted by name prefix, with the
// names of any other.
static void tourProbeAppIcons(void) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"14b#F016d app icons")) {
        return;
    }
    id icons = NSBundle.mainBundle.infoDictionary[@"CFBundleIcons"];
    id primary = [icons isKindOfClass:[NSDictionary class]] ? icons[@"CFBundlePrimaryIcon"] : nil;
    id primaryName = [primary isKindOfClass:[NSDictionary class]] ? primary[@"CFBundleIconName"] : nil;
    id alternates = [icons isKindOfClass:[NSDictionary class]] ? icons[@"CFBundleAlternateIcons"] : nil;
    NSArray<NSString*>* prefixes = @[ @"Custom-", @"Legacy-", @"Seasonal-", @"Production" ];
    NSUInteger counts[4] = {0, 0, 0, 0};
    NSMutableArray<NSString*>* others = [NSMutableArray array];
    NSArray* names = [alternates isKindOfClass:[NSDictionary class]] ? [[alternates allKeys] sortedArrayUsingSelector:@selector(compare:)] : @[];
    for (id name in names) {
        NSString* text = [name isKindOfClass:[NSString class]] ? name : @"?";
        NSUInteger kind = [prefixes indexOfObjectPassingTest:^BOOL(NSString* prefix, NSUInteger index, BOOL* stop) {
          return [text hasPrefix:prefix];
        }];
        if (kind != NSNotFound) {
            counts[kind]++;
        } else if (others.count < 20) {
            [others addObject:text];
        }
    }
    PFBProbeNote(@"14b#F016d app icons",
                 @"14b#F016d app icons: primary %@, %lu alternates: Custom- %lu, Legacy- %lu, Seasonal- %lu, Production %lu, "
                 @"other %lu (%@)",
                 [primaryName isKindOfClass:[NSString class]] ? primaryName : @"unnamed", (unsigned long)names.count,
                 (unsigned long)counts[0], (unsigned long)counts[1], (unsigned long)counts[2], (unsigned long)counts[3],
                 (unsigned long)(names.count - counts[0] - counts[1] - counts[2] - counts[3]),
                 others.count ? [others componentsJoinedByString:@", "] : @"none");
}

// Probe: on a PrimeFreeBird page with the window held dark, notes which backgrounds differ
// from the palette's current one: the view, the table, and each visible cell by class.
static void tourProbeSettingsInDark(UIViewController* page) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"03#F033 settings in dark")) {
        return;
    }
    if (![page isKindOfClass:[PFBModernSettingsPageViewController class]] || !page.viewIfLoaded.window) {
        PFBProbeNote(@"03#F033 settings in dark", @"03#F033 settings in dark: no PrimeFreeBird page on screen");
        return;
    }
    UITableView* table = ((PFBModernSettingsPageViewController*)page).tableView;
    UITraitCollection* traits = page.traitCollection;
    UIColor* expected = [PFBPalette currentBackgroundColor];
    NSMutableArray<NSString*>* kinds = [NSMutableArray array];
    NSMutableDictionary<NSString*, NSArray<NSNumber*>*>* tally = [NSMutableDictionary dictionary];
    for (UITableViewCell* cell in table.visibleCells) {
        NSString* name = NSStringFromClass([cell class]);
        name = [name hasPrefix:@"PFBModernSettings"] ? [name substringFromIndex:17] : name;
        BOOL clear = !cell.backgroundColor ||
                     CGColorGetAlpha([cell.backgroundColor resolvedColorWithTraitCollection:traits].CGColor) < 0.01;
        BOOL stale = !clear && !tourSameColor(cell.backgroundColor, expected, traits);
        NSArray<NSNumber*>* counts = tally[name] ?: @[ @0, @0, @0 ];
        if (!tally[name]) {
            [kinds addObject:name];
        }
        tally[name] = @[ @(counts[0].integerValue + (stale ? 1 : 0)), @(counts[1].integerValue + (clear ? 1 : 0)),
                         @(counts[2].integerValue + 1) ];
    }
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* name in kinds) {
        NSArray<NSNumber*>* counts = tally[name];
        [parts addObject:[NSString stringWithFormat:@"%@ %@/%@ stale%@", name, counts[0], counts[2],
                                                    counts[1].integerValue ? [NSString stringWithFormat:@" (%@ clear)", counts[1]]
                                                                           : @""]];
    }
    PFBProbeNote(@"03#F033 settings in dark",
                 @"03#F033 settings in dark (page %@, palette %@ rgba(%@)): view %@, table %@, %@",
                 traits.userInterfaceStyle == UIUserInterfaceStyleDark ? @"dark" : @"light", tourPaletteName(tourPalette()),
                 PFBProbeColor(expected, traits), tourSameColor(page.view.backgroundColor, expected, traits) ? @"ok" : @"stale",
                 tourSameColor(table.backgroundColor, expected, traits) ? @"ok" : @"stale",
                 parts.count ? [parts componentsJoinedByString:@", "] : @"no cells");
}

// Probe: notes which window is key at a moment of the tour, with its level.
static void tourProbeKeyWindow(NSString* tag, NSString* moment) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    UIWindow* key = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            key = window.isKeyWindow ? window : key;
        }
    }
    NSString* name = key ? NSStringFromClass([key class]) : @"none";
    NSString* note = [NSString stringWithFormat:@"02#F022 %@ %@", tag, name];
    if (PFBProbeWants(note)) {
        PFBProbeNote(note, @"02#F022 key window %@: %@ (level %.0f)", moment, name, key ? key.windowLevel : 0.0);
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

// MARK: - Probe steps

// A probe passage's step: built only for a full tour while the debugger records, it owes no
// proof, waits for its check to finish the passage, and ends early once the passage gives up.
static NSDictionary* tourProbeStep(NSTimeInterval wait, NSDictionary* step, BOOL (^over)(void)) {
    NSMutableDictionary* probe = [tourStepWaiting(wait, step) mutableCopy];
    probe[@"probe"] = @YES;
    if (over) {
        probe[@"over"] = [over copy];
    }
    return probe;
}

// P1: Twitter's settings, its PrimeFreeBird row and back with the back arrow, its first row
// that opens a page and back, then closed.
static NSDictionary* tourProbeSettingsStep(void) {
    __block NSInteger phase = 0;
    __block CFTimeInterval since = 0;
    __block BOOL secondWay = NO;
    __block BOOL gaveUp = NO;
    __block __weak UIViewController* container = nil;
    __block __weak UIViewController* rootPage = nil;
    NSDictionary* step = tourStep(@"probe settings", @"Twitter settings", ^{
          tourDismissPresented();
          tourPopToRoot();
        }, ^{
          phase = 0;
          since = CACurrentMediaTime();
          gaveUp = NO;
          rootPage = nil;
          container = tourPresentTwitterSettings();
          secondWay = container == nil;
          if (secondWay) {
              tourAskNavigationForSettings();
          }
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          UIViewController* page = rootPage ?: tourSettingsRootPage(container);
          UINavigationController* stack = page.navigationController;
          BOOL atRoot = page.viewIfLoaded.window != nil && stack.topViewController == page;
          switch (phase) {
              case 0:
                  if (atRoot) {
                      rootPage = page;
                      PFBCompatTourLog(@"[tour] probe settings: root page %@ in %@, %@", NSStringFromClass([page class]),
                                       NSStringFromClass([stack class]),
                                       stack.presentingViewController
                                           ? [@"presented by " stringByAppendingString:NSStringFromClass(
                                                                                         [stack.presentingViewController class])]
                                           : @"not presented");
                      phase = 1;
                      since = now;
                  } else if (!secondWay && now - since >= 2.5) {
                      secondWay = YES;
                      since = now;
                      tourAskNavigationForSettings();
                  } else if (secondWay && now - since >= 3.0) {
                      PFBCompatTourLog(@"[tour] probe settings: Twitter's settings did not show, %@ in front",
                                       tourScreenName(after));
                      gaveUp = YES;
                  }
                  break;
              case 1:
              case 4:
                  // The root page for a moment, then its PrimeFreeBird row, later its first row.
                  if (atRoot && now - since >= (phase == 1 ? 1.5 : 0.8)) {
                      BOOL pfb = phase == 1;
                      phase = tourSelectSettingsRow(page, pfb) ? phase + 1 : (pfb ? 4 : 7);
                      since = now;
                  } else if (!atRoot && now - since >= 3.0) {
                      PFBCompatTourLog(@"[tour] probe settings: root page not back in front");
                      phase = 7;
                      since = now;
                  }
                  break;
              case 2:
              case 5:
                  // The page the row opened, once it is pushed.
                  if (stack.topViewController && stack.topViewController != page) {
                      PFBCompatTourLog(@"[tour] probe settings: %@ opened %@", phase == 2 ? @"PrimeFreeBird row" : @"first row",
                                       NSStringFromClass([stack.topViewController class]));
                      phase++;
                      since = now;
                  } else if (now - since >= 3.0) {
                      PFBCompatTourLog(@"[tour] probe settings: %@ opened nothing", phase == 2 ? @"PrimeFreeBird row" : @"first row");
                      phase = phase == 2 ? 4 : 7;
                      since = now;
                  }
                  break;
              case 3:
              case 6:
                  // Back with the back arrow, which pops the page animated.
                  if (now - since >= 1.5) {
                      [stack popViewControllerAnimated:YES];
                      phase = phase == 3 ? 4 : 7;
                      since = now;
                  }
                  break;
              case 7:
                  if ((atRoot && now - since >= 0.6) || now - since >= 3.0) {
                      tourCloseTwitterSettings(page);
                      phase = 8;
                      since = now;
                  }
                  break;
              default:
                  return !page.viewIfLoaded.window || now - since >= 1.5;
          }
          return NO;
        }, nil, ^{
          tourDismissPresented();
          tourPopToRoot();
          tourSelectTab(0);
        });
    return tourProbeStep(18.0, step, ^BOOL {
      return gaveUp;
    });
}

// P2: on Notifications, a Tweet opened and scrolled a little, then the Notifications tab
// tapped again to come back to the list. Twitter's own texts are read here too.
static NSDictionary* tourProbeNotificationsStep(NSInteger notifications) {
    __block NSInteger phase = 0;
    __block CFTimeInterval since = 0;
    __block BOOL gaveUp = NO;
    __block __weak UIViewController* list = nil;
    NSDictionary* step = tourStep(@"probe notifications", @"Notifications, a Tweet", ^{
          tourHomeFront();
        }, ^{
          phase = 0;
          since = CACurrentMediaTime();
          gaveUp = NO;
          list = nil;
          tourSelectTab(notifications);
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          switch (phase) {
              case 0:
                  if ([tourScreenName(after) containsString:@"Notifications"] && now - since >= 1.5) {
                      list = after;
                      PFBProbeTwitterStrings();
                      gaveUp = !tourOpenNotificationsRow();
                      phase = 1;
                      since = now;
                  } else if (now - since >= 6.0) {
                      PFBCompatTourLog(@"[tour] probe notifications: %@ in front, not Notifications", tourScreenName(after));
                      gaveUp = YES;
                  }
                  break;
              case 1:
                  if (after && after != list) {
                      PFBCompatTourLog(@"[tour] probe notifications: %@ opened", tourScreenName(after));
                      phase = 2;
                      since = now;
                  } else if (now - since >= 3.0) {
                      PFBCompatTourLog(@"[tour] probe notifications: the row opened nothing");
                      gaveUp = YES;
                  }
                  break;
              case 2:
                  if (now - since >= 1.2) {
                      UITableView* front = tourFrontList();
                      tourDrag(front, front.bounds.size.height * 0.4);
                      phase = 3;
                      since = now;
                  }
                  break;
              case 3:
                  if (now - since >= 1.2) {
                      tourTapTabAgain(notifications);
                      phase = 4;
                      since = now;
                  }
                  break;
              case 4:
                  if (after == list) {
                      PFBCompatTourLog(@"[tour] probe notifications: back on the list");
                      phase = 5;
                      since = now;
                  } else if (now - since >= 2.0) {
                      PFBCompatTourLog(@"[tour] probe notifications: %@ still in front after the tab tap, stack popped",
                                       tourScreenName(after));
                      tourPopToRoot();
                      phase = 5;
                      since = now;
                  }
                  break;
              default:
                  return now - since >= 0.8;
          }
          return NO;
        }, nil, ^{
          tourHomeFront();
        });
    return tourProbeStep(15.0, step, ^BOOL {
      return gaveUp;
    });
}

// P3: Hide notifications switched off, the Notifications list scrolled a little, then the
// option put back, which happens at the next launch too should Twitter close.
static NSDictionary* tourProbeNotificationsOffStep(NSInteger notifications) {
    __block NSInteger phase = 0;
    __block CFTimeInterval since = 0;
    __block BOOL gaveUp = NO;
    NSDictionary* step = tourStep(@"probe notifications off", @"Notifications, Hide notifications off", ^{
          tourHomeFront();
          tourSwitchOption(@"hide_notifications", NO);
        }, ^{
          phase = 0;
          since = CACurrentMediaTime();
          gaveUp = NO;
          tourSelectTab(notifications);
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          switch (phase) {
              case 0:
                  if ([tourScreenName(after) containsString:@"Notifications"] && now - since >= 1.5) {
                      UITableView* front = tourFrontList();
                      tourDrag(front, front.bounds.size.height * 0.6);
                      PFBCompatTourLog(@"[tour] probe notifications off: %@ scrolled", front ? NSStringFromClass([front class]) : @"no list");
                      phase = 1;
                      since = now;
                  } else if (now - since >= 6.0) {
                      PFBCompatTourLog(@"[tour] probe notifications off: %@ in front, not Notifications", tourScreenName(after));
                      gaveUp = YES;
                  }
                  break;
              case 1:
                  if (now - since >= 1.5) {
                      tourRestoreOptions(@"after the scroll");
                      phase = 2;
                      since = now;
                  }
                  break;
              default:
                  return now - since >= 1.0;
          }
          return NO;
        }, nil, ^{
          tourRestoreOptions(@"after the step");
          tourScrollHomeToTop();
          tourHomeFront();
        });
    return tourProbeStep(10.0, step, ^BOOL {
      return gaveUp;
    });
}

// P4: on Explore, a trend opened and scrolled a little, its Latest tab shown, then the
// Explore tab tapped again to come back.
static NSDictionary* tourProbeExploreStep(NSInteger explore) {
    __block NSInteger phase = 0;
    __block NSInteger tries = 0;
    __block CFTimeInterval since = 0;
    __block BOOL gaveUp = NO;
    __block __weak UIViewController* guide = nil;
    __block __weak UIViewController* trend = nil;
    NSDictionary* step = tourStep(@"probe explore", @"Explore, a trend", ^{
          tourHomeFront();
        }, ^{
          phase = 0;
          tries = 0;
          since = CACurrentMediaTime();
          gaveUp = NO;
          guide = nil;
          trend = nil;
          tourSelectTab(explore);
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          switch (phase) {
              case 0:
                  if ([tourScreenName(after) containsString:@"Guide"] && now - since >= 1.5) {
                      guide = after;
                      if (tries == 0) {
                          tourScrollHomeToTop();
                      }
                      if (tourOpenTrend()) {
                          phase = 1;
                          since = now;
                      } else if (++tries >= 4) {
                          PFBCompatTourLog(@"[tour] probe explore: no trend within %ld screens of Explore", (long)tries);
                          gaveUp = YES;
                      } else {
                          UITableView* front = tourFrontList();
                          [front setContentOffset:CGPointMake(front.contentOffset.x,
                                                              front.contentOffset.y + front.bounds.size.height * 0.8)
                                         animated:NO];
                          since = now - 1.0;
                      }
                  } else if (now - since >= 6.0) {
                      PFBCompatTourLog(@"[tour] probe explore: %@ in front, not Explore", tourScreenName(after));
                      gaveUp = YES;
                  }
                  break;
              case 1:
                  if (after && after != guide) {
                      trend = after;
                      PFBCompatTourLog(@"[tour] probe explore: %@ opened", tourScreenName(after));
                      phase = 2;
                      since = now;
                  } else if (now - since >= 4.0) {
                      PFBCompatTourLog(@"[tour] probe explore: the trend opened nothing");
                      gaveUp = YES;
                  }
                  break;
              case 2:
                  if (now - since >= 1.5) {
                      UITableView* front = tourFrontList();
                      tourDrag(front, front.bounds.size.height * 0.4);
                      phase = 3;
                      since = now;
                  }
                  break;
              case 3:
                  if (now - since >= 1.2) {
                      tourShowLatestTab(trend ?: after);
                      phase = 4;
                      since = now;
                  }
                  break;
              case 4:
                  if (now - since >= 1.5) {
                      tourTapTabAgain(explore);
                      phase = 5;
                      since = now;
                  }
                  break;
              case 5:
                  if (after == guide) {
                      PFBCompatTourLog(@"[tour] probe explore: back on Explore");
                      phase = 6;
                      since = now;
                  } else if (now - since >= 2.0) {
                      PFBCompatTourLog(@"[tour] probe explore: %@ still in front after the tab tap, stack popped",
                                       tourScreenName(after));
                      tourPopToRoot();
                      phase = 6;
                      since = now;
                  }
                  break;
              default:
                  return now - since >= 0.8;
          }
          return NO;
        }, nil, ^{
          tourHomeFront();
        });
    return tourProbeStep(20.0, step, ^BOOL {
      return gaveUp;
    });
}

// P5: one of Twitter's side-menu screens opened, a moment in front, then Home. A factory, when
// given, builds it first; the tab controller's panel command is the other way in.
static NSDictionary* tourProbePanelStep(NSString* name, NSString* label, NSString* command, NSString* factoryClass,
                                        NSString* factory) {
    __block NSInteger phase = 0;
    __block CFTimeInterval since = 0;
    __block BOOL secondWay = NO;
    __block BOOL gaveUp = NO;
    NSDictionary* step = tourStep(name, label, ^{
          tourHomeFront();
        }, ^{
          phase = 0;
          since = CACurrentMediaTime();
          gaveUp = NO;
          BOOL built = factoryClass && tourPushFactoryScreen(factoryClass, factory, name);
          secondWay = !built;
          if (!built) {
              tourSendPanelCommand(command, name);
          }
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          if (phase == 0) {
              if (after && after != before) {
                  PFBCompatTourLog(@"[tour] %@: %@ in front", name, tourScreenName(after));
                  phase = 1;
                  since = now;
              } else if (!secondWay && now - since >= 2.5) {
                  secondWay = YES;
                  since = now;
                  tourSendPanelCommand(command, name);
              } else if (secondWay && now - since >= 3.0) {
                  PFBCompatTourLog(@"[tour] %@: nothing opened, %@ in front", name, tourScreenName(after));
                  gaveUp = YES;
              }
              return NO;
          }
          return now - since >= 2.0;
        }, nil, ^{
          tourHomeFront();
        });
    return tourProbeStep(10.0, step, ^BOOL {
      return gaveUp;
    });
}

// P7: Hide Tweet button switched on without a relaunch while Home shows for 2 s, then put
// back, which happens at the next launch too should Twitter close; the button is laid out
// again so the value put back reaches it.
static NSDictionary* tourProbeTweetButtonStep(void) {
    __block CFTimeInterval since = 0;
    NSDictionary* step = tourStep(@"probe tweet button", @"Home, Hide Tweet button on", ^{
          tourHomeFront();
          tourSwitchOption(@"hide_tweet_button", YES);
          // Its own moment, apart from the person's switch (Branding.x notes each).
          PFBProbeMark(@"hide_tweet_button on (tour)");
        }, ^{
          since = CACurrentMediaTime();
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          if (CACurrentMediaTime() - since < 2.0) {
              return NO;
          }
          UIView* button = tourTweetButton();
          PFBCompatTourLog(@"[tour] probe tweet button: Tweet button %@ after 2 s with the option on",
                           !button ? @"not found" : (button.hidden || button.alpha < 0.01 ? @"hidden" : @"shown"));
          return YES;
        }, nil, ^{
          tourRestoreOptions(@"after the step");
          UIView* button = tourTweetButton();
          [button setNeedsLayout];
          [button layoutIfNeeded];
          // Probe: Twitter's texts, read here when the Notifications passage did not run.
          PFBProbeTwitterStrings();
        });
    return tourProbeStep(5.0, step, nil);
}

// P6: while the dark mode step holds the window dark, once Twitter's palette is dark, the
// colors are read; once the step is done, Explore then Notifications show for 1.5 s each
// before Home. The step's check, proofs and outcome are its own; it is only held up while
// the tabs show, and Home comes back should it stop first.
static NSDictionary* tourProbeDarkModeStep(NSDictionary* step, NSInteger explore, NSInteger notifications) {
    NSMutableDictionary* extended = [step mutableCopy];
    PFBTourCheck check = step[@"check"];
    dispatch_block_t cleanUp = step[@"after"];
    __block BOOL dark = NO;
    __block BOOL started = NO;
    __block BOOL running = NO;
    extended[@"check"] = [^BOOL(UIViewController* before, UIViewController* after) {
      BOOL shown = check(before, after);
      if (shown && !dark) {
          dark = YES;
          tourProbeDarkColors();
      }
      return shown;
    } copy];
    // Asked only once the step is done, so the tabs show after its outcome is set.
    extended[@"busy"] = [^BOOL {
      if (dark && !started) {
          started = YES;
          running = YES;
          tourAttempt(@"dark mode", @"showing tabs in dark", ^{
            tourShowTabsInDark(explore, notifications, ^{
              running = NO;
            });
          });
      }
      return running;
    } copy];
    extended[@"held"] = [NSMutableDictionary dictionary];
    extended[@"after"] = [^{
      if (cleanUp) {
          cleanUp();
      }
      if (started) {
          tourSelectTab(0);
      }
    } copy];
    return extended;
}

// P8: once the PrimeFreeBird page is up, the text size, the fonts, the custom fonts list and
// the Home Screen icons are read; once the step is done, the page is held dark with Twitter's
// dark palette for 0.6 s to read its backgrounds, and the style and palette are put back, at
// the step's end too should it stop first. The step's check, proofs and outcome are its own.
static NSDictionary* tourProbePFBSettingsStep(NSDictionary* step) {
    NSMutableDictionary* extended = [step mutableCopy];
    PFBTourCheck check = step[@"check"];
    dispatch_block_t cleanUp = step[@"after"];
    __block BOOL pageRead = NO;
    __block BOOL started = NO;
    __block BOOL running = NO;
    __block BOOL dark = NO;
    __block UIUserInterfaceStyle styleBefore = UIUserInterfaceStyleUnspecified;
    dispatch_block_t putBack = ^{
      if (dark) {
          dark = NO;
          tourWindow().overrideUserInterfaceStyle = styleBefore;
          tourRestorePalette();
      }
    };
    extended[@"check"] = [^BOOL(UIViewController* before, UIViewController* after) {
      BOOL shown = check(before, after);
      if (shown && !pageRead) {
          pageRead = YES;
          tourProbeTextSize();
          PFBProbeFontLoading();
          PFBProbeCustomFontsFile();
          tourProbeAppIcons();
      }
      return shown;
    } copy];
    // Asked only once the step is done, so the page turns dark after its outcome is set.
    extended[@"busy"] = [^BOOL {
      if (!pageRead || started) {
          return running;
      }
      started = YES;
      if (!PFBProbeWants(@"03#F033 settings in dark")) {
          return NO;
      }
      running = YES;
      tourAttempt(@"PFB settings", @"holding the page in dark", ^{
        __weak UIViewController* page =
            tourFindController(tourRootController().presentedViewController, @"PFBModernSettingsPageViewController");
        UIWindow* window = tourWindow();
        styleBefore = window.overrideUserInterfaceStyle;
        dark = YES;
        window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        NSUInteger generation = gPFBTourGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          if (generation != gPFBTourGeneration || ![gPFBTourStepLive isEqualToString:@"PFB settings"]) {
              return;
          }
          if (!tourBoolGetter(tourPalette(), @"isDark")) {
              tourAttempt(@"PFB settings", @"switching to the dark palette", ^{
                tourSwitchToDarkPalette();
              });
          }
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != gPFBTourGeneration || ![gPFBTourStepLive isEqualToString:@"PFB settings"]) {
                return;
            }
            tourAttempt(@"PFB settings", @"reading the page in dark", ^{
              tourProbeSettingsInDark(page);
            });
            putBack();
            running = NO;
          });
        });
      });
      return running;
    } copy];
    extended[@"held"] = [NSMutableDictionary dictionary];
    extended[@"after"] = [^{
      putBack();
      if (cleanUp) {
          cleanUp();
      }
    } copy];
    return extended;
}

// For 10b#F025: profiles set to open on their Media tab, then the profile the other profile
// step picks opened by its link, or else through a Tweet's author row, 3 s in front so the
// profile and its tab hooks run; then Home, and the option put back, which happens at the
// next launch too should Twitter close.
static NSDictionary* tourProbeProfileTabStep(void) {
    __block NSInteger phase = 0;
    __block CFTimeInterval since = 0;
    __block BOOL secondWay = NO;
    __block BOOL gaveUp = NO;
    __block __weak UIViewController* profile = nil;
    NSDictionary* step = tourStep(@"probe profile tab", @"Profile on its Media tab", ^{
          tourHomeFront();
          tourSwitchInteger(@"profile_initial_tab", 4);
        }, ^{
          phase = 0;
          secondWay = NO;
          gaveUp = NO;
          profile = nil;
          NSString* longest = tourLongestBioHandle();
          NSString* first = longest ? nil : tourAuthorHandle();
          tourOpenLink([@"twitter://user?screen_name=" stringByAppendingString:longest ?: first ?: @"X"]);
          PFBCompatTourLog(@"[tour] probe profile tab: link sent for %@",
                           longest ? @"the author with the longest bio" : (first ? @"the first author" : @"the fallback account"));
          since = CACurrentMediaTime();
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          if (phase == 0) {
              if ([tourScreenName(after) containsString:@"Profile"]) {
                  profile = after;
                  PFBCompatTourLog(@"[tour] probe profile tab: %@ in front", tourScreenName(after));
                  phase = 1;
                  since = now;
              } else if (!secondWay && now - since >= 2.5) {
                  secondWay = YES;
                  since = now;
                  gaveUp = !tourTapAuthorRow(@"probe profile tab");
              } else if (secondWay && now - since >= 3.0) {
                  PFBCompatTourLog(@"[tour] probe profile tab: no profile opened, %@ in front", tourScreenName(after));
                  gaveUp = YES;
              }
              return NO;
          }
          if (now - since < 3.0) {
              return NO;
          }
          PFBCompatTourLog(@"[tour] probe profile tab: %@ after 3 s", tourShownTab(profile ?: after));
          return YES;
        }, nil, ^{
          tourHomeFront();
          tourRestoreOptions(@"after the step");
        });
    return tourProbeStep(12.0, step, ^BOOL {
      return gaveUp;
    });
}

// For 10a#F034: the full-screen player's pill on Sound on, then a Home video opened full
// screen the way the video step opens it, its tap handler first and the media view's tap
// second, 3 s in front so the player's sound is read; the video plays with its sound. Then
// the player closed the way that step closes it, Home, and the option put back, which
// happens at the next launch too should Twitter close.
static NSDictionary* tourProbeVideoSoundStep(void) {
    __block NSInteger phase = 0;
    __block CFTimeInterval since = 0;
    __block BOOL secondWay = NO;
    __block BOOL gaveUp = NO;
    __block __weak UIView* video = nil;
    __block BOOL soundRead = NO;
    __block BOOL soundAllowed = NO;
    NSDictionary* step = tourStep(@"probe video sound", @"Video full screen, Sound on", ^{
          tourHomeFront();
          soundRead = YES;
          soundAllowed = pfbProbeSoundAllowed();
          tourSwitchOption(@"video_starts_muted", NO);
        }, ^{
          phase = 0;
          secondWay = NO;
          UIView* opened = tourOpenVideo();
          video = opened;
          gaveUp = opened == nil;
          since = CACurrentMediaTime();
        }, ^BOOL(UIViewController* before, UIViewController* after) {
          CFTimeInterval now = CACurrentMediaTime();
          BOOL open = tourRootController().presentedViewController != nil ||
                      [tourScreenName(after) containsString:@"Immersive"];
          if (phase == 0) {
              if (open) {
                  PFBCompatTourLog(@"[tour] probe video sound: player in front, opened by %@",
                                   secondWay ? @"the media view's tap" : @"the video's tap handler");
                  phase = 1;
                  since = now;
              } else if (!secondWay && now - since >= 2.5) {
                  secondWay = YES;
                  since = now;
                  tourTapMedia(video, @"probe video sound");
              } else if (secondWay && now - since >= 3.0) {
                  PFBCompatTourLog(@"[tour] probe video sound: no player opened, %@ in front", tourScreenName(after));
                  gaveUp = YES;
              }
              return NO;
          }
          return now - since >= 3.0;
        }, nil, ^{
          tourDismissPresented();
          // The tap with Sound on allowed sound in full screen; the next video opened another
          // way finds the state it had before the passage.
          if (soundRead) {
              soundRead = NO;
              pfbProbeRestoreSoundAllowed(soundAllowed);
          }
          tourScrollHomeToTop();
          tourHomeFront();
          tourRestoreOptions(@"after the step");
        });
    return tourProbeStep(10.0, step, ^BOOL {
      return gaveUp;
    });
}

// The probe passages, after every regular step so none of those is changed: P1 to P5, P7, then
// the profile tab and video sound passages.
static NSArray<NSDictionary*>* tourProbeSteps(NSInteger explore, NSInteger notifications) {
    NSMutableArray<NSDictionary*>* steps = [NSMutableArray array];
    [steps addObject:tourProbeSettingsStep()];
    if (notifications != NSNotFound) {
        [steps addObject:tourProbeNotificationsStep(notifications)];
        [steps addObject:tourProbeNotificationsOffStep(notifications)];
    }
    if (explore != NSNotFound) {
        [steps addObject:tourProbeExploreStep(explore)];
    }
    [steps addObject:tourProbePanelStep(@"probe bookmarks", @"Bookmarks", @"handleBookmarksPanelKeyCommand",
                                        kPFBTourBookmarksFactory, @"allBookmarksTimelineWithAccount:")];
    [steps addObject:tourProbePanelStep(@"probe lists", @"Lists", @"handleListsPanelKeyCommand", kPFBTourListsPage,
                                        @"listManagementViewControllerWithAccount:")];
    [steps addObject:tourProbePanelStep(@"probe communities", @"Communities", @"handleCommunitiesPanelKeyCommand", nil, nil)];
    [steps addObject:tourProbeTweetButtonStep()];
    [steps addObject:tourProbeProfileTabStep()];
    [steps addObject:tourProbeVideoSoundStep()];
    return steps;
}

// Every step in order. Each brings the app where it needs it, so any subset runs on
// its own. With probe, the probe passages come along.
static NSArray<NSDictionary*>* tourAllSteps(BOOL probe) {
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
                 PFBCompatTourLog(@"[tour] search field: no search screen after 2.5 s, link opened again");
                 tourOpenLink(@"twitter://search?query=news");
             }
           }, ^{
             UIView* typing = tourFirstResponder();
             PFBCompatTourLog(@"[tour] search field: screen %@, typing in %@", tourScreenName(tourScreen()),
                              typing ? NSStringFromClass([typing class]) : @"nothing");
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
             tourDrag(list, list.bounds.size.height * 1.5);
             tourPull();
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
             PFBCompatTourLog(@"[tour] following timeline: %@ \u00b7 tab %@ shown, was %@ \u00b7 first retweet: %@",
                         homeTabs ? NSStringFromClass([homeTabs class]) : @"no Home tabs", tourIndexText(shown),
                         tourIndexText(homeTabShown), PFBFirstRetweetSummary() ?: @"none examined");
             if (homeTabShown != NSNotFound && homeTabShown != shown) {
                 tourShowHomeTab(homeTabs, homeTabShown);
             }
           })];
    __block CGFloat scrollStart = 0.0;
    [steps addObject:tourStep(@"scroll", @"Scroll", home, ^{
             UITableView* list = tourFrontList();
             scrollStart = list.contentOffset.y;
             tourDrag(list, list.bounds.size.height * 1.5);
             PFBCompatTourLog(@"[tour] scroll: %@ dragged from %.0f to %.0f", list ? NSStringFromClass([list class]) : @"no list",
                              scrollStart, list.contentOffset.y);
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
             tourProbeVideoStepEnd();
             tourDismissPresented();
             tourScrollHomeToTop();
           })];
    __block BOOL menuBuilt = NO;
    [steps addObject:tourStep(@"video long press", @"Video menu", home, ^{
             menuBuilt = NO;
             UIView* pressed = tourHomeViewOfClass(@"T1InlineVideoView");
             tourDescribeChain(@"video long press", pressed, tourAncestor(pressed, @"T1StatusCell") ?: pressed.superview);
             menuBuilt = tourTableMenuDoor(pressed, @"first");
             // Twitter's share sheet names the Tweet a moment after an ask; the asks that
             // follow find it, as the menu of a real long press does.
             __weak UIView* weakPressed = pressed;
             NSUInteger generation = gPFBTourGeneration;
             for (NSInteger ask = 1; ask <= 2; ask++) {
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * ask * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{
                                  if (generation == gPFBTourGeneration &&
                                      [gPFBTourStepLive isEqualToString:@"video long press"]) {
                                      tourAttempt(@"video long press", @"asking the menu again", ^{
                                        menuBuilt = tourTableMenuDoor(weakPressed, ask == 1 ? @"again" : @"a third time") || menuBuilt;
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
    __block NSInteger profileLooks = 0;
    [steps addObject:tourStep(@"other profile", @"Another profile", home, ^{
             followRead = NO;
             profileLooks = 0;
             NSString* handle = tourLongestBioHandle() ?: tourAuthorHandle() ?: @"X";
             PFBCompatTourLog(@"[tour] other profile: @%@", handle);
             tourOpenLink([@"twitter://user?screen_name=" stringByAppendingString:handle]);
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             BOOL profile = [tourScreenName(after) containsString:@"Profile"];
             if (profile && !followRead) {
                 followRead = tourCheckFollowButton(after);
             }
             // Folded under the bar, the header shows the post count.
             if (profile && ++profileLooks == 6) {
                 tourAttempt(@"other profile", @"folding the header", ^{
                   UITableView* list = tourFrontList();
                   tourDrag(list, list.bounds.size.height * 0.8);
                 });
             }
             return profile;
           }, nil, ^{
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
        __block BOOL inboxEmpty = NO;
        [steps addObject:tourStep(@"conversation", @"Conversation", root, ^{
                 inbox = nil;
                 inboxEmpty = NO;
                 tourSelectTab((NSInteger)messages);
                 NSUInteger generation = gPFBTourGeneration;
                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), ^{
                                  if (generation == gPFBTourGeneration) {
                                      tourAttempt(@"conversation", @"opening a row", ^{
                                        inbox = tourScreenName(tourScreen());
                                        tourOpenReadConversation();
                                      });
                                  }
                                });
               }, ^BOOL(UIViewController* before, UIViewController* after) {
                 NSString* name = tourScreenName(after);
                 return inboxEmpty || (inbox && ![name isEqualToString:inbox] &&
                                       ([name containsString:@"Conversation"] || [name containsString:@"Chat"]));
               }, ^{
                 // Chat may still be loading its conversations after the first look; still
                 // empty then, the inbox is the screen, with nothing to open.
                 inbox = tourScreenName(tourScreen());
                 tourOpenReadConversation();
                 inboxEmpty = [NSStringFromClass([tourFrontView() class]) containsString:@"EmptyState"];
                 if (inboxEmpty) {
                     PFBCompatTourLog(@"[tour] conversation: Chat shows its empty state, no conversation to open");
                 }
               }, ^{
                 tourPopToRoot();
                 tourSelectTab(0);
               })];
    }
    // Chronological replies switched on for one conversation, whatever the setting says:
    // Home's Tweet with the most replies is opened, read at its top, then three times a
    // little further down, and its replies judged by their IDs.
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
    NSDictionary* darkMode = tourStep(@"dark mode", @"Dark mode", ^{
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
           });
    NSUInteger explore = [pages indexOfObject:@"guide"];
    NSUInteger notifications = [pages indexOfObject:@"ntab"];
    NSInteger exploreTab = explore == NSNotFound ? NSNotFound : (NSInteger)explore;
    NSInteger notificationsTab = notifications == NSNotFound ? NSNotFound : (NSInteger)notifications;
    [steps addObject:probe ? tourProbeDarkModeStep(darkMode, exploreTab, notificationsTab) : darkMode];
    [steps addObject:tourStep(@"web link", @"Web link", home, ^{
             tourOpenWebLink();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourFindController(tourRootController().presentedViewController, @"SFSafariViewController") != nil;
           }, nil, ^{
             tourDismissPresented();
           })];
    NSDictionary* pfbSettings = tourStep(@"PFB settings", @"PrimeFreeBird settings", root, ^{
             tourShowSettings();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourFindController(tourRootController().presentedViewController,
                                       @"PFBModernSettingsPageViewController") != nil;
           }, nil, ^{
             tourDismissPresented();
           });
    [steps addObject:probe ? tourProbePFBSettingsStep(pfbSettings) : pfbSettings];
    if (probe) {
        [steps addObjectsFromArray:tourProbeSteps(exploreTab, notificationsTab)];
    }
    return steps;
}

// The steps a tour takes: all, or those whose screen still owes a proof on this build.
// A step that closed Twitter is left out until a new build. The probe passages join a
// full tour while the debugger records.
static NSArray<NSDictionary*>* tourSteps(BOOL full) {
    NSArray<NSDictionary*>* steps = tourAllSteps(full && PFBDebugIsRecording());
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
    tourProbeKeyWindow(@"end", @"at the tour's end");
    PFBProbeMark(@"02#F022 tour end");
    tourRestoreOptions(@"at the end of the tour");
    PFBCompatTourRecord(full, stop, results);
    tourJournalWrite([@"end: " stringByAppendingString:stop ?: @"completed"]);
    tourJournalClose();
    gPFBTourRunning = NO;
    tourHideOverlay();
    PFBDebuggerSetTriggerHidden(NO);
    // Probe: tells the probe readings the tour ended, once its record is written.
    if (PFBDebugIsRecording()) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PFBProbeTourEndedNotification object:nil];
    }
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
    tourAttempt(current[@"name"], @"clean-up", current[@"after"]);
    PFBCompatTourLog(@"[tour] cancelled at %@", current[@"name"]);
    tourConclude(results, full, [@"cancelled at " stringByAppendingString:current[@"name"]]);
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
    title.text = @"Check every path";
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
                                             tourProbeKeyWindow(@"cancel", @"at the tour's Cancel tap");
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

// Whether this run judged the start's own proofs yet: after the regular steps, before
// the probe passages when there are some.
static BOOL gPFBTourLaunchJudged;

// The start's own proofs, judged after the regular steps, so the late ones still count.
static void tourJudgeLaunch(void) {
    if (gPFBTourLaunchJudged) {
        return;
    }
    gPFBTourLaunchJudged = YES;
    NSSet<NSString*>* launch = PFBCompatStationPending(@"launch");
    PFBCompatStationRecord(@"launch", YES, launch);
    if (launch.count) {
        PFBCompatTourLog(@"[tour] launch: missed %@",
                         [[launch.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]);
    }
}

// The start's own proofs are judged last, so the late ones still count; then Home
// comes back to front and the report opens.
static void tourFinish(NSMutableArray<NSString*>* results, BOOL full) {
    tourAttempt(@"finish", @"return to Home", ^{
      tourHomeFront();
    });
    tourJudgeLaunch();
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
    NSArray<NSString*>* missed = [pending.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSString* outcome = !reached ? @"not reached"
                                 : (missed.count ? [NSString stringWithFormat:@"missed %lu", (unsigned long)missed.count]
                                                 : @"ok");
    [results addObject:[NSString stringWithFormat:@"%@ %@", name, outcome]];
    PFBCompatStationRecord(name, reached, pending);
    PFBCompatTourLog(@"[tour] %@: %@ \u00b7 %@%@", name, outcome, detail,
                     reached && missed.count ? [@" \u00b7 missed: " stringByAppendingString:[missed componentsJoinedByString:@", "]]
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
        PFBCompatTourLog(@"[tour] %@: nothing shown after %.1f s, trying the second way in", name, elapsed);
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
    // A probe passage ends its step once it gives up, and holds the step while it runs: the
    // step then keeps the outcome of the moment it was done.
    BOOL (^over)(void) = step[@"over"];
    BOOL (^busy)(void) = step[@"busy"];
    NSMutableDictionary* held = step[@"held"];
    done = done || (over && over());
    if (done && busy && busy() && elapsed < kPFBTourHoldLimit) {
        if (held && !held[@"pending"]) {
            held[@"reached"] = @(reached);
            held[@"pending"] = pending;
            held[@"detail"] = [NSString stringWithFormat:@"%@ -> %@ in %.1f s", tourScreenName(before), tourScreenName(after),
                                                         elapsed];
        }
        done = NO;
    }
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
    if (held[@"pending"]) {
        tourConcludeStep(steps, index, results, full, [held[@"reached"] boolValue], held[@"pending"],
                         [held[@"detail"] stringByAppendingFormat:@", held %.1f s for a probe passage", elapsed]);
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
    if ([step[@"probe"] boolValue]) {
        tourJudgeLaunch();
    }
    gPFBTourStepLive = name;
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
        PFBDebugLog(@"[tour] nothing left to prove on this build");
        return;
    }
    gPFBTourRunning = YES;
    gPFBTourLaunchJudged = NO;
    NSUInteger generation = ++gPFBTourGeneration;
    PFBDebuggerSetTriggerHidden(YES);
    tourJournalClose();
    [[NSFileManager defaultManager] removeItemAtPath:tourJournalPath() error:nil];
    tourJournalWrite([NSString stringWithFormat:@"start: %@ \u00b7 %lu steps \u00b7 build %@", full ? @"full" : @"what is left",
                                                (unsigned long)steps.count, PFBCompatBuildID()]);
    for (NSDictionary* step in tourAllSteps(full && PFBDebugIsRecording())) {
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

// The screens a tour would show: all of them, or those with proofs still owed on this build.
NSUInteger PFBCompatTourScreens(BOOL full) {
    return tourSteps(full).count;
}

// MARK: - At launch

void PFBCompatScheduleTourAtLaunch(void) {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPFBTourPendingKey];
}

// On a new Twitter binary, once per launch until a full tour has run on it.
static void tourAskAtLaunch(void) {
    UIViewController* top = tourTopController();
    if (gPFBTourRunning || !top) {
        return;
    }
    NSString* version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    NSUInteger screens = tourSteps(YES).count;
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Twitter %@ installed", version]
                         message:[NSString stringWithFormat:@"Check every option on this version. The tour opens "
                                                            @"%lu screens on its own, %@. Cancel stops it at "
                                                            @"any time.",
                                                            (unsigned long)screens, tourDuration(screens)]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction* now = [UIAlertAction actionWithTitle:@"Check now"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction* action) {
                                                  PFBCompatRunTour();
                                                }];
    [alert addAction:now];
    alert.preferredAction = now;
    [top presentViewController:alert animated:YES completion:nil];
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
// asked for before quitting runs, or a new Twitter binary asks whether to check it. The
// options a step had switched are put back first, before Twitter reads them.
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
                  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPFBTourLaunchDelay * NSEC_PER_SEC)),
                                 dispatch_get_main_queue(), ^{
                                   if (scheduled) {
                                       PFBCompatRunTour();
                                   } else if (PFBCompatCheckIsDue()) {
                                       tourAskAtLaunch();
                                   }
                                 });
                }];
}
