// Launch-time hooks: the padlock, the classic launch animation and the Liquid Glass opt-in.

#import <LocalAuthentication/LocalAuthentication.h>
#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import "Support/TwitterChirpFont.h"

// MARK: - Padlock helpers

static void askToUnlock(void);

static UIWindow* activeKeyWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene* ws = (UIWindowScene*)scene;
            for (UIWindow* w in ws.windows) {
                if (w.isKeyWindow)
                    return w;
            }
            for (UIWindow* w in ws.windows) {
                if (!w.hidden)
                    return w;
            }
        }
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow)
            return w;
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (!w.hidden)
            return w;
    }
    return nil;
}

// The padlock's own window, above the app with its sheets, the debugger and FLEX, so
// nothing the app presents while locked shows over it. Rebuilt only for another scene.
static UIWindow* gPadlockWindow = nil;

static UIWindow* padlockWindowForScene(UIWindowScene* scene) {
    if (gPadlockWindow.windowScene == scene) {
        return gPadlockWindow;
    }
    UIWindow* window = [[UIWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert + 1000;
    window.rootViewController = [UIViewController new];
    UIView* root = window.rootViewController.view;

    // A tap anywhere on the cover asks again.
    UIControl* overlay = [[UIControl alloc] initWithFrame:root.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.systemBackgroundColor;
    [overlay addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
                 askToUnlock();
             }]
        forControlEvents:UIControlEventTouchUpInside];

    UIImageView* icon = [[UIImageView alloc]
        initWithImage:PFBTwitterGlyphFor(@"lock_stroke", [UIImage systemImageNamed:@"lock.fill"])];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        [[PFBBundle sharedBundle] localizedStringForKey:@"PADLOCK_LOCKED_LABEL"];
    label.textColor = UIColor.labelColor;
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:22]);
    label.textAlignment = NSTextAlignmentCenter;

    [overlay addSubview:icon];
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor
                                           constant:-20],
        [label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor
                                        constant:8]
    ]];

    [root addSubview:overlay];
    gPadlockWindow = window;
    return window;
}

// The cover over the app while it is locked.
static void showPadlockOverlay(void) {
    UIWindowScene* scene = activeKeyWindow().windowScene;
    if (!scene) {
        return;
    }
    UIWindow* window = padlockWindowForScene(scene);
    window.hidden = NO;
    [window makeKeyWindow];
}

// Hides the cover and gives the key window back to the app's own.
static void removePadlockOverlay(void) {
    if (!gPadlockWindow || gPadlockWindow.hidden) {
        return;
    }
    gPadlockWindow.hidden = YES;
    for (UIWindow* window in gPadlockWindow.windowScene.windows) {
        if (window != gPadlockWindow && !window.hidden && window.windowLevel == UIWindowLevelNormal) {
            [window makeKeyWindow];
            return;
        }
    }
}

// Deliberately in-memory only: the padlock must always re-prompt after a
// relaunch, so persisting this would only risk skipping it.
static BOOL padlockAuthenticated = NO;

// iOS's prompt can make the app inactive, then active again. While it is up, and for the
// activation it leaves behind, the padlock does not ask a second time.
static BOOL padlockAsking = NO;
static BOOL padlockSkipActivation = NO;

static BOOL isAuthenticated(void) {
    return padlockAuthenticated;
}

static void setAuthenticated(BOOL yes) {
    padlockAuthenticated = yes;
}

// Face ID, Touch ID or the device passcode, whichever iOS offers. With no passcode set
// there is nothing to ask, so the app opens rather than stay locked for good.
static void askToUnlock(void) {
    if (isAuthenticated() || padlockAsking) {
        return;
    }
    LAContext* context = [[LAContext alloc] init];
    NSError* unavailable = nil;
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&unavailable]) {
        PFBDebugLog(@"[padlock] nothing to ask, the app opens: %@", unavailable.localizedDescription);
        PFBCOMPAT_OBSERVE(PFBCompat_padlock, @"no passcode to ask for");
        setAuthenticated(YES);
        removePadlockOverlay();
        return;
    }
    padlockAsking = YES;
    PFBCOMPAT_ACTION(PFBCompat_padlock, @"unlock asked");
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:[[PFBBundle sharedBundle] localizedStringForKey:@"PADLOCK_REASON"]
                      reply:^(BOOL success, NSError* error) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                              padlockAsking = NO;
                              setAuthenticated(success);
                              if (success) {
                                  removePadlockOverlay();
                                  return;
                              }
                              // Turned down while the prompt still holds the app inactive: the
                              // activation that follows is the prompt's own.
                              padlockSkipActivation =
                                  UIApplication.sharedApplication.applicationState == UIApplicationStateInactive &&
                                  (error.code == LAErrorUserCancel || error.code == LAErrorAuthenticationFailed ||
                                   error.code == LAErrorUserFallback);
                          });
                      }];
}

