// The inbox "All" pill rebuilt as a plain UIBarButtonItem, so the app's SwiftUI
// rebuild never flashes it. Same look, same native menu.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

// A named subclass, so captures can identify the button. The bar's item wrapper
// clamps its child to the standard bar-button box, so the capsule is drawn
// larger than the button, anchored to its right edge, and the touch area follows.
@interface PFBInboxPillButton : UIButton
@property (nonatomic, assign) CGSize pfbIntrinsic;
@property (nonatomic, assign) CGRect pfbTouchRect;
@property (nonatomic, assign) CGFloat pfbPillWidth;   // target capsule width
@property (nonatomic, assign) CGFloat pfbSpacing;     // label ↔ chevron
@end
@implementation PFBInboxPillButton

- (CGSize)intrinsicContentSize {
    if (self.pfbIntrinsic.width > 0) {
        return self.pfbIntrinsic;
    }
    return [super intrinsicContentSize];
}

// The geometry is laid out from the bounds the wrapper actually hands over, on
// every resize: the capsule's right edge is the box's right edge, its left edge
// the native pill's width to the left of it.
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.pfbPillWidth <= 0) {
        return;
    }
    CGFloat height = 40.0;
    CGRect box = self.bounds;
    CGRect capsuleFrame = CGRectMake(box.size.width - self.pfbPillWidth,
                                     (box.size.height - height) / 2.0,
                                     self.pfbPillWidth, height);
    self.pfbTouchRect = capsuleFrame;

    // Resolved on every pass: a CGColor does not follow a trait change on its
    // own, and the bar is drawn in both appearances.
    UIView* ring = [self viewWithTag:3];
    if (ring) {
        ring.frame = capsuleFrame;
        ring.layer.cornerRadius = height / 2.0;
        UIColor* hairline =
            [[[UIColor labelColor]
                resolvedColorWithTraitCollection:self.traitCollection]
                colorWithAlphaComponent:0.14];
        ring.layer.borderColor = hairline.CGColor;
    }

    UILabel* label = (UILabel*)[self viewWithTag:1];
    UIImageView* chevron = (UIImageView*)[self viewWithTag:2];
    CGFloat x = capsuleFrame.origin.x + 10.0;
    CGFloat midY = CGRectGetMidY(capsuleFrame);
    label.frame = CGRectMake(x, midY - label.bounds.size.height / 2.0,
                             label.bounds.size.width, label.bounds.size.height);
    if (!chevron.hidden) {
        chevron.frame = CGRectMake(x + label.bounds.size.width + self.pfbSpacing,
                                   midY - chevron.bounds.size.height / 2.0,
                                   chevron.bounds.size.width,
                                   chevron.bounds.size.height);
    }
}

// The visible pill spills outside bounds; a tap anywhere on it must count.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    if (!CGRectIsEmpty(self.pfbTouchRect)) {
        return CGRectContainsPoint(self.pfbTouchRect, point);
    }
    return [super pointInside:point withEvent:event];
}
@end

// The tweak's item (built once, reused across stomps) and the latest original from
// Twitter (strong: it left the bar, but its menu must stay alive for the replacement).
static UIBarButtonItem*  gPFBSwapItem;
// Horizontal nudge of the pill: negative moves it left, positive right. A visual
// translation only, which layout never fights.
static CGFloat           gPFBSwapShift = 0.0;
static UIBarButtonItem*  gPFBSwapOriginal;
static UIMenu*           gPFBSwapMenu;   // harvested from the live control; outlives it
static NSInteger         gPFBSwapCount;
static const char*       kPFBSwapNavKey = "pfbSwapNav";

