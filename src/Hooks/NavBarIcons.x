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

// MARK: the re-host gap — the measured fact the ride is built on
//
// Measured at 60 fps: on returning to the Messages list the pill is REMOVED
// from the hierarchy for about six frames and then recreated — the avatar and
// the title hold perfectly still while its pixel count goes 781 → 0 → 780.
// Nothing fades and nothing transforms; the view simply is not there. That is
// why refusing animations, of any kind, changed nothing: there was never an
// animation to refuse. The platter re-hosts its SwiftUI content, and the gap
// between the old instance leaving and the new one arriving is the flash.
// (The snapshot bridge, the curtain and the pinned mirror all tried to cover
// that gap from the outside; their measured post-mortems live in the project
// journal. The block below replaces them all.)

// THE RIDE — the pill's text travels WITH the platter.
//
// Twenty builds taught one structural lesson, measured on video at 60 fps:
// every covering strategy so far — tint, opacity pinning, snapshot bridge,
// persistent curtain, glass, understudy, pinned mirror — was the same idea in
// different clothes: hold a static cover and chase content that the platter
// destroys and moves. A static cover on an animated platter can only relocate
// the artifact. The 21:34 video shows its terminal form: on every return the
// pinned text sits 3.7 pt left of rest for 567 ms and then snaps right in two
// frames, and around every transition the region goes empty because the
// content dies before it can draw.
//
// The one invariant every measurement agreed on (video 16:17: not a single
// missing frame): the CAPSULE never dies and animates smoothly. So the anchor
// changes sides. The text is no longer pinned to a slot and synced from the
// mortal content — it RIDES the platter: a display link reads the platter's
// presentation geometry every frame and places the text centred inside it,
// with the platter's own composite opacity. Morphs, re-hosts and fades are
// no longer fought; they are followed. Content (label text, font, colour,
// chevron) still copies from the real stack whenever the real stack exists,
// and simply holds while it is being rebuilt.
//
// The build measures itself (the debugger is the test bench): every ride
// episode ends with a summary line — tick count, x/y envelope, at-rest jumps,
// anchor re-links — and any fault (jump at rest, unresolvable platter, lost
// anchor) is named in DECISIONS with the data needed to fix it without a
// guess. The receipts for THIS build are written in those lines.

@interface NFBRideDriver : NSObject
- (void)nfbRideTick:(CADisplayLink*)link;
@end

static const char* kNFBPillMirrorKey = "nfbPillMirror";

// The tweak's own Liquid Glass switch, read the same way the rest of the file
// reads its settings.
static BOOL nfbLiquidGlassEnabled(void) {
    return [BHTSettings boolForKey:@"enable_liquid_glass"];
}

// The bar the mirror hangs on (weak: the bar owns itself), the pill instance
// the content last copied from, and the platter the geometry rides.
static __weak UIView* gNFBInboxMirrorBar;
static __weak UIView* gNFBInboxMirrorSourcePill;
static __weak UIView* gNFBPillPlatter;

// The container instance, kept weak so creation can ask the only structural
// question that matters: is the inbox on the glass right now? (Measured
// 21:00:51.711: a stray layout of the departing pill once re-posed an orphan.)
static void (*gNFBOrigContainerWillMove)(id, SEL, UIWindow*);
static __weak UIView* gNFBInboxContainer;

// Exit choreography: when the container leaves, the ride carries the text out
// with the capsule and the tick's fuse takes it down — faded, recycled, or
// timed out — instead of a hard drop that leaves an empty capsule behind
// (measured: the pill outlives the container by ~500 ms on every exit).
static BOOL     gNFBInboxLeaving;
static int      gNFBRideOffTicks;
static CGFloat  gNFBRideMinAlphaLeaving = 1.0;

// The ride itself.
static CADisplayLink*  gNFBRideLink;
static NFBRideDriver*  gNFBRideDriver;
static CGFloat         gNFBRideSpacing = 4.0;

