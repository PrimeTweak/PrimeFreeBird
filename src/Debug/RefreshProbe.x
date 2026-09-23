// Measurement only: whether a list refresh starts and ends after an unhide, and on
// which class. Prefix [refreshprobe]; inert unless debug tools are on.

#import <UIKit/UIKit.h>
#import "Debug/NFBDebugger.h"

%hook TFNDataViewController

- (void)loadTopDidBegin {
    %orig;
    NFBDebugLog(@"[refreshprobe] load began on %@", NSStringFromClass([self class]));
}

- (void)loadTopDidEnd {
    %orig;
    NFBDebugLog(@"[refreshprobe] load ended on %@", NSStringFromClass([self class]));
}

%end

%hook T1URTViewController

- (void)loadTop:(id)sender {
    NFBDebugLog(@"[refreshprobe] loadTop: on %@ (sender %@)", NSStringFromClass([self class]),
                sender ? NSStringFromClass([sender class]) : @"nil");
    %orig;
}

%end
