// Measurement only: whether a list refresh starts and ends after an unhide, and on
// which class. Prefix [refreshprobe]; inert unless debug tools are on.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Debug/NFBDebugger.h"

// The hooked classes are only forward-declared here, so self is never messaged:
// its class is read through the runtime.
static NSString* NFBProbeClassName(id object) {
    return object ? NSStringFromClass(object_getClass(object)) : @"nil";
}

%hook TFNDataViewController

- (void)loadTopDidBegin {
    %orig;
    NFBDebugLog(@"[refreshprobe] load began on %@", NFBProbeClassName((id)self));
}

- (void)loadTopDidEnd {
    %orig;
    NFBDebugLog(@"[refreshprobe] load ended on %@", NFBProbeClassName((id)self));
}

%end

%hook T1URTViewController

- (void)loadTop:(id)sender {
    NFBDebugLog(@"[refreshprobe] loadTop: on %@ (sender %@)", NFBProbeClassName((id)self),
                NFBProbeClassName(sender));
    %orig;
}

%end
