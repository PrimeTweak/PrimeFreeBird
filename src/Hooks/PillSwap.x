// PillSwap.x — the "All" pill, rebuilt as a button nobody destroys.
//
// Spec: a button identical to the native one. The measured
// story (project journal, 16-17/08): under forced Liquid Glass the SwiftUI
// bridge destroys and recreates the DMInbox trailing item on every pass —
// that rebuild IS the flash. The avatar, in the same bar under the same
// glass, never moves: the glass is innocent, the rebuild is the culprit.
// So the SwiftUI item is swapped for OUR plain UIBarButtonItem the moment
// it shows up: same typography (copied live from the real label), same
// chevron (copied), same paddings (measured: content + 10 pt sides inside
// a 40 pt row), same glass (UIKit's own default treatment — nothing about
// backgrounds is touched), and the SAME native
// UIMenu (Twitter's object, reused — tap opens the real All/Requests menu,
// their handlers run). When SwiftUI stomps the items back on a later pass,
// the stomp itself is the signal: the original's view fires the hook, and the
// item is
// swap again (~1 ms, measured cadence of the finder) and refresh the label
// read from the menu's checked state, so Twitter's own re-render keeps it in
// sync.
//
// Two unknowns, journaled loudly rather than assumed:
//   · does the bridge item carry its UIMenu? If not, the swap is abandoned,
//     the native item stays and nothing is broken.
//   · does the label follow a filter change? The stomp should carry it;
//     a 2 s belt after each menu opening re-reads the checked state.
// Every action has its line; removal is `git rm` of this one file.

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"
#import <QuartzCore/QuartzCore.h>

static void nfbSwapEnsureGlass(UIVisualEffectView* capsule);

// A named subclass so captures and the watch can identify the button, and so
// it can answer the ONE question the bar's wrapper actually asks. Measured the
// hard way: _TtCC5UIKit19NavigationButtonBar15ItemWrapperView sizes its child
// from intrinsicContentSize, then CLAMPS it to the standard bar-button box —
// a capture caught it at {{376, 67}, {44, 34}} while the native pill is
// 57.33 x 40. So the box is not fought: the capsule is drawn LARGER than
// the button, anchored to its right edge, and the touch area follows it.
@interface NFBInboxPillButton : UIButton
@property (nonatomic, assign) CGSize nfbIntrinsic;
@property (nonatomic, assign) CGRect nfbTouchRect;
@property (nonatomic, assign) CGFloat nfbPillWidth;   // capsule width we want
@property (nonatomic, assign) CGFloat nfbSpacing;     // label ↔ chevron
@end
@implementation NFBInboxPillButton

- (CGSize)intrinsicContentSize {
    if (self.nfbIntrinsic.width > 0) {
        return self.nfbIntrinsic;
    }
    return [super intrinsicContentSize];
}

// v6, measured on screen: the capsule spanned 318.7 to 376.0 while the button
// was logged at frame={{376, 67}, {0, 0}}. The placement had been computed
// ONCE, at a moment the wrapper had not sized the view yet (bounds 0 x 0), and
// was never redone when it handed over the real 44 x 34 box. So the geometry
// now lives HERE: every time the wrapper resizes the view, it lays itself out
// again from the bounds it actually has. Right edge of the capsule = right edge
// of
// the box (measured at 420.0 = the native right edge), so 420 − 57.33 = 362.67
// = the native left edge, whatever the box turns out to be.
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.nfbPillWidth <= 0) {
        return;
    }
    CGFloat height = 40.0;
    CGRect box = self.bounds;
    CGRect capsuleFrame = CGRectMake(box.size.width - self.nfbPillWidth,
                                     (box.size.height - height) / 2.0,
                                     self.nfbPillWidth, height);
    UIVisualEffectView* capsule = (UIVisualEffectView*)[self viewWithTag:3];
    capsule.frame = capsuleFrame;
    nfbSwapEnsureGlass(capsule);
    self.nfbTouchRect = capsuleFrame;

    UILabel* label = (UILabel*)[self viewWithTag:1];
    UIImageView* chevron = (UIImageView*)[self viewWithTag:2];
    CGFloat x = capsuleFrame.origin.x + 10.0;
    CGFloat midY = CGRectGetMidY(capsuleFrame);
    label.frame = CGRectMake(x, midY - label.bounds.size.height / 2.0,
                             label.bounds.size.width, label.bounds.size.height);
    if (!chevron.hidden) {
        chevron.frame = CGRectMake(x + label.bounds.size.width + self.nfbSpacing,
                                   midY - chevron.bounds.size.height / 2.0,
                                   chevron.bounds.size.width,
                                   chevron.bounds.size.height);
    }
}

