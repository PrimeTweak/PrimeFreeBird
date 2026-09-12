// A single disposable file that measures what the eye cannot time: when the
// empty-state panel comes and goes, how the reply bar ends up laid out, and the
// state of a navigation bar after a pop. `git rm` removes it whole.

#import "Hooks/HookHelpers.h"
#import "Debug/NFBDebugger.h"
#import <QuartzCore/QuartzCore.h>

static NSTimeInterval gNFBProbeLaunch = 0;

static double nfbProbeSinceLaunch(void) {
    if (gNFBProbeLaunch == 0) {
        gNFBProbeLaunch = CACurrentMediaTime();
    }
    return CACurrentMediaTime() - gNFBProbeLaunch;
}

// The app's own empty-state panel. Every mount and unmount is timed from
// launch: a flash is two lines a few hundred milliseconds apart.
%hook TFNEmptyStateView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        UIView* view = (UIView*)self;
        if (view.window) {
            NFBDebugLog(@"[probe] empty-state MOUNTED <%p> t=%.2fs host=%@ frame=%@ "
                        @"alpha=%.2f hidden=%d",
                        self, nfbProbeSinceLaunch(),
                        NSStringFromClass([view.superview class]),
                        NSStringFromCGRect(view.frame), view.alpha, view.hidden ? 1 : 0);
        } else {
            NFBDebugLog(@"[probe] empty-state UNMOUNTED <%p> t=%.2fs", self,
                        nfbProbeSinceLaunch());
        }
    } @catch (id exception) {
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    if (NFBDebugIsRecording()) {
        NFBDebugLog(@"[probe] empty-state <%p> hidden=%d t=%.2fs", self, hidden ? 1 : 0,
                    nfbProbeSinceLaunch());
    }
}

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (NFBDebugIsRecording() && (alpha == 0.0 || alpha == 1.0)) {
        NFBDebugLog(@"[probe] empty-state <%p> alpha=%.0f t=%.2fs", self, alpha,
                    nfbProbeSinceLaunch());
    }
}

%end

// The reply bar after the glass pass. Logged from the next run-loop turn so the
// tweak's own layout work has already run, and only when the size changes.
%hook T1PersistentComposeView

- (void)layoutSubviews {
    %orig;
    @try {
        if (!NFBDebugIsRecording()) {
            return;
        }
        UIView* bar = (UIView*)self;
        NSValue* last = objc_getAssociatedObject(bar, @selector(nfbProbeLastSize));
        CGSize size = bar.bounds.size;
        if (last && CGSizeEqualToSize(last.CGSizeValue, size)) {
            return;
        }
        objc_setAssociatedObject(bar, @selector(nfbProbeLastSize),
                                 [NSValue valueWithCGSize:size],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView* weakBar = bar;
        dispatch_async(dispatch_get_main_queue(), ^{
          UIView* strongBar = weakBar;
          if (!strongBar || !strongBar.window) {
              return;
          }
          UIView* glass = nil;
          NSInteger hairlines = 0;
          for (UIView* sub in strongBar.subviews) {
              if ([sub isKindOfClass:[UIVisualEffectView class]]) {
                  glass = sub;
              }
              if (sub.bounds.size.height <= 1.0 && sub.backgroundColor && !sub.hidden) {
                  hairlines++;
              }
          }
          UIView* host = strongBar.superview;
          NSInteger opaqueSiblings = 0;
          for (UIView* sibling in host.superview.subviews) {
              CGFloat a = 0.0;
              [sibling.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&a];
              if (sibling != host && a >= 0.9 && sibling.subviews.count == 0) {
                  opaqueSiblings++;
              }
          }
          NFBDebugLog(@"[probe] reply bar %@ glass=%@ radius=%.0f visible-hairlines=%ld "
                      @"opaque-siblings=%ld",
                      NSStringFromCGRect(strongBar.frame),
                      glass ? NSStringFromCGRect(glass.frame) : @"none",
                      glass ? glass.layer.cornerRadius : 0.0, (long)hairlines,
                      (long)opaqueSiblings);
        });
    } @catch (id exception) {
    }
}

%end

// A navigation bar inside a presented stack, one second after it settles: its
// first-level subviews with a background. This is the bar the chevron returns
// to, and where the opaque band used to sit.
%hook UINavigationBar

- (void)didMoveToWindow {
    %orig;
    @try {
        if (!NFBDebugIsRecording() || !self.window) {
            return;
        }
        UIResponder* responder = (UIResponder*)self;
        UINavigationController* navigation = nil;
        for (NSInteger up = 0; responder && up < 6; up++) {
            responder = responder.nextResponder;
            if ([responder isKindOfClass:[UINavigationController class]]) {
                navigation = (UINavigationController*)responder;
                break;
            }
        }
        if (!navigation.presentingViewController) {
            return;
        }
        __weak UINavigationBar* weakBar = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
          UINavigationBar* bar = weakBar;
          if (!bar || !bar.window) {
              return;
          }
          NSMutableString* lines = [NSMutableString string];
          for (UIView* sub in bar.subviews) {
              CGFloat a = 0.0;
              [sub.backgroundColor getRed:NULL green:NULL blue:NULL alpha:&a];
              if (a > 0.05 || sub.layer.backgroundColor) {
                  [lines appendFormat:@" %@%@ a=%.2f;", NSStringFromClass([sub class]),
                                      NSStringFromCGRect(sub.frame), a];
              }
          }
          NFBDebugLog(@"[probe] presented bar %@ settled:%@", NSStringFromCGRect(bar.frame),
                      lines.length ? lines : @" no coloured subview");
        });
    } @catch (id exception) {
    }
}

%end
