// Shared helpers for the hook files.

#import "Support/HookHelpers.h"
#import "Support/TwitterChirpFont.h"

void PFBEnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView)) {
    if (!view || !block)
        return;

    // Hidden branches never need live restyling, so skip them entirely.
    if (view.hidden || view.alpha <= 0.01)
        return;

    block(view);

    // Depth cap; a static counter is fine since traversal only runs on the main
    // thread.
    static NSInteger recursionDepth = 0;
    if (recursionDepth > 15)
        return;

    recursionDepth++;
    for (UIView* subview in view.subviews) {
        PFBEnumerateSubviewsRecursively(subview, block);
    }
    recursionDepth--;
}

static void PFBWalkSubviews(UIView* view, NSInteger depthLeft, void (^block)(UIView* currentView)) {
    block(view);
    if (depthLeft <= 0) {
        return;
    }
    for (UIView* subview in view.subviews) {
        PFBWalkSubviews(subview, depthLeft - 1, block);
    }
}

void PFBWalkAllSubviews(UIView* view, NSInteger maxDepth, void (^block)(UIView* currentView)) {
    if (view && block) {
        PFBWalkSubviews(view, maxDepth, block);
    }
}

// Module content reaches the section arrays wrapped in TFNDataViewItem (the
// real view model is its -item); standalone timeline items are the view model
// directly.
id PFBUnwrapDataViewItem(id item) {
    if ([item isKindOfClass:objc_getClass("TFNDataViewItem")] &&
        [item respondsToSelector:@selector(item)]) {
        return [item performSelector:@selector(item)];
    }

    return item;
}

