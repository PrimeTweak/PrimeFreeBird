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
// Marks an image the tweak produced. Two paths repaint on Notifications, and
// without the mark each treats the other's result as unpainted. The mark travels
// with the image, so any path recognises it.
static const void* kNFBPaintedFlagKey = &kNFBPaintedFlagKey;
// Marks a layer that must never render at partial opacity. Correcting afterwards
// is too late, so every route that could lower it is refused as it is used: the
// alpha, the layer's opacity and the animation.
static const void* kNFBNoFadeKey = &kNFBNoFadeKey;
// Marks a bar item already asked to go without the shared glass, so the request
// is made once instead of on every layout pass.
static const void* kNFBFlatItemKey = &kNFBFlatItemKey;

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

// Exported under its own name: QuickMutedWords.x carries a private copy of
// NFBGreyGlyph, so that symbol cannot be made public without a clash.
UIImage* NFBPaintedGlyph(UIImage* source, UIColor* colour) {
    return NFBGreyGlyph(source, colour);
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
            // Repaint when the image changed or when the colour did. At launch the
            // trait collection is unsettled, so labelColor resolves differently and
            // the first paint comes out pale.
            UIColor* usedColour = objc_getAssociatedObject(imageView, kNFBGreyTargetKey);
            BOOL colourChanged = usedColour && ![usedColour isEqual:colour];
            BOOL alreadyOurs =
                objc_getAssociatedObject(current, kNFBPaintedFlagKey) != nil;

            // The painted flag records that the tweak painted the image, not that
            // it painted it for this view: a glyph baked elsewhere carries it too,
            // so the recorded image is compared as well.
            if (current && alreadyOurs && ours && current != ours && !colourChanged) {
                imageView.image = ours;
                static BOOL said;
                if (!said) {
                    said = YES;
                    NFBDebugLog(@"glyph: view image restored (repainted elsewhere)");
                }
            } else if (current && !alreadyOurs && (current != ours || colourChanged)) {
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
        // The encrypted chat, the regular DM conversation and this tweak's own
        // settings screens, each named by its controller so no other screen is
        // reached. Their trailing glyphs take the label-colour bake at first set.
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

// The container holding the bar and the tab strip, reached from the bar upwards.
// The walk stops before the first view tall enough to be the screen itself, so
// only the header band is held.
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

// The notifications tab is named after activity, and the bar belongs to the
// All/Mentions container, whose name says nothing. Both spellings are accepted,
// and children and parents are searched as well as the controller.
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

// On Notifications the gear is a bar button item, so its image is repainted
// directly. The caller has established the bar; icon-only items are picked here,
// so a text button is never touched.
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

        // The painted flag records that the tweak painted the image, not that it
        // painted it for this button. A tweak image that is not the recorded one
        // was overwritten by another path, so the recorded one is put back.
        if (alreadyOurs && ours && button.image != ours && !colourChanged) {
            button.image = ours;
            static BOOL said;
            if (!said) {
                said = YES;
                NFBDebugLog(@"glyph: bar icon restored (it had been repainted elsewhere)");
            }
            continue;
        }
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

// The gear and the avatar are Twitter's own bar items, so the flat treatment the
// tweak already applies to its own buttons is asked of them here. Icon-only items
// only: a text button such as Done keeps the capsule iOS gives it.
static void nfbFlattenBarItemGlass(UIView* bar) {
    if (![BHTSettings boolForKey:@"enable_liquid_glass"] ||
        ![bar respondsToSelector:@selector(topItem)]) {
        return;
    }
    UINavigationItem* item =
        ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    if (!item) {
        return;
    }
    SEL hideShared = NSSelectorFromString(@"setHidesSharedBackground:");
    NSMutableArray<UIBarButtonItem*>* items = [NSMutableArray array];
    [items addObjectsFromArray:item.leftBarButtonItems ?: @[]];
    [items addObjectsFromArray:item.rightBarButtonItems ?: @[]];
    for (UIBarButtonItem* button in items) {
        if (![button isKindOfClass:[UIBarButtonItem class]] ||
            button.title.length > 0 ||
            objc_getAssociatedObject(button, kNFBFlatItemKey) != nil ||
            ![button respondsToSelector:hideShared]) {
            continue;
        }
        objc_setAssociatedObject(button, kNFBFlatItemKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(button, hideShared, YES);
        NFBDebugLog(@"[p24] bar item flattened: image=%@ customView=%@",
                    button.image ? @"yes" : @"no",
                    button.customView
                        ? NSStringFromClass([button.customView class])
                        : @"none");
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
        nfbFlattenBarItemGlass(bar);

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

// Twitter puts its own image back after a repaint and nothing calls back until
// the bar lays out, so the image is caught as it is set. Only views already taken
// over are affected; everything else pays one associated-object read.

// The colour a bar glyph should carry: the text colour, resolved for the
// current appearance.
static UIColor* nfbBarGlyphColour(UIView* view) {
    UIColor* colour = [UIColor labelColor];
    if (view && [colour respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [colour resolvedColorWithTraitCollection:view.traitCollection] ?: colour;
    }
    return colour;
}

// The button's own chain, four levels at most, and never past the button. Above it
// sits the platter host every item of the bar draws from, so a tint written there
// fills the glass capsule of the siblings too.
static void nfbTintGlyphChain(UIView* view, UIColor* colour) {
    UIView* node = view;
    NSInteger depth = 0;
    while (node && depth < 4) {
        NSString* name = NSStringFromClass([node class]);
        if ([node isKindOfClass:[UINavigationBar class]] ||
            [name containsString:@"Platter"] ||
            [name containsString:@"ItemWrapperView"]) {
            return;
        }
        if (![node.tintColor isEqual:colour]) {
            node.tintColor = colour;
        }
        node = node.superview;
        depth++;
    }
}

// True of a back button's own subtree only: _UIBackButtonMaskView is created for
// back buttons and nothing else. Class names are read, never touched, and no view
// in the subtree is painted.
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

%hook UIImageView

// The second half of the two-step claim: the button is in the bar, the chain
// reaches the navigation controller, the screen is finally readable.
- (void)didMoveToWindow {
    %orig;
    if (!((UIView*)self).window) {
        return;
    }
    // Cold-start belt for the conversation bar: on the first conversation after a
    // relaunch, setImage: fires before the button is attached and the retry cannot
    // read the chain. Here the chain is complete by definition.
    UIImage* chatImage = self.image;
    if (chatImage &&
        chatImage.renderingMode != UIImageRenderingModeAlwaysOriginal &&
        (nfbIsChatBarGlyph((UIView*)self) ||
         nfbIsBackArrowGlyph((UIView*)self))) {
        UIColor* colour = nfbBarGlyphColour((UIView*)self);
        UIImage* baked = NFBGreyGlyph(chatImage, colour);
        if (baked) {
            NFBDebugLog(@"glyph: chat bar baked at didMoveToWindow (cold start)");
            NFBMark((UIView*)self, @"NavBarIcons/chatBarGlyph -> baked (window)");
            nfbTintGlyphChain((UIView*)self, colour);
            self.image = baked;  // AlwaysOriginal: re-enters the setter and passes through
        }
    }
}

- (void)setImage:(UIImage*)image {
    UIColor* target = objc_getAssociatedObject(self, kNFBGreyTargetKey);
    if (!target || !image) {
        // Not "== AlwaysTemplate": a bar glyph usually arrives in automatic mode,
        // which a bar button draws as a template all the same, so anything not
        // already original is claimed. Correcting the mode provokes no layout.
        if (image.renderingMode != UIImageRenderingModeAlwaysOriginal) {
            if (nfbIsChatBarGlyph((UIView*)self) ||
                nfbIsBackArrowGlyph((UIView*)self)) {
                // Baked at the setter: whoever writes last, the pixels that
                // land carry the colour. A mode change alone leaves an alpha mask,
                // which a bar button re-tints per its own contrast rule.
                UIColor* colour = nfbBarGlyphColour((UIView*)self);
                UIImage* baked = NFBGreyGlyph(image, colour);
                NFBMark((UIView*)self,
                        nfbIsBackArrowGlyph((UIView*)self)
                            ? @"NavBarIcons/backArrow -> baked"
                            : @"NavBarIcons/chatBarGlyph -> baked");
                // Belt for the one frame a freshly created button can show
                // before its first baked image lands: with the button's own
                // chain tinted, even a frame treated as a template is right.
                nfbTintGlyphChain((UIView*)self, colour);
                %orig(baked ?: image);
                return;
            }
            // A bar button is given its image before it is placed in the bar, so
            // the ancestors that name it do not exist yet. The question is asked
            // again on the next run-loop turn, outside any layout pass.
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

// The same treatment as Explore, reached from the other side: Notifications
// builds its bar differently, so the gear is not found in the bar's subtree, but
// the button class is the one Twitter uses everywhere.

// A bar button qualifies only as an icon on the right-hand side: no title, a
// glyph-sized image inside, and past the middle of its own bar. A back chevron
// and a text button are both excluded by that.
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

// The repaint runs on both entry points: didMoveToWindow alone catches the button
// before its image view exists on Notifications, so nothing is marked and the
// interception never arms. Once marked, every later pass is a pointer comparison.
%new
- (void)nfbGreySettingsGlyphIfNeeded {
    @try {
        UIView* button = (UIView*)self;
        if (!button.window) {
            return;
        }
        // Either the button identifies itself as the settings one, which covers
        // Explore, or the screen is Notifications, where no view carries that
        // identifier and the gear is the only icon in the bar.
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

// The platter that holds the bar's buttons: wider than the pill test above,
// narrower than the whole bar. Bounded and class-name only, since this runs on an
// animation path.
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

// 12.21: the vibrancy filter is also animated onto the tab bar's icons. Only
// while a themed bar is switched on; otherwise the bar keeps its glass.
static BOOL NFBViewSitsInXTabBar(UIView* view) {
    if (!NFBThemedTabBarWanted()) {
        return NO;
    }
    Class xBar = NSClassFromString(@"_TtC11XNavigation10TabBarView");
    if (!xBar) {
        return NO;
    }
    for (UIView* v = view; v; v = v.superview) {
        if ([v isKindOfClass:xBar]) {
            return YES;
        }
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

    // 12.21 on iOS 27: the glass vibrancy filter is animated back onto the logo
    // after the tint is set. Refusing the animation and dropping the filter
    // keeps the logo the chosen colour. Only that one view.
    if (ownerIsView && [key hasPrefix:@"filters."] &&
        (owner == (UIView*)NFBTopBarLogoViewCurrent() || NFBViewSitsInXTabBar(owner))) {
        self.filters = nil;
        static NSInteger refused = 0;
        if (refused < 3) {
            refused++;
            NFBDebugLog(@"[logo] vibrancy animation refused (%@)", key);
        }
        return;
    }

    // Every animation reaching the button platter is recorded, whatever its kind:
    // the fade is not an opacity animation, and a transition or a transform
    // carries no opacity keyPath.
    if (NFBDebugIsRecording() && ownerIsView && nfbViewSitsInBarPlatter(owner)) {
        NSString* path = @"—";
        if ([animation isKindOfClass:[CABasicAnimation class]]) {
            path = ((CABasicAnimation*)animation).keyPath ?: @"nil";
        } else if ([animation isKindOfClass:[CATransition class]]) {
            path = [NSString stringWithFormat:@"transition:%@",
                    ((CATransition*)animation).type ?: @"?"];
        }
        NFBDebugLog(@"platter anim: %@ [%@] key=%@ path=%@ duration=%.2f pill=%@",
                    NSStringFromClass([owner classForCoder]),
                    NSStringFromClass([animation classForCoder]),
                    key ?: @"nil", path, animation.duration,
                    nfbViewSitsInInboxPill(owner) ? @"YES" : @"no");
    }

    // Every animation on this one control is refused, not just opacity: the fade
    // never announces itself as an opacity change. Its neighbours in the same bar
    // are untouched.
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

// The back arrow and the portrait sit in different branches of the bar. Each is
// given its own tint, on itself, and only inside one of Twitter's navigation
// bars: no image is replaced and no parent is walked, so no sibling is caught.





// MARK: - a portrait is not a glyph

// The avatar's image arrives as a template with the accent as its tint, so the
// picture is drawn as a flat disc of it. The rendering mode is corrected on this
// class alone; nothing is repainted and no view is walked.

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

// Left native. Under forced Liquid Glass the platter recreates the pill's content
// on every re-host, so it blinks for about 140 ms; no view in that relay survives
// a cascade. Standard mode does not have it.