// The visible pill spills outside bounds; a tap anywhere on it must count.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    if (!CGRectIsEmpty(self.nfbTouchRect)) {
        return CGRectContainsPoint(self.nfbTouchRect, point);
    }
    return [super pointInside:point withEvent:event];
}
@end

// Our item (built once, reused across stomps) and the latest original from
// Twitter (strong: it left the bar, but its menu must stay alive for ours).
static UIBarButtonItem*  gNFBSwapItem;
// The one number to turn if the pill still sits a hair off: negative moves it
// LEFT, positive RIGHT. It is a visual translation only — layout never fights
// it. The build measures the result itself (see the ruler below), so the next
// adjustment is arithmetic, not another guess.
static CGFloat           gNFBSwapShift = 0.0;
static BOOL              gNFBSwapMeasured;
static UIBarButtonItem*  gNFBSwapOriginal;
static UIMenu*           gNFBSwapMenu;   // harvested from the live control; outlives it
static NSInteger         gNFBSwapCount;
static const char*       kNFBSwapNavKey = "nfbSwapNav";

static UIViewController* nfbSwapOwningVC(UIView* view) {
    UIResponder* responder = view;
    NSInteger hops = 0;
    while (responder && hops < 40) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
        responder = responder.nextResponder;
        hops++;
    }
    return nil;
}

// A bar button's responder chain stops at the NAVIGATION controller; the
// items live one storey down (measured 17/08: T1TwitterSwift.XChatViewController
// holds the single trailing item).
static NSArray<UIViewController*>* nfbSwapCandidates(UIViewController* vc) {
    NSMutableArray<UIViewController*>* out = [NSMutableArray array];
    void (^add)(UIViewController*) = ^(UIViewController* candidate) {
        if (candidate && ![out containsObject:candidate] && out.count < 8) {
            [out addObject:candidate];
        }
    };
    add(vc);
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController* nav = (UINavigationController*)vc;
        add(nav.topViewController);
        for (UIViewController* child in nav.topViewController.childViewControllers) {
            add(child);
        }
        for (UIViewController* stacked in nav.viewControllers) {
            add(stacked);
        }
    }
    return out;
}

// The checked entry of the menu is the truthful, localized label source
// ("All" / "Requests" with Twitter's own wording).
static NSString* nfbSwapCheckedTitle(UIMenu* menu) {
    for (UIMenuElement* element in menu.children) {
        if ([element isKindOfClass:[UIAction class]]) {
            UIAction* action = (UIAction*)element;
            if (action.state == UIMenuElementStateOn && action.title.length) {
                return action.title;
            }
        } else if ([element isKindOfClass:[UIMenu class]]) {
            NSString* nested = nfbSwapCheckedTitle((UIMenu*)element);
            if (nested) {
                return nested;
            }
        }
    }
    return nil;
}

