//
//  AppLifecycle.x
//  PrimeFreeBird
//

#import "HookHelpers.h"
extern void NFBInstallPasteboardObserver(void);

// MARK: - Padlock helpers

static const NSInteger PadlockOverlayTag = 909;

static NSArray<UIWindow*>* allActiveWindows(void) {
    NSMutableArray<UIWindow*>* result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        [result addObject:w];
                }
            }
        }
    }
    if (result.count == 0) {
        for (UIWindow* w in UIApplication.sharedApplication.windows) {
            if (!w.hidden)
                [result addObject:w];
        }
    }
    return result;
}

static UIWindow* activeKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
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

static UIViewController* topViewController(UIViewController* root) {
    if (!root)
        return nil;
    UIViewController* vc = root;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController*)vc).visibleViewController ?: vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController* sel = ((UITabBarController*)vc).selectedViewController;
        if (sel)
            vc = sel;
    }
    return vc;
}

static void showPadlockOverlay(void) {
    UIWindow* window = activeKeyWindow();
    if (!window)
        return;

    for (UIWindow* w in allActiveWindows()) {
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [v removeFromSuperview];
        }
    }

    UIView* overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.systemBackgroundColor;
    overlay.userInteractionEnabled = YES;
    overlay.tag = PadlockOverlayTag;

    UIImageView* icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"PADLOCK_LOCKED_LABEL"];
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
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

    [window addSubview:overlay];
}

static void removePadlockOverlay(void) {
    for (UIWindow* w in allActiveWindows()) {
        NSMutableArray<UIView*>* toRemove = [NSMutableArray array];
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [toRemove addObject:v];
        }
        for (UIView* v in toRemove)
            [v removeFromSuperview];
    }
}

// Deliberately in-memory only: the padlock must always re-prompt after a
// relaunch, so persisting this would only risk skipping it.
static BOOL padlockAuthenticated = NO;

static BOOL isAuthenticated(void) {
    return padlockAuthenticated;
}

static void setAuthenticated(BOOL yes) {
    padlockAuthenticated = yes;
}

static void presentAuthIfNeeded(void) {
    if (isAuthenticated()) {
        removePadlockOverlay();
        return;
    }

    UIWindow* window = activeKeyWindow();
    if (!window) {
        showPadlockOverlay();
        return;
    }

    UIViewController* root = window.rootViewController;
    if (!root) {
        window.rootViewController = [UIViewController new];
        root = window.rootViewController;
    }
    UIViewController* host = topViewController(root);

    AuthViewController* auth = [[AuthViewController alloc] init];
    auth.completion = ^(BOOL authenticated) {
        setAuthenticated(authenticated);
        if (authenticated) {
            removePadlockOverlay();
        }
    };
    auth.modalPresentationStyle = UIModalPresentationFullScreen;
    if ([auth respondsToSelector:@selector(setModalInPresentation:)]) {
        auth.modalInPresentation = YES;
    }

    if (host.presentedViewController == nil) {
        [host presentViewController:auth animated:NO completion:nil];
    } else {
        [host dismissViewControllerAnimated:NO
                                 completion:^{
                                     UIViewController* newTop =
                                         topViewController(root);
                                     [newTop presentViewController:auth
                                                          animated:NO
                                                        completion:nil];
                                 }];
    }
}

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [BHTManager cleanCache];
    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        applySelectedThemeColor();
    });

    return orig;
}

- (void)applicationDidBecomeActive:(__unsafe_unretained id)arg1 {
    %orig;

    NFBInstallPasteboardObserver();

    applySelectedThemeColor();
    prewarmWebCookiesIfNeeded();

    if ([BHTSettings boolForKey:@"padlock"]) {
        if (isAuthenticated()) {
            removePadlockOverlay();
        } else {
            showPadlockOverlay();
            dispatch_async(dispatch_get_main_queue(), ^{
                presentAuthIfNeeded();
            });
        }
    } else {
        removePadlockOverlay();
    }
}

- (void)applicationWillResignActive:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // Cover the UI (and the app-switcher snapshot) and mark unauthenticated so
        // the next activation prompts again; the overlay persists into background.
        showPadlockOverlay();
        setAuthenticated(NO);
    }

    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
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
    // Fresh installs still flashed black: on the very first render the
    // backdrop comes from bare CALayers (no backing view) and from subviews
    // that carry no background colour of their own, so a view-only,
    // only-if-already-painted repaint never reached it. Paint the layer tree
    // as well, and paint every non-image subview unconditionally.
    view.layer.backgroundColor = twitterBlue.CGColor;
    for (CALayer* layer in view.layer.sublayers) {
        layer.backgroundColor = twitterBlue.CGColor;
    }
    EnumerateSubviewsRecursively(view, ^(UIView* sub) {
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

// Render our bundled white bird from its PDF (same technique as the settings bird).
static UIImage* launchBirdImage(CGFloat side) {
    NSURL* url = [[BHTBundle sharedBundle] pathForFile:@"LaunchTwitterBird.pdf"];
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

// Replace Twitter's launch "xLogo" with our bundled bird.
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

// The black frame comes at the END, not the start: the splash is torn
// down before the timeline has drawn, and a window with no background colour
// is black. Painting the window blue fills exactly that gap, and letting the
// splash fade out rather than cutting hides the seam.

static BOOL gNFBSplashRevealing = NO;

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
    // Released once the timeline is on screen, so nothing else inherits it.
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
    if (!gNFBSplashRevealing) {
        applySplashBrandColors((UIView*)self);
    }
}

- (void)animateRevealWithCompletion:(id)completion {
    // Strip only the X mask, then let the native zoom animation run.
    // Our bundled bird is correctly sized, so the zoom no longer distorts it.
    stripLaunchRevealMask((UIView*)self);
    gNFBSplashRevealing = YES;
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

%ctor {
    BOOL glassEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"enable_liquid_glass"];
    [[NSUserDefaults standardUserDefaults] setBool:glassEnabled
                                            forKey:@"com.apple.SwiftUI.IgnoreSolariumOptOut"];
}
