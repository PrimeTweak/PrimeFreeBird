// Opens replies in an authenticated web composer instead of the native one and
// captures the posted reply's id from the webview (reply_in_webview).

#import "Support/HookHelpers.h"
#import <QuartzCore/QuartzCore.h>
#import "Sideload/PFBReplyWebViewState.h"
#import "Sideload/PFBReplyWebViewController.h"

// MARK: - Reply webview helpers

static TFNTwitterStatus* statusFromObject(id object) {
    if (!object) {
        return nil;
    }

    if ([object isKindOfClass:%c(TFNTwitterStatus)]) {
        return (TFNTwitterStatus*)object;
    }

    @try {
        id tweet = [object valueForKey:@"tweet"];
        if ([tweet isKindOfClass:%c(TFNTwitterStatus)]) {
            return (TFNTwitterStatus*)tweet;
        }
    } @catch (__unused NSException* exception) {
    }

    @
    try {
        id status = [object valueForKey:@"status"];
        if ([status isKindOfClass:%c(TFNTwitterStatus)]) {
            return (TFNTwitterStatus*)status;
        }
    } @catch (__unused NSException* exception) {
    }

    return nil;
}

// YES only while the tweak's reply web view is on screen, so the keyboard swizzle below never forces
// the keyboard for any other web view in the app.
BOOL gPFBReplyWebViewActive = NO;

// One-shot: set right before the tweak issues the programmatic focus() (after the icon bar is built),
// consumed by the WKContentView swizzle to raise the keyboard for that focus only. Any later
// focus (e.g. x.com re-focusing after a dismiss) is NOT forced, so a user dismiss sticks.
BOOL gPFBForceNextFocus = NO;

__weak UIScrollView* gPFBReplyScroller = nil;   // identity for the CALayer hook
// The reveal is a CABasicAnimation on the scroll view layer's bounds.origin
// (from {0,-173} to {0,0}, 0.25s). During the keyboard-up window the tweak drops exactly
// that animation when WebKit tries to add it; the counter records that it fired.
int gPFBAnimsKilled = 0;
CFTimeInterval gPFBSquelchUntil = 0;   // drop bounds.origin animations before this time

// Native compose icon bar. The web toolbar cannot be glued to the keyboard, so the
// real toolbar SVGs are shown in a small WKWebView that is the keyboard's
// inputAccessoryView, with taps relayed to the hidden real buttons.
WKWebView* gPFBIconBar = nil;           // the icon-bar web view = the accessory
__weak WKWebView* gPFBRelayWebView = nil;

// Find the current first responder to reload its input accessory.
UIView* PFBFindFirstResponder(UIView* v) {
    if (v.isFirstResponder) { return v; }
    for (UIView* sub in v.subviews) {
        UIView* r = PFBFindFirstResponder(sub);
        if (r) { return r; }
    }
    return nil;
}

// ---------------------------------------------------------------------------

void PFBOpenStatusNatively(NSString* statusID) {
    if (statusID.length == 0) {
        return;
    }

    NSURL* url =
        [NSURL URLWithString:[NSString stringWithFormat:@"twitter://status?id=%@", statusID]];
    if (!url) {
        return;
    }

    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(openURL:options:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(openURL:options:), url, @{});
    }
}

static BOOL openAuthenticatedTweetWebView(NSString* statusID) {
    if (statusID.length == 0) {
        return NO;
    }

    UIViewController* presentingController = topMostController();
    if (!presentingController) {
        return NO;
    }

    PFBReplyWebViewController* replyController = [[PFBReplyWebViewController alloc] init];
    replyController.statusID = statusID;

    UINavigationController* modalNavigationController =
        [[UINavigationController alloc] initWithRootViewController:replyController];
    modalNavigationController.modalPresentationStyle = UIModalPresentationFullScreen;

    [presentingController presentViewController:modalNavigationController animated:YES completion:nil];
    return YES;
}

// No web session yet: present the interactive login once, then open the reply once
// cookies have been harvested. There is no fallback to a native reply here
// (that's the attestation path the user turned reply_in_webview on to avoid).
static void ensureSessionThenOpenReply(NSString* statusID) {
    PFBPresentWebSessionLogin(^(BOOL success) {
        if (success && PFBHasUsableWebCredentials()) {
            openAuthenticatedTweetWebView(statusID);
        }
    });
}

// MARK: - Hooks

// The inline reply button has no dedicated ObjC subclass; every tap funnels through
// this handler. WebKit reveals the field with a pair of animations on the scroll
// view layer, dropped here during the keyboard-up window on that layer only.
%hook CALayer
- (void)addAnimation:(CAAnimation*)anim forKey:(NSString*)key {
    if (gPFBReplyWebViewActive && gPFBReplyScroller
        && self == gPFBReplyScroller.layer
        && CACurrentMediaTime() < gPFBSquelchUntil
        && [anim isKindOfClass:[CABasicAnimation class]]) {
        NSString* kp = [(CABasicAnimation*)anim keyPath];
        if ([kp isEqualToString:@"bounds.origin"] || [kp isEqualToString:@"bounds.size"]
            || [kp isEqualToString:@"bounds"]) {
            gPFBAnimsKilled++;
            return;  // never install WebKit's mis-targeted reveal animation
        }
    }
    %orig(anim, key);
}
%end

