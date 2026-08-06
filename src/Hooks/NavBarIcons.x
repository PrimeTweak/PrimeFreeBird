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
        UIColor* grey = [UIColor secondaryLabelColor];
        if (![settingsButton.tintColor isEqual:grey]) {
            settingsButton.tintColor = grey;
        }
        nfbTintGlyphsIn(settingsButton, grey);
    } @catch (id exception) {
    }
}

%end
