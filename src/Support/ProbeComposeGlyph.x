// Probe for Twitter 12.45, removed once read: why the compose button keeps Twitter's "+" after Chat.
// Each change of what the button shows is written with the tab under the lens, as are each configuration
// Twitter applies to the button, each image it sets there with its callers, and the host's layout passes.

#import "Support/HookHelpers.h"
#import "Support/TFNHeaders.h"

@interface XDSButton : UIControl
@end

static NSString* const kPFBGlyphProbeTopic = @"probe compose glyph";
static const NSUInteger kPFBGlyphProbeCap = 90;
static const NSUInteger kPFBGlyphProbeImageLines = 16;
static NSUInteger gPFBGlyphProbeSeq;
static CFAbsoluteTime gPFBGlyphProbeStart;
static __weak UIView* gPFBGlyphProbeHost;
static __weak UIView* gPFBGlyphProbeBar;
static NSUInteger gPFBGlyphProbeLayouts;
static NSUInteger gPFBGlyphProbeImageWritten;
static NSString* gPFBGlyphProbeLast;
static CADisplayLink* gPFBGlyphProbeLink;

static void PFBGlyphProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBGlyphProbeTopic,
                     [NSString stringWithFormat:@"%02lu %.2f s %@", (unsigned long)++gPFBGlyphProbeSeq,
                                                CFAbsoluteTimeGetCurrent() - gPFBGlyphProbeStart, line],
                     kPFBGlyphProbeCap);
}

// A short name per view or image, kept for as long as it lives.
static NSString* PFBGlyphProbeId(id object, NSString* prefix) {
    static NSMapTable* ids;
    static NSUInteger next;
    ids = ids ?: [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                         valueOptions:NSPointerFunctionsStrongMemory
                                             capacity:0];
    NSNumber* number = [ids objectForKey:object];
    if (!number) {
        number = @(++next);
        [ids setObject:number forKey:object];
    }
    return [prefix stringByAppendingString:number.stringValue];
}

// Where the image draws on an 8 x 8 grid, as 16 hex digits: each glyph gets its own.
static NSString* PFBGlyphProbeMask(UIImage* image) {
    uint8_t pixels[64] = {0};
    CGContextRef context = CGBitmapContextCreate(pixels, 8, 8, 8, 8, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) {
        return @"?";
    }
    CGContextTranslateCTM(context, 0.0, 8.0);
    CGContextScaleCTM(context, 1.0, -1.0);
    UIGraphicsPushContext(context);
    [image drawInRect:CGRectMake(0.0, 0.0, 8.0, 8.0)];
    UIGraphicsPopContext();
    CGContextRelease(context);
    uint64_t bits = 0;
    for (int i = 0; i < 64; i++) {
        if (pixels[i] > 64) {
            bits |= (uint64_t)1 << i;
        }
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)bits];
}

// An image as its name, "feather" when it draws the tweak's feather, its size and its symbol name.
static NSString* PFBGlyphProbeKind(UIImage* image) {
    static NSMapTable* kinds;
    static NSString* featherMask;
    if (!image) {
        return @"none";
    }
    kinds = kinds ?: [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                             valueOptions:NSPointerFunctionsStrongMemory
                                                 capacity:0];
    if (!featherMask) {
        UIImage* feather = [UIImage tfn_vectorImageNamed:@"feather" fitsSize:CGSizeMake(24.0, 24.0) fillColor:[UIColor whiteColor]];
        featherMask = feather ? PFBGlyphProbeMask(feather) : @"-";
    }
    NSString* kind = [kinds objectForKey:image];
    if (kind) {
        return kind;
    }
    NSString* mask = PFBGlyphProbeMask(image);
    NSString* symbol = @"";
    NSString* text = image.description;
    NSRange open = [text rangeOfString:@"symbol("];
    if (image.isSymbolImage && open.location != NSNotFound) {
        NSRange close = [text rangeOfString:@")" options:0 range:NSMakeRange(open.location, text.length - open.location)];
        if (close.location != NSNotFound) {
            symbol = [@" " stringByAppendingString:[text substringWithRange:NSMakeRange(open.location, close.location - open.location + 1)]];
        }
    }
    kind = [NSString stringWithFormat:@"%@ %@ %.0fx%.0f%@", PFBGlyphProbeId(image, @"img"),
                                      [mask isEqualToString:featherMask] ? @"feather" : mask, image.size.width, image.size.height,
                                      symbol];
    [kinds setObject:kind forKey:image];
    return kind;
}

