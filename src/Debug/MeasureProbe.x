// Measurement only: three open questions on Twitter 12.26, written into the
// capture under [probe] so the decision log cannot evict them. Inert unless the
// debugger is recording. Removed once the answers are in.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/BHTSettings.h"
#import "Debug/NFBDebugger.h"

// MARK: - shared state

static NSObject* gLock;
static NSMutableArray<NSString*>* gFollowTransitions;   // "before -> after"
static NSMutableDictionary<NSString*, NSNumber*>* gFontCounts;
static NSMutableDictionary<NSString*, NSString*>* gFontFamily;  // factory -> first family seen
static CFTimeInterval gWorstFrame;                      // longest frame gap in the rolling window
static CFTimeInterval gWorstFrameAt;
static CFTimeInterval gLastFrame;

static void probePrepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gLock = [NSObject new];
      gFollowTransitions = [NSMutableArray array];
      gFontCounts = [NSMutableDictionary dictionary];
      gFontFamily = [NSMutableDictionary dictionary];
    });
}

static void noteFont(NSString* factory, UIFont* font) {
    if (!NFBDebugIsRecording() || ![BHTSettings boolForKey:@"custom_fonts"]) {
        return;
    }
    probePrepare();
    @synchronized(gLock) {
        gFontCounts[factory] = @(gFontCounts[factory].unsignedIntegerValue + 1);
        if (!gFontFamily[factory] && font.familyName) {
            gFontFamily[factory] = font.familyName;
        }
    }
}

// MARK: - lag: longest frame in a rolling two-second window

@interface NFBProbeFrameWatcher : NSObject
@end

@implementation NFBProbeFrameWatcher
- (void)tick:(CADisplayLink*)link {
    if (!NFBDebugIsRecording()) {
        gLastFrame = 0;
        return;
    }
    CFTimeInterval now = link.timestamp;
    if (gLastFrame > 0) {
        CFTimeInterval gap = now - gLastFrame;
        if (now - gWorstFrameAt > 2.0) {
            gWorstFrame = 0;
        }
        if (gap > gWorstFrame) {
            gWorstFrame = gap;
            gWorstFrameAt = now;
        }
    }
    gLastFrame = now;
}
@end

// MARK: - summary

static NSString* probeSummary(void) {
    probePrepare();
    NSMutableString* out = [NSMutableString string];
    @synchronized(gLock) {
        NSString* follows = gFollowTransitions.count
            ? [gFollowTransitions componentsJoinedByString:@", "] : @"no follow taps seen";
        [out appendFormat:@"[probe] follow state before->after: %@\n", follows];

        if (gFontCounts.count) {
            NSMutableArray<NSString*>* parts = [NSMutableArray array];
            for (NSString* factory in gFontCounts) {
                [parts addObject:[NSString stringWithFormat:@"%@ %@x -> %@", factory,
                                  gFontCounts[factory], gFontFamily[factory] ?: @"?"]];
            }
            [out appendFormat:@"[probe] fonts (custom on): %@", [parts componentsJoinedByString:@" | "]];
        } else {
            [out appendString:@"[probe] fonts: no font built while recording with custom fonts on"];
        }
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    for (NSString* key in @[ @"bhtwitter_font_1", @"bhtwitter_font_2" ]) {
        NSString* chosen = [defaults objectForKey:key];
        if (chosen.length) {
            [out appendFormat:@"\n[probe] %@ = %@ (resolves: %@)", key, chosen,
                              [UIFont fontWithName:chosen size:12.0] ? @"yes" : @"no"];
        }
    }
    if (gWorstFrame > 0) {
        [out appendFormat:@"\n[probe] lag: worst frame %.0f ms, %.1f s ago",
                          gWorstFrame * 1000.0, CACurrentMediaTime() - gWorstFrameAt];
    }
    return out;
}

static CADisplayLink* gFrameLink;

%ctor {
    probePrepare();
    NFBDebugAddProbeSummary(^NSString* { return probeSummary(); });
    // Started once the app is up, and only while recording, so a frame clock
    // never runs at full rate outside a measurement session.
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!NFBDebugIsRecording() || gFrameLink) {
          return;
      }
      gFrameLink = [CADisplayLink displayLinkWithTarget:[NFBProbeFrameWatcher new]
                                               selector:@selector(tick:)];
      [gFrameLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}

// MARK: - follow button state, before and after a tap

%hook TUIFollowButtonV2

- (void)buttonTapped {
    if (!NFBDebugIsRecording()) {
        return %orig;
    }
    // The class is only forward-declared, so it is reached through id.
    id button = (id)self;
    SEL sel = @selector(followState);
    NSInteger before = [button respondsToSelector:sel]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(button, sel) : -999;
    %orig;
    __weak id weakButton = button;
    dispatch_async(dispatch_get_main_queue(), ^{
      id strongButton = weakButton;
      NSInteger after = (strongButton && [strongButton respondsToSelector:sel])
          ? ((NSInteger (*)(id, SEL))objc_msgSend)(strongButton, sel) : -999;
      probePrepare();
      @synchronized(gLock) {
        [gFollowTransitions addObject:[NSString stringWithFormat:@"%ld->%ld",
                                       (long)before, (long)after]];
      }
    });
}

%end

// MARK: - which font factories the app actually calls

%hook UIFont

+ (UIFont*)tfn_fontWithName:(NSString*)name size:(CGFloat)size {
    UIFont* font = %orig;
    noteFont(@"UIFont.tfn_fontWithName", font);
    return font;
}

%end

%hook XFontCatalog

+ (UIFont*)contentFontWithOffset:(CGFloat)offset weight:(NSInteger)weight {
    UIFont* font = %orig;
    noteFont(@"XFontCatalog.contentFont", font);
    return font;
}

+ (UIFont*)customFontOfSize:(CGFloat)size weight:(NSInteger)weight
      scalesWithDynamicType:(BOOL)scales {
    UIFont* font = %orig;
    noteFont(@"XFontCatalog.customFont", font);
    return font;
}

+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(CGFloat)weight {
    UIFont* font = %orig;
    noteFont(@"XFontCatalog.tabularDigits", font);
    return font;
}

%end
