// Launch-time hooks: the padlock, app-delegate lifecycle, the classic launch
// animation and the Liquid Glass declaration.

#import <LocalAuthentication/LocalAuthentication.h>
#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Support/TwitterChirpFont.h"
extern void PFBInstallPasteboardObserver(void);

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
// nothing the app presents while locked shows over it. One per scene, built once.
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
        setAuthenticated(YES);
        removePadlockOverlay();
        return;
    }
    padlockAsking = YES;
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

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [PFBManager cleanCache];
    if ([PFBSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
        PFBCOMPAT_ACTION(PFBCompat_flex_twitter, @"explorer shown at launch");
    } else if (%c(FLEXManager)) {
        PFBCOMPAT_OBSERVE(PFBCompat_flex_twitter, @"explorer available");
    }
    // The debugger places its floating button only when debug_tools is on.
    PFBDebuggerInstall();

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
            PFBCOMPAT_ACTION(PFBCompat_padlock, @"unlock asked");
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

    if ([PFBSettings boolForKey:@"padlock"]) {
        // Cover the UI (and the app-switcher snapshot) and mark unauthenticated so
        // the next activation prompts again; the overlay persists into background.
        showPadlockOverlay();
        setAuthenticated(NO);
        PFBCOMPAT_ACTION(PFBCompat_padlock, @"screen covered on leaving");
    }

    if ([PFBSettings boolForKey:@"flex_twitter"]) {
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

// Renders the bundled white bird from its PDF (same technique as the settings bird).
static UIImage* launchBirdImage(CGFloat side) {
    NSURL* url = [[PFBBundle sharedBundle] pathForFile:@"LaunchTwitterBird.pdf"];
    if (!url) {
        return nil;
    }
    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
    if (!pdf) {
        return nil;
    }
    CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
    UIGraphicsImageRendererFormat* fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    UIImage* image = [renderer imageWithActions:^(UIGraphicsImageRendererContext* ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextTranslateCTM(c, 0, side);
        CGContextScaleCTM(c, side / 24.0, -side / 24.0);
        CGContextDrawPDFPage(c, page);
    }];
    CGPDFDocumentRelease(pdf);
    return image;
}

// Replaces Twitter's launch "xLogo" with the bundled bird.
%hook UIImage

+ (UIImage*)imageNamed:(NSString*)name {
    if ([name isEqualToString:@"xLogo"]) {
        UIImage* bird = launchBirdImage(180);
        if (bird) {
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

// Twitter carries its own gate for the iOS 26 design, and it is unreachable: the
// app resets it at every launch, the same millisecond it reads the feature switch,
// and its own answer stays NO whatever the gate holds.
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString*)key {
    if ([key isEqualToString:@"UIDesignRequiresCompatibility"] &&
        self == [NSBundle mainBundle]) {
        BOOL glassEnabled =
            [[NSUserDefaults standardUserDefaults] boolForKey:@"enable_liquid_glass"];
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