// Telemetry — this build's own receipts.
static int     gNFBRideTicks;
static CGFloat gNFBRideMinX, gNFBRideMaxX, gNFBRideMinY, gNFBRideMaxY;
static int     gNFBRideRestJumps;
static int     gNFBRideRelinks;
static CGFloat gNFBRideRelinkMaxDelta;
static CGRect  gNFBRideLastFrame;
static BOOL    gNFBRideLastAtRest;

// Defined below; declared here so the driver and the watch can call them.
static void nfbDropInboxMirror(UIView* bar);
static void nfbStopRide(void);

@implementation NFBRideDriver

- (void)nfbRideTick:(CADisplayLink*)link {
    UIView* bar = gNFBInboxMirrorBar;
    UIView* mirror = bar ? objc_getAssociatedObject(bar, kNFBPillMirrorKey) : nil;
    if (!bar || !mirror || !nfbLiquidGlassEnabled()) {
        if (bar && mirror) {
            nfbDropInboxMirror(bar);
        } else {
            nfbStopRide();
        }
        return;
    }
    UIView* platter = gNFBPillPlatter;
    if (!platter || !platter.window) {
        NFBDebugLog(@"pill: ride — platine morte, drop");
        nfbDropInboxMirror(bar);
        return;
    }

    // The animated truth: convert through the PRESENTATION tree, so every
    // in-flight transform of every ancestor is included. The model convert is
    // both the sanity fallback and the at-rest reference.
    CGRect model = [bar convertRect:platter.bounds fromView:platter];
    CALayer* pres = platter.layer.presentationLayer ?: platter.layer;
    CALayer* barPres = bar.layer.presentationLayer ?: bar.layer;
    CGRect r = [pres convertRect:pres.bounds toLayer:barPres];
    BOOL sane = !isnan(r.origin.x) && !isnan(r.origin.y) &&
                r.size.width > 0 && r.size.width < 2000 &&
                fabs(r.origin.x) < 4000 && fabs(r.origin.y) < 4000;
    if (!sane) {
        r = model;
    }

    // Composite opacity of the platter chain, presentation values included —
    // the text fades exactly as the capsule fades, in and out.
    CGFloat alpha = 1.0;
    UIView* v = platter;
    NSInteger depth = 0;
    while (v && v != bar && depth < 40) {
        CALayer* pl = v.layer.presentationLayer ?: v.layer;
        alpha *= pl.opacity;
        if (v.hidden) { alpha = 0; }
        v = v.superview;
        depth++;
    }

    BOOL atRest = fabs(r.origin.x - model.origin.x) < 0.1 &&
                  fabs(r.origin.y - model.origin.y) < 0.1 &&
                  fabs(r.size.width - model.size.width) < 0.1;

    UILabel* label = (UILabel*)[mirror viewWithTag:1];
    UIImageView* chevron = (UIImageView*)[mirror viewWithTag:2];
    CGFloat lw = label.bounds.size.width, lh = label.bounds.size.height;
    CGFloat cw = chevron.hidden ? 0 : chevron.bounds.size.width;
    CGFloat chh = chevron.hidden ? 0 : chevron.bounds.size.height;
    CGFloat sp = (chevron.hidden || cw <= 0) ? 0 : gNFBRideSpacing;
    CGFloat total = lw + sp + cw;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mirror.frame = r;
    // Centred in the ridden rect — the measured rest layout IS centred:
    // platter 57.33x44, stack 37.33x16 at {10, 14} = dead centre both ways.
    CGFloat x0 = (r.size.width - total) / 2.0;
    label.frame = CGRectMake(x0, (r.size.height - lh) / 2.0, lw, lh);
    if (!chevron.hidden) {
        chevron.frame = CGRectMake(x0 + lw + sp,
                                   (r.size.height - chh) / 2.0, cw, chh);
    }
    mirror.alpha = alpha;
    [CATransaction commit];

    // ---- telemetry: the receipts of this build ----
    if (gNFBRideTicks == 0) {
        gNFBRideMinX = gNFBRideMaxX = r.origin.x;
        gNFBRideMinY = gNFBRideMaxY = r.origin.y;
        gNFBRideLastFrame = r;
        gNFBRideLastAtRest = atRest;
    }
    gNFBRideTicks++;
    if (r.origin.x < gNFBRideMinX) { gNFBRideMinX = r.origin.x; }
    if (r.origin.x > gNFBRideMaxX) { gNFBRideMaxX = r.origin.x; }
    if (r.origin.y < gNFBRideMinY) { gNFBRideMinY = r.origin.y; }
    if (r.origin.y > gNFBRideMaxY) { gNFBRideMaxY = r.origin.y; }
    if (atRest && gNFBRideLastAtRest) {
        CGFloat dx = fabs(r.origin.x - gNFBRideLastFrame.origin.x);
        CGFloat dy = fabs(r.origin.y - gNFBRideLastFrame.origin.y);
        if (dx > 0.5 || dy > 0.5) {
            gNFBRideRestJumps++;
            if (gNFBRideRestJumps <= 3) {
                NFBDebugLog(@"pill: RIDE FAUTE — saut au repos dx=%.1f dy=%.1f pt",
                            dx, dy);
            }
        }
    }
    gNFBRideLastFrame = r;
    gNFBRideLastAtRest = atRest;

    // ---- exit fuse ----
    if (gNFBInboxLeaving) {
        if (alpha < gNFBRideMinAlphaLeaving) { gNFBRideMinAlphaLeaving = alpha; }
        gNFBRideOffTicks++;
        BOOL faded = alpha < 0.05;
        BOOL recycled = gNFBRideMinAlphaLeaving < 0.2 &&
                        alpha > gNFBRideMinAlphaLeaving + 0.3;
        if (faded || recycled || gNFBRideOffTicks > 90) {
            NFBDebugLog(@"pill: ride sortie — %@ (%.0f ms)",
                        faded ? @"fondu complet"
                              : (recycled ? @"platine recyclee" : @"fusible"),
                        gNFBRideOffTicks * (1000.0 / 60.0));
            nfbDropInboxMirror(bar);
            return;
        }
    }
}

