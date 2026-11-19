// Probe for Twitter 12.45, removed once read: how the compose button gets Twitter's "+" back after Chat,
// and how its button tells itself from Chat's. Everything drawn where the button stands is written as it
// changes, with the tab, the button's own names, and each view or image Twitter puts in it with its callers.

#import "Support/HookHelpers.h"
#import "Support/TFNHeaders.h"

@interface XDSButton : UIControl
@end

static NSString* const kPFBGlyphProbeTopic = @"probe compose glyph";
static const NSUInteger kPFBGlyphProbeCap = 200;
static const NSUInteger kPFBGlyphProbeCallLines = 24;
static NSUInteger gPFBGlyphProbeSeq;
static CFAbsoluteTime gPFBGlyphProbeStart;
static NSHashTable<UIView*>* gPFBGlyphProbeHosts;
static __weak UIView* gPFBGlyphProbeBar;
static NSUInteger gPFBGlyphProbeLayouts;
static NSUInteger gPFBGlyphProbeAdded;
static NSUInteger gPFBGlyphProbeImages;
static NSUInteger gPFBGlyphProbeConfigurations;
static NSString* gPFBGlyphProbeLast;
static NSString* gPFBGlyphProbeLastViews;
static CADisplayLink* gPFBGlyphProbeLink;

static void PFBGlyphProbeLine(NSString* line) {
    PFBCompatMeasure(kPFBGlyphProbeTopic,
                     [NSString stringWithFormat:@"%03lu %.2f s %@", (unsigned long)++gPFBGlyphProbeSeq,
                                                CFAbsoluteTimeGetCurrent() - gPFBGlyphProbeStart, line],
                     kPFBGlyphProbeCap);
}

static NSMapTable* PFBGlyphProbeTable(void) {
    return [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                     valueOptions:NSPointerFunctionsStrongMemory
                                         capacity:0];
}

// A short name per view or image, kept for as long as it lives.
static NSString* PFBGlyphProbeId(id object, NSString* prefix) {
    static NSMapTable* ids;
    static NSUInteger next;
    ids = ids ?: PFBGlyphProbeTable();
    NSNumber* number = [ids objectForKey:object];
    if (!number) {
        number = @(++next);
        [ids setObject:number forKey:object];
    }
    return [prefix stringByAppendingString:number.stringValue];
}

static NSString* PFBGlyphProbeShort(id object, NSUInteger length) {
    NSString* text = [object description] ?: @"-";
    text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return text.length > length ? [[text substringToIndex:length] stringByAppendingString:@"..."] : text;
}

// Where the image draws on an 8 x 8 grid, as 16 hex digits, drawn the way UIKit draws it.
static NSString* PFBGlyphProbeMask(UIImage* image) {
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

// An image as its name, "feather" when it draws the tweak's feather, its size, rendering mode and how
// it describes itself.
static NSString* PFBGlyphProbeKind(UIImage* image) {
    static NSMapTable* kinds;
    static NSString* featherMask;
    if (!image) {
        return @"none";
    }
    kinds = kinds ?: PFBGlyphProbeTable();
    if (!featherMask) {
        UIImage* feather = [UIImage tfn_vectorImageNamed:@"feather" fitsSize:CGSizeMake(24.0, 24.0) fillColor:[UIColor whiteColor]];
        featherMask = feather ? PFBGlyphProbeMask(feather) : @"-";
    }
    NSString* kind = [kinds objectForKey:image];
    if (!kind) {
        NSString* mask = PFBGlyphProbeMask(image);
        kind = [NSString stringWithFormat:@"%@ %@ %.0fx%.0f mode %ld symbol %d \"%@\"", PFBGlyphProbeId(image, @"img"),
                                          [mask isEqualToString:featherMask] ? @"feather" : mask, image.size.width, image.size.height,
                                          (long)image.renderingMode, image.isSymbolImage, PFBGlyphProbeShort(image, 90)];
        [kinds setObject:kind forKey:image];
    }
    return kind;
}

// How much of the view shows up to the given ancestor, as drawn: 0 when hidden.
static float PFBGlyphProbeShown(UIView* view, UIView* top) {
    float alpha = 1.0f;
    for (UIView* level = view; level; level = level.superview) {
        CALayer* layer = level.layer.presentationLayer ?: level.layer;
        if (level.hidden || layer.hidden) {
            return 0.0f;
        }
        alpha *= layer.opacity;
        if (level == top) {
            break;
        }
    }
    return alpha;
}

// A view that draws something of its own: an image, layer contents, a copy of other views, or text.
static NSString* PFBGlyphProbeDrawn(UIView* view) {
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage* image = ((UIImageView*)view).image;
        return image ? [@"image " stringByAppendingString:PFBGlyphProbeKind(image)] : nil;
    }
    NSString* name = NSStringFromClass([view class]);
    if ([name containsString:@"Snapshot"] || [name containsString:@"Replicant"] || [name containsString:@"Portal"]) {
        return [@"copy " stringByAppendingString:name];
    }
    if ([view isKindOfClass:[UILabel class]] && ((UILabel*)view).text.length) {
        return [NSString stringWithFormat:@"text \"%@\"", ((UILabel*)view).text];
    }
    return view.layer.contents ? [@"contents " stringByAppendingString:name] : nil;
}

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

