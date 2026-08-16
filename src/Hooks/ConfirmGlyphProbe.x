//
//  ConfirmGlyphProbe.x
//
//  TEMPORARY. One question: what carries the accent disc under Twitter's round
//  confirm button? Without that, the glyph cannot be claimed without also
//  claiming the gear and the share button beside it. Delete once read.
//
//  An earlier attempt guessed the disc was a backgroundColor on a near ancestor
//  inside a UINavigationBar, and shipped dead code: the bar sits some fourteen
//  levels up, and nothing within five carried a colour. This reads the whole
//  chain instead of assuming any part of it.
//
//  Console.app, filter on:  subsystem:com.primefreebird.probe
//

#import "HookHelpers.h"
#import <os/log.h>
#import <QuartzCore/QuartzCore.h>

static os_log_t NFBGlyphProbeLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.primefreebird.probe", "confirm-glyph");
    });
    return log;
}

static NSString* NFBGlyphProbeColour(UIColor* colour) {
    if (!colour) {
        return @"nil";
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([colour getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.2f)",
                r * 255, g * 255, b * 255, a];
    }
    CGFloat w = 0;
    if ([colour getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"white(%.2f,%.2f)", w, a];
    }
    return [colour description] ?: @"?";
}

// Reports every colour a view can be carrying, since a SwiftUI-drawn disc may
// sit on the layer rather than on the view.
static NSString* NFBGlyphProbeColours(UIView* view) {
    UIColor* layerColour = view.layer.backgroundColor
        ? [UIColor colorWithCGColor:view.layer.backgroundColor]
        : nil;
    NSString* effect = @"";
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffect* fx = ((UIVisualEffectView*)view).effect;
        effect = [NSString stringWithFormat:@" effect=%@",
                  fx ? NSStringFromClass([fx classForCoder]) : @"nil"];
    }
    return [NSString stringWithFormat:@"bg=%@ layer=%@ tint=%@%@",
            NFBGlyphProbeColour(view.backgroundColor),
            NFBGlyphProbeColour(layerColour),
            NFBGlyphProbeColour(view.tintColor),
            effect];
}

static BOOL NFBGlyphProbeInModernBarButton(UIView* view) {
    UIView* node = view.superview;
    NSInteger depth = 0;
    while (node && depth < 3) {
        if ([NSStringFromClass([node classForCoder])
                isEqualToString:@"_UIModernBarButton"]) {
            return YES;
        }
        node = node.superview;
        depth++;
    }
    return NO;
}

// A navigation bar lays out constantly — every scroll, every transition — and
// the sweep below walks its whole subtree. Reading cannot loop the way changing
// an image during layout once did, but the cost is real, so the sweep is rate
// limited and stops for good once it has collected enough. Past that point the
// probe costs one comparison per layout pass.
static NSMutableSet<NSString*>* gNFBGlyphProbeSeen;
static CFTimeInterval gNFBGlyphProbeLastSweep;
static BOOL gNFBGlyphProbeFinished;

static BOOL NFBGlyphProbeShouldSweep(void) {
    if (gNFBGlyphProbeFinished) {
        return NO;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gNFBGlyphProbeLastSweep < 0.4) {
        return NO;
    }
    gNFBGlyphProbeLastSweep = now;
    return YES;
}

// Only the first sighting of a given chain is reported, so revisiting a screen
// does not repeat it.
static BOOL NFBGlyphProbeFirstTime(NSString* signature) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gNFBGlyphProbeSeen = [NSMutableSet set]; });
    if ([gNFBGlyphProbeSeen containsObject:signature]) {
        return NO;
    }
    if (gNFBGlyphProbeSeen.count >= 30) {
        // Enough gathered: the probe retires rather than keep walking.
        if (!gNFBGlyphProbeFinished) {
            gNFBGlyphProbeFinished = YES;
            os_log(NFBGlyphProbeLog(),
                   "SONDE GLYPHE — 30 chaînes relevées, balayage arrêté");
        }
        return NO;
    }
    [gNFBGlyphProbeSeen addObject:signature];
    return YES;
}

static void NFBGlyphProbeReport(UIImageView* glyph) {
    UIImage* image = glyph.image;
    NSString* signature = [NSString stringWithFormat:@"%@|%.0fx%.0f|%@",
        NSStringFromClass([glyph classForCoder]),
        glyph.bounds.size.width, glyph.bounds.size.height,
        NSStringFromCGRect(glyph.frame)];
    if (!NFBGlyphProbeFirstTime(signature)) {
        return;
    }

    os_log(NFBGlyphProbeLog(), "──────── GLYPHE DE BARRE ────────");
    os_log(NFBGlyphProbeLog(),
           "GLYPHE  frame=%{public}@  image=%{public}@  mode=%{public}ld  %{public}@",
           NSStringFromCGRect(glyph.frame),
           image ? NSStringFromCGSize(image.size) : @"nil",
           image ? (long)image.renderingMode : -1L,
           NFBGlyphProbeColours(glyph));

    // The disc is somewhere above. Twelve levels clears the SwiftUI platter and
    // reaches the navigation bar, which the earlier five never did.
    UIView* node = glyph.superview;
    NSInteger depth = 1;
    while (node && depth <= 12) {
        os_log(NFBGlyphProbeLog(), "  ↑%{public}ld %{public}@ frame=%{public}@ %{public}@",
               (long)depth,
               NSStringFromClass([node classForCoder]),
               NSStringFromCGRect(node.frame),
               NFBGlyphProbeColours(node));
        node = node.superview;
        depth++;
    }
}

static void NFBGlyphProbeSweep(UIView* view, NSInteger depth) {
    if (!view || depth > 14) {
        return;
    }
    if ([view isKindOfClass:[UIImageView class]] &&
        view.bounds.size.width > 0 && view.bounds.size.width <= 40 &&
        NFBGlyphProbeInModernBarButton(view)) {
        NFBGlyphProbeReport((UIImageView*)view);
    }
    for (UIView* sub in view.subviews) {
        NFBGlyphProbeSweep(sub, depth + 1);
    }
}

%hook UINavigationBar

// Reads only: no view is painted, no image replaced, no frame touched. The
// sweep is bounded in depth and each chain is reported once.
- (void)layoutSubviews {
    %orig;
    if (NFBGlyphProbeShouldSweep()) {
        NFBGlyphProbeSweep((UIView*)self, 0);
    }
}

%end

%ctor {
    os_log(NFBGlyphProbeLog(),
           "SONDE GLYPHE CONFIRM CHARGÉE — ouvre Explore settings, puis un écran avec la roue dentée");
}
