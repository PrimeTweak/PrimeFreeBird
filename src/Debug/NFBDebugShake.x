// The shake gesture handed to the debugger (motionEnded:withEvent: on UIWindow).
// Inert unless debug_tools is on.

#import "Hooks/HookHelpers.h"

// Defined in NFBDebugger.m.
extern void NFBDebuggerHandleShake(void);

%hook UIWindow

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent*)event {
    %orig;
    if (motion == UIEventSubtypeMotionShake) {
        NFBDebuggerHandleShake();
    }
}

%end