@end

static void nfbContainerWillMoveToWindow(id self, SEL _cmd, UIWindow* newWindow) {
    gNFBInboxContainer = self;
    if (!newWindow) {
        if (gNFBRideLink && gNFBInboxMirrorBar) {
            // The text rides out with the capsule; the tick's fuse drops it
            // faded instead of cutting it here and leaving an empty capsule
            // for the ~500 ms the pill outlives the container.
            gNFBInboxLeaving = YES;
            gNFBRideOffTicks = 0;
            gNFBRideMinAlphaLeaving = 1.0;
            NFBDebugLog(@"pill: sortie — le texte suit la capsule");
        } else if (gNFBInboxMirrorBar) {
            nfbDropInboxMirror(gNFBInboxMirrorBar);
        }
    } else {
        gNFBInboxLeaving = NO;
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

static void nfbStartRide(void) {
    if (gNFBRideLink) {
        return;
    }
    if (!gNFBRideDriver) {
        gNFBRideDriver = [NFBRideDriver new];
    }
    gNFBRideLink = [CADisplayLink displayLinkWithTarget:gNFBRideDriver
                                               selector:@selector(nfbRideTick:)];
    [gNFBRideLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];
    NFBDebugLog(@"pill: ride demarre");
}

static void nfbStopRide(void) {
    [gNFBRideLink invalidate];
    gNFBRideLink = nil;
}

static void nfbDropInboxMirror(UIView* bar) {
    UIView* mirror = objc_getAssociatedObject(bar, kNFBPillMirrorKey);
    if (!mirror) {
        return;
    }
    nfbStopRide();
    if (gNFBRideTicks > 0) {
        // The episode's receipt: envelope, at-rest jumps, anchor re-links.
        NFBDebugLog(@"pill: ride fini — %d ticks, x %.1f-%.1f, y %.1f-%.1f, "
                    @"sauts_repos=%d, re-liees=%d (max %.1f pt)",
                    gNFBRideTicks, gNFBRideMinX, gNFBRideMaxX,
                    gNFBRideMinY, gNFBRideMaxY,
                    gNFBRideRestJumps, gNFBRideRelinks, gNFBRideRelinkMaxDelta);
    }
    // The native content steps back in — whatever happens after us is
    // Twitter's own drawing, exactly what standard mode shows.
    BOOL restored = NO;
    UIView* source = gNFBInboxMirrorSourcePill;
    for (UIView* sub in source.subviews) {
        if ([sub isKindOfClass:[UIStackView class]]) {
            sub.hidden = NO;
            restored = YES;
            break;
        }
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
    gNFBPillPlatter = nil;
    gNFBInboxLeaving = NO;
    gNFBRideTicks = 0;
    gNFBRideRestJumps = 0;
    gNFBRideRelinks = 0;
    gNFBRideRelinkMaxDelta = 0;
    [mirror removeFromSuperview];
    NFBDebugLog(restored ? @"pill: miroir retire (natif rendu)"
                         : @"pill: miroir retire");
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
    // Audit of 16/08: this was the only silent, persistent failure path of
    // the sync. When a mirror is already up, its bar is the fallback — the
    // descendant test walks the whole chain, uncapped, with no class check.
    UIView* mirrorBar = gNFBInboxMirrorBar;
    if (mirrorBar && [pill isDescendantOfView:mirrorBar]) {
        return mirrorBar;
    }
    return nil;
}

// The view the geometry rides: the glass platter above the pill. Measured in
// the 21:31 capture: DMInbox...ItemView sits under UIPlatformGlassInteractionView
// {{362.67, 0}, {57.33, 44}} inside the bar. The container_v2 is the fallback
// if the interaction view ever renames; both are named in the journal.
static UIView* nfbPillPlatterFor(UIView* pill) {
    UIView* node = pill.superview;
    UIView* fallback = nil;
    NSInteger depth = 0;
    while (node && depth < 32) {
        NSString* cls = NSStringFromClass([node classForCoder]);
        if ([cls containsString:@"PlatformGlass"]) {
            return node;
        }
        if (!fallback && [cls containsString:@"Platter"]) {
            fallback = node;
        }
        if ([node isKindOfClass:[UINavigationBar class]]) {
            break;
        }
        node = node.superview;
        depth++;
    }
    return fallback;
}

static void nfbMirrorInboxPill(UIView* pill) {
    if (CGSizeEqualToSize(pill.bounds.size, CGSizeZero) || !pill.window) {
        return;
    }
    UIView* bar = nfbPillBar(pill);
    if (!bar) {
        // Named, never silent — this exact silence is what froze the mirror
        // on 16/08. One line per instance, WITH the chain.
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
        // here. One teardown path for every state.
        if (mirror) {
            nfbDropInboxMirror(bar);
        }
        stack.hidden = NO;
        return;
    }
    if (!stack || !realLabel) {
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

    // The geometry's anchor. Without it, nothing is hidden and nothing is
    // shown of ours — fail loud, native stays.
    UIView* platter = nfbPillPlatterFor(pill);
    if (!platter) {
        static const char* kNFBPlatterMissKey = "nfbPillPlatterMiss";
        if (!objc_getAssociatedObject(pill, kNFBPlatterMissKey)) {
            objc_setAssociatedObject(pill, kNFBPlatterMissKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSMutableArray<NSString*>* chain = [NSMutableArray array];
            UIView* node = pill.superview;
            NSInteger hops = 0;
            while (node && hops < 40) {
                [chain addObject:NSStringFromClass([node classForCoder])];
                node = node.superview;
                hops++;
            }
            NFBDebugLog(@"pill: platine INTROUVABLE <%p> chaine=%@",
                        pill, [chain componentsJoinedByString:@" > "]);
        }
        stack.hidden = NO;
        return;
    }

    UILabel* mirrorLabel;
    UIImageView* mirrorChevron;
    if (!mirror) {
        // CREATION is gated on the inbox being on the glass (measured race
        // of 21:00: a late layout of the departing pill re-posed an orphan).
        UIView* inbox = gNFBInboxContainer;
        if (inbox && !inbox.window) {
            stack.hidden = NO;
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
        NFBMark(mirror, @"NavBarIcons/inboxPill → ride");
        NFBDebugLog(@"pill: miroir posé dans %@ — le texte suivra la platine",
                    NSStringFromClass([bar classForCoder]));
    } else {
        mirrorLabel = (UILabel*)[mirror viewWithTag:1];
        mirrorChevron = (UIImageView*)[mirror viewWithTag:2];
        if (mirror.superview != bar) {
            [bar addSubview:mirror];
        }
    }

    // Anchor bind or handover — always named, with the switch delta so a
    // visible jump can be traced to its exact re-link.
    UIView* previousPlatter = gNFBPillPlatter;
    if (previousPlatter != platter) {
        NSString* cls = NSStringFromClass([platter classForCoder]);
        if (previousPlatter) {
            CGFloat delta = 0;
            if (previousPlatter.window) {
                CGRect a = [bar convertRect:previousPlatter.bounds
                                   fromView:previousPlatter];
                CGRect b = [bar convertRect:platter.bounds fromView:platter];
                delta = MAX(fabs(a.origin.x - b.origin.x),
                            fabs(a.origin.y - b.origin.y));
            }
            gNFBRideRelinks++;
            if (delta > gNFBRideRelinkMaxDelta) { gNFBRideRelinkMaxDelta = delta; }
            NFBDebugLog(@"pill: ancre re-liee <%p> -> <%p> (%@) delta=%.1f pt",
                        previousPlatter, platter, cls, delta);
        } else {
            NFBDebugLog(@"pill: ancre platine posee: %@ <%p>", cls, platter);
        }
        gNFBPillPlatter = platter;
        // First position immediately — the tick refines 16 ms later.
        mirror.frame = [bar convertRect:platter.bounds fromView:platter];
    }
    nfbStartRide();

    // Content handover, named with both pointers.
    UIView* previousSource = gNFBInboxMirrorSourcePill;
    if (previousSource != pill) {
        if (previousSource) {
            NFBDebugLog(@"pill: source re-liee <%p> -> <%p>", previousSource, pill);
        }
        gNFBInboxMirrorSourcePill = pill;
    }

    // CONTENT ONLY — geometry belongs to the ride tick. Text, font, colour
    // and chevron copy from the real thing whenever it exists, and simply
    // hold while the platter rebuilds it.
    mirrorLabel.attributedText = realLabel.attributedText;
    if (!mirrorLabel.attributedText.length && realLabel.text.length) {
        mirrorLabel.text = realLabel.text;
        mirrorLabel.font = realLabel.font;
        mirrorLabel.textColor = realLabel.textColor;
    }
    [mirrorLabel sizeToFit];
    gNFBRideSpacing = stack.spacing > 0 ? stack.spacing : 4.0;
    if (realChevron.image) {
        mirrorChevron.hidden = NO;
        mirrorChevron.image = realChevron.image;
        mirrorChevron.tintColor = realChevron.tintColor;
        mirrorChevron.contentMode = realChevron.contentMode;
        CGSize chevronSize = CGRectIsEmpty(realChevron.frame)
            ? realChevron.image.size
            : realChevron.frame.size;
        mirrorChevron.bounds = (CGRect){CGPointZero, chevronSize};
    } else {
        mirrorChevron.hidden = YES;
    }
    if (NFBDebugIsRecording() &&
        CGSizeEqualToSize(mirrorLabel.bounds.size, CGSizeZero)) {
        NFBDebugLog(@"pill: miroir sans texte mesurable");
    }

    // The blinking original steps aside; the ridden text is what is seen.
    stack.hidden = YES;
}

%hook _TtC7DMInbox39InboxNavigationBarMenuBarButtonItemView

// willMoveToWindow: and didAddSubview: used to be hooked here as well. The
// health report measured both as never landing — this Swift class does not
// redefine either method. Their only job was opacity pinning, which the two
// methods below already cover, and nfbForceOpaque walks the subtree.
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
    // Replacements arrive zero-sized and grow; the content is synced here, at
    // every layout that has a real size. Geometry never is — the ride owns it.
    nfbMirrorInboxPill((UIView*)self);
}

%end
