// What changes when Twitter comes back to the front, from the background or from an inactive
// spell (the app switcher): how it was launched, whether iOS gave it a new scene, window or first
// screen, the Tweet button and its feather, and the side menu: every read of its list, the ways
// it opens and how it shows. Each line names its moment and is kept across launches.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBReturnTopic = @"app return";
static const NSUInteger kPFBReturnLines = 30;

static NSString* gPFBMoment = @"at launch";
static BOOL gPFBWasAway;
static BOOL gPFBWasInactive;
static BOOL gPFBWasInFront;
static __weak UIScene* gPFBLastScene;
static __weak UIWindow* gPFBLastWindow;
static __weak UIViewController* gPFBLastRoot;
static CFTimeInterval gPFBReturnAt;
static BOOL gPFBDashOpen;
static BOOL gPFBDashOpenWhenAway;
static __weak UIViewController* gPFBSplit;

static void PFBReturnNote(NSString* fact) {
    PFBCompatMeasure(kPFBReturnTopic, [NSString stringWithFormat:@"%@: %@", gPFBMoment, fact], kPFBReturnLines);
}

static UIWindowScene* PFBFrontScene(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)scene;
        }
    }
    return nil;
}

static UIWindow* PFBFrontWindow(UIWindowScene* scene) {
    UIWindow* fallback = nil;
    for (UIWindow* window in scene.windows) {
        if (window.isKeyWindow) {
            return window;
        }
        if (!fallback && window.rootViewController && !window.hidden) {
            fallback = window;
        }
    }
    return fallback;
}

static NSString* PFBSameOrNew(id now, id before) {
    if (!now) {
        return @"none";
    }
    return now == before ? @"same" : @"new";
}

// MARK: - Tweet button

static void PFBReturnTweetButton(NSString* when) {
    UIWindow* window = PFBFrontWindow(PFBFrontScene());
    if (!window) {
        PFBReturnNote([when stringByAppendingString:@", Tweet button: no window in front"]);
        return;
    }
    Class host = NSClassFromString(@"_TtC11XNavigation23TabBarAccessoryHostView");
    Class classic = NSClassFromString(@"TFNFloatingActionButton");
    NSMutableArray<NSString*>* accessories = [NSMutableArray array];
    __block NSUInteger classics = 0;
    PFBWalkAllSubviews(window, 40, ^(UIView* view) {
      if (host && [view isKindOfClass:host]) {
          CGRect frame = [view convertRect:view.bounds toView:nil];
          [accessories addObject:[NSString stringWithFormat:@"%.0fx%.0f at %.0f,%.0f shown %.2f, %@",
                                                             frame.size.width, frame.size.height, frame.origin.x,
                                                             frame.origin.y, PFBShownOpacity(view),
                                                             PFBGlassAccessoryFacts(view)]];
      } else if (classic && [view isKindOfClass:classic] && PFBShownOpacity(view) > 0.05) {
          classics++;
      }
    });
    PFBReturnNote([NSString stringWithFormat:@"%@, Tweet button: %lu glass accessor%@ [%@], classic button shown %lu",
                                             when, (unsigned long)accessories.count,
                                             accessories.count == 1 ? @"y" : @"ies",
                                             [accessories componentsJoinedByString:@"; "], (unsigned long)classics]);
}

static void PFBSideMenuState(NSString* when);
static BOOL PFBDashIsOpen(void);

// MARK: - Coming to the front

