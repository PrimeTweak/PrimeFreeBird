// Shared helpers for the hook files.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

void PFBEnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView)) {
    if (!view || !block)
        return;

    // Hidden branches never need live restyling, so skip them entirely.
    if (view.hidden || view.alpha <= 0.01)
        return;

    block(view);

    // Depth cap; a static counter is fine since traversal only runs on the main
    // thread.
    static NSInteger recursionDepth = 0;
    if (recursionDepth > 15)
        return;

    recursionDepth++;
    for (UIView* subview in view.subviews) {
        PFBEnumerateSubviewsRecursively(subview, block);
    }
    recursionDepth--;
}

// Module content reaches the section arrays wrapped in TFNDataViewItem (the
// real view model is its -item); standalone timeline items are the view model
// directly.
id PFBUnwrapDataViewItem(id item) {
    if ([item isKindOfClass:objc_getClass("TFNDataViewItem")] &&
        [item respondsToSelector:@selector(item)]) {
        return [item performSelector:@selector(item)];
    }

    return item;
}

BOOL PFBIsModuleHeaderItem(id item) {
    return [NSStringFromClass([PFBUnwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"];
}

BOOL PFBIsModuleFooterItem(id item) {
    return [NSStringFromClass([PFBUnwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleFooterViewModel"];
}

// A module renders as a consecutive run of header, content, footer. When a
// module's content is removed entirely, mark its header and footer too.
void PFBMarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed) {
    NSUInteger count = items.count;

    for (NSUInteger i = 0; i < count; i++) {
        if ([removed containsIndex:i] || !PFBIsModuleHeaderItem(items[i])) {
            continue;
        }

        NSUInteger contentCount = 0;
        BOOL contentRemoved = YES;
        NSUInteger j = i + 1;
        while (j < count && !PFBIsModuleHeaderItem(items[j]) &&
               !PFBIsModuleFooterItem(items[j])) {
            contentCount++;
            if (![removed containsIndex:j]) {
                contentRemoved = NO;
            }
            j++;
        }

        if (contentCount > 0 && contentRemoved) {
            [removed addIndex:i];
            if (j < count && PFBIsModuleFooterItem(items[j])) {
                [removed addIndex:j];
            }
        }
    }
}

// Twitter's brand blue. Not iOS systemBlue, which is darker and belongs to
// UIKit's own controls.
UIColor* PFBTwitterBlueColor(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0xA1 / 255.0
                            blue:0xF2 / 255.0
                           alpha:1.0];
}

// The color for surfaces carrying Twitter's branding: the tab bar accent and the
// navigation logo. A picked accent wins; with none, the brand blue is used rather
// than PFBCurrentAccentColor's systemBlue fallback, which feeds the window tint.
UIColor* PFBBrandAccentColor(void) {
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
    BOOL picked = [defs objectForKey:@"pfb_custom_accent_hex"] ||
                  [defs objectForKey:@"pfb_color_theme_selectedColor"] ||
                  [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1;
    if (picked) {
        return PFBCurrentAccentColor() ?: PFBTwitterBlueColor();
    }
    return PFBTwitterBlueColor();
}

UIColor* PFBCurrentAccentColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    if (!TAEColorSettingsCls) {
        return [UIColor systemBlueColor];
    }

    id settings = [TAEColorSettingsCls sharedSettings];
    id current = [settings currentColorPalette];
    id palette = [current colorPalette];
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];

    // The tweak's stored pick wins over Twitter's own color option.
    if ([defs objectForKey:@"pfb_color_theme_selectedColor"]) {
        NSInteger opt = [defs integerForKey:@"pfb_color_theme_selectedColor"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    if ([defs objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        NSInteger opt =
            [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    return [UIColor systemBlueColor];
}

const CGFloat PFBPopoverArrowReserve = 13.0;

// Read from the clipping ancestor once the popover is open, so an iOS update that
// changes the arrow shows in the log as a gap between the two values.
void PFBPopoverLogOverflow(UIView* content) {
    if (!PFBDebugIsRecording() || !content.window) {
        return;
    }
    CGFloat past = 0.0;
    NSString* clipper = @"none";
    UIView* node = content.superview;
    for (NSInteger depth = 0; node && node != content.window && depth < 10; depth++) {
        CGRect clip = CGRectNull;
        CALayer* mask = node.layer.mask;
        if (mask) {
            clip = mask.frame;
            if ([mask isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer*)mask).path) {
                CGRect shape = CGPathGetBoundingBox(((CAShapeLayer*)mask).path);
                clip = CGRectOffset(shape, mask.frame.origin.x, mask.frame.origin.y);
            }
        } else if (node.clipsToBounds) {
            clip = node.bounds;
        }
        if (!CGRectIsNull(clip)) {
            CGRect mine = [content convertRect:content.bounds toView:node];
            CGFloat overflow = CGRectGetMaxY(mine) - CGRectGetMaxY(clip);
            if (overflow > past) {
                past = overflow;
                clipper = NSStringFromClass([node class]);
            }
        }
        node = node.superview;
    }
    PFBDebugLog(@"[popover] %.1f pt under the bubble edge, %.1f reserved (clip: %@)",
                past, PFBPopoverArrowReserve, clipper);
}

// The material iOS gives its bars. Liquid Glass exists from iOS 26 and is
// resolved by name because the build SDK predates it; older systems fall back
// to the chrome material bars used before.
static UIVisualEffect* PFBBarMaterial(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if (glass) {
        UIVisualEffect* effect = [[glass alloc] init];
        if (effect) {
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

UIVisualEffectView* PFBMaterialBehind(UIView* host) {
    UIVisualEffectView* material =
        [[UIVisualEffectView alloc] initWithEffect:PFBBarMaterial()];
    material.translatesAutoresizingMaskIntoConstraints = NO;
    material.userInteractionEnabled = NO;
    material.alpha = 0.0;
    [host insertSubview:material atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [material.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [material.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [material.topAnchor constraintEqualToAnchor:host.topAnchor],
        [material.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
    return material;
}

BOOL PFBIsXDomain(NSString* domainOrHost) {
    NSString* domain = domainOrHost.lowercaseString;
    if ([domain hasPrefix:@"."]) {
        domain = [domain substringFromIndex:1];
    }
    for (NSString* root in @[ @"x.com", @"twitter.com" ]) {
        if ([domain isEqualToString:root] ||
            [domain hasSuffix:[@"." stringByAppendingString:root]]) {
            return YES;
        }
    }
    return NO;
}

// A Twitter glyph drawn in the box of the system symbol it replaces; the symbol stays
// as the fallback when the app does not ship that glyph.
UIImage* PFBTwitterGlyphFor(NSString* name, UIImage* systemImage) {
    if (!systemImage || ![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return systemImage;
    }
    UIImage* glyph = [UIImage tfn_vectorImageNamed:name fitsSize:systemImage.size fillColor:[UIColor blackColor]];
    return glyph ? [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : systemImage;
}
