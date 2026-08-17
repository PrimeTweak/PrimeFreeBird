// PillCompat.x — the "All" pill leaves Liquid Glass, at the source.
//
// His idea, his words: "Pourquoi ne pas désactiver Liquid Glass dans ce
// bouton uniquement ?" Since iOS 26 the switch exists officially, per bar
// button: UIBarButtonItem.hidesSharedBackground removes the glass background
// of ONE item and leaves the rest of the app alone. Every covering strategy
// fought the platter machinery from the outside; this asks the machinery to
// let go of this one control.
//
// This is a MEASUREMENT build with one unknown, stated up front: does taking
// the glass off the item also take its content out of the destroy/recreate
// hosting (the measured cause of the flash), or does it only undress it?
// The journal answers that on its own — the 0.6 s platter check below and
// the ⌚ watch tell the story in one capture:
//   · "pillcompat: verre retiré sur N item(s)"        the switch landed
//   · "pillcompat: platine ABSENTE — sorti de la machine"   the win
//   · "pillcompat: platine ENCORE présente (…)"       undressed only
//   · "pillcompat: hidesSharedBackground ABSENT"      no switch on this OS
// Nothing here draws, covers or moves anything: one property, plus receipts.
//
// The SDK this repo builds against predates the switch, so the property is
// reached by name at runtime (NSSelectorFromString + KVC), guarded, and its
// absence is journaled — never fatal, never a compile-time dependency.

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// Keys are addresses; the strings are only for reading the binary.
static const char* kNFBPillCompatDoneKey = "nfbPillCompatDone";
static const char* kNFBPillCompatMissKey = "nfbPillCompatMiss";

static UIViewController* nfbPillCompatOwningVC(UIView* view) {
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

// Every trailing item the navigation item exposes, classic list and iOS 16
// groups alike — on Messages the "All" pill is the only one, and the journal
// prints the count so that assumption is checked, not trusted.
static NSArray<UIBarButtonItem*>* nfbPillCompatTrailingItems(UINavigationItem* nav) {
    NSMutableArray<UIBarButtonItem*>* all = [NSMutableArray array];
    if (nav.rightBarButtonItems.count) {
        [all addObjectsFromArray:nav.rightBarButtonItems];
    }
    if (@available(iOS 16.0, *)) {
        for (UIBarButtonItemGroup* group in nav.trailingItemGroups) {
            for (UIBarButtonItem* item in group.barButtonItems) {
                if (![all containsObject:item]) {
                    [all addObject:item];
                }
            }
        }
    }
    return all;
}

static void nfbPillCompatApply(UIView* pill) {
    if (!pill.window) {
        return;
    }
    if (objc_getAssociatedObject(pill, kNFBPillCompatDoneKey)) {
        return;
    }

    UIViewController* vc = nfbPillCompatOwningVC(pill);
    if (!vc) {
        if (!objc_getAssociatedObject(pill, kNFBPillCompatMissKey)) {
            objc_setAssociatedObject(pill, kNFBPillCompatMissKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NFBDebugLog(@"pillcompat: aucun controleur dans la chaine <%p>", pill);
        }
        return;
    }
    NSArray<UIBarButtonItem*>* items =
        nfbPillCompatTrailingItems(vc.navigationItem);
    if (!items.count) {
        // The bridge can attach its items a beat after the view lands; every
        // later layout retries. Named once so a permanent miss leaves a trace.
        if (!objc_getAssociatedObject(pill, kNFBPillCompatMissKey)) {
            objc_setAssociatedObject(pill, kNFBPillCompatMissKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NFBDebugLog(@"pillcompat: items pas encore la (ecran=%@) — on ressaie",
                        NSStringFromClass([vc class]));
        }
        return;
    }

    SEL setter = NSSelectorFromString(@"setHidesSharedBackground:");
    SEL getter = NSSelectorFromString(@"hidesSharedBackground");
    NSInteger applied = 0;
    NSInteger already = 0;
    NSInteger index = 0;
    for (UIBarButtonItem* item in items) {
        BOOL supports = [item respondsToSelector:setter] &&
                        [item respondsToSelector:getter];
        if (!supports) {
            NFBDebugLog(@"pillcompat: item %ld %@ — hidesSharedBackground ABSENT",
                        (long)index, NSStringFromClass([item classForCoder]));
            index++;
            continue;
        }
        BOOL before = [[item valueForKey:@"hidesSharedBackground"] boolValue];
        if (before) {
            already++;
        } else {
            NSString* customView = item.customView
                ? NSStringFromClass([item.customView classForCoder])
                : @"-";
            NFBDebugLog(@"pillcompat: item %ld %@ customView=%@ verre_cache avant=non",
                        (long)index, NSStringFromClass([item classForCoder]),
                        customView);
            [item setValue:@YES forKey:@"hidesSharedBackground"];
            applied++;
        }
        index++;
    }

    if (!applied && !already) {
        // No item on this OS carries the switch: measured, closed, no spam.
        objc_setAssociatedObject(pill, kNFBPillCompatDoneKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(pill, kNFBPillCompatDoneKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (applied) {
        NFBDebugLog(@"pillcompat: verre retiré sur %ld item(s) — ecran=%@",
                    (long)applied, NSStringFromClass([vc class]));
        NFBMark(pill, @"PillCompat/verre retiré");
    } else {
        NFBDebugLog(@"pillcompat: deja applique (instance <%p>)", pill);
    }

    // The direct answer to the one unknown: is the glass platter still an
    // ancestor once the change has settled? Asked once per applied instance.
    if (applied) {
        __weak UIView* weakPill = pill;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView* live = weakPill;
            if (!live || !live.window) {
                NFBDebugLog(@"pillcompat: pill remplacé avant la vérif platine "
                            @"(la machine a reconstruit — attendu)");
                return;
            }
            UIView* node = live.superview;
            NSInteger depth = 0;
            NSString* found = nil;
            while (node && depth < 32) {
                NSString* cls = NSStringFromClass([node classForCoder]);
                if ([cls containsString:@"PlatformGlass"] ||
                    [cls containsString:@"Platter"]) {
                    found = cls;
                    break;
                }
                node = node.superview;
                depth++;
            }
            if (found) {
                NFBDebugLog(@"pillcompat: platine ENCORE présente (%@) — verre parti, machine pas sortie",
                            found);
            } else {
                NFBDebugLog(@"pillcompat: platine ABSENTE — sorti de la machine");
            }
        });
    }
}

%hook _TtC7DMInbox39InboxNavigationBarMenuBarButtonItemView

- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window) {
        nfbPillCompatApply((UIView*)self);
    }
}

- (void)layoutSubviews {
    %orig;
    nfbPillCompatApply((UIView*)self);
}

%end
