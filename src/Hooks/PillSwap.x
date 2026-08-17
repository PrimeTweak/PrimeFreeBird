// PillSwap.x — the "All" pill, rebuilt as a button nobody destroys.
//
// His call, his spec: « Fais un bouton identique au natif. » The measured
// story (project journal, 16-17/08): under forced Liquid Glass the SwiftUI
// bridge destroys and recreates the DMInbox trailing item on every pass —
// that rebuild IS the flash. The avatar, in the same bar under the same
// glass, never moves: the glass is innocent, the rebuild is the culprit.
// So the SwiftUI item is swapped for OUR plain UIBarButtonItem the moment
// it shows up: same typography (copied live from the real label), same
// chevron (copied), same paddings (measured: content + 10 pt sides inside
// a 40 pt row), same glass (UIKit's own default treatment — nothing about
// backgrounds is touched, per « identique au natif »), and the SAME native
// UIMenu (Twitter's object, reused — tap opens the real All/Requests menu,
// their handlers run). When SwiftUI stomps the items back on a later pass,
// the stomp itself is our signal: the original's view fires our hook, we
// swap again (~1 ms, measured cadence of the finder) and refresh the label
// from the menu's checked state — Twitter's own re-render keeps us in sync.
//
// Two unknowns, journaled loudly rather than assumed:
//   · does the bridge item carry its UIMenu? If not: « menu original
//     ABSENT — abandon », native stays, nothing broken.
//   · does the label follow a filter change? The stomp should carry it;
//     a 2 s belt after each menu opening re-reads the checked state.
// Every action has its line; removal is `git rm` of this one file.

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// A named subclass so captures and the watch can identify our button.
@interface NFBInboxPillButton : UIButton
@end
@implementation NFBInboxPillButton
@end

// Our item (built once, reused across stomps) and the latest original from
// Twitter (strong: it left the bar, but its menu must stay alive for ours).
static UIBarButtonItem*  gNFBSwapItem;
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
    button.bounds = CGRectMake(0, 0, width, 40.0);
    CGFloat x = 10.0;
    label.frame = CGRectMake(x, (40.0 - label.bounds.size.height) / 2.0,
                             label.bounds.size.width, label.bounds.size.height);
    if (!chevron.hidden) {
        chevron.frame = CGRectMake(x + label.bounds.size.width + spacing,
                                   (40.0 - chevron.bounds.size.height) / 2.0,
                                   chevron.bounds.size.width,
                                   chevron.bounds.size.height);
    }
}

// Belt for the label after a menu pick: the stomp normally carries the new
// state, this re-read covers a bridge that would not stomp.
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
        NFBDebugLog(@"remplacement: libelle -> %@ (menu)", checked);
    }
}

// v2 — measured on the 06:41 video: the residual flash was OUR OWN swap.
// On every return SwiftUI re-sets its item; it lands EMPTY for ~150 ms (the
// rebuilt content arrives late — the original disease), then our swap-back
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
    NFBDebugLog(@"remplacement: intercepté au setter #%ld", (long)gNFBSwapCount);
    nfbSwapRefreshLabelFromMenu();
    return @[gNFBSwapItem];
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
        if (candidateNav.rightBarButtonItems.count || candidateNav.trailingItemGroups.count) {
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
    if (!realLabel || !liveTitle.length) {
        static const char* kNFBSwapWaitKey = "nfbSwapWait";
        if (!objc_getAssociatedObject(pillView, kNFBSwapWaitKey)) {
            objc_setAssociatedObject(pillView, kNFBSwapWaitKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NFBDebugLog(@"remplacement: attente contenu — on ressaie");
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
            NFBDebugLog(@"remplacement: menu INTROUVABLE — sonde: lignee=%@ | "
                        @"interactions=%@ | primaryAction=%@",
                        [lineage componentsJoinedByString:@" < "],
                        interactions.count
                            ? [interactions componentsJoinedByString:@","] : @"-",
                        original.primaryAction
                            ? NSStringFromClass([original.primaryAction class])
                            : @"nil");
        }
        return;  // natif conservé, la sonde a parlé
    }
    gNFBSwapMenu = menu;  // strong: it must outlive the mortal native button

    // Build ours once; later passes only refresh content and re-install.
    NFBInboxPillButton* button;
    UILabel* label;
    UIImageView* chevron;
    if (!gNFBSwapItem) {
        button = [NFBInboxPillButton new];
        label = [UILabel new];
        label.tag = 1;
        [button addSubview:label];
        chevron = [UIImageView new];
        chevron.tag = 2;
        [button addSubview:chevron];
        button.showsMenuAsPrimaryAction = YES;
        gNFBSwapItem = [[UIBarButtonItem alloc] initWithCustomView:button];
        NFBMark(button, @"PillSwap/bouton maison — identique au natif");
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
        NSMutableArray<UIBarButtonItem*>* swapped =
            [nav.rightBarButtonItems mutableCopy];
        [swapped replaceObjectAtIndex:[swapped indexOfObject:original]
                           withObject:gNFBSwapItem];
        nav.rightBarButtonItems = swapped;
    }
    NFBDebugLog(@"remplacement: item posé #%ld — « %@ », menu %lu action(s) via %@, "
                @"conteneur %@, écran %@",
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
                    NFBDebugLog(@"remplacement: intercepté au setter (groupe) #%ld",
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