static BOOL PFBIsModuleHeaderItem(id item) {
    return [NSStringFromClass([PFBUnwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"];
}

static BOOL PFBIsModuleFooterItem(id item) {
    return [NSStringFromClass([PFBUnwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleFooterViewModel"];
}

// A module renders as a consecutive run of header, content, footer. When a
// module's content is removed entirely, mark its header and footer too.
void PFBMarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed) {
    NSUInteger count = items.count;

    for (NSUInteger i = 0; i < count; i++) {
        if ([removed containsIndex:i] || !PFBIsModuleHeaderItem(items[i])) {
            continue;
        }

        NSUInteger contentCount = 0;
        BOOL contentRemoved = YES;
        NSUInteger j = i + 1;
        while (j < count && !PFBIsModuleHeaderItem(items[j]) &&
               !PFBIsModuleFooterItem(items[j])) {
            contentCount++;
            if (![removed containsIndex:j]) {
                contentRemoved = NO;
            }
            j++;
        }

        if (contentCount > 0 && contentRemoved) {
            [removed addIndex:i];
            if (j < count && PFBIsModuleFooterItem(items[j])) {
                [removed addIndex:j];
            }
        }
    }
}

// Twitter's brand blue. Not iOS systemBlue, which is darker and belongs to
// UIKit's own controls.
static UIColor* PFBTwitterBlueColor(void) {
    return [UIColor colorWithRed:0x1D / 255.0
                           green:0xA1 / 255.0
                            blue:0xF2 / 255.0
                           alpha:1.0];
}

// The color for surfaces carrying Twitter's branding: the tab bar accent and the
// navigation logo. A picked accent wins; with none, the brand blue is used rather
// than PFBCurrentAccentColor's systemBlue fallback, which feeds the window tint.
UIColor* PFBBrandAccentColor(void) {
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
    BOOL picked = [defs objectForKey:@"pfb_custom_accent_hex"] ||
                  [defs objectForKey:@"pfb_color_theme_selectedColor"] ||
                  [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"] >= 1;
    if (picked) {
        return PFBCurrentAccentColor() ?: PFBTwitterBlueColor();
    }
    return PFBTwitterBlueColor();
}

UIColor* PFBCurrentAccentColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    if (!TAEColorSettingsCls) {
        return [UIColor systemBlueColor];
    }

    id settings = [TAEColorSettingsCls sharedSettings];
    id current = [settings currentColorPalette];
    id palette = [current colorPalette];
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];

    // The stored PrimeFreeBird pick wins over Twitter's own color option.
    if ([defs objectForKey:@"pfb_color_theme_selectedColor"]) {
        NSInteger opt = [defs integerForKey:@"pfb_color_theme_selectedColor"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    if ([defs objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        NSInteger opt =
            [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    return [UIColor systemBlueColor];
}

NSString* const PFBMobileSafariUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like "
    @"Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

// The material iOS gives its bars. Liquid Glass exists from iOS 26 and is
// resolved by name because the build SDK predates it; older systems get the
// chrome material.
static UIVisualEffect* PFBBarMaterial(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if (glass) {
        UIVisualEffect* effect = [[glass alloc] init];
        if (effect) {
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

UIVisualEffectView* PFBMaterialBehind(UIView* host) {
    UIVisualEffectView* material =
        [[UIVisualEffectView alloc] initWithEffect:PFBBarMaterial()];
    material.translatesAutoresizingMaskIntoConstraints = NO;
    material.userInteractionEnabled = NO;
    material.alpha = 0.0;
    [host insertSubview:material atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [material.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [material.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [material.topAnchor constraintEqualToAnchor:host.topAnchor],
        [material.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
    return material;
}

BOOL PFBIsXDomain(NSString* domainOrHost) {
    NSString* domain = domainOrHost.lowercaseString;
    if ([domain hasPrefix:@"."]) {
        domain = [domain substringFromIndex:1];
    }
    for (NSString* root in @[ @"x.com", @"twitter.com" ]) {
        if ([domain isEqualToString:root] ||
            [domain hasSuffix:[@"." stringByAppendingString:root]]) {
            return YES;
        }
    }
    return NO;
}

// Flat bitmap + AlwaysOriginal: the theme's window tint cannot repaint it.
UIImage* PFBFlatGlyph(UIImage* source, UIColor* color) {
    if (!source || !color) {
        return source;
    }
    CGSize size = source.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return source;
    }
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = source.scale;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* painted = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
        [source drawInRect:rect];
        CGContextSetBlendMode(context.CGContext, kCGBlendModeSourceIn);
        [color setFill];
        CGContextFillRect(context.CGContext, rect);
    }];
    return [painted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// The label color, as Twitter tints its own bar buttons. Resolved to a fixed color: the
// vector renderer turns a dynamic one black, and the theme would claim it.
UIColor* PFBBarIconColor(UITraitCollection* traits) {
    UIColor* color = [UIColor labelColor];
    if (traits) {
        return [color resolvedColorWithTraitCollection:traits] ?: color;
    }
    return color;
}

// imageNamed: cannot see loose PDFs in a bundle, so the page is opened by path and drawn.
UIImage* PFBBundlePDFImage(NSString* file, CGSize size, CGFloat fill) {
    NSURL* url = [[PFBBundle sharedBundle] pathForFile:file];
    if (!url || size.width < 1 || size.height < 1) {
        return nil;
    }
    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
    if (!pdf) {
        return nil;
    }
    UIImage* rendered = nil;
    CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
    if (page) {
        UIGraphicsImageRendererFormat* fmt = [UIGraphicsImageRendererFormat preferredFormat];
        fmt.opaque = NO;
        UIGraphicsImageRenderer* renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
        rendered = [renderer imageWithActions:^(UIGraphicsImageRendererContext* ctx) {
            CGContextRef c = ctx.CGContext;
            CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
            CGFloat scale =
                MIN(size.width / box.size.width, size.height / box.size.height) * fill;
            CGFloat drawnW = box.size.width * scale;
            CGFloat drawnH = box.size.height * scale;
            CGContextTranslateCTM(c, (size.width - drawnW) / 2.0,
                                  size.height - (size.height - drawnH) / 2.0);
            CGContextScaleCTM(c, 1, -1);
            CGContextScaleCTM(c, scale, scale);
            CGContextDrawPDFPage(c, page);
        }];
    }
    CGPDFDocumentRelease(pdf);
    return rendered;
}

static const NSInteger kPFBToastTag = 90312;

static void PFBDismissToast(UIView* toast) {
    [UIView animateWithDuration:0.22
        animations:^{
          toast.alpha = 0;
          toast.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
        }
        completion:^(__unused BOOL finished) {
          [toast removeFromSuperview];
        }];
}

// Built end to end, since the app's own strip draws its label white. Under Liquid Glass
// the capsule is real glass, which shapes its own edge; otherwise the frosted material
// is clipped to the rounded shape with a hairline border.
void PFBShowToast(UIWindow* window, NSString* text, void (^undo)(void)) {
    if (!window) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            for (UIWindow* candidate in ((UIWindowScene*)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                }
            }
        }
    }
    if (!window) {
        return;
    }
    [[window viewWithTag:kPFBToastTag] removeFromSuperview];

    BOOL liquidGlass = [PFBSettings boolForKey:@"enable_liquid_glass"];
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect* effect = liquidGlass && glassClass ? [[glassClass alloc] init] : nil;
    if (!effect) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial];
        liquidGlass = NO;
    }
    UIVisualEffectView* toast = [[UIVisualEffectView alloc] initWithEffect:effect];
    toast.tag = kPFBToastTag;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.layer.cornerRadius = 22.0;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    if (!liquidGlass) {
        toast.clipsToBounds = YES;
        toast.layer.borderWidth = 0.5;
        toast.layer.borderColor = [UIColor separatorColor].CGColor;
    }
    toast.layer.shadowColor = [UIColor blackColor].CGColor;
    toast.layer.shadowOpacity = 0.16f;
    toast.layer.shadowRadius = 10.0;
    toast.layer.shadowOffset = CGSizeMake(0, 4);
    [window addSubview:toast];

    // The material alone lets the screen read through the words, so a veil of the
    // background color at 80 % sits behind the content, rounded like the capsule.
    UIView* content = toast.contentView;
    UIView* veil = [[UIView alloc] init];
    veil.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.80];
    veil.userInteractionEnabled = NO;
    veil.layer.cornerRadius = 22.0;
    veil.layer.cornerCurve = kCACornerCurveContinuous;
    veil.layer.masksToBounds = YES;
    veil.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:veil];

    UILabel* label = [[UILabel alloc] init];
    label.text = text;
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15]);
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:label];

    NSMutableArray<NSLayoutConstraint*>* constraints = [@[
        [veil.topAnchor constraintEqualToAnchor:content.topAnchor],
        [veil.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [veil.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [veil.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [toast.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [toast.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor
                                        constant:6],
        [toast.heightAnchor constraintEqualToConstant:44],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.leadingAnchor
                                                        constant:20],
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [label.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
    ] mutableCopy];
    if (undo) {
        UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"THREADS_UNDO"]
                forState:UIControlStateNormal];
        [button setTitleColor:PFBCurrentAccentColor() forState:UIControlStateNormal];
        button.titleLabel.font =
            PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:15]);
        button.translatesAutoresizingMaskIntoConstraints = NO;
        // Weak: the capsule holds the button, which holds this action.
        __weak UIVisualEffectView* weakToast = toast;
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction* action) {
                  undo();
                  PFBDismissToast(weakToast);
                }]
            forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:button];
        [constraints addObjectsFromArray:@[
            [button.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:14],
            [button.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
            [button.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        ]];
    } else {
        [constraints addObject:[label.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                                                    constant:-18]];
    }
    [NSLayoutConstraint activateConstraints:constraints];

    toast.alpha = 0;
    toast.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
    [UIView animateWithDuration:0.22
                     animations:^{
                       toast.alpha = 1;
                       toast.transform = CGAffineTransformIdentity;
                     }];
    // A capsule with an Undo stays a second longer, so the button can be reached.
    NSTimeInterval shown = undo ? 4.0 : 3.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(shown * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (toast.superview) {
                         PFBDismissToast(toast);
                     }
                   });
}

@implementation PFBHitButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    CGRect bounds = self.bounds;
    CGFloat dx = MIN(0.0, (CGRectGetWidth(bounds) - 44.0) / 2.0);
    CGFloat dy = MIN(0.0, (CGRectGetHeight(bounds) - 44.0) / 2.0);
    return CGRectContainsPoint(CGRectInset(bounds, dx, dy), point);
}

@end

UIViewController* PFBOwningController(UIView* view) {
    UIResponder* responder = view;
    while ((responder = responder.nextResponder)) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController*)responder;
        }
    }
    return nil;
}

UIViewController* PFBOwningTopController(UIView* view) {
    UIViewController* controller = PFBOwningController(view);
    if ([controller isKindOfClass:[UINavigationController class]]) {
        return ((UINavigationController*)controller).topViewController ?: controller;
    }
    return controller;
}

BOOL PFBOnNativeGlassStack(UIViewController* controller) {
    static Class stack;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      stack = NSClassFromString(@"XNAVNavigationController");
    });
    return stack && [controller.navigationController isKindOfClass:stack];
}

// A Twitter glyph drawn in the box of the system symbol it replaces; the symbol stays
// as the fallback when the app does not ship that glyph.
UIImage* PFBTwitterGlyphFor(NSString* name, UIImage* systemImage) {
    if (!systemImage || ![UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        return systemImage;
    }
    UIImage* glyph = [UIImage tfn_vectorImageNamed:name fitsSize:systemImage.size fillColor:[UIColor blackColor]];
    return glyph ? [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : systemImage;
}