// How much of the view shows up to the host, as drawn: 0 when hidden.
static float PFBGlyphProbeShown(UIView* view, UIView* host) {
    float alpha = 1.0f;
    for (UIView* level = view; level; level = level.superview) {
        CALayer* layer = level.layer.presentationLayer ?: level.layer;
        if (level.hidden || layer.hidden) {
            return 0.0f;
        }
        alpha *= layer.opacity;
        if (level == host) {
            break;
        }
    }
    return alpha;
}

// The images the button carries: those that show, and how many image views hold one.
static NSString* PFBGlyphProbeState(UIView* host) {
    NSMutableArray<NSString*>* shown = [NSMutableArray array];
    __block NSUInteger count = 0;
    PFBWalkAllSubviews(host, 16, ^(UIView* view) {
      UIImage* image = [view isKindOfClass:[UIImageView class]] ? ((UIImageView*)view).image : nil;
      if (!image) {
          return;
      }
      count++;
      float alpha = PFBGlyphProbeShown(view, host);
      if (alpha >= 0.05f) {
          [shown addObject:[NSString stringWithFormat:@"%@ %@ %@", PFBGlyphProbeId(view, @"iv"), PFBGlyphProbeKind(image),
                                                      alpha > 0.95f ? @"full" : @"partly"]];
      }
    });
    return [NSString stringWithFormat:@"shows [%@], %lu image views", [shown componentsJoinedByString:@"; "], (unsigned long)count];
}

// The tab whose place the selection lens is nearest, counted from the left.
static NSString* PFBGlyphProbeTab(void) {
    static Class lensClass;
    static Class itemClass;
    lensClass = lensClass ?: NSClassFromString(@"_TtC13XDesignSystem10LiquidLens");
    itemClass = itemClass ?: NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    UIView* bar = gPFBGlyphProbeBar;
    if (!bar || !lensClass || !itemClass) {
        return @"?";
    }
    __block UIView* lens = nil;
    NSMutableArray<UIView*>* items = [NSMutableArray array];
    PFBWalkAllSubviews(bar, 8, ^(UIView* view) {
      if (!lens && [view isKindOfClass:lensClass]) {
          lens = view;
      }
      if ([view isKindOfClass:itemClass]) {
          [items addObject:view];
      }
    });
    if (!lens) {
        return @"?";
    }
    NSMutableSet<NSNumber*>* places = [NSMutableSet set];
    for (UIView* item in items) {
        if (![item isDescendantOfView:lens]) {
            [places addObject:@(round([bar convertPoint:item.center fromView:item.superview].x))];
        }
    }
    NSArray<NSNumber*>* sorted = [places.allObjects sortedArrayUsingSelector:@selector(compare:)];
    CALayer* drawn = lens.layer.presentationLayer ?: lens.layer;
    CGFloat x = [bar convertPoint:drawn.position fromView:lens.superview].x;
    NSUInteger nearest = NSNotFound;
    CGFloat best = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < sorted.count; i++) {
        CGFloat distance = fabs(sorted[i].doubleValue - x);
        if (distance < best) {
            best = distance;
            nearest = i;
        }
    }
    return nearest == NSNotFound ? @"?" : [NSString stringWithFormat:@"%lu of %lu", (unsigned long)nearest + 1, (unsigned long)sorted.count];
}

// The calls that led here, as image and offset, with the nearest exported name when there is one.
static NSString* PFBGlyphProbeStack(void) {
    NSArray<NSNumber*>* addresses = [NSThread callStackReturnAddresses];
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for (NSUInteger i = 2; i < addresses.count && frames.count < 18; i++) {
        void* address = (void*)addresses[i].unsignedLongValue;
        Dl_info info;
        if (!dladdr(address, &info) || !info.dli_fname) {
            continue;
        }
        NSString* symbol = info.dli_sname ? [NSString stringWithUTF8String:info.dli_sname] : @"";
        if (symbol.length > 50) {
            symbol = [symbol substringToIndex:50];
        }
        [frames addObject:[NSString stringWithFormat:@"%@+0x%lx %@", [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent],
                                                     (unsigned long)((uintptr_t)address - (uintptr_t)info.dli_fbase), symbol]];
    }
    return [frames componentsJoinedByString:@" < "];
}

@interface PFBGlyphProbeTicker : NSObject
@end

@implementation PFBGlyphProbeTicker

