// What changes when Twitter comes back to the front: how it was launched, whether iOS gave it a
// new scene, window or first screen, the side menu's panels, the Tweet button and whether its
// feather is in place. Each line names its moment and is kept across launches.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBReturnTopic = @"app return";
static const NSUInteger kPFBReturnLines = 30;

static NSString* gPFBMoment = @"at launch";
static BOOL gPFBWasAway;
static BOOL gPFBWasInFront;
static __weak UIScene* gPFBLastScene;
static __weak UIWindow* gPFBLastWindow;
static __weak UIViewController* gPFBLastRoot;
static NSHashTable* gPFBDashControllers;

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

// MARK: - Coming to the front

static void PFBReturnInFront(void) {
    UIWindowScene* scene = PFBFrontScene();
    UIWindow* window = PFBFrontWindow(scene);
    UIViewController* root = window.rootViewController;
    if (gPFBWasAway) {
        gPFBMoment = [NSString stringWithFormat:@"after a return (scene %@, window %@, first screen %@)",
                                                PFBSameOrNew(scene, gPFBLastScene), PFBSameOrNew(window, gPFBLastWindow),
                                                PFBSameOrNew(root, gPFBLastRoot)];
    } else if (!gPFBWasInFront) {
        gPFBMoment = [gPFBMoment stringByAppendingString:@", first time in front"];
    }
    gPFBWasAway = NO;
    gPFBWasInFront = YES;
    gPFBLastScene = scene;
    gPFBLastWindow = window;
    gPFBLastRoot = root;
    PFBReturnNote([NSString stringWithFormat:@"in front, first screen %@", root ? PFBReadableClassName(root) : @"none"]);
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

// MARK: - Side menu

// The panels the side menu holds as the tab bar's: a row is left out for each of them. The
// field is read the way key-value coding reads it, and its type is named when that fails.
static NSString* PFBDashPanels(id controller) {
    Ivar ivar = class_getInstanceVariable(object_getClass(controller), "visiblePanelIDs");
    const char* type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    NSString* field = [NSString stringWithFormat:@"field %@, type \"%s\"", ivar ? @"found" : @"not found", type ?: ""];
    id panels = nil;
    @try {
        panels = [controller valueForKey:@"visiblePanelIDs"];
    } @catch (__unused id exception) {
        return [@"unread, " stringByAppendingString:field];
    }
    NSMutableArray* list = nil;
    if ([panels isKindOfClass:[NSArray class]]) {
        list = [panels mutableCopy];
    } else if ([panels isKindOfClass:[NSSet class]]) {
        list = [[(NSSet*)panels allObjects] mutableCopy];
    } else if ([panels isKindOfClass:[NSOrderedSet class]]) {
        list = [[(NSOrderedSet*)panels array] mutableCopy];
    } else if ([panels isKindOfClass:[NSIndexSet class]]) {
        list = [NSMutableArray array];
        [(NSIndexSet*)panels enumerateIndexesUsingBlock:^(NSUInteger index, __unused BOOL* stop) {
          [list addObject:@(index)];
        }];
    }
    if (!list) {
        return [NSString stringWithFormat:@"%@ (%@)", panels ? PFBReadableClassName(panels) : @"none", field];
    }
    [list sortUsingComparator:^NSComparisonResult(id a, id b) {
      return [a isKindOfClass:[NSNumber class]] && [b isKindOfClass:[NSNumber class]]
                 ? [(NSNumber*)a compare:(NSNumber*)b]
                 : NSOrderedSame;
    }];
    return [NSString stringWithFormat:@"[%@]", [list componentsJoinedByString:@", "]];
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

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    %orig;
    [gPFBDashControllers addObject:self];
    PFBReturnNote([@"side menu took the tab bar's panels " stringByAppendingString:PFBDashPanels(self)]);
}

- (void)prepareForReuse {
    %orig;
    [gPFBDashControllers addObject:self];
    PFBReturnNote([@"side menu reset, panels now " stringByAppendingString:PFBDashPanels(self)]);
}

%end

%hook T1DashContentPresenter

- (void)dashDidSettleOpen:(BOOL)open {
    %orig;
    if (!open) {
        return;
    }
    NSMutableArray<NSString*>* held = [NSMutableArray array];
    for (id controller in gPFBDashControllers) {
        Ivar presenter = class_getInstanceVariable(object_getClass(controller), "presenter");
        if (presenter && object_getIvar(controller, presenter) == self) {
            [held addObject:PFBDashPanels(controller)];
        }
    }
    PFBReturnNote([NSString stringWithFormat:@"side menu opened, holding %@",
                                             held.count ? [held componentsJoinedByString:@" / "]
                                                        : @"the panels of a menu not seen updating"]);
}

%end

%ctor {
    %init;
    gPFBDashControllers = [NSHashTable weakObjectsHashTable];
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
                      } @catch (__unused id exception) {
                      }
                    }];
}