// Native paddings, measured on the real thing: content sits at x=10 in a
// row 20 pt wider than it, centred in 40 pt of height (stack 37.33x16 at
// {10, 12} inside 57.33x40).
static void nfbSwapLayoutButton(void) {
    NFBInboxPillButton* button = (NFBInboxPillButton*)gNFBSwapItem.customView;
    UILabel* label = (UILabel*)[button viewWithTag:1];
    UIImageView* chevron = (UIImageView*)[button viewWithTag:2];
    [label sizeToFit];
    CGFloat spacing = (chevron.hidden || chevron.bounds.size.width <= 0) ? 0 : 4.0;
    CGFloat contentW = label.bounds.size.width + spacing + (chevron.hidden ? 0 : chevron.bounds.size.width);
    CGFloat width = contentW + 20.0;
    CGFloat height = 40.0;
    // Content sizes only. WHERE it all goes is decided in -layoutSubviews,
    // which runs again every time the wrapper changes the box.
    button.nfbPillWidth = width;
    button.nfbSpacing = spacing;
    button.nfbIntrinsic = CGSizeMake(width, height);
    [button invalidateIntrinsicContentSize];
    button.clipsToBounds = NO;
    button.transform = CGAffineTransformMakeTranslation(gNFBSwapShift, 0);
    [button setNeedsLayout];
    [button layoutIfNeeded];

    // THE RULER — measures the VISIBLE capsule now, not the wrapper's box.
    // Reference measured on screen: the native pill spans 362.7 to 420.0.
    if (!gNFBSwapMeasured && NFBDebugIsRecording()) {
        gNFBSwapMeasured = YES;
        __weak NFBInboxPillButton* weakButton = button;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NFBInboxPillButton* live = weakButton;
            if (!live.window) {
                gNFBSwapMeasured = NO;  // try again on the next layout
                return;
            }
            UIView* liveCapsule = [live viewWithTag:3];
            CGRect onScreen = [live convertRect:liveCapsule.frame toView:nil];
            NFBDebugLog(@"swap: RULER - capsule on screen %.1f to %.1f pt "
                        @"(native 362.7 to 420.0, imposed box %.0fx%.0f)",
                        onScreen.origin.x,
                        onScreen.origin.x + onScreen.size.width,
                        live.bounds.size.width, live.bounds.size.height);
        });
    }
}

// Belt for the label after a menu pick: the stomp normally carries the new
// state, this re-read covers a bridge that would not stomp.
// The label the pill last showed, kept across launches. Without it the pill
// has nothing to say until the app's own item arrives with its menu, which is
// what made it appear only after a swipe between tabs.
static NSString* nfbSwapRememberedTitle(void) {
    NSString* stored =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"nfb_swap_last_title"];
    return stored.length ? stored : nil;
}

static void nfbSwapRememberTitle(NSString* title) {
    if (title.length) {
        [[NSUserDefaults standardUserDefaults] setObject:title forKey:@"nfb_swap_last_title"];
    }
}

static void nfbSwapRefreshLabelFromMenu(void) {
    UIMenu* live = gNFBSwapOriginal.menu ?: gNFBSwapMenu;
    if (!gNFBSwapItem || !live) {
        return;
    }
    NSString* checked = nfbSwapCheckedTitle(live);
    if (!checked.length) {
        return;
    }
    NFBInboxPillButton* button = (NFBInboxPillButton*)gNFBSwapItem.customView;
    UILabel* label = (UILabel*)[button viewWithTag:1];
    if (![label.text isEqualToString:checked]) {
        label.text = checked;
        nfbSwapLayoutButton();
        NFBDebugLog(@"swap: label -> %@ (menu)", checked);
    }
    nfbSwapRememberTitle(checked);
}

// v2 — measured on the 06:41 video: the residual flash was OUR OWN swap.
// On every return SwiftUI re-sets its item; it lands EMPTY for ~150 ms (the
// rebuilt content arrives late, the original disease), then the swap-back
// re-hosts the platter once more. So after the bootstrap, the stomp is
// intercepted at the SETTER, before anything reaches the bar: the incoming
// foreign item is captured (fresh menu, fresh checked state) and OUR item
// goes through in its place. The bar receives the very instance it already
// hosts — nothing changes, nothing re-hosts, nothing can flash — and the
// native view is never built again: the ⌚ watch on the ItemView goes silent.
static NSArray<UIBarButtonItem*>* nfbSwapInterceptItems(UINavigationItem* nav,
                                                        NSArray<UIBarButtonItem*>* items) {
    if (!gNFBSwapItem || items.count != 1 ||
        !objc_getAssociatedObject(nav, kNFBSwapNavKey)) {
        return items;
    }
    UIBarButtonItem* incoming = items.firstObject;
    if (incoming == gNFBSwapItem) {
        return items;
    }
    if (![BHTSettings boolForKey:@"enable_liquid_glass"]) {
        return items;
    }
    gNFBSwapOriginal = incoming;
    gNFBSwapCount++;
    NFBDebugLog(@"swap: intercepted at setter #%ld", (long)gNFBSwapCount);
    nfbSwapRefreshLabelFromMenu();
    return @[gNFBSwapItem];
}

