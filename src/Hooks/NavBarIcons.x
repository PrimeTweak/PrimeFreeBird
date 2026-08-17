//
//  NavBarIcons.x
//  PrimeFreeBird
//
//  Twitter draws the settings gear at full label strength, which reads as
//  black next to the muted grey of the tab labels beside it.
//
//  Colour routes are reclaimed by something in every case: the tint
//  by the theme, the alpha by the button's own highlight after a tap, and
//  Twitter's fillColor renders black. So the glyph is repainted into a flat
//  grey bitmap, which nothing can take back.
//
//  Two screens, two shapes. On Explore the gear is a TFNBarButtonItemButton
//  carrying "NavigationBarSettingsButton", with its image nested a few levels
//  below. On Notifications it is a plain bar button item. The hook sits on
//  UINavigationBar — UIKit's base class, always loaded — because Twitter's own
//  subclass differs between screens.
//
//  During bar transitions the whole header — avatar, search field, gear and
//  tab strip — can lighten by one constant factor behind a hard edge, which
//  is a single container view drawn at partial opacity, not the glyph. So the
//  container is held opaque, not the gear.
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"
#import <QuartzCore/QuartzCore.h>

static NSString* const kNFBSettingsButtonIdentifier = @"NavigationBarSettingsButton";
static const void* kNFBGreyedImageKey = &kNFBGreyedImageKey;
// Holds the colour to force on a view the tweak have taken over, so any image set
// later goes through the same repaint.
static const void* kNFBGreyTargetKey = &kNFBGreyTargetKey;
// The untouched glyph. Repainting is not idempotent — a colour at 60% opacity
// laid over a colour already at 60% lands at 36% — so every repaint starts
// from this original.
static const void* kNFBOriginalImageKey = &kNFBOriginalImageKey;
// Marks an image the tweak produced. Two paths repaint on Notifications — the bar
// button item and the image view UIKit builds from it — and without the mark
// each treats the other's result as unpainted, painting the glyph twice. The
// mark travels with the image, so any path recognises it.
static const void* kNFBPaintedFlagKey = &kNFBPaintedFlagKey;
// Marks a layer that must never render at partial opacity. Correcting after
// the fact never worked — the tweak's pass runs before the value is lowered, so there
// is nothing to correct yet. Every route that could lower it is refused at the
// moment it is used instead: the alpha, the layer's opacity, and the animation.
static const void* kNFBNoFadeKey = &kNFBNoFadeKey;