static UIViewController* pfbSwapOwningVC(UIView* view) {
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

// A bar button's responder chain stops at the navigation controller; the items
// live one level down (the chat view controller holds the trailing item).
static NSArray<UIViewController*>* pfbSwapCandidates(UIViewController* vc) {
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

// The button class is shared across screens, so only the inbox's own is swapped.
static BOOL pfbSwapIsInbox(UIViewController* vc) {
    for (UIViewController* candidate in pfbSwapCandidates(vc)) {
        if ([NSStringFromClass([candidate class]) containsString:@"Inbox"]) {
            return YES;
        }
    }
    return NO;
}

// The checked entry of the menu is the truthful, localized label source
// ("All" / "Requests" with Twitter's own wording).
static NSString* pfbSwapCheckedTitle(UIMenu* menu) {
    for (UIMenuElement* element in menu.children) {
        if ([element isKindOfClass:[UIAction class]]) {
            UIAction* action = (UIAction*)element;
            if (action.state == UIMenuElementStateOn && action.title.length) {
                return action.title;
            }
        } else if ([element isKindOfClass:[UIMenu class]]) {
            NSString* nested = pfbSwapCheckedTitle((UIMenu*)element);
            if (nested) {
                return nested;
            }
        }
    }
    return nil;
}

// Native paddings, measured on the real thing: content sits at x=10 in a
// row 20 pt wider than it, centered in 40 pt of height (stack 37.33x16 at
// {10, 12} inside 57.33x40).
static void pfbSwapLayoutButton(void) {
    PFBInboxPillButton* button = (PFBInboxPillButton*)gPFBSwapItem.customView;
    UILabel* label = (UILabel*)[button viewWithTag:1];
    UIImageView* chevron = (UIImageView*)[button viewWithTag:2];
    [label sizeToFit];
    CGFloat spacing = (chevron.hidden || chevron.bounds.size.width <= 0) ? 0 : 4.0;
    CGFloat contentW = label.bounds.size.width + spacing + (chevron.hidden ? 0 : chevron.bounds.size.width);
    CGFloat width = contentW + 20.0;
    CGFloat height = 40.0;
    // Content sizes only. WHERE it all goes is decided in -layoutSubviews,
    // which runs again every time the wrapper changes the box.
    button.pfbPillWidth = width;
    button.pfbSpacing = spacing;
    button.pfbIntrinsic = CGSizeMake(width, height);
    [button invalidateIntrinsicContentSize];
    button.clipsToBounds = NO;
    button.transform = CGAffineTransformMakeTranslation(gPFBSwapShift, 0);
    [button setNeedsLayout];
    [button layoutIfNeeded];
}

// Belt for the label after a menu pick: the stomp normally carries the new
// state, this re-read covers a bridge that would not stomp.
static void pfbSwapRefreshLabelFromMenu(void) {
    UIMenu* live = gPFBSwapOriginal.menu ?: gPFBSwapMenu;
    if (!gPFBSwapItem || !live) {
        return;
    }
    NSString* checked = pfbSwapCheckedTitle(live);
    if (!checked.length) {
        return;
    }
    PFBInboxPillButton* button = (PFBInboxPillButton*)gPFBSwapItem.customView;
    UILabel* label = (UILabel*)[button viewWithTag:1];
    if (![label.text isEqualToString:checked]) {
        label.text = checked;
        pfbSwapLayoutButton();
        PFBDebugLog(@"[swap] label -> %@ (menu)", checked);
    }
}

// After the bootstrap the stomp is intercepted at the setter, before anything
// reaches the bar: the incoming foreign item is read (fresh menu, fresh checked
// state) and the tweak's item goes through in its place, so nothing re-hosts.
static NSArray<UIBarButtonItem*>* pfbSwapInterceptItems(UINavigationItem* nav,
                                                        NSArray<UIBarButtonItem*>* items) {
    if (!gPFBSwapItem || items.count != 1 ||
        !objc_getAssociatedObject(nav, kPFBSwapNavKey)) {
        return items;
    }
    UIBarButtonItem* incoming = items.firstObject;
    if (incoming == gPFBSwapItem) {
        return items;
    }
    if (![PFBSettings boolForKey:@"enable_liquid_glass"]) {
        return items;
    }
    gPFBSwapOriginal = incoming;
    gPFBSwapCount++;
    pfbSwapRefreshLabelFromMenu();
    return @[gPFBSwapItem];
}

static void pfbSwapApply(UIView* pillView) {
    if (!pillView.window) {
        return;
    }
    if (![PFBSettings boolForKey:@"enable_liquid_glass"]) {
        return;  // standard interface never had the problem — nothing to do
    }

    UIViewController* vc = pfbSwapOwningVC(pillView);
    if (!vc || !pfbSwapIsInbox(vc)) {
        return;
    }

    // Locate the holder and the original among its trailing items. Ours is
    // recognized by pointer; anything else in trailing position is Twitter's.
    UINavigationItem* nav = nil;
    UIBarButtonItem* original = nil;
    UIBarButtonItemGroup* group = nil;
    for (UIViewController* candidate in pfbSwapCandidates(vc)) {
        UINavigationItem* candidateNav = candidate.navigationItem;
        for (UIBarButtonItem* item in candidateNav.rightBarButtonItems) {
            if (item != gPFBSwapItem) {
                nav = candidateNav;
                original = item;
                break;
            }
        }
        if (!original) {
            if (@available(iOS 16.0, *)) {
                for (UIBarButtonItemGroup* candidateGroup in candidateNav.trailingItemGroups) {
                    for (UIBarButtonItem* item in candidateGroup.barButtonItems) {
                        if (item != gPFBSwapItem) {
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
            // Only the tweak's item is installed - nothing to swap on this pass.
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
        static const char* kPFBSwapWaitKey = "pfbSwapWait";
        if (!objc_getAssociatedObject(pillView, kPFBSwapWaitKey)) {
            objc_setAssociatedObject(pillView, kPFBSwapWaitKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PFBDebugLog(@"[swap] waiting for content - retrying");
        }
        return;  // content not built yet; the next layout retries
    }

    // The bridge item carries no menu; the pill is (or contains) a real UIButton
    // with showsMenuAsPrimaryAction, so the menu is harvested from that control.
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
        PFBDebugLog(@"[swap] menu not found on the native item - native kept");
        return;
    }
    gPFBSwapMenu = menu;  // strong: it must outlive the mortal native button

    // Built once; later passes only refresh content and re-install.
    PFBInboxPillButton* button;
    UILabel* label;
    UIImageView* chevron;
    if (!gPFBSwapItem) {
        // Custom type: a system button gets its own glass configuration on iOS 26
        // (a stray inner lens); a custom button draws nothing.
        button = (PFBInboxPillButton*)
            [PFBInboxPillButton buttonWithType:UIButtonTypeCustom];
        label = [UILabel new];
        label.tag = 1;
        [button addSubview:label];
        chevron = [UIImageView new];
        chevron.tag = 2;
        [button addSubview:chevron];

        // The native capsule outline, kept without its glass: a hairline ring
        // on the capsule rect, never a filled color.
        UIView* ring = [UIView new];
        ring.tag = 3;
        ring.userInteractionEnabled = NO;
        ring.backgroundColor = [UIColor clearColor];
        ring.layer.borderWidth = 1.0;
        [button insertSubview:ring atIndex:0];

        button.showsMenuAsPrimaryAction = YES;
        // No capsule behind the label: the navigation bar shows glass nowhere
        // else (gear, avatar), so the replacement is flat label and chevron.
        gPFBSwapItem = [[UIBarButtonItem alloc] initWithCustomView:button];
        // On a plain UIKit item the per-item switch does what it is meant to: it
        // removes the circular default treatment.
        if ([gPFBSwapItem respondsToSelector:
                NSSelectorFromString(@"setHidesSharedBackground:")]) {
            [gPFBSwapItem setValue:@YES forKey:@"hidesSharedBackground"];
        }
        PFBMark(button, @"PillSwap/custom button - identical to native");
    } else {
        button = (PFBInboxPillButton*)gPFBSwapItem.customView;
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
    pfbSwapLayoutButton();

    // The same native menu, read fresh at every opening so the checkmarks
    // are always current; each opening arms the 2 s label belt.
    gPFBSwapOriginal = original;
    if (@available(iOS 15.0, *)) {
        button.menu = [UIMenu menuWithChildren:@[
            [UIDeferredMenuElement elementWithUncachedProvider:
                ^(void (^completion)(NSArray<UIMenuElement*>*)) {
                UIMenu* live = gPFBSwapOriginal.menu ?: gPFBSwapMenu;
                completion(live ? live.children : @[]);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(2.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    pfbSwapRefreshLabelFromMenu();
                });
            }]
        ]];
    } else {
        button.menu = menu;
    }

    // Install in the exact container the original occupied — and arm the
    // setter interception on this navigation item: from here on, stomps are
    // stopped before they reach the bar.
    objc_setAssociatedObject(nav, kPFBSwapNavKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gPFBSwapCount++;
    if (group) {
        NSMutableArray<UIBarButtonItem*>* swapped =
            [group.barButtonItems mutableCopy];
        [swapped replaceObjectAtIndex:[swapped indexOfObject:original]
                           withObject:gPFBSwapItem];
        group.barButtonItems = swapped;
    } else {
        NSMutableArray<UIBarButtonItem*>* swappedRight =
            [nav.rightBarButtonItems mutableCopy];
        [swappedRight replaceObjectAtIndex:[swappedRight indexOfObject:original]
                                withObject:gPFBSwapItem];
        nav.rightBarButtonItems = swappedRight;
    }
    PFBDebugLog(@"[swap] item placed #%ld - \"%@\", menu %lu action(s) via %@, "
                @"container %@, screen %@",
                (long)gPFBSwapCount, liveTitle,
                (unsigned long)menu.children.count, menuSource,
                group ? @"groupe" : @"right",
                NSStringFromClass([vc class]));
    PFBCOMPAT_ACTION(PFBCompat_enable_liquid_glass, @"inbox pill placed");
}

// The navigation bar carries no glass. Forcing the iOS 26 design switches on
%hook UINavigationItem

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items {
    %orig(pfbSwapInterceptItems(self, items));
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem*>*)items animated:(BOOL)animated {
    %orig(pfbSwapInterceptItems(self, items), animated);
}

- (void)setTrailingItemGroups:(NSArray<UIBarButtonItemGroup*>*)groups {
    if (gPFBSwapItem && objc_getAssociatedObject(self, kPFBSwapNavKey) &&
        [PFBSettings boolForKey:@"enable_liquid_glass"]) {
        if (@available(iOS 16.0, *)) {
            for (UIBarButtonItemGroup* group in groups) {
                if (group.barButtonItems.count == 1 &&
                    group.barButtonItems.firstObject != gPFBSwapItem) {
                    gPFBSwapOriginal = group.barButtonItems.firstObject;
                    gPFBSwapCount++;
                    group.barButtonItems = @[gPFBSwapItem];
                    pfbSwapRefreshLabelFromMenu();
                }
            }
        }
    }
    %orig;
}

%end

// The inbox filter pill, a TFNUISwift class.
%hook _TtC10TFNUISwift34NavigationBarMenuBarButtonItemView

// The original's view appearing is the stomp signal: SwiftUI has put its item
// back, so the tweak's goes back in, about 1 ms after the view lands.
- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window) {
        pfbSwapApply((UIView*)self);
    }
}

- (void)layoutSubviews {
    %orig;
    pfbSwapApply((UIView*)self);
}

%end