%hook T1StatusViewInlineActionTapEventHandler
- (void)performReplyActionWithAccount:(__unsafe_unretained id)account
                                event:(__unsafe_unretained id)event
                           controller:(__unsafe_unretained id)controller
                        scribeContext:(__unsafe_unretained id)scribeContext
                        scribeElement:(__unsafe_unretained id)scribeElement
                           parameters:(__unsafe_unretained id)parameters
                       originalStatus:(__unsafe_unretained TFNTwitterStatus*)originalStatus {
    if (![PFBSettings boolForKey:@"reply_in_webview"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_reply_in_webview, @"reply tapped");
        return %orig;
    }

    if (![originalStatus respondsToSelector:@selector(statusID)]) {
        return %orig;
    }

    NSInteger statusID = originalStatus.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString* statusIDString = @(statusID).stringValue;
    PFBCOMPAT_ACTION(PFBCompat_reply_in_webview, @"reply opened in the web view");
    if (PFBHasUsableWebCredentials()) {
        if (!openAuthenticatedTweetWebView(statusIDString)) {
            return %orig;
        }
    } else {
        ensureSessionThenOpenReply(statusIDString);
    }
}
%end

%hook T1PersistentComposeViewController
- (void)persistentComposeViewDidTap:(id)composeView {
    if (![PFBSettings boolForKey:@"reply_in_webview"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_reply_in_webview, @"reply tapped");
        return %orig;
    }

    TFNTwitterStatus* status = statusFromObject(self.statusViewModel);
    NSInteger statusID = status.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString* statusIDString = @(statusID).stringValue;
    PFBCOMPAT_ACTION(PFBCompat_reply_in_webview, @"reply opened in the web view");
    if (PFBHasUsableWebCredentials()) {
        if (!openAuthenticatedTweetWebView(statusIDString)) {
            return %orig;
        }
    } else {
        ensureSessionThenOpenReply(statusIDString);
    }
}
%end

%hook T1WebViewController
- (void)didFinishLoadingWithError:(id)error {
    %orig;
    // Still needed: the offscreen bootstrap harvest webview (WebCreateTweet.x) is a
    // T1WebViewController and relies on this hook to harvest its cookies. The reply itself
    // uses the custom PFBReplyWebViewController above, not T1WebViewController.
    PFBMaybeHandleHarvestWebView(self);
}
%end

// Lets the injected focus() raise the keyboard without a tap, only while the reply
// web view is on screen. method_setImplementation, not %hook: the first parameter
// is a C++ reference and must be typed void*, or ARC retains it and crashes.
void PFBWebReplyStart(void) {
    @autoreleasepool {
        Class contentViewClass = NSClassFromString(@"WKContentView");
        if (!contentViewClass) {
            return;
        }
        SEL focusSel = sel_getUid(
            "_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:");
        Method focusMethod = class_getInstanceMethod(contentViewClass, focusSel);
        if (!focusMethod) {
            return;
        }
        __block IMP originalFocusIMP = method_getImplementation(focusMethod);
        IMP overrideIMP = imp_implementationWithBlock(^void(id self_, void* information,
                                                            BOOL userIsInteracting, BOOL blurPreviousNode,
                                                            unsigned long long activityStateChanges,
                                                            id userObject) {
            if (gPFBReplyWebViewActive && gPFBForceNextFocus) {
                gPFBForceNextFocus = NO;  // only the tweak's own focus is forced; a dismiss sticks
                userIsInteracting = YES;
            }
            ((void (*)(id, SEL, void*, BOOL, BOOL, unsigned long long, id))originalFocusIMP)(
                self_, focusSel, information, userIsInteracting, blurPreviousNode, activityStateChanges,
                userObject);
        });
        method_setImplementation(focusMethod, overrideIMP);

        // Removes the form-assistant bar while the reply web view is on screen, by
        // returning nil from WKContentView's inputAccessoryView. Swizzled only if
        // WKContentView implements it itself, never UIResponder's.
        SEL accessorySel = @selector(inputAccessoryView);
        unsigned int methodCount = 0;
        Method* methods = class_copyMethodList(contentViewClass, &methodCount);
        Method accessoryMethod = NULL;
        for (unsigned int i = 0; i < methodCount; i++) {
            if (method_getName(methods[i]) == accessorySel) {
                accessoryMethod = methods[i];
                break;
            }
        }
        free(methods);
        if (accessoryMethod) {
            __block IMP originalAccessoryIMP = method_getImplementation(accessoryMethod);
            IMP accessoryOverride = imp_implementationWithBlock(^id(id self_) {
                if (gPFBReplyWebViewActive) {
                    return gPFBIconBar;  // the tweak's icon bar; nil until built, so no form bar
                }
                return ((id (*)(id, SEL))originalAccessoryIMP)(self_, accessorySel);
            });
            method_setImplementation(accessoryMethod, accessoryOverride);
        }
    }
}
