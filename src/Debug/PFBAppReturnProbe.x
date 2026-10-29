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

// The rows the side menu shows, by their VoiceOver labels, top to bottom.
static NSString* PFBAccessibilityText(id element, NSInteger depth) {
    NSString* label = [element accessibilityLabel];
    if (label.length || depth > 3) {
        return label;
    }
    for (id inner in [element accessibilityElements] ?: @[]) {
        NSString* found = PFBAccessibilityText(inner, depth + 1);
        if (found.length) {
            return found;
        }
    }
    if ([element isKindOfClass:[UIView class]]) {
        for (UIView* sub in ((UIView*)element).subviews) {
            NSString* found = PFBAccessibilityText(sub, depth + 1);
            if (found.length) {
                return found;
            }
        }
    }
    return nil;
}

static NSString* PFBDashRows(void) {
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
        return menu ? @"no list found in the menu" : @"no menu found";
    }
    NSArray<UICollectionViewCell*>* cells =
        [list.visibleCells sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell* a, UICollectionViewCell* b) {
          return a.frame.origin.y < b.frame.origin.y ? NSOrderedAscending : NSOrderedDescending;
        }];
    NSMutableArray<NSString*>* rows = [NSMutableArray array];
    for (UICollectionViewCell* cell in cells) {
        if (!cell.hidden) {
            [rows addObject:PFBAccessibilityText(cell, 0) ?: @"?"];
        }
    }
    return [NSString stringWithFormat:@"[%@]", [rows componentsJoinedByString:@", "]];
}

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    %orig;
    PFBReturnNote([@"side menu built: " stringByAppendingString:PFBDashPanelFacts()]);
}

- (void)prepareForReuse {
    %orig;
    PFBReturnNote(@"side menu reset");
}

%end

%hook T1DashContentPresenter

- (void)dashDidSettleOpen:(BOOL)open {
    %orig;
    if (!open) {
        return;
    }
    @try {
        PFBReturnNote([NSString stringWithFormat:@"side menu opened, rows %@ · last answer: %@", PFBDashRows(),
                                                 PFBDashPanelFacts()]);
    } @catch (__unused id exception) {
    }
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
