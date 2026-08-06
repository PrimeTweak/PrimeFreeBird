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
        if ([subview.accessibilityIdentifier
                isEqualToString:kNFBSettingsButtonIdentifier]) {
            return subview;
        }
        UIView* found = nfbFindSettingsButton(subview);
        if (found) {
            return found;
        }
    }
    return nil;
}

%hook TFNNavigationBar

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
    } @catch (id exception) {
    }
}

%end