// The glass on the capsule, set now or repaired later. Filmed: on a cold
// launch the pill showed its outline with no glass behind it for two seconds,
// until a tab change - the effect had been chosen once, at a moment
// UIGlassEffect was not resolvable yet, and the fallback material stayed for
// the session. The effect is therefore re-read on every pass and upgraded the
// moment the class answers.
static void nfbSwapEnsureGlass(UIVisualEffectView* capsule) {
    if (!capsule) {
        return;
    }
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    BOOL hasGlass = glassClass && [capsule.effect isKindOfClass:glassClass];
    // Reports what the capsule actually ends up with, at most twice a second:
    // the class, the effect on it, its frame, and whether it is on screen. The
    // glass was assumed missing at launch and set again on every pass, and the
    // pill still showed no glass at all - so the assumption is measured now
    // instead of replaced by another one.
    static NSTimeInterval lastNote = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - lastNote > 0.5) {
        lastNote = now;
        NFBDebugLog(@"[glass] class=%@ effect=%@ frame=%.0fx%.0f alpha=%.2f hidden=%d "
                    @"window=%@ subviews=%lu",
                    glassClass ? @"yes" : @"NO",
                    capsule.effect ? NSStringFromClass([capsule.effect class]) : @"nil",
                    capsule.bounds.size.width, capsule.bounds.size.height, capsule.alpha,
                    capsule.hidden, capsule.window ? @"yes" : @"no",
                    (unsigned long)capsule.subviews.count);
    }
    // Measured: effect=UIGlassEffect, frame 57x40, on screen, alpha 1 - and
    // subviews=0. A visual effect view that renders builds a backdrop of its
    // own, so an empty one draws nothing, which is the pill with no glass. The
    // effect was set before the view had a size, and setting it again to the
    // same object is a no-op. Clearing it first forces the rebuild.
    if (hasGlass && capsule.subviews.count == 0 && capsule.window &&
        capsule.bounds.size.width > 0) {
        UIVisualEffect* effect = capsule.effect;
        capsule.effect = nil;
        capsule.effect = effect;
        NFBDebugLog(@"[glass] backdrop was empty - effect reapplied, subviews now %lu",
                    (unsigned long)capsule.subviews.count);
        return;
    }
    if (hasGlass) {
        return;
    }
    if (glassClass) {
        capsule.effect = [[glassClass alloc] init];
        NFBDebugLog(@"[glass] effect set to UIGlassEffect");
        return;
    }
    if (!capsule.effect) {
        capsule.effect =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        NFBDebugLog(@"[glass] effect set to material fallback");
    }
}

