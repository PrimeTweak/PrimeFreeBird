// The inbox "All" pill rebuilt as a plain UIBarButtonItem, so the app's SwiftUI
// rebuild never flashes it. Same look, same native menu.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

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

// The replacement item (built once, reused across stomps) and the latest original from
// Twitter (strong: it left the bar, but its menu must stay alive for the replacement).
static UIBarButtonItem*  gPFBSwapItem;
static UIBarButtonItem*  gPFBSwapOriginal;
static UIMenu*           gPFBSwapMenu;   // harvested from the live control; outlives it
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

// MARK: - Probe

// Probe: a bar item named without its title: custom view class, action and menu.
static NSString* pfbProbeSwapItem(UIBarButtonItem* item) {
    if (!item) {
        return @"none";
    }
    BOOL menu = item.menu != nil ||
                ([item.customView isKindOfClass:[UIButton class]] && ((UIButton*)item.customView).menu != nil);
    return [NSString stringWithFormat:@"%@, %@, has menu %@",
                                      item.customView ? PFBProbeClassName(item.customView) : @"no custom view",
                                      item.action ? NSStringFromSelector(item.action) : @"no action", menu ? @"yes" : @"no"];
}

// Probe: the screen in front of a navigation stack.
static UIViewController* pfbProbeSwapTop(UIViewController* vc) {
    return [vc isKindOfClass:[UINavigationController class]] ? ((UINavigationController*)vc).topViewController : vc;
}

// Probe: how a candidate stands to the pill's controller.
static NSString* pfbProbeSwapRelation(UIViewController* vc, UIViewController* candidate) {
    if (candidate == vc) {
        return @"the pill's own controller";
    }
    if (![vc isKindOfClass:[UINavigationController class]]) {
        return @"?";
    }
    UINavigationController* stack = (UINavigationController*)vc;
    if (candidate == stack.topViewController) {
        return @"top";
    }
    if (candidate.parentViewController == stack.topViewController) {
        return @"child of top";
    }
    NSUInteger index = [stack.viewControllers indexOfObject:candidate];
    return index == NSNotFound ? @"?"
                               : [NSString stringWithFormat:@"stacked at depth %lu",
                                                            (unsigned long)(stack.viewControllers.count - 1 - index)];
}

// Probe: the swap as installed, once per screen in front (at most 6).
enum { kPFBProbeSwapScreenLimit = 6 };
static BOOL gPFBProbeSwapDone;
static __unsafe_unretained Class gPFBProbeSwapScreens[kPFBProbeSwapScreenLimit];
static NSUInteger gPFBProbeSwapScreenCount;
static void pfbProbeSwapTarget(UIView* pillView, UIViewController* vc, UINavigationItem* nav, UIBarButtonItem* original,
                               UIBarButtonItemGroup* group) {
    if (gPFBProbeSwapDone || !PFBDebugIsRecording()) {
        return;
    }
    UIViewController* top = pfbProbeSwapTop(vc);
    Class topClass = top ? [top class] : Nil;
    for (NSUInteger i = 0; i < gPFBProbeSwapScreenCount; i++) {
        if (gPFBProbeSwapScreens[i] == topClass) {
            return;
        }
    }
    gPFBProbeSwapScreens[gPFBProbeSwapScreenCount++] = topClass;
    gPFBProbeSwapDone = gPFBProbeSwapScreenCount >= kPFBProbeSwapScreenLimit;
    UIViewController* matched = nil;
    UIViewController* holder = nil;
    for (UIViewController* candidate in pfbSwapCandidates(vc)) {
        if (!matched && [NSStringFromClass([candidate class]) containsString:@"Inbox"]) {
            matched = candidate;
        }
        if (!holder && candidate.navigationItem == nav) {
            holder = candidate;
        }
    }
    NSString* hosts = original.customView ? ([pillView isDescendantOfView:original.customView] ? @"yes" : @"no") : @"?";
    PFBProbeNote([@"10b#F029 swap " stringByAppendingString:PFBProbeClassName(top)],
                 @"10b#F029 pill swap: pill view on %@, matched Inbox on %@ (%@) · original %@, holds the pill %@, "
                 @"in %@ of %@",
                 PFBProbeClassName(top), PFBProbeClassName(matched), matched ? pfbProbeSwapRelation(vc, matched) : @"-",
                 pfbProbeSwapItem(original), hosts, group ? @"trailing group" : @"right items", PFBProbeClassName(holder));
}

