// Path tour: shows Twitter's own screens one after another so the report proves the
// paths they carry, whatever the toggles say. Each step waits for the proofs its
// screen owes, then notes whether the screen came up and what it still missed.

#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#import <objc/message.h>
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

// Left to the app between a step's clean-up and the next step.
static const NSTimeInterval kPFBTourSettle = 0.4;

// What one step takes on average, as measured on a full tour (24 screens in 1 min 27),
// for the duration the launch alert announces.
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

// What the timeline filter saw first this launch, kept by Timeline.x.
extern NSString* PFBFirstRetweetSummary(void);

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

// MARK: - What the new steps do

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
// entries are built without the menu showing, through the same hooks.
static void tourTableMenuDoor(UIView* video, NSString* pass) {
    UITableView* list = (UITableView*)tourAncestor(video, @"UITableView");
    UITableViewCell* cell = (UITableViewCell*)tourAncestor(video, @"UITableViewCell");
    NSIndexPath* row = cell ? [list indexPathForCell:cell] : nil;
    id<UITableViewDelegate> delegate = list.delegate;
    SEL build = @selector(tableView:contextMenuConfigurationForRowAtIndexPath:point:);
    if (!row || ![delegate respondsToSelector:build]) {
        PFBCompatTourLog(@"[tour] video long press: %@", !row ? @"no row under the video" : @"the list builds no context menu");
        return;
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

// What closing the full-screen player would do with the video, asked while it is on
// screen. Each question is a getter with no side effect.
static void tourAskDocking(void) {
    UIViewController* player = tourFindController(tourRootController(), @"T1ImmersiveFullScreenViewController");
    if (!player) {
        PFBCompatTourLog(@"[tour] video full screen: docking not read, no full-screen player");
        return;
    }
    NSString* (^answer)(id, NSString*) = ^NSString*(id target, NSString* name) {
        SEL selector = NSSelectorFromString(name);
        if (!target || ![target respondsToSelector:selector]) {
            return @"absent";
        }
        return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector) ? @"yes" : @"no";
    };
    Class segment = NSClassFromString(@"T1ImmersiveVideoBottomSegment");
    SEL shared = NSSelectorFromString(@"shared");
    id bottom = [segment respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(segment, shared) : nil;
    PFBCompatTourLog(@"[tour] video full screen: drop zone %@, can dock %@, docks on closing %@, bottom player %@",
                     answer(player, @"isDropToDockEnabled"), answer(player, @"_canDockCurrentVideoToBottomSegment"),
                     answer(player, @"_shouldAutoDockOnDismiss"), answer(bottom, @"isActive"));
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
    if ([text.lowercaseString containsString:@"unread"]) {
        return @"marked unread";
    }
    UIView* dot = tourFindView(cell, ^BOOL(UIView* view) {
      CGSize size = view.bounds.size;
      CGFloat red = 0, green = 0, blue = 0, alpha = 0;
      return !view.hidden && size.width >= 4 && size.width <= 14 && fabs(size.width - size.height) < 1.0 &&
             [view.backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha] && alpha > 0.5 && blue > 0.8 &&
             red < 0.35 && green > 0.45 && green < 0.75;
    });
    return dot ? @"unread dot" : nil;
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
    NSMutableArray<NSString*>* skipped = [NSMutableArray array];
    for (UIView* cell in cells) {
        NSString* unread = tourUnreadMark(cell);
        PFBCompatTourLog(@"[tour] conversation: row %@ %@", NSStringFromClass([cell class]), unread ?: @"reads as read");
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
                           if (drag == drags) {
                               PFBCompatTourLog(@"[tour] %@: %@ scrolled to %.0f", step,
                                                list ? NSStringFromClass([list class]) : @"no list", list.contentOffset.y);
                           }
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
             // The footer carrying the source sits under the Tweet's text and media.
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
    // On the screen the search step leaves open: a search link opened later in the tour,
    // after the composer, goes nowhere (measured twice).
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
             PFBCompatTourLog(@"[tour] scroll: offset %.0f at the end", tourFrontList().contentOffset.y);
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
    [steps addObject:tourStep(@"video long press", @"Video menu", home, ^{
             UIView* pressed = tourHomeViewOfClass(@"T1InlineVideoView");
             tourDescribeChain(@"video long press", pressed, tourAncestor(pressed, @"T1StatusCell") ?: pressed.superview);
             tourTableMenuDoor(pressed, @"first");
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
                                        tourTableMenuDoor(weakPressed, ask == 1 ? @"again" : @"a third time");
                                      });
                                  }
                                });
             }
           }, presented, nil, ^{
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
                   PFBCompatTourLog(@"[tour] other profile: %@ dragged to %.0f",
                                    list ? NSStringFromClass([list class]) : @"no list", list.contentOffset.y);
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
    [steps addObject:tourStep(@"side menu", @"Side menu", home, ^{
             tourOpenSideMenu();
           }, ^BOOL(UIViewController* before, UIViewController* after) {
             return tourBoolGetter(tourSideMenuOwner(), @"isDashOpen");
           }, nil, ^{
             tourCloseSideMenu();
           })];
    __block UIUserInterfaceStyle styleBefore = UIUserInterfaceStyleUnspecified;
    [steps addObject:tourStep(@"dark mode", @"Dark mode", home, ^{
             UIWindow* window = tourWindow();
             styleBefore = window.overrideUserInterfaceStyle;
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

// The steps a tour takes: all, or those whose screen still owes a proof on this build.
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
    tourAttempt(current[@"name"], @"clean-up", current[@"after"]);
    PFBCompatTourLog(@"[tour] cancelled at %@", current[@"name"]);
    tourConclude(results, full, [@"cancelled at " stringByAppendingString:current[@"name"]]);
}

// A box over the app while the tour runs, in its own window: it says what is
// happening, and its Cancel button is the one thing that takes a touch.
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
        PFBCompatTourLog(@"[tour] launch: missed %@",
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

// One look at a step: done once its screen shows and it owes nothing, or when time is
// up. Shown means the check passed or an owed proof arrived; a second way in, tried at
// doorAt (negative until then), gets its own time.
static void tourWatch(NSArray<NSDictionary*>* steps, NSUInteger index, NSMutableArray<NSString*>* results, BOOL full,
                      UIViewController* before, NSSet<NSString*>* owed, NSDate* start, NSTimeInterval doorAt) {
    NSDictionary* step = steps[index];
    NSString* name = step[@"name"];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    UIViewController* after = tourScreen();
    NSSet<NSString*>* pending = PFBCompatStationPending(name);
    PFBTourCheck check = step[@"check"];
    __block BOOL shown = NO;
    if (!tourAttempt(name, @"check", ^{
          shown = check(before, after);
        })) {
        tourConcludeStep(steps, index, results, full, NO, nil, @"stopped by an exception");
        return;
    }
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
    BOOL done = elapsed >= limit || (owes && reached && pending.count == 0);
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
// asked for before quitting runs, or a new Twitter binary asks whether to check it.
void PFBCompatTourResumeAtLaunch(void) {
    __block id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification* note) {
                  [[NSNotificationCenter defaultCenter] removeObserver:observer];
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