static void nfbSwapApply(UIView* pillView) {
    if (!pillView.window) {
        return;
    }
    if (![BHTSettings boolForKey:@"enable_liquid_glass"]) {
        return;  // standard interface never had the problem — nothing to do
    }

    UIViewController* vc = nfbSwapOwningVC(pillView);
    if (!vc) {
        return;
    }

    // Locate the holder and the original among its trailing items. Ours is
    // recognised by pointer; anything else in trailing position is Twitter's.
    UINavigationItem* nav = nil;
    UIBarButtonItem* original = nil;
    UIBarButtonItemGroup* group = nil;
    for (UIViewController* candidate in nfbSwapCandidates(vc)) {
        UINavigationItem* candidateNav = candidate.navigationItem;
        for (UIBarButtonItem* item in candidateNav.rightBarButtonItems) {
            if (item != gNFBSwapItem) {
                nav = candidateNav;
                original = item;
                break;
            }
        }
        if (!original) {
            if (@available(iOS 16.0, *)) {
                for (UIBarButtonItemGroup* candidateGroup in candidateNav.trailingItemGroups) {
                    for (UIBarButtonItem* item in candidateGroup.barButtonItems) {
                        if (item != gNFBSwapItem) {
                            nav = candidateNav;
                            original = item;
                            group = candidateGroup;
                            break;
                        }
                    }
                    if (original) {
                        break;
                    }
                }
            }
        }
        if (original) {
            break;
        }
        BOOL hasTrailing = candidateNav.rightBarButtonItems.count > 0;
        if (@available(iOS 16.0, *)) {
            hasTrailing = hasTrailing || candidateNav.trailingItemGroups.count > 0;
        }
        if (hasTrailing) {
            // Only ours is installed — nothing to swap on this pass.
            return;
        }
    }
    if (!original) {
        return;  // items not attached yet; the next layout retries
    }

    // The native content, read live from the real thing — same reader the
    // mirror proved (stack -> label + chevron).
    UIStackView* stack = nil;
    for (UIView* sub in pillView.subviews) {
        if ([sub isKindOfClass:[UIStackView class]]) {
            stack = (UIStackView*)sub;
            break;
        }
    }
    UILabel* realLabel = nil;
    UIImageView* realChevron = nil;
    for (UIView* piece in stack.arrangedSubviews) {
        if (!realLabel && [piece isKindOfClass:[UILabel class]]) {
            realLabel = (UILabel*)piece;
        } else if (!realChevron && [piece isKindOfClass:[UIImageView class]]) {
            realChevron = (UIImageView*)piece;
        }
    }
    NSString* liveTitle = realLabel.attributedText.length
        ? realLabel.attributedText.string : realLabel.text;
    // The app fills its own label only once the inbox has drawn, so the swap
    // used to stand down until then and the pill appeared on the first swipe
    // between tabs. The remembered title carries it through that gap; the live
    // one replaces it as soon as it arrives.
    if (realLabel && !liveTitle.length) {
        liveTitle = nfbSwapRememberedTitle();
        if (liveTitle.length) {
            NFBDebugLog(@"swap: no live title yet - using remembered '%@'", liveTitle);
        }
    }
    if (!realLabel || !liveTitle.length) {
        static const char* kNFBSwapWaitKey = "nfbSwapWait";
        if (!objc_getAssociatedObject(pillView, kNFBSwapWaitKey)) {
            objc_setAssociatedObject(pillView, kNFBSwapWaitKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NFBDebugLog(@"swap: waiting for content - retrying");
        }
        return;  // content not built yet; the next layout retries
    }

    // First unknown, ANSWERED on 17/08 06:59: the bridge item carries NO
    // menu — the abandon fired as designed, native stayed. But the 21:31
    // capture had the clue all along: a UIButtonLabel INSIDE the pill view.
    // The pill is (or contains) a real UIButton, and a native tap-menu means
    // showsMenuAsPrimaryAction — the menu lives on that control. Harvest it
    // there; if it is nowhere, a loud probe prints the class lineage, the
    // interactions and primaryAction, so the next capture names the carrier.
    UIMenu* menu = original.menu;
    NSString* menuSource = @"item";
    if (!menu) {
        NSMutableArray<UIView*>* pool = [NSMutableArray arrayWithObject:pillView];
        for (UIView* sub in pillView.subviews) {
            [pool addObject:sub];
            for (UIView* deep in sub.subviews) {
                [pool addObject:deep];
            }
        }
        for (UIView* candidate in pool) {
            if ([candidate isKindOfClass:[UIControl class]] &&
                [candidate respondsToSelector:@selector(menu)]) {
                UIMenu* found = ((UIButton*)candidate).menu;
                if (found) {
                    menu = found;
                    menuSource = NSStringFromClass([candidate classForCoder]);
                    break;
                }
            }
        }
    }
    if (!menu) {
        static BOOL probed;
        if (!probed) {
            probed = YES;
            NSMutableArray<NSString*>* lineage = [NSMutableArray array];
            Class cls = [pillView class];
            NSInteger depth = 0;
            while (cls && depth < 6) {
                [lineage addObject:NSStringFromClass(cls)];
                cls = class_getSuperclass(cls);
                depth++;
            }
            NSMutableArray<NSString*>* interactions = [NSMutableArray array];
            for (id<UIInteraction> interaction in pillView.interactions) {
                [interactions addObject:NSStringFromClass([interaction class])];
            }
            NFBDebugLog(@"swap: menu NOT FOUND - probe: lineage=%@ | "
                        @"interactions=%@ | primaryAction=%@",
                        [lineage componentsJoinedByString:@" < "],
                        interactions.count
                            ? [interactions componentsJoinedByString:@","] : @"-",
                        original.primaryAction
                            ? NSStringFromClass([original.primaryAction class])
                            : @"nil");
        }
        return;  // native kept, the probe has spoken
    }
    gNFBSwapMenu = menu;  // strong: it must outlive the mortal native button

    // Build ours once; later passes only refresh content and re-install.
    NFBInboxPillButton* button;
    UILabel* label;
    UIImageView* chevron;
    if (!gNFBSwapItem) {
        // CUSTOM type: [UIButton new] means a SYSTEM button, and iOS 26
        // gives system buttons their own glass configuration — the stray
        // inner lens measured on the 07:34 video. Custom draws nothing.
        button = (NFBInboxPillButton*)
            [NFBInboxPillButton buttonWithType:UIButtonTypeCustom];
        label = [UILabel new];
        label.tag = 1;
        [button addSubview:label];
        chevron = [UIImageView new];
        chevron.tag = 2;
        [button addSubview:chevron];
        button.showsMenuAsPrimaryAction = YES;
        // Our OWN capsule, native-shaped (the bar's default treatment for a
        // plain UIKit item is a CIRCLE — measured ~63 pt on the 07:34 video,
        // nothing like the wide native pill). Glass via the runtime so the
        // The iOS 16 SDK never hears about UIGlassEffect; the working recipe:
        // effect behind the content, radius = height / 2.
        UIVisualEffectView* capsule = [[UIVisualEffectView alloc] initWithEffect:nil];
        capsule.userInteractionEnabled = NO;
        capsule.layer.cornerRadius = 20.0;
        capsule.layer.masksToBounds = YES;
        capsule.tag = 3;
        [button insertSubview:capsule atIndex:0];
        nfbSwapEnsureGlass(capsule);
        gNFBSwapItem = [[UIBarButtonItem alloc] initWithCustomView:button];
        // On OUR plain UIKit item the official per-item switch is exactly in
        // its intended case — it kills the circular default treatment.
        if ([gNFBSwapItem respondsToSelector:
                NSSelectorFromString(@"setHidesSharedBackground:")]) {
            [gNFBSwapItem setValue:@YES forKey:@"hidesSharedBackground"];
            NFBDebugLog(@"swap: UIKit glass removed on the replacement item");
        }
        NFBMark(button, @"PillSwap/custom button - identical to native");
    } else {
        button = (NFBInboxPillButton*)gNFBSwapItem.customView;
        label = (UILabel*)[button viewWithTag:1];
        chevron = (UIImageView*)[button viewWithTag:2];
    }

    // Identical: typography and chevron copied from the live original.
    label.text = liveTitle;
    label.font = realLabel.font;
    label.textColor = realLabel.textColor;
    if (realChevron.image) {
        chevron.hidden = NO;
        chevron.image = realChevron.image;
        chevron.tintColor = realChevron.tintColor;
        chevron.contentMode = realChevron.contentMode;
        CGSize size = CGRectIsEmpty(realChevron.frame)
            ? realChevron.image.size : realChevron.frame.size;
        chevron.bounds = (CGRect){CGPointZero, size};
    } else {
        chevron.hidden = YES;
    }
    nfbSwapLayoutButton();

    // The same native menu, read fresh at every opening so the checkmarks
    // are always current; each opening arms the 2 s label belt.
    gNFBSwapOriginal = original;
    if (@available(iOS 15.0, *)) {
        button.menu = [UIMenu menuWithChildren:@[
            [UIDeferredMenuElement elementWithUncachedProvider:
                ^(void (^completion)(NSArray<UIMenuElement*>*)) {
                UIMenu* live = gNFBSwapOriginal.menu ?: gNFBSwapMenu;
                completion(live ? live.children : @[]);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(2.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    nfbSwapRefreshLabelFromMenu();
                });
            }]
        ]];
    } else {
        button.menu = menu;
    }

    // Install in the exact container the original occupied — and arm the
    // setter interception on this navigation item: from here on, stomps are
    // stopped before they reach the bar.
    objc_setAssociatedObject(nav, kNFBSwapNavKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gNFBSwapCount++;
    if (group) {
        NSMutableArray<UIBarButtonItem*>* swapped =
            [group.barButtonItems mutableCopy];
        [swapped replaceObjectAtIndex:[swapped indexOfObject:original]
                           withObject:gNFBSwapItem];
        group.barButtonItems = swapped;
    } else {
        NSMutableArray<UIBarButtonItem*>* swappedRight =
            [nav.rightBarButtonItems mutableCopy];
        [swappedRight replaceObjectAtIndex:[swappedRight indexOfObject:original]
                                withObject:gNFBSwapItem];
        nav.rightBarButtonItems = swappedRight;
    }
    NFBDebugLog(@"swap: item placed #%ld - \"%@\", menu %lu action(s) via %@, "
                @"container %@, screen %@",
                (long)gNFBSwapCount, liveTitle,
                (unsigned long)menu.children.count, menuSource,
                group ? @"groupe" : @"right",
                NSStringFromClass([vc class]));
}

%hook UINavigationItem

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    %orig(nfbSwapInterceptItems(self, items));
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items animated:(BOOL)animated {
    %orig(nfbSwapInterceptItems(self, items), animated);
}

- (void)setTrailingItemGroups:(NSArray<UIBarButtonItemGroup*>*)groups {
    if (gNFBSwapItem && objc_getAssociatedObject(self, kNFBSwapNavKey) &&
        [BHTSettings boolForKey:@"enable_liquid_glass"]) {
        if (@available(iOS 16.0, *)) {
            for (UIBarButtonItemGroup* group in groups) {
                if (group.barButtonItems.count == 1 &&
                    group.barButtonItems.firstObject != gNFBSwapItem) {
                    gNFBSwapOriginal = group.barButtonItems.firstObject;
                    gNFBSwapCount++;
                    NFBDebugLog(@"swap: intercepted at setter (group) #%ld",
                                (long)gNFBSwapCount);
                    group.barButtonItems = @[gNFBSwapItem];
                    nfbSwapRefreshLabelFromMenu();
                }
            }
        }
    }
    %orig;
}

%end

// Coming back from a conversation, the inbox is restored with the app's own
// item and the replacement waits for that view to enter a window again -
// filmed: the pill blanks for about a second on the way back. The screen
// appearing is a second signal, and the swap runs from whichever pill view is
// on the bar. Nothing happens when the item is already the tweak's.
static void nfbSwapApplyFromScreen(void) {
    Class inboxItemClass =
        NSClassFromString(@"_TtC7DMInbox39InboxNavigationBarMenuBarButtonItemView");
    if (!inboxItemClass) {
        return;
    }
    for (id scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene respondsToSelector:@selector(windows)]) {
            continue;
        }
        for (UIWindow* window in [scene windows]) {
            __block UIView* pillView = nil;
            EnumerateSubviewsRecursively(window, ^(UIView* view) {
                if (!pillView && [view isKindOfClass:inboxItemClass]) {
                    pillView = view;
                }
            });
            if (pillView) {
                nfbSwapApply(pillView);
                return;
            }
        }
    }
}

