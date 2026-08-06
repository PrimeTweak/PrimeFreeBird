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
            return;   // pas cet écran : rien à faire
        }
        UIColor* grey = [UIColor secondaryLabelColor];
        if (![settingsButton.tintColor isEqual:grey]) {
            settingsButton.tintColor = grey;
        }
        nfbTintGlyphsIn(settingsButton, grey);

        // The diagnostic build settled it: the button IS found — painting its
        // background red worked — but the glyph stayed black. We run during
        // the BAR's layout, and the button lays itself out afterwards, undoing
        // the tint. Re-applying on the next runloop turn lands after it.
        __weak UIView* weakButton = settingsButton;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView* button = weakButton;
            if (button.window) {
                button.tintColor = grey;
                nfbTintGlyphsIn(button, grey);
            }
        });
    } @catch (id exception) {
    }
}

%end