// Measurement: which of the app's ways of announcing a departure actually arrive, the
// delegate call, the application notification and the scene notification.
static void pfbProbeLeavingSignals(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
      [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
                      usingBlock:^(__unused NSNotification* note) {
                        PFB_PROBE(@"leaving the app", 4, @"application notification arrived");
                      }];
      [center addObserverForName:UISceneWillDeactivateNotification object:nil queue:nil
                      usingBlock:^(__unused NSNotification* note) {
                        PFB_PROBE(@"leaving the app", 4, @"scene notification arrived");
                      }];
    });
}

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [PFBManager cleanCache];
    if ([PFBSettings boolForKey:@"flex_twitter"] && %c(FLEXManager)) {
        [[%c(FLEXManager) sharedManager] showExplorer];
        PFBCOMPAT_ACTION(PFBCompat_flex_twitter, @"explorer shown at launch");
    } else if (%c(FLEXManager)) {
        PFBCOMPAT_OBSERVE(PFBCompat_flex_twitter, @"explorer available");
    }
    // The debugger places its floating button only when debug_tools is on.
    PFBDebuggerInstall();
    pfbProbeLeavingSignals();

    dispatch_async(dispatch_get_main_queue(), ^{
        PFBApplySelectedThemeColor();
    });

    return orig;
}

- (void)applicationDidBecomeActive:(__unsafe_unretained id)arg1 {
    %orig;

    PFBInstallPasteboardObserver();

    PFBApplySelectedThemeColor();
    PFBPrewarmWebCookiesIfNeeded();

    if (![PFBSettings boolForKey:@"padlock"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_padlock, @"app activation seen");
    }
    if ([PFBSettings boolForKey:@"padlock"]) {
        if (isAuthenticated()) {
            removePadlockOverlay();
        } else if (padlockAsking || padlockSkipActivation) {
            padlockSkipActivation = NO;
            showPadlockOverlay();
        } else {
            showPadlockOverlay();
            dispatch_async(dispatch_get_main_queue(), ^{
                askToUnlock();
            });
        }
    } else {
        removePadlockOverlay();
    }
}

- (void)applicationWillResignActive:(__unsafe_unretained id)arg1 {
    %orig;
    PFBCompatReach(PFBCompatPath_leaving_app);
    PFB_PROBE(@"leaving the app", 4, @"app delegate called");

    if ([PFBSettings boolForKey:@"padlock"]) {
        // Cover the UI (and the app-switcher snapshot) and mark unauthenticated so
        // the next activation prompts again; the overlay persists into background.
        showPadlockOverlay();
        setAuthenticated(NO);
        PFBCOMPAT_ACTION(PFBCompat_padlock, @"screen covered on leaving");
    }

    if ([PFBSettings boolForKey:@"flex_twitter"] && %c(FLEXManager)) {
        [[%c(FLEXManager) sharedManager] showExplorer];
        PFBCOMPAT_ACTION(PFBCompat_flex_twitter, @"explorer shown on leaving");
    }
}

%end

// MARK: - Restore Launch Animation

// The launch animation reveals the app through a growing X-shaped mask
// (revealMaskLayer / holePathInView); detach it so the logo zoom is kept but
// the splash simply fades out.

static void stripLaunchRevealMask(UIView* view) {
    // The X-shaped hole lives on the container subview's layer.mask; the top
    // view itself is unmasked, but clear it too for safety.
    view.layer.mask = nil;
    for (UIView* sub in view.subviews) {
        sub.layer.mask = nil;
    }
}

