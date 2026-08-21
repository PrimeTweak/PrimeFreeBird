//
//  BHTHookHelpers.m
//  PrimeFreeBird
//

#import "HookHelpers.h"

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

// The colour for surfaces that carry Twitter's branding: the tab bar accent and
// the navigation logo. When the user has actually picked an accent it wins;
// with nothing picked the brand blue is used, never CurrentAccentColor's
// systemBlue fallback, which would leak iOS blue onto a Twitter surface.
//
// Deliberately separate from CurrentAccentColor: that one feeds the window
// tint, and UIKit's own controls, alert buttons among them, inherit it. Their
// blue must stay iOS blue.
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
