//
//  NavBarIcons.x
//  PrimeFreeBird
//
//  Twitter draws the settings gear at full label strength, which reads as
//  black next to the muted grey of the tab labels beside it.
//
//  Three earlier attempts failed, and the reason matters. The gear is not a
//  bar button item, and TFNBarButtonItemButton — the class FLEX named — does
//  not live in the framework this tweak hooks at load time, so hooking it
//  directly never applied. What does reliably run is TFNNavigationBar's
//  layout, proven by the quick-access button sitting in that same bar.
//
//  So: start from the bar, walk down to the view carrying the accessibility
//  identifier "NavigationBarSettingsButton" — an exact, stable anchor read off
//  the binary — and tint the glyph inside it. Nothing else is touched.
//

#import "HookHelpers.h"

static NSString* const kNFBSettingsButtonIdentifier = @"NavigationBarSettingsButton";

// secondaryLabelColor is the label colour at 60% opacity; dimming the button
// to the same value gives an identical result whatever draws the glyph.
static const CGFloat kNFBGreyAlpha = 0.6;

// Forces template rendering, without which a tint is simply ignored.
static void nfbTintGlyphsIn(UIView* view, UIColor* colour) {
    for (UIView* subview in view.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            UIImageView* imageView = (UIImageView*)subview;
            if (imageView.image) {
                if (imageView.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    imageView.image = [imageView.image
                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                }
                if (![imageView.tintColor isEqual:colour]) {
                    imageView.tintColor = colour;
                }
            }
        }
        nfbTintGlyphsIn(subview, colour);
    }
}

// Depth-first search for the settings button by its accessibility identifier.
static UIView* nfbFindSettingsButton(UIView* view) {
    for (UIView* subview in view.subviews) {
        // FLEX shows either the identifier or the accessibility label after
        // the dot, and we cannot tell which from the screenshot — so both are
        // accepted, plus a prefix match in case Twitter suffixes it.
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

// Notifications: the gear is a plain bar button item. Scoped to that screen
// through the owning controller, so no other bar is touched.
static void nfbDimNotificationsGear(UIView* bar) {
    UIResponder* responder = bar;
    UIViewController* owner = nil;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            owner = (UIViewController*)responder;
            if ([owner isKindOfClass:[UINavigationController class]]) {
                owner = ((UINavigationController*)owner).topViewController ?: owner;
            }
            break;
        }
    }
    if (!owner || ![NSStringFromClass([owner class]) containsString:@"Notification"]) {
        return;
    }
    if (![bar respondsToSelector:@selector(topItem)]) {
        return;
    }
    UINavigationItem* item =
        ((id (*)(id, SEL))objc_msgSend)(bar, @selector(topItem));
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    for (UIBarButtonItem* button in item.rightBarButtonItems) {
        if (![button.tintColor isEqual:grey]) {
            button.tintColor = grey;
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
        UIView* settingsButton = nfbFindSettingsButton(bar);
        if (!settingsButton) {
            // Notifications builds its bar the classic way — a title and a
            // right bar button item — so no view there carries the identifier.
            // That screen is handled through the item instead, and only there.
            nfbDimNotificationsGear(bar);
            return;
        }
        // Opacity, not tint. The diagnostic proved the button is found and
        // that view properties stick — its background turned red — yet the
        // glyph stayed black through every tinting route. So we stop fighting
        // over how the glyph is drawn: secondaryLabel IS the label colour at
        // 60% opacity, and dimming the button reproduces it exactly.
        if (settingsButton.alpha > kNFBGreyAlpha + 0.01) {
            settingsButton.alpha = kNFBGreyAlpha;
        }

        // Tinting is still attempted, harmlessly: if a future build makes the
        // glyph tintable, the colour becomes exact rather than simulated.
        UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
        if (![settingsButton.tintColor isEqual:grey]) {
            settingsButton.tintColor = grey;
        }
        nfbTintGlyphsIn(settingsButton, grey);
    } @catch (id exception) {
    }
}

%end