// Keep the animated splash consistent with the static launch screen (white
// bird on Twitter-blue) instead of the stock second phase: tint every logo
// image view white and paint the backdrop Twitter blue.
static void applySplashBrandColors(UIView* view) {
    UIColor* twitterBlue = [UIColor colorWithRed:0x1D / 255.0
                                           green:0xA1 / 255.0
                                            blue:0xF2 / 255.0
                                           alpha:1.0];
    view.backgroundColor = twitterBlue;
    // On the very first render the backdrop comes from bare CALayers and from
    // subviews carrying no background color, which a view-only repaint never
    // reaches. The layer tree and every non-image subview are painted too.
    view.layer.backgroundColor = twitterBlue.CGColor;
    for (CALayer* layer in view.layer.sublayers) {
        layer.backgroundColor = twitterBlue.CGColor;
    }
    PFBEnumerateSubviewsRecursively(view, ^(UIView* sub) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)sub;
            if (imageView.image &&
                imageView.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                imageView.image =
                    [imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }
            imageView.tintColor = [UIColor whiteColor];
        } else {
            sub.backgroundColor = twitterBlue;
            sub.layer.backgroundColor = twitterBlue.CGColor;
        }
    });
}

// Replaces Twitter's launch "xLogo" with the bundled white bird.
%hook UIImage

+ (UIImage*)imageNamed:(NSString*)name {
    if ([name isEqualToString:@"xLogo"]) {
        UIImage* bird = PFBBundlePDFImage(@"LaunchTwitterBird.pdf", CGSizeMake(180, 180), 1.0);
        if (bird) {
            PFBCOMPAT_ACTION(PFBCompat_launch_screen, @"bird shown");
            return bird;
        }
    }
    return %orig;
}

%end

// The splash is torn down before the timeline has drawn, and a window with no
// background color is black. Painting the window fills that gap, and fading the
// splash out rather than cutting hides the seam.

static BOOL gPFBSplashRevealing = NO;

static void paintWindowForSplash(UIView* view) {
    UIColor* twitterBlue = [UIColor colorWithRed:0x1D / 255.0
                                           green:0xA1 / 255.0
                                            blue:0xF2 / 255.0
                                           alpha:1.0];
    UIWindow* window = view.window;
    if (!window) {
        return;
    }
    window.backgroundColor = twitterBlue;
    // Cleared after a fixed 2 s, so nothing else inherits it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       window.backgroundColor = nil;
                   });
}

%hook T1AnimatedLaunchScreenView

- (void)layoutSubviews {
    %orig;
    // layoutSubviews re-installs the mask each pass, so re-strip after %orig.
    stripLaunchRevealMask((UIView*)self);
    // Repainting during the fade would fight the animation, so it stops once
    // the reveal has begun.
    if (!gPFBSplashRevealing) {
        applySplashBrandColors((UIView*)self);
    }
}

- (void)animateRevealWithCompletion:(id)completion {
    // Strip only the X mask, then let the native zoom animation run.
    // The bundled bird is sized for this slot, so the zoom leaves it undistorted.
    stripLaunchRevealMask((UIView*)self);
    PFBCOMPAT_ACTION(PFBCompat_launch_screen, @"X reveal mask stripped");
    gPFBSplashRevealing = YES;
    paintWindowForSplash((UIView*)self);

    // Dissolve instead of cutting: the splash thins out over the blue window
    // while the timeline takes over underneath.
    UIView* splash = (UIView*)self;
    [UIView animateWithDuration:0.5
                     animations:^{
                         for (UIView* sub in splash.subviews) {
                             sub.backgroundColor = [UIColor clearColor];
                         }
                     }];

    %orig(completion);
}

%end

// MARK: - Liquid Glass

// The iOS 26 design follows enable_liquid_glass through UIDesignRequiresCompatibility:
// Twitter's own switch for it is reset at every launch and always answers NO.
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString*)key {
    if ([key isEqualToString:@"UIDesignRequiresCompatibility"] &&
        self == [NSBundle mainBundle]) {
        BOOL glassEnabled =
            [[NSUserDefaults standardUserDefaults] boolForKey:@"enable_liquid_glass"];
        // Read at launch from inside NSBundle: counted without loading the store.
        if (glassEnabled) {
            PFBCompatCount(PFBCompat_enable_liquid_glass);
        } else {
            PFBCOMPAT_OBSERVE(PFBCompat_enable_liquid_glass, @"system design asked");
        }
        return @(!glassEnabled);
    }
    return %orig;
}
%end

void PFBAppLifecycleStart(void) {
    // enable_liquid_glass is read straight from NSUserDefaults, here and in the
    // NSBundle hook, so its YES default is seeded when the key is absent.
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"enable_liquid_glass"] == nil) {
        [defaults setBool:YES forKey:@"enable_liquid_glass"];
    }
    BOOL glassEnabled = [defaults boolForKey:@"enable_liquid_glass"];
    [defaults setBool:glassEnabled forKey:@"com.apple.SwiftUI.IgnoreSolariumOptOut"];
}