static void PFBReturnInFront(void) {
    UIWindowScene* scene = PFBFrontScene();
    UIWindow* window = PFBFrontWindow(scene);
    UIViewController* root = window.rootViewController;
    if (gPFBWasAway) {
        gPFBMoment = [NSString stringWithFormat:@"after a return (scene %@, window %@, first screen %@)",
                                                PFBSameOrNew(scene, gPFBLastScene), PFBSameOrNew(window, gPFBLastWindow),
                                                PFBSameOrNew(root, gPFBLastRoot)];
    } else if (gPFBWasInactive && gPFBWasInFront) {
        gPFBMoment = @"after an inactive spell (app switcher or a system panel)";
    } else if (!gPFBWasInFront) {
        gPFBMoment = [gPFBMoment stringByAppendingString:@", first time in front"];
    }
    gPFBWasAway = NO;
    gPFBWasInactive = NO;
    gPFBWasInFront = YES;
    gPFBLastScene = scene;
    gPFBLastWindow = window;
    gPFBLastRoot = root;
    PFBReturnNote([NSString stringWithFormat:@"in front, first screen %@", root ? PFBReadableClassName(root) : @"none"]);
    if (gPFBDashOpenWhenAway || PFBDashIsOpen()) {
        PFBSideMenuState(@"0.5 s later");
        for (NSNumber* delay in @[ @2.0, @5.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay.doubleValue - 0.5) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                             @try {
                                 PFBSideMenuState([NSString stringWithFormat:@"%.0f s later", delay.doubleValue]);
                             } @catch (__unused id exception) {
                             }
                           });
        }
    }
    for (NSNumber* delay in @[ @1.5, @5.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         @try {
                             PFBReturnTweetButton([NSString stringWithFormat:@"%.1f s later", delay.doubleValue]);
                         } @catch (__unused id exception) {
                         }
                       });
    }
}

// MARK: - Feather on the compose button

static const void* kPFBComposeCheckedAtKey = &kPFBComposeCheckedAtKey;

// The compose button's glass and images, with where each image sits and what it shows.
static NSString* PFBComposeStructure(UIView* host) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    PFBWalkAllSubviews(host, 10, ^(UIView* view) {
      CGRect frame = [view convertRect:view.bounds toView:host];
      NSString* place = [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", frame.origin.x, frame.origin.y,
                                                   frame.size.width, frame.size.height];
      if ([view isKindOfClass:[UIVisualEffectView class]]) {
          [parts addObject:[NSString stringWithFormat:@"glass %@ %@", PFBReadableClassName(view), place]];
      } else if ([view isKindOfClass:[UIImageView class]] && ((UIImageView*)view).image) {
          BOOL inGlass = NO;
          for (UIView* node = view.superview; node && node != host; node = node.superview) {
              inGlass = inGlass || [node isKindOfClass:[UIVisualEffectView class]];
          }
          UIImage* image = ((UIImageView*)view).image;
          [parts addObject:[NSString stringWithFormat:@"image %@ %.0fx%.0f, %@, ink %@, %@, %@", place,
                                                      image.size.width, image.size.height,
                                                      PFBGlassIsFeather(image) ? @"the feather" : @"not the feather",
                                                      PFBImageInk(image) ?: @"none",
                                                      inGlass ? @"in the glass" : @"outside the glass",
                                                      view.hidden || PFBShownOpacity(view) < 0.05 ? @"not shown" : @"shown"]];
      }
    });
    return [parts componentsJoinedByString:@" | "];
}

