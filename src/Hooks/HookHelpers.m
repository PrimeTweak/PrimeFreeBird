// Shared helpers for the hook files.

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

void EnumerateSubviewsRecursively(UIView* view,
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
        EnumerateSubviewsRecursively(subview, block);
    }
    recursionDepth--;
}

// Module content reaches the section arrays wrapped in TFNDataViewItem (the
// real view model is its -item); standalone timeline items are the view model
// directly.
id unwrapDataViewItem(id item) {
    if ([item isKindOfClass:objc_getClass("TFNDataViewItem")] &&
        [item respondsToSelector:@selector(item)]) {
        return [item performSelector:@selector(item)];
    }

    return item;
}

BOOL IsModuleHeaderItem(id item) {
    return [NSStringFromClass([unwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"];
}

BOOL IsModuleFooterItem(id item) {
    return [NSStringFromClass([unwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleFooterViewModel"];
}

// A module renders as a consecutive run of header, content, footer. When a
// module's content is removed entirely, mark its header and footer too.
void MarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed) {
    NSUInteger count = items.count;

    for (NSUInteger i = 0; i < count; i++) {
        if ([removed containsIndex:i] || !IsModuleHeaderItem(items[i])) {
            continue;
        }

        NSUInteger contentCount = 0;
        BOOL contentRemoved = YES;
        NSUInteger j = i + 1;
        while (j < count && !IsModuleHeaderItem(items[j]) &&
               !IsModuleFooterItem(items[j])) {
            contentCount++;
            if (![removed containsIndex:j]) {
                contentRemoved = NO;
            }
            j++;
        }

        if (contentCount > 0 && contentRemoved) {
            [removed addIndex:i];
            if (j < count && IsModuleFooterItem(items[j])) {
                [removed addIndex:j];
            }
        }
    }
}

// Twitter's brand blue. Not iOS systemBlue, which is darker and belongs to
// UIKit's own controls.
UIColor* NFBTwitterBlueColor(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0xA1 / 255.0
                            blue:0xF2 / 255.0
                           alpha:1.0];
}

// The colour for surfaces carrying Twitter's branding: the tab bar accent and the
// navigation logo. A picked accent wins; with none, the brand blue is used rather
// than CurrentAccentColor's systemBlue fallback, which feeds the window tint.
UIColor* NFBBrandAccentColor(void) {
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
    BOOL picked = [defs objectForKey:@"bh_custom_accent_hex"] ||
                  [defs objectForKey:@"bh_color_theme_selectedColor"] ||
                  [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1;
    if (picked) {
        return CurrentAccentColor() ?: NFBTwitterBlueColor();
    }
    return NFBTwitterBlueColor();
}

UIColor* CurrentAccentColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    if (!TAEColorSettingsCls) {
        return [UIColor systemBlueColor];
    }

    id settings = [TAEColorSettingsCls sharedSettings];
    id current = [settings currentColorPalette];
    id palette = [current colorPalette];
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];

    // The tweak's stored pick wins over Twitter's own colour option.
    if ([defs objectForKey:@"bh_color_theme_selectedColor"]) {
        NSInteger opt = [defs integerForKey:@"bh_color_theme_selectedColor"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    if ([defs objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        NSInteger opt =
            [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    return [UIColor systemBlueColor];
}

// With an arrow, a popover's content view runs past the bubble's bottom edge.
// The overflow is read from the clipping ancestor rather than assumed, and each
// new value is journaled so a change after an iOS update shows in the log.
CGFloat NFBPopoverHiddenBottom(UIView* content) {
    if (!content.window) {
        return 0.0;
    }
    CGFloat hidden = 0.0;
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
            // Measured in the clipper's own space, so a presentation transform
            // above it does not scale the result.
            CGRect mine = [content convertRect:content.bounds toView:node];
            CGFloat past = CGRectGetMaxY(mine) - CGRectGetMaxY(clip);
            if (past > hidden) {
                hidden = past;
                clipper = NSStringFromClass([node class]);
            }
        }
        node = node.superview;
    }
    static CGFloat logged = -1.0;
    if (fabs(hidden - logged) > 0.5) {
        logged = hidden;
        NFBDebugLog(@"[popover] %.1f pt of content under the bubble edge (clip: %@)",
                    hidden, clipper);
    }
    return hidden;
}

// The material iOS gives its bars. Liquid Glass exists from iOS 26 and is
// resolved by name because the build SDK predates it; older systems fall back
// to the chrome material bars used before.
static UIVisualEffect* NFBBarMaterial(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if (glass) {
        UIVisualEffect* effect = [[glass alloc] init];
        if (effect) {
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

UIVisualEffectView* NFBMaterialBehind(UIView* host) {
    UIVisualEffectView* material =
        [[UIVisualEffectView alloc] initWithEffect:NFBBarMaterial()];
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