// A display link for the length of the transition: one pass per frame for
// half a second, then it stops. Cheap - each pass returns at once when the
// item on the bar is already the tweak's.
@interface NFBSwapTicker : NSObject
@property (nonatomic, strong) CADisplayLink* link;
@property (nonatomic, assign) NSTimeInterval until;
@end

@implementation NFBSwapTicker
- (void)tick {
    if ([NSDate timeIntervalSinceReferenceDate] > self.until) {
        [self.link invalidate];
        self.link = nil;
        return;
    }
    nfbSwapApplyFromScreen();
}
@end

static NFBSwapTicker* gNFBSwapTicker = nil;

static void nfbSwapWatchTransition(void) {
    if (!gNFBSwapTicker) {
        gNFBSwapTicker = [NFBSwapTicker new];
    }
    gNFBSwapTicker.until = [NSDate timeIntervalSinceReferenceDate] + 0.5;
    if (!gNFBSwapTicker.link) {
        gNFBSwapTicker.link = [CADisplayLink displayLinkWithTarget:gNFBSwapTicker
                                                          selector:@selector(tick)];
        [gNFBSwapTicker.link addToRunLoop:[NSRunLoop mainRunLoop]
                                  forMode:NSRunLoopCommonModes];
    }
}

%hook _TtC7DMInbox19InboxViewController

// The gap the reader filmed is about a quarter second wide, while the screen
// is still coming back - it opens before viewDidAppear and closes on its own.
// The swap therefore starts at viewWillAppear and runs on every frame of the
// transition, which is what covers a gap that short.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    nfbSwapApplyFromScreen();
    nfbSwapWatchTransition();
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    nfbSwapApplyFromScreen();
    nfbSwapWatchTransition();
}

%end

%hook _TtC7DMInbox39InboxNavigationBarMenuBarButtonItemView

// The original's view appearing IS the stomp signal: SwiftUI has put its
// item back, so ours goes back in. Measured cadence of this finder: ~1 ms
// after the view lands.
- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window) {
        nfbSwapApply((UIView*)self);
    }
}

- (void)layoutSubviews {
    %orig;
    nfbSwapApply((UIView*)self);
}

%end
