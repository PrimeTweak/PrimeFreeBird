//  FABProbe.x
//  Measurement only: logs the compose button's class and view tree so the classic
//  FAB styling can be aimed at the right class under the Liquid Glass redesign.
//  Inert unless debug_tools is on. Prefix [fabprobe].
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/BHTSettings.h"
#import "Debug/NFBDebugger.h"

@interface TFNFloatingActionButton : UIView
@end

// Compact recursive dump: class, frame, corner radius, background, visibility.
static void nfbFabTree(UIView* v, NSInteger depth, NSMutableString* out) {
    if (!v || depth > 5) {
        return;
    }
    for (NSInteger i = 0; i < depth; i++) {
        [out appendString:@"  "];
    }
    CGRect f = v.frame;
    [out appendFormat:@"%@ (%.0f,%.0f %.0fx%.0f) r=%.1f bg=%d a=%.1f hidden=%d\n",
                      NSStringFromClass([v class]), f.origin.x, f.origin.y, f.size.width,
                      f.size.height, v.layer.cornerRadius, v.backgroundColor != nil, v.alpha,
                      v.hidden];
    for (UIView* sub in v.subviews) {
        nfbFabTree(sub, depth + 1, out);
    }
}

// Walks the window for a round-ish control parked bottom-right - the compose FAB,
// whatever its class - and dumps each candidate's tree.
static void nfbFabScan(UIView* v, UIView* root, CGFloat W, CGFloat H, NSMutableString* found,
                       NSInteger depth) {
    if (!v || depth > 40) {
        return;
    }
    for (UIView* sub in v.subviews) {
        CGRect abs = [sub convertRect:sub.bounds toView:root];
        BOOL bottomRight = abs.origin.x > W * 0.55 && CGRectGetMaxY(abs) > H * 0.6;
        BOOL sizeOK = fabs(abs.size.width - abs.size.height) < 12 && abs.size.width >= 44 &&
                      abs.size.width <= 90;
        if (bottomRight && sizeOK && !sub.hidden && sub.alpha > 0.1) {
            NSMutableString* tree = [NSMutableString string];
            nfbFabTree(sub, 0, tree);
            [found appendFormat:@"--- candidate %@ at (%.0f,%.0f %.0fx%.0f):\n%@",
                                NSStringFromClass([sub class]), abs.origin.x, abs.origin.y,
                                abs.size.width, abs.size.height, tree];
        }
        nfbFabScan(sub, root, W, H, found, depth + 1);
    }
}

static void nfbFabSweep(void) {
    if (![BHTSettings boolForKey:@"debug_tools"]) {
        return;
    }
    UIWindow* key = nil;
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) {
            key = w;
            break;
        }
    }
    if (!key) {
        return;
    }
    NSMutableString* found = [NSMutableString string];
    nfbFabScan(key, key, key.bounds.size.width, key.bounds.size.height, found, 0);
    NFBDebugLog(@"[fabprobe] sweep glass=%d\n%@", [BHTSettings boolForKey:@"enable_liquid_glass"],
                found.length ? found : @"(no bottom-right round control found)");
}

%hook TFNFloatingActionButton

- (void)didMoveToWindow {
    %orig;
    static BOOL logged = NO;
    if (!logged && self.window && [BHTSettings boolForKey:@"debug_tools"]) {
        logged = YES;
        NSMutableString* tree = [NSMutableString string];
        nfbFabTree((UIView*)self, 0, tree);
        NFBDebugLog(@"[fabprobe] TFNFloatingActionButton present, glass=%d\n%@",
                    [BHTSettings boolForKey:@"enable_liquid_glass"], tree);
    }
}

%end

%ctor {
    // Delayed so the timeline and its compose button are on screen before the sweep.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     nfbFabSweep();
                   });
}