static UIView* PFBGlyphProbeHostOnScreen(void) {
    for (UIView* host in gPFBGlyphProbeHosts) {
        if (host.window && PFBGlyphProbeIsCompose(host)) {
            return host;
        }
    }
    return nil;
}

static UIView* PFBGlyphProbeHostAbove(UIView* view) {
    static Class hostClass;
    hostClass = hostClass ?: NSClassFromString(@"_TtC11XNavigation23TabBarAccessoryHostView");
    UIView* level = view.superview;
    for (NSInteger depth = 0; level && depth < 16; depth++, level = level.superview) {
        if ([level isKindOfClass:hostClass]) {
            return PFBGlyphProbeIsCompose(level) ? level : nil;
        }
    }
    return nil;
}

// The tab whose place the selection lens is nearest, with the name the tab gives itself.
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

// The names Twitter gives the button and the content it was last given.
static NSString* PFBGlyphProbeButtonNames(UIView* host) {
    static Class accessoryClass;
    accessoryClass = accessoryClass ?: NSClassFromString(@"_TtC11XNavigation25TabBarAccessoryButtonView");
    __block UIView* accessory = nil;
    __block UIControl* button = nil;
    Class buttonClass = NSClassFromString(@"XDSButton");
    PFBWalkAllSubviews(host, 4, ^(UIView* view) {
      if (!accessory && accessoryClass && [view isKindOfClass:accessoryClass]) {
          accessory = view;
      }
      if (!button && buttonClass && [view isKindOfClass:buttonClass]) {
          button = (UIControl*)view;
      }
    });
    SEL current = NSSelectorFromString(@"currentConfiguration");
    id configuration = [button respondsToSelector:current] ? ((id (*)(id, SEL))objc_msgSend)(button, current) : nil;
    return [NSString stringWithFormat:@"host id \"%@\" | accessory label \"%@\" id \"%@\" | button label \"%@\" id \"%@\" value \"%@\" | configuration %@ %@",
                                      host.accessibilityIdentifier ?: @"-", accessory.accessibilityLabel ?: @"-",
                                      accessory.accessibilityIdentifier ?: @"-", button.accessibilityLabel ?: @"-",
                                      button.accessibilityIdentifier ?: @"-", button.accessibilityValue ?: @"-",
                                      configuration ? NSStringFromClass([configuration class]) : @"-",
                                      configuration ? PFBGlyphProbeShort(configuration, 300) : @""];
}

