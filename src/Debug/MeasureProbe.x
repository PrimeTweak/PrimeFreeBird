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
static NSUInteger gTfnSubstituted;                      // tfn_fontWithName calls that returned a custom font
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
            [out appendFormat:@"[probe] fonts (custom on): %@\n", [parts componentsJoinedByString:@" | "]];
            [out appendFormat:@"[probe] fonts: tfn_fontWithName substituted %lu time(s)",
                              (unsigned long)gTfnSubstituted];
        } else {
            [out appendString:@"[probe] fonts: no font built while recording with custom fonts on"];
        }
    }
    if (gWorstFrame > 0) {
        [out appendFormat:@"\n[probe] lag: worst frame %.0f ms, %.1f s ago",
                          gWorstFrame * 1000.0, CACurrentMediaTime() - gWorstFrameAt];
    }
    return out;
}

%ctor {
    probePrepare();
    NFBDebugAddProbeSummary(^NSString* { return probeSummary(); });
    NFBProbeFrameWatcher* watcher = [NFBProbeFrameWatcher new];
    CADisplayLink* link = [CADisplayLink displayLinkWithTarget:watcher selector:@selector(tick:)];
    // The watcher is captured by the display link, which the run loop keeps.
    objc_setAssociatedObject(link, _cmd, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// MARK: - follow button state, before and after a tap

%hook TUIFollowButtonV2

- (void)buttonTapped {
    if (!NFBDebugIsRecording()) {
        return %orig;
    }
    SEL sel = @selector(followState);
    NSInteger before = [self respondsToSelector:sel]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(self, sel) : -999;
    %orig;
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __typeof__(self) strongSelf = weakSelf;
      NSInteger after = (strongSelf && [strongSelf respondsToSelector:sel])
          ? ((NSInteger (*)(id, SEL))objc_msgSend)(strongSelf, sel) : -999;
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
    if (NFBDebugIsRecording() && [BHTSettings boolForKey:@"custom_fonts"]) {
        noteFont(@"UIFont.tfn_fontWithName", font);
        NSString* wanted = [[NSUserDefaults standardUserDefaults]
            objectForKey:([name containsString:@"Bold"] || [name containsString:@"Heavy"])
                             ? @"bhtwitter_font_2" : @"bhtwitter_font_1"];
        if (wanted && [font.fontName isEqualToString:wanted]) {
            @synchronized(gLock) { gTfnSubstituted++; }
        }
    }
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
