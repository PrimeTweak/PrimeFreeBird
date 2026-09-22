// Measurement only: while the keyboard rises, does the reply glass capsule
// track the bar, or lag it. Samples both presentation layers across the
// animation and logs whether the app lays out inside an animation. Prefix [replyprobe].

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Debug/NFBDebugger.h"

// The glass capsule is the bar's first visual-effect subview; found by class so
// this probe needs no constant from the feature file.
static UIView* nfbReplyProbeGlass(UIView* bar) {
    for (UIView* sub in bar.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            return sub;
        }
    }
    return nil;
}

static NSString* nfbReplyProbeRect(CALayer* layer) {
    if (!layer) {
        return @"none";
    }
    CGRect frame = [layer convertRect:layer.bounds toLayer:nil];
    return [NSString stringWithFormat:@"y=%.1f w=%.1f h=%.1f", frame.origin.y,
            frame.size.width, frame.size.height];
}

// Six samples over the animation, reading the presentation layers (the values
// on screen right now), so a lag between bar and glass shows as diverging y.
static void nfbReplyProbeSample(UIView* bar, int step) {
    if (step >= 6 || !bar.window) {
        return;
    }
    UIView* glass = nfbReplyProbeGlass(bar);
    NFBDebugLog(@"[replyprobe] +%dms bar %@ | glass %@", step * 50,
                nfbReplyProbeRect(bar.layer.presentationLayer),
                nfbReplyProbeRect(glass.layer.presentationLayer));
    __weak UIView* weakBar = bar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIView* strong = weakBar;
        if (strong) {
            nfbReplyProbeSample(strong, step + 1);
        }
    });
}

%hook T1PersistentComposeView

- (void)layoutSubviews {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        UIView* bar = (UIView*)self;
        UIView* glass = nfbReplyProbeGlass(bar);
        // areAnimationsEnabled alone is not proof of an active animation, but a
        // non-nil action for the position key is: the layout is inside one.
        BOOL animated = [bar.layer animationForKey:@"position"] != nil ||
                        [glass.layer animationForKey:@"position"] != nil;
        NFBDebugLog(@"[replyprobe] layout bar y=%.1f h=%.1f | glass %@ | inAnim=%d t=%.0f",
                    bar.frame.origin.y, bar.bounds.size.height,
                    glass ? [NSString stringWithFormat:@"y=%.1f w=%.1f",
                             glass.frame.origin.y, glass.frame.size.width]
                          : @"none",
                    animated, CACurrentMediaTime() * 1000);
        // Start one sampling run per keyboard change, coalesced by a short flag.
        if (!objc_getAssociatedObject(bar, _cmd)) {
            objc_setAssociatedObject(bar, _cmd, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIKeyboardWillChangeFrameNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification* note) {
                CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
                NFBDebugLog(@"[replyprobe] keyboard -> y=%.1f dur=%.0fms", end.origin.y,
                            [note.userInfo[UIKeyboardAnimationDurationUserInfoKey]
                                doubleValue] * 1000);
                nfbReplyProbeSample(bar, 0);
            }];
        }
    } @catch (id exception) {
    }
}

%end