// Checked once a second at most, after the button's own layout and PrimeFreeBird's restyle.
static void PFBComposeCheck(UIView* host) {
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber* last = objc_getAssociatedObject(host, kPFBComposeCheckedAtKey);
    if (last && now - last.doubleValue < 1.0) {
        return;
    }
    objc_setAssociatedObject(host, kPFBComposeCheckedAtKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView* weakHost = host;
    dispatch_async(dispatch_get_main_queue(), ^{
      UIView* button = weakHost;
      if (!button) {
          return;
      }
      @try {
          NSString* miss = PFBGlassComposeMiss(button);
          static BOOL referenceNoted;
          if (miss) {
              PFBCompatMeasure(@"compose feather",
                               [NSString stringWithFormat:@"%@: MISSING, %@ · %@", gPFBMoment, miss,
                                                          PFBComposeStructure(button)],
                               12);
          } else if (!referenceNoted && button.window && [PFBSettings boolForKey:@"restore_tweet_button"] &&
                     [PFBGlassAccessoryFacts(button) hasPrefix:@"compose yes"]) {
              referenceNoted = YES;
              PFBCompatMeasure(@"compose feather",
                               [NSString stringWithFormat:@"%@: in place · %@", gPFBMoment, PFBComposeStructure(button)],
                               12);
          }
      } @catch (__unused id exception) {
      }
    });
}

%hook _TtC11XNavigation23TabBarAccessoryHostView

- (void)layoutSubviews {
    %orig;
    PFBComposeCheck((UIView*)self);
}

%end

// MARK: - Side menu

static NSString* const kPFBSideMenuTopic = @"side menu";
static const NSUInteger kPFBSideMenuLines = 60;

static void PFBSideMenuNote(NSString* fact) {
    PFBCompatMeasure(kPFBSideMenuTopic,
                     [NSString stringWithFormat:@"%@%@: %@", gPFBMoment,
                                                gPFBDashOpenWhenAway ? @", side menu open when the app left" : @"", fact],
                     kPFBSideMenuLines);
}

static UIViewController* PFBFindSplit(UIViewController* controller, NSInteger depth) {
    Class split = NSClassFromString(@"T1AppSplitViewController");
    if (!controller || !split || depth > 5) {
        return nil;
    }
    if ([controller isKindOfClass:split]) {
        return controller;
    }
    for (UIViewController* child in controller.childViewControllers) {
        UIViewController* found = PFBFindSplit(child, depth + 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

// Open as the split screen that hosts the menu says, or as the last settle notice said.
static BOOL PFBDashIsOpen(void) {
    if (!gPFBSplit) {
        gPFBSplit = PFBFindSplit(PFBFrontWindow(PFBFrontScene()).rootViewController, 0);
    }
    UIViewController* split = gPFBSplit;
    SEL open = NSSelectorFromString(@"isDashOpen");
    return split && [split respondsToSelector:open] ? ((BOOL (*)(id, SEL))objc_msgSend)(split, open) : gPFBDashOpen;
}

static NSString* PFBDashOpenText(void) {
    return PFBDashIsOpen() ? @"menu open" : @"menu closed";
}

// "T1Twitter+0x12a748": the first caller outside PrimeFreeBird, past the hooks stacked on the
// method, read from the frame records arm64 keeps.
static NSString* PFBSideMenuCaller(const void* frameAddress) {
    static const void* ours;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      Dl_info info;
      ours = dladdr((const void*)&PFBSideMenuCaller, &info) ? info.dli_fbase : NULL;
    });
    const void* const* frame = (const void* const*)frameAddress;
    for (NSInteger hop = 0; frame && hop < 6; hop++) {
        Dl_info info;
        if (!frame[1] || !dladdr(frame[1], &info) || !info.dli_fbase) {
            return @"?";
        }
        if (info.dli_fbase != ours) {
            const char* slash = info.dli_fname ? strrchr(info.dli_fname, '/') : NULL;
            return [NSString stringWithFormat:@"%s+0x%lx", slash ? slash + 1 : (info.dli_fname ?: "?"),
                                              (unsigned long)((uintptr_t)frame[1] - (uintptr_t)info.dli_fbase)];
        }
        frame = (const void* const*)frame[0];
    }
    return @"PrimeFreeBird";
}

static NSString* PFBPanelsText(NSArray* panels) {
    return [panels isKindOfClass:[NSArray class]] ? [panels componentsJoinedByString:@", "] : @"none";
}

// A read of the tab panels, each caller and answer noted once per moment and menu state.
static void PFBPanelsRead(NSString* reader, const void* frameAddress, NSArray* panels) {
    PFBSideMenuNote([NSString stringWithFormat:@"%@ read by %@, [%@], %@, %@", reader, PFBSideMenuCaller(frameAddress),
                                               PFBPanelsText(panels),
                                               PFBDashAnswerApplies(frameAddress) ? @"PrimeFreeBird's answer" : @"Twitter's own",
                                               PFBDashOpenText()]);
}

// The menu as it shows: where it sits, its rows (8 trimmed, 13 standard on this account) and
// the texts shown on screen in it.
static void PFBSideMenuState(NSString* when) {
    UIWindow* window = PFBFrontWindow(PFBFrontScene());
    __block UIView* menu = nil;
    PFBWalkAllSubviews(window, 30, ^(UIView* view) {
      if (!menu && [NSStringFromClass([view class]) containsString:@"DashNavigationView"]) {
          menu = view;
      }
    });
    __block UICollectionView* list = nil;
    PFBWalkAllSubviews(menu, 10, ^(UIView* view) {
      if (!list && [view isKindOfClass:[UICollectionView class]]) {
          list = (UICollectionView*)view;
      }
    });
    if (!list) {
        PFBSideMenuNote([NSString stringWithFormat:@"%@, %@, %@", when, PFBDashOpenText(),
                                                   menu ? @"no list in the menu" : @"no menu in the window"]);
        return;
    }
    NSInteger rows = 0;
    for (NSInteger section = 0; section < list.numberOfSections; section++) {
        rows += [list numberOfItemsInSection:section];
    }
    NSMutableArray<NSString*>* texts = [NSMutableArray array];
    PFBWalkAllSubviews(list, 20, ^(UIView* view) {
      NSString* text = [view isKindOfClass:[UILabel class]] ? ((UILabel*)view).text : nil;
      if (text.length && texts.count < 16 && PFBShownOpacity(view) > 0.05 &&
          CGRectIntersectsRect([view convertRect:view.bounds toView:nil], window.bounds)) {
          [texts addObject:text];
      }
    });
    CGRect frame = [menu convertRect:menu.bounds toView:nil];
    PFBSideMenuNote([NSString stringWithFormat:@"%@, %@, menu at x %.0f shown %.2f, %ld rows, texts on screen [%@]", when,
                                               PFBDashOpenText(), frame.origin.x, PFBShownOpacity(menu), (long)rows,
                                               [texts componentsJoinedByString:@", "]]);
}

@interface _TtC14T1TwitterSwift20XTabbedAppNavigation : NSObject
- (NSArray*)visiblePanelIDs;
- (void)recalculateVisiblePanels;
- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(NSArray*)panelIDs;
@end

@interface T1TabbedAppNavigationViewController (PFBSideMenuProbe)
- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation;
- (void)recalculateVisiblePanels;
- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(NSArray*)panelIDs;
@end

@interface T1DashContentController : NSObject
- (id)initWithAccount:(id)account interactionsTimelineBridge:(id)bridge;
- (void)accountUserDidUpdateWithNotification:(id)notification;
@end

@interface T1AppSplitViewController : UIViewController
- (void)presentDashFromViewController:(UIViewController*)controller animated:(BOOL)animated completion:(id)completion;
- (void)private_presentDashFromViewController:(UIViewController*)controller
                               withPanGesture:(id)gesture
                                     animated:(BOOL)animated
                                   completion:(id)completion;
- (void)private_notifyDashDidSettleOpen:(BOOL)open;
- (void)private_loadDashHostView;
- (void)private_endDashPan:(id)gesture finished:(BOOL)finished completion:(id)completion;
- (void)dismissDashAnimated:(BOOL)animated completion:(id)completion;
- (void)private_dashShowContentViewControllerAnimated:(BOOL)animated completion:(id)completion;
@end

@interface _TtC11TwitterDash21DashHostingController : UIViewController
@end

%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (NSArray*)visiblePanelIDs {
    NSArray* panels = %orig;
    PFBPanelsRead(@"tab panels", __builtin_frame_address(0), panels);
    return panels;
}

- (void)recalculateVisiblePanels {
    PFBSideMenuNote([NSString stringWithFormat:@"glass navigation recalculated by %@, %@",
                                               PFBSideMenuCaller(__builtin_frame_address(0)), PFBDashOpenText()]);
    %orig;
}

- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(NSArray*)panelIDs {
    PFBSideMenuNote([NSString stringWithFormat:@"glass navigation recalculated with [%@] by %@, %@", PFBPanelsText(panelIDs),
                                               PFBSideMenuCaller(__builtin_frame_address(0)), PFBDashOpenText()]);
    %orig;
}

%end

%hook T1TabbedAppNavigationViewController

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    NSArray* panels = %orig;
    PFBPanelsRead(@"classic tab panels", __builtin_frame_address(0), panels);
    return panels;
}

- (void)recalculateVisiblePanels {
    PFBSideMenuNote([NSString stringWithFormat:@"classic navigation recalculated by %@, %@",
                                               PFBSideMenuCaller(__builtin_frame_address(0)), PFBDashOpenText()]);
    %orig;
}

- (void)recalculateVisiblePanelsWithUpdatedPanelIDs:(NSArray*)panelIDs {
    PFBSideMenuNote([NSString stringWithFormat:@"classic navigation recalculated with [%@] by %@, %@",
                                               PFBPanelsText(panelIDs), PFBSideMenuCaller(__builtin_frame_address(0)),
                                               PFBDashOpenText()]);
    %orig;
}

%end

%hook T1DashContentController

- (id)init {
    id controller = %orig;
    PFBSideMenuNote([@"menu content made by " stringByAppendingString:PFBSideMenuCaller(__builtin_frame_address(0))]);
    return controller;
}

- (id)initWithAccount:(id)account interactionsTimelineBridge:(id)bridge {
    id controller = %orig;
    PFBSideMenuNote([@"menu content made with an account by " stringByAppendingString:PFBSideMenuCaller(__builtin_frame_address(0))]);
    return controller;
}

- (void)updateVisiblePanelIDs {
    %orig;
    PFBSideMenuNote([NSString stringWithFormat:@"menu built by %@, %@: %@", PFBSideMenuCaller(__builtin_frame_address(0)),
                                               PFBDashOpenText(), PFBDashPanelFacts()]);
}

- (void)prepareForReuse {
    %orig;
    PFBSideMenuNote([NSString stringWithFormat:@"menu reset by %@, %@", PFBSideMenuCaller(__builtin_frame_address(0)),
                                               PFBDashOpenText()]);
}

- (void)accountUserDidUpdateWithNotification:(id)notification {
    %orig;
    PFBSideMenuNote([@"account update received, " stringByAppendingString:PFBDashOpenText()]);
}

%end

%hook T1AppSplitViewController

- (void)presentDashFromViewController:(UIViewController*)controller animated:(BOOL)animated completion:(id)completion {
    gPFBSplit = (UIViewController*)self;
    PFBSideMenuNote([@"opening asked by " stringByAppendingString:PFBSideMenuCaller(__builtin_frame_address(0))]);
    %orig;
}

- (void)private_presentDashFromViewController:(UIViewController*)controller
                               withPanGesture:(id)gesture
                                     animated:(BOOL)animated
                                   completion:(id)completion {
    gPFBSplit = (UIViewController*)self;
    PFBSideMenuNote([NSString stringWithFormat:@"opening %@ by %@", gesture ? @"by a swipe" : @"without a swipe",
                                               PFBSideMenuCaller(__builtin_frame_address(0))]);
    %orig;
}

- (void)private_endDashPan:(id)gesture finished:(BOOL)finished completion:(id)completion {
    gPFBSplit = (UIViewController*)self;
    %orig;
    PFBSideMenuNote([NSString stringWithFormat:@"swipe ended, %@, %@", finished ? @"finished" : @"not finished",
                                               PFBDashOpenText()]);
}

- (void)private_notifyDashDidSettleOpen:(BOOL)open {
    gPFBSplit = (UIViewController*)self;
    %orig;
    @try {
        PFBSideMenuState([NSString stringWithFormat:@"settled %@ · last answer: %@", open ? @"open" : @"closed",
                                                    PFBDashPanelFacts()]);
    } @catch (__unused id exception) {
    }
}

- (void)private_loadDashHostView {
    gPFBSplit = (UIViewController*)self;
    %orig;
    PFBSideMenuNote(@"menu host loaded");
}

- (void)dismissDashAnimated:(BOOL)animated completion:(id)completion {
    %orig;
    PFBSideMenuNote([@"closing asked by " stringByAppendingString:PFBSideMenuCaller(__builtin_frame_address(0))]);
}

- (void)private_dashShowContentViewControllerAnimated:(BOOL)animated completion:(id)completion {
    %orig;
    PFBSideMenuNote([@"content shown again by " stringByAppendingString:PFBSideMenuCaller(__builtin_frame_address(0))]);
}

%end

%hook _TtC11TwitterDash21DashHostingController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    PFBSideMenuNote([@"menu screen about to appear, " stringByAppendingString:PFBDashOpenText()]);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PFBSideMenuNote([@"menu screen appeared, " stringByAppendingString:PFBDashOpenText()]);
}

