// Measurement only: what NeoFreeBird's features rely on, observed on this Twitter
// build before anything is ported. Prefix [port]; inert unless debug tools are on.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/BHTSettings.h"
#import "Debug/NFBDebugger.h"

// Once per session per subject, so hot paths stay quiet.
static BOOL NFBPortFirst(NSString* subject) {
    static NSMutableSet<NSString*>* seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      seen = [NSMutableSet set];
    });
    @synchronized(seen) {
        if ([seen containsObject:subject]) {
            return NO;
        }
        [seen addObject:subject];
        return YES;
    }
}

static BOOL NFBPortWatchedSwitch(NSString* key) {
    return [key isEqualToString:@"home_timeline_foreground_refresh_min_background_seconds"] ||
           [key isEqualToString:@"ios_ui_multi_media_carousel_enabled"] ||
           [key isEqualToString:@"ios_ui_multi_media_carousel_avatar_avoidance_enabled"];
}

static void NFBPortNoteSwitch(NSString* reader, NSString* key, double value) {
    if (NFBDebugIsRecording() && NFBPortWatchedSwitch(key) &&
        NFBPortFirst([reader stringByAppendingString:key])) {
        NFBDebugLog(@"[port] switch %@ read by %@ = %g", key, reader, value);
    }
}

// Which control answers a Follow tap; the tweak confirms only TUIFollowControl.
%hook TUIFollowButtonV2

- (void)buttonTapped {
    if (NFBDebugIsRecording()) {
        NFBDebugLog(@"[port] follow tap on TUIFollowButtonV2 (confirm follows=%d)",
                    [BHTSettings boolForKey:@"follow_confirm"]);
    }
    %orig;
}

%end

%hook TUIFollowControl

- (void)_followUser:(id)sender event:(id)event {
    if (NFBDebugIsRecording()) {
        NFBDebugLog(@"[port] follow tap on TUIFollowControl (confirm follows=%d)",
                    [BHTSettings boolForKey:@"follow_confirm"]);
    }
    %orig;
}

%end

// Whether a reply from the bottom bar goes through this path.
%hook T1PersistentComposeViewController

- (void)_t1_sendReply {
    if (NFBDebugIsRecording()) {
        NFBDebugLog(@"[port] reply sent from the bottom bar (confirm Tweets=%d)",
                    [BHTSettings boolForKey:@"tweet_confirm"]);
    }
    %orig;
}

%end

// Which fonts reach buttons and counters while custom fonts are on.
%hook XFontCatalog

+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont* font = %orig;
    if (NFBDebugIsRecording() && NFBPortFirst(@"tabular")) {
        NFBDebugLog(@"[port] counter digits drawn in %@ (custom fonts=%d)",
                    font.familyName ?: @"nil", [BHTSettings boolForKey:@"custom_fonts"]);
    }
    return font;
}

%end

%hook XDSButtonContentElement

+ (id)labelWithText:(id)text font:(id)font color:(id)color {
    if (NFBDebugIsRecording() && NFBPortFirst(@"button")) {
        NSString* family = [font isKindOfClass:[UIFont class]] ? [(UIFont*)font familyName] : nil;
        NFBDebugLog(@"[port] button label drawn in %@ (custom fonts=%d)", family ?: @"nil",
                    [BHTSettings boolForKey:@"custom_fonts"]);
    }
    return %orig;
}

%end

// The switches behind "No focus lost" and "Disable media carousel", as the app
// reads them today.
%hook TFSFeatureSwitches

- (double)doubleForKey:(NSString*)key {
    double value = %orig;
    NFBPortNoteSwitch(@"doubleForKey", key, value);
    return value;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    double value = %orig;
    NFBPortNoteSwitch(@"unsafePeekDoubleForKey", key, value);
    return value;
}

- (BOOL)boolForKey:(NSString*)key {
    BOOL value = %orig;
    NFBPortNoteSwitch(@"boolForKey", key, value);
    return value;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    BOOL value = %orig;
    NFBPortNoteSwitch(@"unsafePeekBoolForKey", key, value);
    return value;
}

%end

%hook TFSInstrumentedFeatureSwitches

- (double)doubleForKey:(NSString*)key {
    double value = %orig;
    NFBPortNoteSwitch(@"instrumented doubleForKey", key, value);
    return value;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    double value = %orig;
    NFBPortNoteSwitch(@"instrumented unsafePeekDoubleForKey", key, value);
    return value;
}

- (BOOL)boolForKey:(NSString*)key {
    BOOL value = %orig;
    NFBPortNoteSwitch(@"instrumented boolForKey", key, value);
    return value;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    BOOL value = %orig;
    NFBPortNoteSwitch(@"instrumented unsafePeekBoolForKey", key, value);
    return value;
}

%end
