//
//  NavBarIcons.x
//  PrimeFreeBird
//
//  Twitter draws the settings gear at full label strength, which reads as
//  black next to the muted grey of the tab labels beside it.
//
//  Every colour route was tried and each was reclaimed by something: the tint
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

#import "HookHelpers.h"

static NSString* const kNFBSettingsButtonIdentifier = @"NavigationBarSettingsButton";
static const void* kNFBGreyedImageKey = &kNFBGreyedImageKey;
// Holds the colour to force on a view we have taken over, so any image set
// later goes through the same repaint.
static const void* kNFBGreyTargetKey = &kNFBGreyTargetKey;
// The untouched glyph. Repainting is not idempotent — a colour at 60% opacity
// laid over a colour already at 60% lands at 36%, which is the pale flash he
// saw before the icon settled. Every repaint starts from this original.
static const void* kNFBOriginalImageKey = &kNFBOriginalImageKey;
// Marks an image we produced. Two paths repaint on Notifications — the bar
// button item and the image view UIKit builds from it — and each saw the
// other's result as "not mine yet", so the glyph was painted twice and came
// out pale. The mark travels with the image, so any path recognises it.
static const void* kNFBPaintedFlagKey = &kNFBPaintedFlagKey;

// One grey for every icon we add or recolour: the label colour at 60%,
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
                // Only remember the original if this image is not one of ours.
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

static BOOL nfbLooksLikeSettingsButton(UIView* view) {
    NSString* identifier = view.accessibilityIdentifier;
    NSString* label = view.accessibilityLabel;
    return [identifier isEqualToString:kNFBSettingsButtonIdentifier] ||
           [label isEqualToString:kNFBSettingsButtonIdentifier] ||
           [identifier hasPrefix:@"NavigationBarSettings"] ||
           [label hasPrefix:@"NavigationBarSettings"];
}

// The gear fades in when the app opens — Twitter animates its opacity, which
// is the pale pass he sees before the real grey. Our own buttons don't do it
// because we place them ourselves. Snapping this one to full opacity, and
// dropping any opacity animation still running on it, removes the fade for
// the settings gear only. Nothing else in the bar is touched.
static void nfbForceOpaque(UIView* view) {
    if (view.alpha < 1.0) {
        view.alpha = 1.0;
    }
    [view.layer removeAnimationForKey:@"opacity"];
    for (UIView* subview in view.subviews) {
        nfbForceOpaque(subview);
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
// directly. Scoped to that screen, and icon-only items, so a text button like
// "Done" is never touched.
static void nfbRepaintNotificationsGear(UIView* bar, UIColor* colour) {
    if (!nfbControllerIsNotifications(nfbBarOwningController(bar))) {
        return;
    }
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

        UIView* settingsButton = nfbFindSettingsButton(bar);
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

// The frames of his screen recording showed the gear flipping between black
// and grey on one screen: our repaint lands, then Twitter puts its own image
// back, and nothing calls us again until the bar happens to lay out. So the
// image is caught as it is set. Only views we have already taken over are
// affected — everything else pays a single associated-object read.

%hook UIImageView

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
    // Twitter's own image is the source; ours would compound and go pale.
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
// builds its bar differently, so searching the bar's subtree never found the
// gear there — but the button class is the same one Twitter uses everywhere,
// and hooking it catches the gear whatever the bar around it looks like.
//
// didMoveToWindow fires exactly when the bar appears, which is also the moment
// the colour used to be lost.

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
// and the interception below never armed — you had to change tab for it to
// take. layoutSubviews closes that window; once marked, every later pass is a
// pointer comparison.
%new
- (void)nfbGreySettingsGlyphIfNeeded {
    @try {
        UIView* button = (UIView*)self;
        if (!button.window) {
            return;
        }
        // Either the button says it is the settings one, or we are on the
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