// Each frame drawn: what the button shows, written when it changes.
- (void)tick:(CADisplayLink*)link {
    UIView* host = gPFBGlyphProbeHost;
    if (gPFBGlyphProbeSeq >= kPFBGlyphProbeCap) {
        link.paused = YES;
        return;
    }
    if (!host.window) {
        return;
    }
    NSString* state = PFBGlyphProbeState(host);
    if ([state isEqualToString:gPFBGlyphProbeLast]) {
        return;
    }
    gPFBGlyphProbeLast = state;
    PFBGlyphProbeLine([NSString stringWithFormat:@"button %@; tab %@; host laid out %lu times since the last line", state, PFBGlyphProbeTab(),
                                                 (unsigned long)gPFBGlyphProbeLayouts]);
    gPFBGlyphProbeLayouts = 0;
}

@end

// The compose button's host: a round accessory of 72 points at most, holding Twitter's button view.
static BOOL PFBGlyphProbeIsCompose(UIView* host) {
    static Class buttonClass;
    buttonClass = buttonClass ?: NSClassFromString(@"_TtC11XNavigation25TabBarAccessoryButtonView");
    CGSize size = host.bounds.size;
    if (!buttonClass || size.width < 1.0 || size.width > 72.0 || fabs(size.width - size.height) > 8.0) {
        return NO;
    }
    __block BOOL found = NO;
    PFBWalkAllSubviews(host, 3, ^(UIView* view) {
      found = found || [view isKindOfClass:buttonClass];
    });
    return found;
}

static void PFBGlyphProbeNoteHost(UIView* host) {
    if (!host.window || !PFBGlyphProbeIsCompose(host)) {
        return;
    }
    gPFBGlyphProbeLayouts++;
    if (gPFBGlyphProbeHost == host) {
        return;
    }
    gPFBGlyphProbeHost = host;
    PFBGlyphProbeLine([NSString stringWithFormat:@"compose host %@ %.0fx%.0f, Classic Tweet button %d, Visual style %d", PFBGlyphProbeId(host, @"host"),
                                                 host.bounds.size.width, host.bounds.size.height, [PFBSettings boolForKey:@"restore_tweet_button"],
                                                 [PFBSettings boolForKey:@"enable_liquid_glass"]]);
    if (!gPFBGlyphProbeLink) {
        gPFBGlyphProbeLink = [CADisplayLink displayLinkWithTarget:[PFBGlyphProbeTicker new] selector:@selector(tick:)];
        [gPFBGlyphProbeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

%hook _TtC11XNavigation23TabBarAccessoryHostView

- (void)layoutSubviews {
    %orig;
    PFBGlyphProbeNoteHost((UIView*)self);
}

- (void)didMoveToWindow {
    %orig;
    PFBGlyphProbeNoteHost((UIView*)self);
}

%end

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    gPFBGlyphProbeBar = (UIView*)self;
}

%end

// Each configuration Twitter gives the compose button, with what it showed before and right after.
%hook XDSButton

- (void)applyConfiguration:(id)configuration animated:(BOOL)animated completion:(id)completion {
    UIView* host = gPFBGlyphProbeHost;
    BOOL ours = host && [(UIView*)self isDescendantOfView:host] && gPFBGlyphProbeSeq < kPFBGlyphProbeCap;
    NSString* before = ours ? PFBGlyphProbeState(host) : nil;
    %orig;
    if (ours) {
        PFBGlyphProbeLine([NSString stringWithFormat:@"configuration %@ applied, animated %d, tab %@ | before: %@ | right after: %@",
                                                     NSStringFromClass([configuration class]), animated, PFBGlyphProbeTab(), before,
                                                     PFBGlyphProbeState(host)]);
    }
}

%end

// Each new image set on a view inside the compose button, with what landed and who set it.
%hook UIImageView

- (void)setImage:(UIImage*)image {
    UIView* host = gPFBGlyphProbeHost;
    UIImage* old = self.image;
    BOOL ours = image && image != old && host && gPFBGlyphProbeImageWritten < kPFBGlyphProbeImageLines &&
                [(UIView*)self isDescendantOfView:host];
    %orig;
    if (ours && ![PFBGlyphProbeKind(old) isEqualToString:PFBGlyphProbeKind(self.image)]) {
        gPFBGlyphProbeImageWritten++;
        PFBGlyphProbeLine([NSString stringWithFormat:@"image set on %@: given %@, now %@ (was %@), tab %@ | %@", PFBGlyphProbeId(self, @"iv"),
                                                     PFBGlyphProbeKind(image), PFBGlyphProbeKind(self.image), PFBGlyphProbeKind(old),
                                                     PFBGlyphProbeTab(), PFBGlyphProbeStack()]);
    }
}

%end

%ctor {
    %init;
    gPFBGlyphProbeStart = CFAbsoluteTimeGetCurrent();
}
