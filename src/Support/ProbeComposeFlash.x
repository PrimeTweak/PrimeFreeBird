// Probe for Twitter 12.45, removed once read: what draws Twitter's "+" for a moment as the compose
// button fades to or from Chat's. Every layer of the button that draws is written as it changes, as
// drawn, with each content set and each layer added there and the calls that did it.

#import "Support/HookHelpers.h"
#import "Support/TFNHeaders.h"

static NSString* const kPFBFlashProbeTopic = @"probe compose flash";
static const NSUInteger kPFBFlashProbeCap = 220;
static const NSUInteger kPFBFlashProbeCallLines = 24;
static NSUInteger gPFBFlashProbeSeq;
static CFAbsoluteTime gPFBFlashProbeStart;
static __weak UIView* gPFBFlashProbeHost;
static __weak UIView* gPFBFlashProbeBar;
static NSUInteger gPFBFlashProbeContentLines;
static NSUInteger gPFBFlashProbeAddLines;
static NSString* gPFBFlashProbeLast;
static CADisplayLink* gPFBFlashProbeLink;

static void PFBFlashProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBFlashProbeTopic,
                     [NSString stringWithFormat:@"%03lu %.3f s %@", (unsigned long)++gPFBFlashProbeSeq,
                                                CFAbsoluteTimeGetCurrent() - gPFBFlashProbeStart, line],
                     kPFBFlashProbeCap);
}

static NSMapTable* PFBFlashProbeTable(void) {
    return [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                     valueOptions:NSPointerFunctionsStrongMemory
                                         capacity:0];
}

// A short name per layer or view, kept for as long as it lives.
static NSString* PFBFlashProbeId(id object, NSString* prefix) {
    static NSMapTable* ids;
    static NSUInteger next;
    ids = ids ?: PFBFlashProbeTable();
    NSNumber* number = [ids objectForKey:object];
    if (!number) {
        number = @(++next);
        [ids setObject:number forKey:object];
    }
    return [prefix stringByAppendingString:number.stringValue];
}

// Where a picture draws on an 8 x 8 grid, as 16 hex digits, the way the v108 probe read glyphs.
static NSString* PFBFlashProbeMask(UIImage* image) {
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1.0;
    format.opaque = NO;
    UIImage* small = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8.0, 8.0) format:format]
        imageWithActions:^(__unused UIGraphicsImageRendererContext* context) {
          [image drawInRect:CGRectMake(0.0, 0.0, 8.0, 8.0)];
        }];
    uint8_t pixels[64] = {0};
    CGContextRef context = CGBitmapContextCreate(pixels, 8, 8, 8, 8, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context || !small.CGImage) {
        if (context) {
            CGContextRelease(context);
        }
        return @"?";
    }
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, 8.0, 8.0), small.CGImage);
    CGContextRelease(context);
    uint64_t bits = 0;
    for (int i = 0; i < 64; i++) {
        if (pixels[i] > 64) {
            bits |= (uint64_t)1 << i;
        }
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)bits];
}

// A layer's contents: a picture named by its shape when the v108 probe saw it (feather, Twitter's
// "+", Chat's glyph), its pixel size, or the kind of contents it is.
static NSString* PFBFlashProbeContents(id contents) {
    static NSMapTable* kinds;
    static NSString* featherMask;
    if (!contents) {
        return @"none";
    }
    kinds = kinds ?: PFBFlashProbeTable();
    if (!featherMask) {
        UIImage* feather = [UIImage tfn_vectorImageNamed:@"feather" fitsSize:CGSizeMake(24.0, 24.0) fillColor:[UIColor whiteColor]];
        featherMask = feather ? PFBFlashProbeMask(feather) : @"-";
    }
    NSString* kind = [kinds objectForKey:contents];
    if (kind) {
        return kind;
    }
    CFTypeRef ref = (__bridge CFTypeRef)contents;
    if (CFGetTypeID(ref) == CGImageGetTypeID()) {
        CGImageRef picture = (CGImageRef)ref;
        NSString* mask = PFBFlashProbeMask([UIImage imageWithCGImage:picture]);
        NSString* name = [mask isEqualToString:featherMask]           ? @"feather"
                         : [mask isEqualToString:@"0000183c3c180000"] ? @"plus"
                         : [mask isEqualToString:@"006e620242423c00"] ? @"chat"
                                                                      : mask;
        kind = [NSString stringWithFormat:@"%@ %zux%zu", name, CGImageGetWidth(picture), CGImageGetHeight(picture)];
    } else {
        CFStringRef type = CFCopyTypeIDDescription(CFGetTypeID(ref));
        kind = [NSString stringWithFormat:@"contents %@", (__bridge_transfer NSString*)type];
    }
    kind = [NSString stringWithFormat:@"%@ %@", PFBFlashProbeId(contents, @"c"), kind];
    [kinds setObject:kind forKey:contents];
    return kind;
}

