//
//  NFBDebugShake.x
//
//  Catches the shake gesture and hands it to the debugger. Hooking
//  motionEnded:withEvent: on UIWindow is lighter than a UIWindow subclass and
//  needs no swap of the app's window. Inert unless flex_twitter is on, which
//  the handler itself re-checks.
//

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
