//
//  QuickMutedWords.x
//  PrimeFreeBird
//
//  A muted-words shortcut in the Home timeline's top bar. FLEX showed that bar
//  is a TFNNavigationBar — a stable Twitter class — even though its *contents*
//  are a SwiftUI hosting view whose name is generated at build time
//  (…$18e770d0c27PlatterContainerHostingView) and must never be hooked. So we
//  hook the bar and use the plain UINavigationBar API on its top item.
//
//  TFNNavigationBar is generic — every screen uses one — so the button is only
//  added to the instance owned by the Home timeline. If that owner can't be
//  identified the button simply never appears, exactly like the Explore
//  advanced-search button: best-effort, never destructive.
//

#import "HookHelpers.h"
#import "MutedWords/MutedWordsViewController.h"
#import <objc/message.h>

static const void* kNFBQuickMutedBtnKey = &kNFBQuickMutedBtnKey;

// Nearest view controller up the responder chain, unwrapping a navigation
// controller to the screen it is actually showing.
static UIViewController* nfbOwningViewController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if (![responder isKindOfClass:[UIViewController class]]) {
            continue;
        }
        UIViewController* controller = (UIViewController*)responder;
        if ([controller isKindOfClass:[UINavigationController class]]) {
            UIViewController* top = ((UINavigationController*)controller).topViewController;
            return top ?: controller;
        }
        return controller;
    }
    return nil;
}

static BOOL nfbIsHomeNavigationBar(UIView* bar) {
    UIViewController* owner = nfbOwningViewController(bar);
    if (!owner) {
        return NO;
    }
    NSString* name = NSStringFromClass([owner class]);
    return [name containsString:@"Home"] || [name containsString:@"Timelines"] ||
           [name containsString:@"TimelineContainer"];
}

%hook TFNNavigationBar

%new
- (void)nfbShowQuickMutedWords:(id)sender {
    UIView* bar = (UIView*)self;
    UIViewController* owner = nfbOwningViewController(bar);
    if (!owner) {
        return;
    }
    while (owner.presentedViewController) {
        owner = owner.presentedViewController;
    }

    MutedWordsViewController* editor = [[MutedWordsViewController alloc] initCompact];
    editor.modalPresentationStyle = UIModalPresentationPopover;

    UIPopoverPresentationController* popover = editor.popoverPresentationController;
    popover.delegate = (id<UIPopoverPresentationControllerDelegate>)editor;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
    UIView* anchor = [sender isKindOfClass:[UIView class]] ? (UIView*)sender : bar;
    popover.sourceView = anchor;
    popover.sourceRect = anchor.bounds;

    [owner presentViewController:editor animated:YES completion:nil];
}

// The button is a plain subview pinned to the trailing edge, re-positioned on
// every layout pass. Bar button items were tried first and never showed: this
// bar draws its contents through a full-width SwiftUI platter, so anything
// added through the navigation item can be covered or ignored. A subview is
// under our control and follows the same re-assert-on-layout pattern the
// compose button already uses.
- (void)layoutSubviews {
    %orig;

    @try {
        UIView* bar = (UIView*)self;
        if (!bar.window || !nfbIsHomeNavigationBar(bar)) {
            return;
        }

        UIButton* button = objc_getAssociatedObject(self, kNFBQuickMutedBtnKey);
        if (!button) {
            // Twitter's own "filter" glyph, from its vector library — the same
            // source as every other icon in this bar, so it matches by
            // construction. The system symbol is only a safety net if the
            // asset ever disappears.
            UIImage* icon = nil;
            if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:
                                                                 fitsSize:
                                                                fillColor:)]) {
                icon = [UIImage tfn_vectorImageNamed:@"filter"
                                            fitsSize:CGSizeMake(22.0, 22.0)
                                           fillColor:[UIColor secondaryLabelColor]];
                icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
            if (!icon) {
                icon = [UIImage systemImageNamed:@"line.3.horizontal.decrease"];
            }
            if (!icon) {
                return;
            }
            button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setImage:icon forState:UIControlStateNormal];
            button.tintColor = [UIColor secondaryLabelColor];
            button.contentMode = UIViewContentModeCenter;
            button.accessibilityLabel = @"Muted words";
            [button addTarget:self
                          action:@selector(nfbShowQuickMutedWords:)
                forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(self, kNFBQuickMutedBtnKey, button,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (button.superview != bar) {
            [bar addSubview:button];
        }
        [bar bringSubviewToFront:button];

        CGFloat side = 34.0;
        CGFloat inset = 16.0;   // même marge que l'avatar à gauche
        button.frame = CGRectMake(CGRectGetWidth(bar.bounds) - side - inset,
                                  (CGRectGetHeight(bar.bounds) - side) / 2.0,
                                  side, side);
    } @catch (id exception) {
    }
}

%end