// A layer that draws something of its own: contents, a filled or stroked path, text, or a copy of
// other layers. Plain containers are left out.
static NSString* PFBFlashProbeDrawn(CALayer* layer) {
    NSString* name = NSStringFromClass([layer class]);
    if (layer.contents) {
        return PFBFlashProbeContents(layer.contents);
    }
    if ([layer isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer*)layer).path) {
        CGRect box = CGPathGetBoundingBox(((CAShapeLayer*)layer).path);
        return [NSString stringWithFormat:@"path %.0fx%.0f", box.size.width, box.size.height];
    }
    if ([layer isKindOfClass:[CATextLayer class]]) {
        return [NSString stringWithFormat:@"text \"%@\"", ((CATextLayer*)layer).string ?: @""];
    }
    if ([name containsString:@"Portal"] || [name containsString:@"Replicat"] || [name containsString:@"Snapshot"]) {
        return [@"copy " stringByAppendingString:name];
    }
    return nil;
}

static NSString* PFBFlashProbeOwner(CALayer* layer) {
    id delegate = layer.delegate;
    if ([delegate isKindOfClass:[UIView class]]) {
        return [NSString stringWithFormat:@"view %@ %@", NSStringFromClass([delegate class]), PFBFlashProbeId(delegate, @"v")];
    }
    return [@"layer " stringByAppendingString:NSStringFromClass([layer class])];
}

// Every drawing layer under the host's layer, as drawn: its own opacity times its parents'.
static void PFBFlashProbeWalk(CALayer* layer, float parent, NSInteger depth, NSMutableArray<NSString*>* shown) {
    CALayer* drawn = layer.presentationLayer ?: layer;
    float opacity = drawn.hidden ? 0.0f : parent * drawn.opacity;
    if (opacity < 0.05f || depth > 24) {
        return;
    }
    NSString* kind = depth > 0 ? PFBFlashProbeDrawn(layer) : nil;
    if (kind) {
        CGRect place = [layer convertRect:layer.bounds toLayer:gPFBFlashProbeHost.layer];
        [shown addObject:[NSString stringWithFormat:@"%@ %@ (%@) at %.0f,%.0f %.0fx%.0f %@", PFBFlashProbeId(layer, @"L"), kind,
                                                    PFBFlashProbeOwner(layer), place.origin.x, place.origin.y, place.size.width,
                                                    place.size.height, opacity > 0.95f ? @"full" : @"partly"]];
    }
    for (CALayer* sublayer in layer.sublayers) {
        PFBFlashProbeWalk(sublayer, opacity, depth + 1, shown);
    }
}

// The tab whose place the selection lens is nearest, with the name the tab gives itself.
static NSString* PFBFlashProbeTab(void) {
    static Class lensClass;
    static Class itemClass;
    lensClass = lensClass ?: NSClassFromString(@"_TtC13XDesignSystem10LiquidLens");
    itemClass = itemClass ?: NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    UIView* bar = gPFBFlashProbeBar;
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
    CALayer* drawn = lens.layer.presentationLayer ?: lens.layer;
    CGFloat x = [bar convertPoint:drawn.position fromView:lens.superview].x;
    UIView* nearest = nil;
    CGFloat best = CGFLOAT_MAX;
    for (UIView* item in items) {
        CGFloat distance = fabs([bar convertPoint:item.center fromView:item.superview].x - x);
        if (![item isDescendantOfView:lens] && distance < best) {
            best = distance;
            nearest = item;
        }
    }
    return nearest ? [NSString stringWithFormat:@"\"%@\"", nearest.accessibilityLabel ?: @"-"] : @"?";
}

// The calls that led here, as image and offset, with the nearest exported name when there is one.
static NSString* PFBFlashProbeStack(void) {
    NSArray<NSNumber*>* addresses = [NSThread callStackReturnAddresses];
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for (NSUInteger i = 2; i < addresses.count && frames.count < 16; i++) {
        void* address = (void*)addresses[i].unsignedLongValue;
        Dl_info info;
        if (!dladdr(address, &info) || !info.dli_fname) {
            continue;
        }
        [frames addObject:[NSString stringWithFormat:@"%@+0x%lx", [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent],
                                                     (unsigned long)((uintptr_t)address - (uintptr_t)info.dli_fbase)]];
    }
    return [frames componentsJoinedByString:@" < "];
}

// Whether the layer sits under the compose host's layer, 24 levels at most.
static BOOL PFBFlashProbeInHost(CALayer* layer) {
    CALayer* top = gPFBFlashProbeHost.layer;
    if (!top) {
        return NO;
    }
    CALayer* level = layer;
    for (NSInteger depth = 0; level && depth < 24; depth++, level = level.superlayer) {
        if (level == top) {
            return YES;
        }
    }
    return NO;
}

// Each layer added to the compose button, with what it draws and who added it, once per addition
// however the adding calls nest.
static NSUInteger gPFBFlashProbeAdding;

