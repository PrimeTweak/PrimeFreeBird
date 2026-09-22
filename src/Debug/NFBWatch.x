// The watch list recorder: window arrivals and departures of every view whose
// class name matches a watched fragment, with millisecond stamps and pointers.

#import "Hooks/HookHelpers.h"
#import "Debug/NFBDebugger.h"

%hook UIView

- (void)willMoveToWindow:(UIWindow*)newWindow {
    %orig;
    if (!newWindow && self.window &&
        NFBWatchMatchesClassName(NSStringFromClass([self classForCoder]))) {
        NFBDebugLog(@"⌚ %@ <%p> left the window  was=%@",
                    NSStringFromClass([self classForCoder]), self,
                    NSStringFromCGRect([self convertRect:self.bounds toView:nil]));
    }
}

- (void)didMoveToWindow {
    %orig;
    if (self.window &&
        NFBWatchMatchesClassName(NSStringFromClass([self classForCoder]))) {
        NFBDebugLog(@"⌚ %@ <%p> placed  frame=%@",
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
        NFBDebugLog(@"⌚ %@ <%p> anim [%@] key=%@ duration=%.2f",
                    NSStringFromClass([owner classForCoder]), owner,
                    NSStringFromClass([animation classForCoder]),
                    key ?: @"nil", animation.duration);
    }
    %orig;
}

%end