%end

%hook T1DashContentPresenter

- (void)dashDidSettleOpen:(BOOL)open {
    %orig;
    gPFBDashOpen = open;
    PFBSideMenuNote([NSString stringWithFormat:@"presenter told the menu settled %@", open ? @"open" : @"closed"]);
}

%end

%ctor {
    %init;
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    NSOperationQueue* main = NSOperationQueue.mainQueue;
    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:main
                    usingBlock:^(__unused NSNotification* note) {
                      BOOL background =
                          UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
                      BOOL prewarmed = [NSProcessInfo.processInfo.environment[@"ActivePrewarm"] isEqualToString:@"1"];
                      gPFBMoment = [NSString stringWithFormat:@"after a launch in the %@%@",
                                                              background ? @"background" : @"foreground",
                                                              prewarmed ? @", prewarmed by iOS" : @""];
                    }];
    [center addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:main
                    usingBlock:^(__unused NSNotification* note) {
                      gPFBWasInactive = YES;
                      gPFBDashOpenWhenAway = PFBDashIsOpen();
                      if (gPFBDashOpenWhenAway) {
                          @try {
                              PFBSideMenuState(@"going inactive");
                          } @catch (__unused id exception) {
                          }
                      }
                    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:main
                    usingBlock:^(__unused NSNotification* note) {
                      gPFBWasAway = YES;
                    }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:main
                    usingBlock:^(__unused NSNotification* note) {
                      CFTimeInterval returnAt = CACurrentMediaTime();
                      gPFBReturnAt = returnAt;
                      // "Open when the app left" holds for the 6 s that follow the return.
                      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                                     dispatch_get_main_queue(), ^{
                                       if (gPFBReturnAt == returnAt) {
                                           gPFBDashOpenWhenAway = NO;
                                       }
                                     });
                      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                                     dispatch_get_main_queue(), ^{
                                       @try {
                                           PFBReturnInFront();
                                       } @catch (__unused id exception) {
                                       }
                                     });
                    }];
    [center addObserverForName:UISceneWillConnectNotification
                        object:nil
                         queue:main
                    usingBlock:^(__unused NSNotification* note) {
                      PFBReturnNote(@"a scene connected");
                    }];
    [center addObserverForName:UISceneDidDisconnectNotification
                        object:nil
                         queue:main
                    usingBlock:^(__unused NSNotification* note) {
                      PFBReturnNote(@"a scene disconnected");
                    }];
    [center addObserverForName:PFBDebuggerWillCaptureNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification* note) {
                      @try {
                          PFBReturnTweetButton(@"at capture");
                          PFBSideMenuState(@"at capture");
                      } @catch (__unused id exception) {
                      }
                    }];
}