static void PFBFlashProbeAdded(CALayer* parent, CALayer* layer) {
    if (gPFBFlashProbeAdding || !layer || gPFBFlashProbeAddLines >= kPFBFlashProbeCallLines || !PFBFlashProbeInHost(parent)) {
        return;
    }
    gPFBFlashProbeAddLines++;
    PFBFlashProbeLine([NSString stringWithFormat:@"%@ (%@) added to %@ (%@), draws %@, tab %@ | %@", PFBFlashProbeId(layer, @"L"),
                                                 PFBFlashProbeOwner(layer), PFBFlashProbeId(parent, @"L"), PFBFlashProbeOwner(parent),
                                                 PFBFlashProbeDrawn(layer) ?: @"nothing yet", PFBFlashProbeTab(), PFBFlashProbeStack()]);
}

@interface PFBFlashProbeTicker : NSObject
@end

@implementation PFBFlashProbeTicker

// Each frame drawn: the button's drawing layers, written when they change.
- (void)tick:(CADisplayLink*)link {
    if (gPFBFlashProbeSeq >= kPFBFlashProbeCap) {
        link.paused = YES;
        return;
    }
    UIView* host = gPFBFlashProbeHost;
    if (!host.window) {
        return;
    }
    NSMutableArray<NSString*>* shown = [NSMutableArray array];
    PFBFlashProbeWalk(host.layer, 1.0f, 0, shown);
    NSString* state = [shown componentsJoinedByString:@"; "];
    if ([state isEqualToString:gPFBFlashProbeLast]) {
        return;
    }
    gPFBFlashProbeLast = state;
    PFBFlashProbeLine([NSString stringWithFormat:@"shows [%@]; tab %@", state, PFBFlashProbeTab()]);
}

@end

// The compose button's host: a round accessory of 72 points at most, holding Twitter's button view.
static void PFBFlashProbeNoteHost(UIView* host) {
    static Class buttonClass;
    buttonClass = buttonClass ?: NSClassFromString(@"_TtC11XNavigation25TabBarAccessoryButtonView");
    CGSize size = host.bounds.size;
    if (!host.window || !buttonClass || size.width < 1.0 || size.width > 72.0 || fabs(size.width - size.height) > 8.0 ||
        gPFBFlashProbeHost == host) {
        return;
    }
    __block BOOL found = NO;
    PFBWalkAllSubviews(host, 3, ^(UIView* view) {
      found = found || [view isKindOfClass:buttonClass];
    });
    if (!found) {
        return;
    }
    gPFBFlashProbeHost = host;
    PFBFlashProbeLine([NSString stringWithFormat:@"compose host %@ %.0fx%.0f, Classic Tweet button %d", PFBFlashProbeId(host, @"host"), size.width,
                                                 size.height, [PFBSettings boolForKey:@"restore_tweet_button"]]);
    if (!gPFBFlashProbeLink) {
        gPFBFlashProbeLink = [CADisplayLink displayLinkWithTarget:[PFBFlashProbeTicker new] selector:@selector(tick:)];
        [gPFBFlashProbeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

%hook _TtC11XNavigation23TabBarAccessoryHostView

- (void)layoutSubviews {
    %orig;
    PFBFlashProbeNoteHost((UIView*)self);
}

- (void)didMoveToWindow {
    %orig;
    PFBFlashProbeNoteHost((UIView*)self);
}

%end

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    gPFBFlashProbeBar = (UIView*)self;
}

%end

%hook CALayer

// Each content set on a layer of the compose button, with who set it.
- (void)setContents:(id)contents {
    %orig;
    if (contents && gPFBFlashProbeContentLines < kPFBFlashProbeCallLines && PFBFlashProbeInHost((CALayer*)self)) {
        gPFBFlashProbeContentLines++;
        PFBFlashProbeLine([NSString stringWithFormat:@"contents set on %@ (%@): %@, tab %@ | %@", PFBFlashProbeId(self, @"L"),
                                                     PFBFlashProbeOwner((CALayer*)self), PFBFlashProbeContents(contents), PFBFlashProbeTab(),
                                                     PFBFlashProbeStack()]);
    }
}

- (void)addSublayer:(CALayer*)layer {
    gPFBFlashProbeAdding++;
    %orig;
    gPFBFlashProbeAdding--;
    PFBFlashProbeAdded((CALayer*)self, layer);
}

- (void)insertSublayer:(CALayer*)layer atIndex:(unsigned)index {
    gPFBFlashProbeAdding++;
    %orig;
    gPFBFlashProbeAdding--;
    PFBFlashProbeAdded((CALayer*)self, layer);
}

- (void)insertSublayer:(CALayer*)layer below:(CALayer*)sibling {
    gPFBFlashProbeAdding++;
    %orig;
    gPFBFlashProbeAdding--;
    PFBFlashProbeAdded((CALayer*)self, layer);
}

- (void)insertSublayer:(CALayer*)layer above:(CALayer*)sibling {
    gPFBFlashProbeAdding++;
    %orig;
    gPFBFlashProbeAdding--;
    PFBFlashProbeAdded((CALayer*)self, layer);
}

%end

%ctor {
    %init;
    gPFBFlashProbeStart = CFAbsoluteTimeGetCurrent();
}
