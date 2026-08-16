//
//  NFBWatch.x
//
//  The event recorder behind the watch list. For every view whose class name
//  matches a watched fragment, window arrivals and departures are journaled
//  with millisecond stamps, the instance pointer and the window frame. The
//  pointer is the point: a view that is removed and REPLACED shows up as two
//  different pointers around a gap — the exact signature that took a 60 fps
//  video to establish for the inbox pill.
//
//  Cost when the list is empty or debugging is off: one boolean per event.
//

#import "Hooks/HookHelpers.h"
#import "Debug/NFBDebugger.h"

%hook UIView

- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (!newWindow && self.window &&
        NFBWatchMatchesClassName(NSStringFromClass([self classForCoder]))) {
        NFBDebugLog(@"⌚ %@ <%p> quitte la fenêtre  était=%@",
                    NSStringFromClass([self classForCoder]), self,
                    NSStringFromCGRect([self convertRect:self.bounds toView:nil]));
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window &&
        NFBWatchMatchesClassName(NSStringFromClass([self classForCoder]))) {
        NFBDebugLog(@"⌚ %@ <%p> posé  frame=%@",
                    NSStringFromClass([self classForCoder]), self,
                    NSStringFromCGRect([self convertRect:self.bounds toView:nil]));
    }
}

%end

// Log-only sibling of the refusal hook in NavBarIcons: every animation aimed at
// a watched view is named, whatever the screen. Both CALayer hooks coexist —
// this one always forwards.
%hook CALayer

- (void)addAnimation:(CAAnimation*)animation forKey:(NSString*)key {
    UIView* owner = (UIView*)self.delegate;
    if ([owner isKindOfClass:[UIView class]] &&
        NFBWatchMatchesClassName(NSStringFromClass([owner classForCoder]))) {
        NFBDebugLog(@"⌚ %@ <%p> anim [%@] clé=%@ durée=%.2f",
                    NSStringFromClass([owner classForCoder]), owner,
                    NSStringFromClass([animation classForCoder]),
                    key ?: @"nil", animation.duration);
    }
    %orig;
}

%end