// Probe: a pill view the swap leaves alone, once per screen in front (at most 6, over 300 passes).
static BOOL gPFBProbeSwapAloneDone;
static __unsafe_unretained Class gPFBProbeSwapAloneScreens[kPFBProbeSwapScreenLimit];
static NSUInteger gPFBProbeSwapAloneCount;
static NSUInteger gPFBProbeSwapAlonePasses;
static void pfbProbeSwapLeftAlone(UIViewController* vc) {
    if (gPFBProbeSwapAloneDone || !PFBDebugIsRecording()) {
        return;
    }
    gPFBProbeSwapAloneDone = ++gPFBProbeSwapAlonePasses >= 300;
    UIViewController* top = pfbProbeSwapTop(vc);
    Class topClass = top ? [top class] : Nil;
    for (NSUInteger i = 0; i < gPFBProbeSwapAloneCount; i++) {
        if (gPFBProbeSwapAloneScreens[i] == topClass) {
            return;
        }
    }
    gPFBProbeSwapAloneScreens[gPFBProbeSwapAloneCount++] = topClass;
    gPFBProbeSwapAloneDone = gPFBProbeSwapAloneDone || gPFBProbeSwapAloneCount >= kPFBProbeSwapScreenLimit;
    PFBProbeNote([@"10b#F029 alone " stringByAppendingString:PFBProbeClassName(top)],
                 @"10b#F029 pill view on %@: left alone", top ? PFBProbeClassName(top) : @"no controller");
}

// Probe: a single incoming item replaced on the armed navigation item, once per kind
// (at most 4, over 200 replacements).
static BOOL gPFBProbeSwapInterceptDone;
static NSUInteger gPFBProbeSwapInterceptNotes;
static NSUInteger gPFBProbeSwapInterceptPasses;
static void pfbProbeSwapIntercepted(UIBarButtonItem* incoming, NSString* container) {
    if (gPFBProbeSwapInterceptDone || !PFBDebugIsRecording() || !NSThread.isMainThread) {
        return;
    }
    gPFBProbeSwapInterceptDone = ++gPFBProbeSwapInterceptPasses >= 200;
    NSString* item = pfbProbeSwapItem(incoming);
    NSString* key = [NSString stringWithFormat:@"10b#F029 intercepted %@ %@", container, item];
    if (!PFBProbeWants(key)) {
        return;
    }
    PFBProbeNote(key, @"10b#F029 pill swap: intercepted single item %@ in %@ on the armed item while %@ is shown", item,
                 container, PFBProbeFrontScreen());
    gPFBProbeSwapInterceptDone = gPFBProbeSwapInterceptDone || ++gPFBProbeSwapInterceptNotes >= 4;
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

// Native paddings: content sits at x=10 in a row 20 pt wider than it, centered in
// 40 pt of height (stack 37.33x16 at {10, 12} inside 57.33x40).
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
    button.transform = CGAffineTransformIdentity;
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
    }
}

// After the bootstrap the stomp is intercepted at the setter, before anything reaches
// the bar: the incoming item is read (fresh menu, fresh checked state) and the replacement
// goes through in its place, so nothing re-hosts.
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
    pfbProbeSwapIntercepted(incoming, @"right items");
    gPFBSwapOriginal = incoming;
    pfbSwapRefreshLabelFromMenu();
    return @[gPFBSwapItem];
}

static void pfbSwapApply(UIView* pillView) {
    if (!pillView.window) {
        return;
    }
    if (![PFBSettings boolForKey:@"enable_liquid_glass"]) {
        return;  // the standard interface keeps the native pill
    }

    UIViewController* vc = pfbSwapOwningVC(pillView);
    if (!vc || !pfbSwapIsInbox(vc)) {
        pfbProbeSwapLeftAlone(vc);
        return;
    }

    // Locates the holder and the original among its trailing items. The replacement is
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
            // Only the replacement is installed: nothing to swap on this pass.
            return;
        }
    }
    if (!original) {
        return;  // items not attached yet; the next layout retries
    }

    // The native content, read live from the original pill (stack -> label + chevron).
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
        return;  // content not built yet; the next layout retries
    }

    // The bridge item carries no menu; the pill is (or contains) a real UIButton
    // with showsMenuAsPrimaryAction, so the menu is harvested from that control.
    UIMenu* menu = original.menu;
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
        // No glass behind the label: the navigation bar shows glass nowhere
        // else (gear, avatar), so the replacement is ring, label and chevron.
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

    // Install in the exact container the original occupied — and arm the
    // setter interception on this navigation item: from here on, stomps are
    // stopped before they reach the bar.
    pfbProbeSwapTarget(pillView, vc, nav, original, group);
    objc_setAssociatedObject(nav, kPFBSwapNavKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    PFBCOMPAT_ACTION(PFBCompat_enable_liquid_glass, @"inbox pill placed");
}

// On the armed inbox navigation item, the setters replace an incoming single item
// with the replacement pill.
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
                    pfbProbeSwapIntercepted(group.barButtonItems.firstObject, @"trailing group");
                    gPFBSwapOriginal = group.barButtonItems.firstObject;
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

// The original's view appearing is the stomp signal: SwiftUI has put its item back,
// so the replacement goes back in, about 1 ms after the view lands.
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
