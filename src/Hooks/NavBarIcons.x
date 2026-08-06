//
//  NavBarIcons.x
//  PrimeFreeBird
//
//  Twitter draws the settings gear at full label strength, which reads as
//  black next to the muted grey of the tab labels beside it. This tints it to
//  the same secondary grey.
//
//  FLEX gave the whole chain, and it changed the approach entirely. The gear
//  is not a bar button item and not a loose image view: it is a
//  TFNBarButtonItemButton carrying the accessibility identifier
//  "NavigationBarSettingsButton", with its glyph in a UIImageView nested three
//  levels below. Hooking that class and matching on the identifier is exact —
//  no walking the navigation bar, no guessing which screen we are on, and no
//  risk of touching any other button.
//

#import "HookHelpers.h"

// The glyph lives a few levels down inside the button; template rendering has
// to be forced, otherwise the tint is simply ignored.
static void nfbTintGlyph(UIView* view, UIColor* colour) {
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
        nfbTintGlyph(subview, colour);
    }
}

%hook TFNBarButtonItemButton

- (void)layoutSubviews {
    %orig;

    @try {
        UIView* button = (UIView*)self;
        if (!button.window) {
            return;
        }
        NSString* identifier = button.accessibilityIdentifier;
        if (![identifier isEqualToString:@"NavigationBarSettingsButton"]) {
            return;
        }
        UIColor* grey = [UIColor secondaryLabelColor];
        if (![button.tintColor isEqual:grey]) {
            button.tintColor = grey;
        }
        nfbTintGlyph(button, grey);
    } @catch (id exception) {
    }
}

%end