// One grey for every icon the tweak adds or recolour: the label colour at 60%,
// resolved to a concrete value so nothing can re-resolve it later.
static UIColor* NFBBarIconGrey(UITraitCollection* traits) {
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

// Repaints a glyph into a flat bitmap of the given colour.
static UIImage* NFBGreyGlyph(UIImage* source, UIColor* colour) {
    if (!source || !colour) {
        return source;
    }
    CGSize size = source.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return source;
    }
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
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
    UIImage* result = [painted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    objc_setAssociatedObject(result, kNFBPaintedFlagKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

// Replaces the image of every glyph-sized image view under a view. The result
// is remembered so the work happens once, and happens again only if Twitter
// puts its own image back.
static void nfbRepaintGlyphs(UIView* view, UIColor* colour) {
    for (UIView* subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)subview;
            UIImage* current = imageView.image;
            UIImage* ours = objc_getAssociatedObject(imageView, kNFBGreyedImageKey);
            // Repaint when the image changed OR when the colour did. At launch
            // the trait collection is not settled yet, so labelColor resolves
            // to a different value and the first paint comes out pale; once
            // the traits land, this comparison catches it.
            UIColor* usedColour = objc_getAssociatedObject(imageView, kNFBGreyTargetKey);
            BOOL colourChanged = usedColour && ![usedColour isEqual:colour];
            BOOL alreadyOurs =
                objc_getAssociatedObject(current, kNFBPaintedFlagKey) != nil;
            if (current && !alreadyOurs && (current != ours || colourChanged)) {
                // Only remember the original if this image is not one of the tweak's.
                UIImage* source = current;
                UIImage* original =
                    objc_getAssociatedObject(imageView, kNFBOriginalImageKey);
                if (original) {
                    source = original;
                } else {
                    objc_setAssociatedObject(imageView, kNFBOriginalImageKey, current,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                UIImage* painted = NFBGreyGlyph(source, colour);
                objc_setAssociatedObject(imageView, kNFBGreyTargetKey, colour,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(imageView, kNFBGreyedImageKey, painted,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                imageView.image = painted;
            }
        }
        nfbRepaintGlyphs(subview, colour);
    }
}

// The conversation bar of the encrypted chat, named by its controller rather
// than by geometry. Everything below is fenced behind this: no other bar in the
// app is touched.
static BOOL nfbIsChatConversationBar(UIView* view) {
    UIResponder* responder = view;
    NSInteger depth = 0;
    while ((responder = responder.nextResponder) && depth < 12) {
        NSString* name = NSStringFromClass([responder class]);
        // The conversation of the encrypted chat, and the settings screens of
        // this tweak — both are named by their controller, so no other screen
        // in the app is reached.
        // T1ConversationContainerViewController is the regular DM
        // conversation — binary-confirmed. Its trailing glyphs (call, video)
        // take the same label-colour bake as the encrypted chat's, at their
        // FIRST image set: no accent beat before the bar settles, the exact
        // pre-regression behaviour.
        if ([name containsString:@"XChatDM"] ||
            [name containsString:@"ConversationContainer"] ||
            [name hasPrefix:@"ModernSettings"]) {
            return YES;
        }
        depth++;
    }
    return NO;
}


static BOOL nfbLooksLikeSettingsButton(UIView* view) {
    NSString* identifier = view.accessibilityIdentifier;
    NSString* label = view.accessibilityLabel;
    return [identifier isEqualToString:kNFBSettingsButtonIdentifier] ||
           [label isEqualToString:kNFBSettingsButtonIdentifier] ||
           [identifier hasPrefix:@"NavigationBarSettings"] ||
           [label hasPrefix:@"NavigationBarSettings"];
}

// Brings one view back to full strength and marks it, so that anything lowering
// it later — an alpha, a layer opacity, an animation — is refused rather than
// undone after the fact.
static void nfbPinOpaque(UIView* view) {
    if (view.alpha < 1.0) {
        view.alpha = 1.0;
    }
    if (view.layer.opacity < 1.0f) {
        view.layer.opacity = 1.0f;
    }
    [view.layer removeAnimationForKey:@"opacity"];
    objc_setAssociatedObject(view.layer, kNFBNoFadeKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The gear and everything inside it.
static void nfbForceOpaque(UIView* view) {
    nfbPinOpaque(view);
    for (UIView* subview in view.subviews) {
        nfbForceOpaque(subview);
    }
}

// The container that holds the bar and the tab strip, reached from the bar
// upwards. The walk stops before the first view tall enough to be the screen
// itself, so a push, a modal or a tab change still fades the way it should —
// only the header band is held. Unmanaged bars never get here.
static void nfbPinHeaderOpacity(UIView* bar) {
    UIWindow* window = bar.window;
    if (!window) {
        return;
    }
    CGFloat screenful = CGRectGetHeight(window.bounds) * 0.5;
    UIView* view = bar;
    while (view && view != window) {
        if (CGRectGetHeight(view.bounds) > screenful) {
            return;
        }
        nfbPinOpaque(view);
        view = view.superview;
    }
}

// Depth-first search for the settings button by its identifier or label.
static UIView* nfbFindSettingsButton(UIView* view) {
    for (UIView* subview in view.subviews) {
        if (nfbLooksLikeSettingsButton(subview)) {
            return subview;
        }
        UIView* found = nfbFindSettingsButton(subview);
        if (found) {
            return found;
        }
    }
    return nil;
}

// The notifications tab is named after activity, not notifications — the class
// is T1ActivityHistory… — and the bar belongs to the All/Mentions container,
// whose own name says nothing. Both spellings are accepted, and children and
// parents are searched as well as the controller itself.
static BOOL nfbNameIsNotifications(UIViewController* controller) {
    NSString* name = controller ? NSStringFromClass([controller class]) : @"";
    // "Activity" alone would also match UIActivityViewController — the share
    // sheet — so the notifications tab is named precisely.
    return [name containsString:@"Notification"] ||
           [name containsString:@"ActivityHistory"];
}

static BOOL nfbControllerIsNotifications(UIViewController* controller) {
    if (!controller) {
        return NO;
    }
    if (nfbNameIsNotifications(controller)) {
        return YES;
    }
    for (UIViewController* child in controller.childViewControllers) {
        if (nfbNameIsNotifications(child)) {
            return YES;
        }
    }
    UIViewController* parent = controller.parentViewController;
    while (parent) {
        if (nfbNameIsNotifications(parent)) {
            return YES;
        }
        parent = parent.parentViewController;
    }
    return NO;
}

static UIViewController* nfbBarOwningController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if (![responder isKindOfClass:[UIViewController class]]) {
            continue;
        }
        UIViewController* controller = (UIViewController*)responder;
        if ([controller isKindOfClass:[UINavigationController class]]) {
            return ((UINavigationController*)controller).topViewController ?: controller;
        }
        return controller;
    }
    return nil;
}

// Notifications: the gear is a bar button item, so its image is repainted
// directly. The caller has already established that this is the notifications
// bar; icon-only items are picked here, so a text button like "Done" is never
// touched.
static void nfbRepaintNotificationsGear(UIView* bar, UIColor* colour) {
    // The item has no view of its own, so the fade is removed from whatever
    // renders it: the icon buttons on the right of this bar.
    for (UIView* subview in bar.subviews) {
        CGRect inBar = [subview convertRect:subview.bounds toView:bar];
        if (CGRectGetMidX(inBar) > CGRectGetWidth(bar.bounds) * 0.6) {
            nfbForceOpaque(subview);
        }
    }
    if (![bar respondsToSelector:@selector(topItem)]) {
        return;
    }
    UINavigationItem* item = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    for (UIBarButtonItem* button in item.rightBarButtonItems) {
        if (button.title.length > 0 || !button.image) {
            continue;
        }
        UIImage* ours = objc_getAssociatedObject(button, kNFBGreyedImageKey);
        UIColor* usedColour = objc_getAssociatedObject(button, kNFBGreyTargetKey);
        BOOL colourChanged = usedColour && ![usedColour isEqual:colour];
        BOOL alreadyOurs =
            objc_getAssociatedObject(button.image, kNFBPaintedFlagKey) != nil;
        if (!alreadyOurs && (button.image != ours || colourChanged)) {
            UIImage* original =
                objc_getAssociatedObject(button, kNFBOriginalImageKey);
            UIImage* source = original ?: button.image;
            if (!original) {
                objc_setAssociatedObject(button, kNFBOriginalImageKey, button.image,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            UIImage* painted = NFBGreyGlyph(source, colour);
            objc_setAssociatedObject(button, kNFBGreyTargetKey, colour,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(button, kNFBGreyedImageKey, painted,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            button.image = painted;
        }
    }
}

%hook UINavigationBar

- (void)layoutSubviews {
    %orig;

    @try {
        UIView* bar = (UIView*)self;
        if (!bar.window) {
            return;
        }
        UIColor* grey = NFBBarIconGrey(bar.traitCollection);

        // Explore is recognised by the button, Notifications by the screen.
        // Anything else is left exactly as Twitter draws it — the header is
        // held opaque on these two bars only.
        UIView* settingsButton = nfbFindSettingsButton(bar);
        BOOL notifications =
            settingsButton
                ? NO
                : nfbControllerIsNotifications(nfbBarOwningController(bar));
        if (!settingsButton && !notifications) {
            return;
        }

        nfbPinHeaderOpacity(bar);

        if (settingsButton) {
            nfbRepaintGlyphs(settingsButton, grey);
            nfbForceOpaque(settingsButton);
            return;
        }
        nfbRepaintNotificationsGear(bar, grey);
    } @catch (id exception) {
    }
}

%end

// Frame-by-frame capture showed the gear flipping between black
// and grey on one screen: the tweak's repaint lands, then Twitter puts its own image
// back, and nothing calls back until the bar happens to lay out. So the
// image is caught as it is set. Only views the tweak have already taken over are
// affected — everything else pays a single associated-object read.

// The colour a bar glyph should carry: the text colour, resolved for the
// current appearance.
static UIColor* nfbBarGlyphColour(UIView* view) {
    UIColor* colour = [UIColor labelColor];
    if (view && [colour respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [colour resolvedColorWithTraitCollection:view.traitCollection] ?: colour;
    }
    return colour;
}

// The button's own chain, four levels at most — never the bar, so no sibling is
// reached.
static void nfbTintGlyphChain(UIView* view, UIColor* colour) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 4) {
        if (![node.tintColor isEqual:colour]) {
            node.tintColor = colour;
        }
        node = node.superview;
        depth++;
    }
}

// A glyph of the conversation bar: inside a bar button or the subtitle stack,
// and inside that bar. Ancestors only — nothing below is visited, so no sibling
// can be reached.
// True of a back button's own subtree only: _UIBackButtonMaskView is created
// for back buttons and for nothing else. Class names are read, never touched —
// no view in the subtree is painted, which is what once flattened an avatar.
static BOOL nfbSubtreeHasBackMask(UIView* view, NSInteger depth) {
    if (!view || depth > 4) {
        return NO;
    }
    if ([NSStringFromClass([view class]) isEqualToString:@"_UIBackButtonMaskView"]) {
        return YES;
    }
    for (UIView* sub in view.subviews) {
        if (nfbSubtreeHasBackMask(sub, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

// A back button, wherever it is. The bar's container is found first, then the
// button is asked whether it carries a back mask at all — the pair names the
// arrow without a controller, without geometry and without a size.
//
// The mask is required rather than accepted alongside _UIModernBarButton: every
// modern bar button has one of those, so the looser test also claimed the round
// confirm of Twitter's own screens and baked its checkmark in the label colour —
// a black check on an accent disc. Asking the CONTAINER for a mask still covers
// both image views a back button carries (they share that container), while a
// button that is not a back button no longer matches.
// The round confirm of Twitter's own screens. A capture of Explore settings
// settled how to name it: NO ancestor carries the accent disc — the glass
// platter draws it, not a view — so every attempt to find a background colour
// was bound to fail. What the capture DOES show is the glyph's tint:
//
//   UIImageView … mode=0 tint=rgba(255,255,255,1.00)      the confirm
//   UIImageView … mode=1 tint=rgba(0,0,0,0.60)            the settings gear
//   UIImageView … mode=0 tint=rgba(0,0,0,1.00)            an ordinary glyph
//
// A bar glyph is tinted white only when it sits on a coloured disc, so white is
// the discriminator. The back arrow is excluded outright, its tint being dark
// in any case.
// The name of the screen the navigation controller currently shows. A bar
// button's responder chain never reaches the content screen — it climbs into
// the navigation controller, and the screen is read from there. This is the
// corrected mechanism behind every screen-scoped decision in this file.
// The FIRST view controller in the responder chain — the screen that OWNS the
// view. The journal proved the previous reading wrong twice in one build: it
// asked the UINavigationController for its top, and in this app that is the
// generic TwitterDash shell — never "Inbox", never "Settings" — so the mirror
// was torn down ON the inbox and the check never baked. TFN bars live inside
// the screen's own hierarchy, so the first controller on the chain IS the
// screen.
static NSString* nfbOwningScreenName(UIView* view) {
    UIResponder* responder = view;
    NSInteger depth = 0;
    while ((responder = responder.nextResponder) && depth < 14) {
        if ([responder isKindOfClass:[UIViewController class]] &&
            ![responder isKindOfClass:[UINavigationController class]]) {
            return NSStringFromClass([responder class]);
        }
        depth++;
    }
    return @"";
}

static BOOL nfbIsBackArrowGlyph(UIView* view) {
    UIView* container = nil;
    UIView* node = view.superview;
    NSInteger depth = 0;
    while (node && depth < 5) {
        if ([NSStringFromClass([node class]) isEqualToString:@"_UIButtonBarButton"]) {
            container = node;
            break;
        }
        node = node.superview;
        depth++;
    }
    if (!container) {
        return NO;
    }
    return nfbSubtreeHasBackMask(container, 0);
}

static BOOL nfbIsChatBarGlyph(UIView* view) {
    UIView* ancestor = view.superview;
    NSInteger depth = 0;
    BOOL inHolder = NO;
    while (ancestor && depth < 4) {
        NSString* name = NSStringFromClass([ancestor class]);
        // A back button carries TWO image views: one under the modern button and
        // one under the mask that UIKit actually draws. Correcting only the
        // first left the visible glyph in the accent — the mask is the one seen.
        if ([name isEqualToString:@"_UIModernBarButton"] ||
            [name isEqualToString:@"_UIBackButtonMaskView"] ||
            [name isEqualToString:@"_UIButtonBarButton"] ||
            [name isEqualToString:@"TFNBarButtonItemButton"] ||
            [name containsString:@"SelfSizingStackView"]) {
            inHolder = YES;
            break;
        }
        ancestor = ancestor.superview;
        depth++;
    }
    return inHolder && nfbIsChatConversationBar(view);
}

// The confirm check of the settings sheets is the only bar glyph in the app
// with a pure-white tint (established by capture), and pure white at maximum
// luminance blooms on the saturated accent disc — measured at 5-6 px of
// stroke, it reads as 7-8. Stepping the white down to 0.92 sits just under
// the bloom threshold: same stroke, same geometry, the glare gone. The claim
// is fenced twice, because a white tint alone once repainted the conversation
// call icons: the glyph must ALSO sit on a settings screen, read from the
// navigation controller's top view controller — a DM conversation reads
// ConversationContainer and can never qualify.
static UIColor* nfbSoftConfirmWhite(void) {
    return [UIColor colorWithWhite:0.92 alpha:1.0];
}

// The claim runs in TWO steps, because its two halves are readable at two
// different moments. The file itself documents that a bar button is given its
// image BEFORE it is placed in the bar — so at setImage time the responder
// chain stops at the detached button, the screen cannot be read, and a screen
// test there says "no settings" for every glyph including the confirm. That is
// exactly how the previous build left the check glaring. So: the LOCAL half
// (pure-white tint, modern bar button, not the back arrow) marks the glyph at
// setImage; the SCREEN half decides at didMoveToWindow, when the chain finally
// reaches the navigation controller.
static const char* kNFBPendingConfirmKey = "nfbPendingConfirm";

static BOOL nfbIsWhiteBarGlyphCandidate(UIView* view) {
    UIView* node = view.superview;
    NSInteger depth = 0;
    BOOL inModernBarButton = NO;
    while (node && depth < 3) {
        if ([NSStringFromClass([node classForCoder])
                isEqualToString:@"_UIModernBarButton"]) {
            inModernBarButton = YES;
            break;
        }
        node = node.superview;
        depth++;
    }
    if (!inModernBarButton || nfbIsBackArrowGlyph(view)) {
        return NO;
    }
    UIColor* tint = view.tintColor;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!tint || ![tint getRed:&r green:&g blue:&b alpha:&a]) {
        return NO;
    }
    return a > 0.9 && r > 0.9 && g > 0.9 && b > 0.9;
}

%hook UIImageView

// The second half of the two-step claim: the button is in the bar, the chain
// reaches the navigation controller, the screen is finally readable.
- (void)didMoveToWindow {
    %orig;
    if (!((UIView*)self).window ||
        !objc_getAssociatedObject(self, kNFBPendingConfirmKey)) {
        return;
    }
    objc_setAssociatedObject(self, kNFBPendingConfirmKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImage* current = self.image;
    if (!current ||
        current.renderingMode == UIImageRenderingModeAlwaysOriginal) {
        return;
    }
    // No screen-name test: three builds proved every guessed name wrong on
    // this app's controller shells. The structural fence is enough — the only
    // false positives ever measured, the conversation call icons, arrive here
    // already baked AlwaysOriginal by the chat-bar path and were refused two
    // lines above. Pure-white tint on a modern bar button that is not the back
    // arrow and not already baked names exactly one glyph.
    NSString* screen = nfbOwningScreenName((UIView*)self);
    // Baked rather than re-tinted: AlwaysOriginal forbids the bar button from
    // painting its own white back over ours — and sends the setter straight
    // through the passthrough above.
    UIImage* softened = NFBGreyGlyph(current, nfbSoftConfirmWhite());
    if (softened) {
        NFBDebugLog(@"glyphe: confirm (ecran=%@) -> blanc adouci",
                    screen.length ? screen : @"?");
        NFBMark((UIView*)self, @"NavBarIcons/confirmGlyph → blanc adouci");
        self.image = softened;
    }
}

- (void)setImage:(UIImage*)image {
    UIColor* target = objc_getAssociatedObject(self, kNFBGreyTargetKey);
    if (!target || !image) {
        // The glyphs of the conversation bar — the arrow, the trailing icons,
        // the padlock — are template images, so they are drawn entirely in
        // whatever tint reaches them. The rendering mode is corrected here
        // rather than painted during layout: an image keeps its own colours,
        // its size does not change, and no layout pass is provoked. Painting a
        // bar button while it was laying out invalidated its intrinsic size and
        // froze the app twice.
        // Not "== AlwaysTemplate": a bar glyph usually arrives in AUTOMATIC mode,
        // which a bar button draws as a template all the same — its description
        // simply names no mode at all. Anything that is not already original is
        // therefore claimed.
        if (image.renderingMode != UIImageRenderingModeAlwaysOriginal) {
            if (nfbIsWhiteBarGlyphCandidate((UIView*)self)) {
                // The screen is not readable yet — the button is not in the
                // bar. Marked here, decided at didMoveToWindow below.
                objc_setAssociatedObject(self, kNFBPendingConfirmKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (nfbIsChatBarGlyph((UIView*)self) ||
                nfbIsBackArrowGlyph((UIView*)self)) {
                // Baked at the setter, the way the confirm glyph of the theme
                // screen already is: whoever writes last, the pixels that land
                // carry the colour. A mode change alone leaves an alpha mask,
                // which a bar button re-tints per its own contrast rule.
                UIColor* colour = nfbBarGlyphColour((UIView*)self);
                UIImage* baked = NFBGreyGlyph(image, colour);
                NFBMark((UIView*)self,
                        nfbIsBackArrowGlyph((UIView*)self)
                            ? @"NavBarIcons/backArrow → cuit"
                            : @"NavBarIcons/chatBarGlyph → cuit");
                // Belt for the one frame a freshly created button can show
                // before its first baked image lands: with the button's own
                // chain tinted, even a frame treated as a template is right.
                nfbTintGlyphChain((UIView*)self, colour);
                %orig(baked ?: image);
                return;
            }
            // A bar button is given its image before it is placed in the bar, so
            // the ancestors that name it do not exist yet and the test above
            // cannot answer. The question is asked again on the next turn of the
            // run loop, once the button has been attached — outside any layout
            // pass, so nothing is invalidated while a layout is in progress.
            if (!((UIView*)self).superview) {
                __weak UIImageView* weakView = (UIImageView*)self;
                dispatch_async(dispatch_get_main_queue(), ^{
                  UIImageView* view = weakView;
                  UIImage* current = view.image;
                  if (!view || !current ||
                      current.renderingMode == UIImageRenderingModeAlwaysOriginal ||
                      (!nfbIsChatBarGlyph(view) && !nfbIsBackArrowGlyph(view))) {
                      return;
                  }
                  view.image =
                      [current imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
                });
            }
        }
        %orig;
        return;
    }
    UIImage* ours = objc_getAssociatedObject(self, kNFBGreyedImageKey);
    if (image == ours ||
        objc_getAssociatedObject(image, kNFBPaintedFlagKey) != nil) {
        %orig;
        return;
    }
    // Twitter's own image is the source; the tweak's would compound and go pale.
    if (objc_getAssociatedObject(self, kNFBOriginalImageKey)) {
        image = objc_getAssociatedObject(self, kNFBOriginalImageKey);
    }
    objc_setAssociatedObject(self, kNFBOriginalImageKey, image,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImage* painted = NFBGreyGlyph(image, target);
    objc_setAssociatedObject(self, kNFBGreyedImageKey, painted,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(painted);
}

%end

%hook UIBarButtonItem

- (void)setImage:(UIImage*)image {
    UIColor* target = objc_getAssociatedObject(self, kNFBGreyTargetKey);
    if (!target || !image) {
        %orig;
        return;
    }
    UIImage* ours = objc_getAssociatedObject(self, kNFBGreyedImageKey);
    if (image == ours ||
        objc_getAssociatedObject(image, kNFBPaintedFlagKey) != nil) {
        %orig;
        return;
    }
    UIImage* painted = NFBGreyGlyph(image, target);
    objc_setAssociatedObject(self, kNFBGreyedImageKey, painted,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(painted);
}

%end

// The same treatment as Explore, reached from the other side. Notifications
// builds its bar differently, so the gear is not found by searching the bar's
// subtree — but the button class is the same one Twitter uses everywhere, and
// hooking it catches the gear whatever the bar around it looks like.
// didMoveToWindow fires exactly when the bar appears.

// A bar button qualifies only if it is an icon on the right-hand side: no
// title, a glyph-sized image inside, and past the middle of its own bar. A
// back chevron sits on the left and a text button has a title, so neither is
// ever touched.
static BOOL nfbIsRightHandGlyphButton(UIView* button) {
    if ([button isKindOfClass:[UIButton class]] &&
        ((UIButton*)button).currentTitle.length > 0) {
        return NO;
    }

    __block BOOL hasGlyph = NO;
    EnumerateSubviewsRecursively(button, ^(UIView* view) {
        if (hasGlyph || ![view isKindOfClass:[UIImageView class]]) {
            return;
        }
        UIImageView* imageView = (UIImageView*)view;
        CGFloat side = CGRectGetWidth(imageView.bounds);
        if (imageView.image && side > 14.0 && side < 34.0) {
            hasGlyph = YES;
        }
    });
    if (!hasGlyph) {
        return NO;
    }

    UIView* bar = button.superview;
    while (bar && ![bar isKindOfClass:[UINavigationBar class]]) {
        bar = bar.superview;
    }
    if (!bar) {
        return NO;
    }
    CGRect inBar = [button convertRect:button.bounds toView:bar];
    return CGRectGetMidX(inBar) > CGRectGetWidth(bar.bounds) * 0.6;
}

%hook TFNBarButtonItemButton

// The repaint runs on both entry points. didMoveToWindow alone caught the
// button before its image view existed on Notifications, so nothing was marked
// and the interception below never armed — a tab change was required for it to
// take. layoutSubviews closes that window; once marked, every later pass is a
// pointer comparison.
%new
- (void)nfbGreySettingsGlyphIfNeeded {
    @try {
        UIView* button = (UIView*)self;
        if (!button.window) {
            return;
        }
        // Either the button says it is the settings one, or the tweak are on the
        // notifications screen, where the gear is the only icon in the bar.
        // The identifier is the precise route and covers Explore. The second
        // route exists only for Notifications, where no view carries it — and
        // it is fenced in tightly so nothing else on that screen is caught.
        BOOL wanted = nfbLooksLikeSettingsButton(button) ||
                      (nfbControllerIsNotifications(nfbBarOwningController(button)) &&
                       nfbIsRightHandGlyphButton(button));
        if (!wanted) {
            return;
        }
        nfbRepaintGlyphs(button, NFBBarIconGrey(button.traitCollection));
        nfbForceOpaque(button);
    } @catch (id exception) {
    }
}

- (void)didMoveToWindow {
    %orig;
    [self nfbGreySettingsGlyphIfNeeded];
}

- (void)layoutSubviews {
    %orig;
    [self nfbGreySettingsGlyphIfNeeded];
}

%end

// Partial opacity is refused where it is set, by all three routes into it.
// Every other view and layer in the app pays one float comparison, which fails
// on the overwhelming majority of calls before anything else is read.

%hook UIView

- (void)setAlpha:(CGFloat)alpha {
    if (alpha < 1.0 &&
        objc_getAssociatedObject(self.layer, kNFBNoFadeKey) != nil) {
        %orig(1.0);
        return;
    }
    %orig;
}

%end

// True of the inbox filter pill or anything inside it. Tighter than the bar
// test below: the avatar in the same bar fades legitimately, and only this
// control must be held. Class name only, no message to a Swift class.
static BOOL nfbViewSitsInInboxPill(UIView* view) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 6) {
        if ([NSStringFromClass([node classForCoder])
                isEqualToString:@"_TtC7DMInbox39InboxNavigationBarMenuBarButtonItemView"]) {
            return YES;
        }
        node = node.superview;
        depth++;
    }
    return NO;
}

// The platter that holds the bar's buttons — wider than the pill test above,
// narrower than the whole bar, so the animation journal names the suspects
// without drowning in the scroll edge effects. Bounded and class-name only:
// this runs on an animation path.
static BOOL nfbViewSitsInBarPlatter(UIView* view) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 12) {
        if ([NSStringFromClass([node classForCoder])
                hasPrefix:@"UIKit.NavigationBarPlatterContainer"]) {
            return YES;
        }
        node = node.superview;
        depth++;
    }
    return NO;
}

%hook CALayer

- (void)setOpacity:(float)opacity {
    if (opacity < 1.0f &&
        objc_getAssociatedObject(self, kNFBNoFadeKey) != nil) {
        %orig(1.0f);
        return;
    }
    %orig;
}

- (void)addAnimation:(CAAnimation*)animation forKey:(NSString*)key {
    UIView* owner = (UIView*)self.delegate;
    BOOL ownerIsView = [owner isKindOfClass:[UIView class]];

    // Every animation reaching the button platter is recorded, whatever its
    // kind. The previous round logged opacity only and stayed silent on the
    // pill — which was itself the finding: the fade is not an opacity
    // animation, so refusing opacity refused nothing. A transition or a
    // transform carries no "opacity" keyPath and slipped straight through.
    if (NFBDebugIsRecording() && ownerIsView && nfbViewSitsInBarPlatter(owner)) {
        NSString* path = @"—";
        if ([animation isKindOfClass:[CABasicAnimation class]]) {
            path = ((CABasicAnimation*)animation).keyPath ?: @"nil";
        } else if ([animation isKindOfClass:[CATransition class]]) {
            path = [NSString stringWithFormat:@"transition:%@",
                    ((CATransition*)animation).type ?: @"?"];
        }
        NFBDebugLog(@"anim platine: %@ [%@] clé=%@ chemin=%@ durée=%.2f pill=%@",
                    NSStringFromClass([owner classForCoder]),
                    NSStringFromClass([animation classForCoder]),
                    key ?: @"nil", path, animation.duration,
                    nfbViewSitsInInboxPill(owner) ? @"OUI" : @"non");
    }

    // Every animation on this one control is refused, not just opacity. The
    // measurement above showed the fade never announced itself as an opacity
    // change, so naming a kind to block was the mistake; the control simply
    // does not animate. Its neighbours in the same bar are untouched, and the
    // pill appearing without a transition is exactly what is wanted here.
    if (ownerIsView && nfbViewSitsInInboxPill(owner)) {
        return;
    }

    BOOL isFade = [key isEqualToString:@"opacity"];
    if (!isFade && [animation isKindOfClass:[CABasicAnimation class]]) {
        isFade = [((CABasicAnimation*)animation).keyPath isEqualToString:@"opacity"];
    }

    if (!objc_getAssociatedObject(self, kNFBNoFadeKey)) {
        %orig;
        return;
    }
    if (isFade) {
        return;
    }
    %orig;
}

%end

// MARK: - the conversation bar: arrow and portrait
//
// Two views in that bar come out in the accent, and the view tree says they are
// in different branches:
//
//   TFNNavigationBar
//    ├ _UIModernBarButton                     the back arrow, a UIKit class
//    └ _UINavigationBarTitleControl
//        └ DMConversation.AvatarTitleButton
//            └ … → T1AvatarImageView          the portrait
//
// Neither is reached by painting: each is given its own tint, on itself, and
// only when it sits inside one of Twitter's navigation bars. No image is
// replaced, no parent is walked, so a sibling cannot be caught — which is what
// went wrong when the arrow was claimed through its superview.





// MARK: - a portrait is not a glyph
//
// Measured on the view itself: its image carries renderingMode = alwaysTemplate
// and its tintColor is the accent, so the picture is drawn as a flat disc of it.
// A template image has no colours of its own — which is why answering the
// palette, the placeholder layer or the view's tint moved nothing.
//
// The rendering mode is what is corrected, on this class alone: an image handed
// to an avatar keeps its own colours. Nothing is repainted and no view is
// walked.

%hook T1AvatarImageView

- (void)setImage:(UIImage*)image {
    if (image.renderingMode == UIImageRenderingModeAlwaysTemplate) {
        %orig([image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]);
        return;
    }
    %orig;
}

%end

// MARK: - the inbox filter pill
//
// Measured frame by frame on a recording of the Messages list, returning to the
// screen: the avatar, the title and the search bar hold a constant pixel count
// while the pill alone drops to ZERO for about a tenth of a second and comes
// back. Across all 156 frames its region contains no coloured pixel at all, so
// nothing here is a tint — it is an opacity fade on that one control.
//
// Its view tree says why it fades alone: the pill is hosted in
// UIKit.NavigationBarPlatterContainer_v2, the system's glass platter, through a
// chain of SwiftUI._UIInheritedView. Returning to the screen re-hosts that
// content, and UIKit cross-fades what it replaces.
//
//   UIKit.NavigationBarPlatterContainer_v2            the system glass platter
//    └ …PlatterContainerHost…                         SwiftUI host
//       └ SwiftUI._UIInheritedView                    ×3
//          └ _TtGC5UIKit22UICorePlatformViewHost…
//             └ NavigationButtonBar.ItemWrapper
//                └ DMInbox.InboxNavigationBarMenuBarButtonItemView   57.33 × 40
//
// The control is pinned opaque with the three-route refusal the header band
// already uses: the running animation is dropped and the layer marked, so
// setAlpha:, setOpacity: and addAnimation: all decline to lower it afterwards.
// Only this control is marked — nothing above it is walked, and nothing below
// it is painted. Addressed as a plain UIView: the class is Swift and Logos
// forward-declares it, so it takes no message of its own.

// MARK: the bridge over the re-host gap
//
// Measured at 60 fps: on returning to the Messages list the pill is REMOVED
// from the hierarchy for about six frames and then recreated — the avatar and
// the title hold perfectly still while its pixel count goes 781 → 0 → 780.
// Nothing fades and nothing transforms; the view simply is not there. That is
// why refusing animations, of any kind, changed nothing: there was never an
// animation to refuse. The platter re-hosts its SwiftUI content, and the gap
// between the old instance leaving and the new one arriving is the flash.
//
// The gap cannot be prevented, so it is covered: as the old pill leaves the
// window, a snapshot of it is pinned where it stood, and the first new pill to
// arrive takes it down. The snapshot lives in the navigation bar's own
// container — never the window — so leaving the tab tears it down with the bar
// instead of leaving a ghost over the next screen. If no new pill ever comes,
// it expires on its own.

// THE MIRROR — the pill's text, owned by us.
//
// Every fact below is measured, none is a theory:
//   · the platter destroys and recreates the pill in cascades (journal:
//     different instance pointers around each gap);
//   · the capsule the platter draws PERSISTS through every gap (video 16:17,
//     not one missing frame);
//   · only the CONTENT — the "All" label and its chevron — blinks, ~133 ms
//     (videos 16:17 and 16:40, identical measurements);
//   · TFNNavigationBar is reachable from the pill and survives the re-host
//     (v5 journal: every bridge landed in it and lived).
//
// So the fix stops covering and starts OWNING: the real content is hidden, and
// a mirror of it — same text, same font, same chevron, same colours, copied
// from the real thing on every layout — lives in the bar, which survives, at
// layer.zPosition 100, which the re-host cannot bury (sibling subtrees are
// composited by zPosition before order, so nothing added later draws over it).
// The real pill stays fully functional underneath: the mirror never takes a
// touch, so the tap and the menu are Twitter's own, untouched. Standard mode
// has no platter and no blink, so the mirror simply never engages there.

static const char* kNFBPillMirrorKey = "nfbPillMirror";
static const char* kNFBPillMirrorSlotKey = "nfbPillMirrorSlot";
static NSInteger gNFBMirrorSettleToken;

// The tweak's own Liquid Glass switch, read the same way the rest of the file
// reads its settings.
static BOOL nfbLiquidGlassEnabled(void) {
    return [BHTSettings boolForKey:@"enable_liquid_glass"];
}

// The bar the mirror currently hangs on, so the container watch below can take
// the mirror down without walking anything. Weak: the bar owns itself.
static __weak UIView* gNFBInboxMirrorBar;

// The pill instance the mirror last synced from. Replacement is the RULE, not
// the exception — journal of 16/08, one single return to Messages: the pill
// <0x150283480> is re-posed at 20:34:02.185, a brand-new <0x1654a8e00> arrives
// at 02.435, and the old one leaves for good at 03.093. Every handover is
// therefore tracked and named, so a mirror stuck on a dead source can never
// again fail silently.
static __weak UIView* gNFBInboxMirrorSourcePill;

// The Messages container class lives in a LAZILY loaded framework — the health
// report itself lists DMInbox among the late loaders, red at launch and green
// once the screen opens. A load-time %hook therefore never lands on it, which
// is exactly how the ghost came back. So the watch is installed the way Chat.x
// already installs its replacement: by IMP, at the moment the first mirror is
// posed — the screen is on the glass, the class is necessarily loaded.
static void (*gNFBOrigContainerWillMove)(id, SEL, UIWindow*);

// The container instance itself, kept weak so the pose below can ask the only
// question that matters structurally: is the inbox on the glass right now?
// Measured 21:00:51.711: a stray layout of the DEPARTING pill re-posed a
// mirror 300 ms after the drop (the pill leaves ~500 ms after the container),
// and that orphan floated over the next screen until the inbox came back.
static __weak UIView* gNFBInboxContainer;

// Defined below; declared here so the watch can call it without moving either
// block.
static void nfbDropInboxMirror(UIView* bar);

static void nfbContainerWillMoveToWindow(id self, SEL _cmd, UIWindow* newWindow) {
    gNFBInboxContainer = self;
    if (!newWindow && gNFBInboxMirrorBar) {
        nfbDropInboxMirror(gNFBInboxMirrorBar);
    }
    if (gNFBOrigContainerWillMove) {
        gNFBOrigContainerWillMove(self, _cmd, newWindow);
    }
}

static void nfbInstallContainerWatch(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class container = objc_getClass("_TtC7DMInbox18InboxContainerView");
        if (!container) {
            NFBDebugLog(@"pill: conteneur introuvable — veille non posée");
            return;
        }
        SEL selector = @selector(willMoveToWindow:);
        Method inherited = class_getInstanceMethod(container, selector);
        if (!inherited) {
            NFBDebugLog(@"pill: willMoveToWindow absent — veille non posée");
            return;
        }
        // The Swift class does not override this method, so the Method above
        // is UIView's own — replacing its implementation swizzles EVERY view
        // in the app, which is precisely what the crash report showed. An
        // override is therefore ADDED to the subclass itself: only container
        // instances ever run our code, and the original to call through is
        // the inherited implementation. If the class one day does override
        // it, class_addMethod fails and the replacement is then correctly
        // scoped to that override.
        gNFBOrigContainerWillMove =
            (void (*)(id, SEL, UIWindow*))method_getImplementation(inherited);
        if (class_addMethod(container, selector,
                            (IMP)nfbContainerWillMoveToWindow,
                            method_getTypeEncoding(inherited))) {
            NFBDebugLog(@"pill: veille du conteneur posée (ajout)");
        } else {
            method_setImplementation(inherited,
                                     (IMP)nfbContainerWillMoveToWindow);
            NFBDebugLog(@"pill: veille du conteneur posée (remplacement)");
        }
    });
}

static void nfbDropInboxMirror(UIView* bar) {
    UIView* mirror = objc_getAssociatedObject(bar, kNFBPillMirrorKey);
    if (!mirror) {
        return;
    }
    // Every trace of state goes FIRST, the destructive call goes LAST. The
    // crash report showed the opposite order recursing to a stack overflow:
    // removeFromSuperview fires willMoveToWindow, and a handler that still
    // sees the state drops again, forever. Cleared first, any re-entry finds
    // nothing and returns at the guard above.
    objc_setAssociatedObject(bar, kNFBPillMirrorKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gNFBInboxMirrorBar = nil;
    gNFBInboxMirrorSourcePill = nil;
    [mirror removeFromSuperview];
    NFBDebugLog(@"pill: miroir retire (ecran quitte)");
}

static UIView* nfbPillBar(UIView* pill) {
    UIView* node = pill.superview;
    NSInteger depth = 0;
    while (node && depth < 32) {
        if ([node isKindOfClass:[UINavigationBar class]]) {
            return node;
        }
        node = node.superview;
        depth++;
    }
    // Audit of 16/08: with every other exit of the sync either logged or
    // self-healing, THIS was the only path left that fails silently and
    // stays failed — a replacement pill whose ancestor chain resolves no
    // UINavigationBar leaves the mirror frozen on the dead instance and its
    // own live content uncovered: the doubled "All". So when a mirror is
    // already up, its bar is the fallback — the descendant test walks the
    // whole chain, uncapped, with no class check to miss on.
    UIView* mirrorBar = gNFBInboxMirrorBar;
    if (mirrorBar && [pill isDescendantOfView:mirrorBar]) {
        return mirrorBar;
    }
    return nil;
}

static void nfbMirrorInboxPill(UIView* pill);

static void nfbScheduleMirrorResync(UIView* pill) {
    NSInteger token = ++gNFBMirrorSettleToken;
    __weak UIView* weakPill = pill;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gNFBMirrorSettleToken != token) {
            return;  // a newer pass owns the chain
        }
        UIView* livePill = weakPill;
        if (!livePill || !livePill.window) {
            // Measured hole: the replaced pill's FINAL layout can own the
            // last token, then leave the window — the pass no-ops and the
            // chain dies holding the provisional 1.2× frame. The live source
            // takes over the pass instead.
            livePill = gNFBInboxMirrorSourcePill;
        }
        if (livePill && livePill.window) {
            nfbMirrorInboxPill(livePill);
        }
    });
}

static void nfbMirrorInboxPill(UIView* pill) {
    if (CGSizeEqualToSize(pill.bounds.size, CGSizeZero) || !pill.window) {
        return;
    }
    UIView* bar = nfbPillBar(pill);
    if (!bar) {
        // Named, never silent — this exact silence is what froze the mirror
        // on 16/08. One line per instance, WITH the chain: if this build
        // still cannot resolve a bar, the next capture hands over the real
        // layout instead of another guess.
        static const char* kNFBPillBarMissKey = "nfbPillBarMiss";
        if (!objc_getAssociatedObject(pill, kNFBPillBarMissKey)) {
            objc_setAssociatedObject(pill, kNFBPillBarMissKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSMutableArray<NSString*>* chain = [NSMutableArray array];
            UIView* node = pill.superview;
            NSInteger hops = 0;
            while (node && hops < 40) {
                [chain addObject:NSStringFromClass([node classForCoder])];
                node = node.superview;
                hops++;
            }
            NFBDebugLog(@"pill: barre INTROUVABLE <%p> chaine=%@",
                        pill, [chain componentsJoinedByString:@" > "]);
        }
        return;
    }

    // The real content: the stack with the label and the chevron.
    UIStackView* stack = nil;
    for (UIView* sub in pill.subviews) {
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

    UIView* mirror = objc_getAssociatedObject(bar, kNFBPillMirrorKey);

    if (!nfbLiquidGlassEnabled()) {
        // Standard interface: no platter, no blink — nothing of ours belongs
        // here. Whatever a previous state left behind is undone.
        if (mirror) {
            [mirror removeFromSuperview];
            objc_setAssociatedObject(bar, kNFBPillMirrorKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        stack.hidden = NO;
        return;
    }
    if (!stack || !realLabel) {
        // A structure this code does not recognise, named once — a silent
        // mirror must never read as a mystery. The native content stays.
        static BOOL warned;
        if (!warned) {
            warned = YES;
            NFBDebugLog(@"pill: structure inattendue (stack=%d, label=%d) — miroir inactif",
                        stack != nil, realLabel != nil);
        }
        return;
    }
    if (CGSizeEqualToSize(stack.bounds.size, CGSizeZero)) {
        return;  // still growing; the next sized layout will carry it
    }

    UILabel* mirrorLabel;
    UIImageView* mirrorChevron;
    if (!mirror) {
        // CREATION is gated on the inbox being on the glass. The journal of
        // 16/08 21:00 showed the race twice (51.711, 54.650): the drop fires
        // exactly when the container leaves, then a late layout of the
        // departing pill — still in the window for ~500 ms — re-posed a fresh
        // mirror that nothing would ever drop. The container is tracked by
        // the watch above; before the watch exists (first ever pose) it is
        // nil and the pose proceeds, which is correct: the screen is up.
        // Syncs of an existing mirror never pass through here.
        UIView* inbox = gNFBInboxContainer;
        if (inbox && !inbox.window) {
            NFBDebugLog(@"pill: pose refusee (inbox hors fenetre)");
            return;
        }
        mirror = [UIView new];
        mirror.userInteractionEnabled = NO;  // every touch reaches the real pill
        mirror.layer.zPosition = 100;        // above anything the re-host adds
        mirrorLabel = [UILabel new];
        mirrorLabel.tag = 1;
        [mirror addSubview:mirrorLabel];
        mirrorChevron = [UIImageView new];
        mirrorChevron.tag = 2;
        [mirror addSubview:mirrorChevron];
        [bar addSubview:mirror];
        objc_setAssociatedObject(bar, kNFBPillMirrorKey, mirror,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gNFBInboxMirrorBar = bar;
        nfbInstallContainerWatch();
        NFBMark(mirror, @"NavBarIcons/inboxPill → miroir");
        NFBDebugLog(@"pill: miroir posé dans %@",
                    NSStringFromClass([bar classForCoder]));
    } else {
        mirrorLabel = (UILabel*)[mirror viewWithTag:1];
        mirrorChevron = (UIImageView*)[mirror viewWithTag:2];
        if (mirror.superview != bar) {
            [bar addSubview:mirror];
        }
    }

    // The sync is acting: this pill is now the mirror's source. A handover —
    // measured on every return to Messages — is named with both pointers, so
    // the journal shows the re-bind (or its absence) without costing a build.
    UIView* previousSource = gNFBInboxMirrorSourcePill;
    if (previousSource != pill) {
        if (previousSource) {
            NFBDebugLog(@"pill: source re-liee <%p> -> <%p>", previousSource, pill);
        }
        gNFBInboxMirrorSourcePill = pill;
    }

    // Text and imagery are copied from the real content; geometry is NOT.
    // The device capture settled why: the mirror only gets to sync during the
    // re-host turbulence, exactly when the real label's frame reads {0,0} — a
    // copied frame is a copied zero, and the mirror held "All" at size zero,
    // invisible, for as long as the screen stayed still. So the sizes are
    // DERIVED from the copied text and image, which are valid at any instant,
    // and the copied frames are never consulted.
    CGRect slot = [stack convertRect:stack.bounds toView:bar];
    if (CGRectIsEmpty(slot)) {
        return;  // a teardown-moment convert; the last good sync stands
    }
    // A mid-morph convert carries the bar's scale — measured at 1.2x in the
    // capture, and seen on screen as the "All" that drifts. Geometry is taken
    // only from a convert that is one-to-one with the stack; otherwise the last
    // settled geometry stands and only the content refreshes. With no settled
    // geometry yet, the native content stays on: nothing of ours is shown from
    // a slot that cannot be trusted.
    BOOL settled =
        fabs(slot.size.width  - stack.bounds.size.width)  <= stack.bounds.size.width  * 0.05 &&
        fabs(slot.size.height - stack.bounds.size.height) <= stack.bounds.size.height * 0.05;
    NSValue* heldSlot = objc_getAssociatedObject(mirror, kNFBPillMirrorSlotKey);
    if (settled) {
        mirror.frame = slot;
    } else if (!heldSlot) {
        // No settled geometry yet — the entry cascade. Refusing to show here
        // starved the cover for the whole cascade and handed the screen back
        // to the blinking native content: the flash returned. So the slot is
        // taken PROVISIONALLY — the cover is up from the first sized layout —
        // and the settling pass below snaps it to the rest geometry within a
        // beat. A bounded, transient drift against a flash: the flash loses.
        mirror.frame = slot;
    }

    mirrorLabel.attributedText = realLabel.attributedText;
    if (!mirrorLabel.attributedText.length && realLabel.text.length) {
        mirrorLabel.text = realLabel.text;
        mirrorLabel.font = realLabel.font;
        mirrorLabel.textColor = realLabel.textColor;
    }
    [mirrorLabel sizeToFit];

    CGFloat spacing = stack.spacing > 0 ? stack.spacing : 2.0;
    CGSize chevronSize = CGSizeZero;
    if (realChevron.image) {
        mirrorChevron.hidden = NO;
        mirrorChevron.image = realChevron.image;
        mirrorChevron.tintColor = realChevron.tintColor;
        mirrorChevron.contentMode = realChevron.contentMode;
        chevronSize = CGRectIsEmpty(realChevron.frame)
            ? realChevron.image.size
            : realChevron.frame.size;
    } else {
        mirrorChevron.hidden = YES;
    }

    CGSize labelSize = mirrorLabel.bounds.size;
    CGFloat height = mirror.bounds.size.height;
    mirrorLabel.frame = CGRectMake(0,
                                   (height - labelSize.height) / 2.0,
                                   labelSize.width, labelSize.height);
    if (!mirrorChevron.hidden) {
        mirrorChevron.frame = CGRectMake(labelSize.width + spacing,
                                         (height - chevronSize.height) / 2.0,
                                         chevronSize.width, chevronSize.height);
    }

    if (NFBDebugIsRecording() && CGSizeEqualToSize(labelSize, CGSizeZero)) {
        NFBDebugLog(@"pill: miroir sans texte mesurable");
    }

    // The blinking original steps aside; the mirror is what is seen.
    stack.hidden = YES;

    // The last sync of a cascade can land mid-morph, when the convert carries
    // the bar's 1.2× transform — the capture showed exactly that geometry held
    // at rest. So a settling pass is scheduled whenever the slot CHANGED: it
    // re-reads the live pill a beat later, and the chain stops by itself the
    // first time two passes agree. Converges in two passes at most.
    if (settled) {
        if (!heldSlot || !CGRectEqualToRect(heldSlot.CGRectValue, slot)) {
            objc_setAssociatedObject(mirror, kNFBPillMirrorSlotKey,
                                     [NSValue valueWithCGRect:slot],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            nfbScheduleMirrorResync(pill);
        }
    } else {
        // Turbulence: one more pass a beat later converges on the rest state.
        nfbScheduleMirrorResync(pill);
    }
}

%hook _TtC7DMInbox39InboxNavigationBarMenuBarButtonItemView

// willMoveToWindow: and didAddSubview: used to be hooked here as well. The
// health report measured both as never landing — this Swift class does not
// redefine either method, and Logos on a method the class does not own is the
// exact trap the container watch documents above. Their only job was opacity
// pinning, which didMoveToWindow and layoutSubviews below already cover, and
// nfbForceOpaque walks the subtree. Removed rather than kept as dead weight:
// the health banner dropping from 5 flags to 3 is this build's own receipt.
- (void)didMoveToWindow {
    %orig;
    if (!((UIView*)self).window) {
        return;
    }
    nfbForceOpaque((UIView*)self);
    nfbMirrorInboxPill((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    nfbForceOpaque((UIView*)self);
    // Replacements arrive zero-sized and grow; the mirror is synced here, at
    // every layout that has a real size — text, chevron and frames copied from
    // the real content each pass.
    nfbMirrorInboxPill((UIView*)self);
}

%end
