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
    return [painted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
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
            if (current && current != ours) {
                UIImage* painted = NFBGreyGlyph(current, colour);
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

// Depth-first search for the settings button by its identifier or label.
static UIView* nfbFindSettingsButton(UIView* view) {
    for (UIView* subview in view.subviews) {
        NSString* identifier = subview.accessibilityIdentifier;
        NSString* label = subview.accessibilityLabel;
        if ([identifier isEqualToString:kNFBSettingsButtonIdentifier] ||
            [label isEqualToString:kNFBSettingsButtonIdentifier] ||
            [identifier hasPrefix:@"NavigationBarSettings"] ||
            [label hasPrefix:@"NavigationBarSettings"]) {
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
    return [name containsString:@"Notification"] || [name containsString:@"Activity"];
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
    if (![bar respondsToSelector:@selector(topItem)]) {
        return;
    }
    UINavigationItem* item = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    for (UIBarButtonItem* button in item.rightBarButtonItems) {
        if (button.title.length > 0 || !button.image) {
            continue;
        }
        UIImage* ours = objc_getAssociatedObject(button, kNFBGreyedImageKey);
        if (button.image != ours) {
            UIImage* painted = NFBGreyGlyph(button.image, colour);
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
    if (image == ours) {
        %orig;
        return;
    }
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
    if (image == ours) {
        %orig;
        return;
    }
    UIImage* painted = NFBGreyGlyph(image, target);
    objc_setAssociatedObject(self, kNFBGreyedImageKey, painted,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(painted);
}

%end
