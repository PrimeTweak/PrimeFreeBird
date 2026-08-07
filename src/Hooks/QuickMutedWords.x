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
// The avatar is the square view furthest to the left of the bar. Using it as
// the reference makes our button match Twitter's own vertical rhythm and
// horizontal margin, whatever the bar's height happens to be.
static UIView* nfbFindAvatarView(UIView* view, UIView* bar) {
    UIView* best = nil;
    CGFloat bestX = CGFLOAT_MAX;
    for (UIView* subview in view.subviews) {
        CGRect inBar = [subview convertRect:subview.bounds toView:bar];
        CGFloat w = CGRectGetWidth(inBar);
        CGFloat h = CGRectGetHeight(inBar);
        BOOL squarish = (w > 24.0 && w < 44.0 && fabs(w - h) < 2.0);
        if (squarish && CGRectGetMinX(inBar) < CGRectGetWidth(bar.bounds) * 0.25 &&
            CGRectGetMinX(inBar) < bestX) {
            bestX = CGRectGetMinX(inBar);
            best = subview;
        }
        UIView* deeper = nfbFindAvatarView(subview, bar);
        if (deeper) {
            CGRect deepRect = [deeper convertRect:deeper.bounds toView:bar];
            if (CGRectGetMinX(deepRect) < bestX) {
                bestX = CGRectGetMinX(deepRect);
                best = deeper;
            }
        }
    }
    return best;
}

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

// One grey for every icon we add, frozen to a static colour. The gear is
// dimmed to 60% opacity because its glyph refuses to be tinted, so our own
// icons use the label colour at the same 60% — the two then match exactly.
// Resolving it here also stops the theme's window tint from claiming the icon
// on a cold launch, a trap the colour work already taught us.
static UIColor* NFBBarIconGrey(UITraitCollection* traits) {
    // Resolved to a concrete colour: a dynamic one handed to Twitter's vector
    // renderer came back black, and let the theme claim it later.
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// Renders a glyph into a flat grey bitmap. Every colour route we tried was
// reclaimed by something: the tint by the theme when the bar re-appears, the
// alpha by the button's own highlight after a tap, and Twitter's fillColor
// comes back black. A colour burnt into the pixels survives all three.
// Twitter's filter_bars drawn one weight heavier. The library has no bold
// variant of it, and measured side by side its bars come out at two thirds the
// stroke of the settings gear beside them — which is exactly what reads as
// "thin" in the bar. The geometry below is Twitter's own, lifted from the
// glyph: three bars centred on x=12, spans 3-21, 6-18 and 9-15, centre lines at
// y=7, 12.5 and 18 on a 24-unit canvas. Only the bar height changes, 2 units to
// 2.8, which lands on the gear's stroke exactly.
static UIImage* NFBFilterBarsGlyph(CGFloat side) {
    const CGFloat kUnit = 24.0;
    const CGFloat kThickness = 2.8;
    const CGFloat bars[3][3] = {{3.0, 21.0, 7.0}, {6.0, 18.0, 12.5}, {9.0, 15.0, 18.0}};
    CGFloat scale = side / kUnit;
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [[UIColor blackColor] setFill];
            for (NSInteger i = 0; i < 3; i++) {
                CGRect bar = CGRectMake(bars[i][0] * scale,
                                        (bars[i][2] - kThickness / 2.0) * scale,
                                        (bars[i][1] - bars[i][0]) * scale,
                                        kThickness * scale);
                CGContextFillRect(context.CGContext, bar);
            }
        }];
    return drawn;
}

static UIImage* NFBGreyGlyph(UIImage* source, UIColor* colour) {
    if (!source || !colour) {
        return source;
    }
    CGSize size = source.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return source;
    }
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = source.scale;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* painted = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
            [source drawInRect:rect];
            CGContextSetBlendMode(context.CGContext, kCGBlendModeSourceIn);
            [colour setFill];
            CGContextFillRect(context.CGContext, rect);
        }];
    return [painted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
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
        if (!bar.window) {
            return;
        }

        UIButton* button = objc_getAssociatedObject(self, kNFBQuickMutedBtnKey);
        // The owner check runs only to decide whether this bar deserves a
        // button. Once one exists here, keep maintaining it: the responder
        // chain is momentarily incomplete during some layout passes, and
        // bailing out then was making the icon vanish until a relaunch.
        if (!button && !nfbIsHomeNavigationBar(bar)) {
            return;
        }
        if (!button) {
            // Twitter's filter_bars shape, drawn here at the gear's weight —
            // see NFBFilterBarsGlyph. Repainted through the same path as
            // before, so the colour still survives the theme's window tint.
            // The old system-symbol safety net is gone with the library
            // lookup it guarded: drawing the shape ourselves cannot come back
            // empty.
            UIImage* icon = NFBGreyGlyph(NFBFilterBarsGlyph(26.0),
                                         NFBBarIconGrey(bar.traitCollection));
            button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setImage:icon forState:UIControlStateNormal];

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

        // Re-asserted every pass, not just at creation: on a cold launch the
        // theme's window tint claimed the icon until the first tab swipe.
        UIColor* grey = NFBBarIconGrey(bar.traitCollection);
        if (![button.tintColor isEqual:grey]) {
            button.tintColor = grey;
        }

        // Align on the avatar rather than on the bar's box: the bar is taller
        // than its content, so centring in bounds left the icon sitting high.
        CGFloat side = 34.0;
        CGFloat inset = 16.0;
        CGFloat centerY = CGRectGetMidY(bar.bounds);
        UIView* avatar = nfbFindAvatarView(bar, bar);
        if (avatar) {
            CGRect inBar = [avatar convertRect:avatar.bounds toView:bar];
            centerY = CGRectGetMidY(inBar);
            side = CGRectGetHeight(inBar);
            inset = CGRectGetMinX(inBar);   // symétrique à la marge de gauche
        }
        button.frame = CGRectMake(CGRectGetWidth(bar.bounds) - side - inset,
                                  centerY - side / 2.0, side, side);
    } @catch (id exception) {
    }
}

%end