// What shows inside the host, and what shows over its place from elsewhere in the bar's chrome.
static NSString* PFBGlyphProbeState(UIView* host, NSString** viewsOut) {
    NSMutableArray<NSString*>* inside = [NSMutableArray array];
    NSMutableArray<NSString*>* views = [NSMutableArray array];
    PFBWalkAllSubviews(host, 16, ^(UIView* view) {
      NSString* drawn = PFBGlyphProbeDrawn(view);
      if (!drawn) {
          return;
      }
      NSString* name = PFBGlyphProbeId(view, @"v");
      [views addObject:name];
      float alpha = PFBGlyphProbeShown(view, host);
      if (alpha >= 0.05f) {
          [inside addObject:[NSString stringWithFormat:@"%@ %@ %@", name, drawn, alpha > 0.95f ? @"full" : @"partly"]];
      }
    });
    NSMutableArray<NSString*>* over = [NSMutableArray array];
    static Class chromeClass;
    chromeClass = chromeClass ?: NSClassFromString(@"_TtC11XNavigation25TabBarChromeContainerView");
    UIView* chrome = nil;
    for (UIView* level = host.superview; level && chromeClass; level = level.superview) {
        if ([level isKindOfClass:chromeClass]) {
            chrome = level;
        }
    }
    if (chrome) {
        CGRect place = [host convertRect:host.bounds toView:nil];
        PFBWalkAllSubviews(chrome, 14, ^(UIView* view) {
          if ([view isDescendantOfView:host] || [host isDescendantOfView:view]) {
              return;
          }
          NSString* drawn = PFBGlyphProbeDrawn(view);
          if (!drawn || !CGRectIntersectsRect(place, [view convertRect:view.bounds toView:nil]) ||
              PFBGlyphProbeShown(view, chrome) < 0.05f) {
              return;
          }
          [over addObject:[NSString stringWithFormat:@"%@ %@", PFBGlyphProbeId(view, @"v"), drawn]];
        });
    }
    *viewsOut = [views componentsJoinedByString:@","];
    return [NSString stringWithFormat:@"inside [%@] views %@%@", [inside componentsJoinedByString:@"; "], *viewsOut,
                                      over.count ? [NSString stringWithFormat:@" | over it [%@]", [over componentsJoinedByString:@"; "]] : @""];
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

// Each frame drawn: what shows at the button, written when it changes, with the button's names when
// the set of drawing views changes.
- (void)tick:(CADisplayLink*)link {
    if (gPFBGlyphProbeSeq >= kPFBGlyphProbeCap) {
        link.paused = YES;
        return;
    }
    UIView* host = PFBGlyphProbeHostOnScreen();
    if (!host) {
        return;
    }
    NSString* views = nil;
    NSString* state = PFBGlyphProbeState(host, &views);
    if ([state isEqualToString:gPFBGlyphProbeLast]) {
        return;
    }
    gPFBGlyphProbeLast = state;
    BOOL newViews = ![views isEqualToString:gPFBGlyphProbeLastViews];
    gPFBGlyphProbeLastViews = views;
    PFBGlyphProbeLine([NSString stringWithFormat:@"%@ %@; tab %@; host laid out %lu times%@", PFBGlyphProbeId(host, @"host"), state,
                                                 PFBGlyphProbeTab(), (unsigned long)gPFBGlyphProbeLayouts,
                                                 newViews ? [@" | " stringByAppendingString:PFBGlyphProbeButtonNames(host)] : @""]);
    gPFBGlyphProbeLayouts = 0;
}

@end

static void PFBGlyphProbeNoteHost(UIView* host) {
    if (!host.window || !PFBGlyphProbeIsCompose(host)) {
        return;
    }
    gPFBGlyphProbeLayouts++;
    gPFBGlyphProbeHosts = gPFBGlyphProbeHosts ?: [NSHashTable weakObjectsHashTable];
    if ([gPFBGlyphProbeHosts containsObject:host]) {
        return;
    }
    [gPFBGlyphProbeHosts addObject:host];
    PFBGlyphProbeLine([NSString stringWithFormat:@"compose host %@ %.0fx%.0f, Classic Tweet button %d, Visual style %d | %@", PFBGlyphProbeId(host, @"host"),
                                                 host.bounds.size.width, host.bounds.size.height, [PFBSettings boolForKey:@"restore_tweet_button"],
                                                 [PFBSettings boolForKey:@"enable_liquid_glass"], PFBGlyphProbeButtonNames(host)]);
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

// Each content Twitter gives a button inside a compose host, either way it can be given.
%hook XDSButton

- (void)applyConfiguration:(id)configuration animated:(BOOL)animated completion:(id)completion {
    %orig;
    UIView* host = PFBGlyphProbeHostAbove((UIView*)self);
    if (host && gPFBGlyphProbeConfigurations++ < kPFBGlyphProbeCallLines) {
        PFBGlyphProbeLine([NSString stringWithFormat:@"configuration applied, animated %d, tab %@ | %@ | %@", animated, PFBGlyphProbeTab(),
                                                     PFBGlyphProbeButtonNames(host), PFBGlyphProbeStack()]);
    }
}

- (void)setCurrentConfiguration:(id)configuration {
    %orig;
    UIView* host = PFBGlyphProbeHostAbove((UIView*)self);
    if (host && gPFBGlyphProbeConfigurations++ < kPFBGlyphProbeCallLines) {
        PFBGlyphProbeLine([NSString stringWithFormat:@"configuration set, tab %@ | %@ | %@", PFBGlyphProbeTab(), PFBGlyphProbeButtonNames(host),
                                                     PFBGlyphProbeStack()]);
    }
}

%end

%hook UIImageView

// Each image view that comes into a compose button, with its image, its place and who put it there.
- (void)didMoveToSuperview {
    %orig;
    UIView* host = self.superview ? PFBGlyphProbeHostAbove((UIView*)self) : nil;
    if (host && gPFBGlyphProbeAdded++ < kPFBGlyphProbeCallLines) {
        PFBGlyphProbeLine([NSString stringWithFormat:@"%@ added with %@, in a window %d, tab %@ | %@", PFBGlyphProbeId(self, @"v"),
                                                     PFBGlyphProbeKind(self.image), self.window != nil, PFBGlyphProbeTab(), PFBGlyphProbeStack()]);
    }
}

// Each new image set on a view inside a compose button, with what landed and who set it.
- (void)setImage:(UIImage*)image {
    UIImage* old = self.image;
    BOOL watched = image && image != old && gPFBGlyphProbeImages < kPFBGlyphProbeCallLines;
    %orig;
    UIView* host = watched ? PFBGlyphProbeHostAbove((UIView*)self) : nil;
    if (host) {
        gPFBGlyphProbeImages++;
        PFBGlyphProbeLine([NSString stringWithFormat:@"image set on %@: given %@, now %@, was %@, tab %@ | %@", PFBGlyphProbeId(self, @"v"),
                                                     PFBGlyphProbeKind(image), PFBGlyphProbeKind(self.image), PFBGlyphProbeKind(old),
                                                     PFBGlyphProbeTab(), PFBGlyphProbeStack()]);
    }
}

%end

%ctor {
    %init;
    gPFBGlyphProbeStart = CFAbsoluteTimeGetCurrent();
}
