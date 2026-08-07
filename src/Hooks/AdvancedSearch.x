//
//  AdvancedSearch.x
//  PrimeFreeBird
//
//  Entry point for the native Advanced Search form, on the Explore screen: a
//  filters button added to the guide container's navigation item. BEST-EFFORT
//  by design — if this build's Explore chrome ignores standard bar button
//  items, nothing appears and nothing breaks; the Settings → Search →
//  Advanced search row remains the guaranteed entry.
//
//  The glyph is drawn here rather than fetched. Twitter draws every one of its
//  line glyphs at 2 units — filter, filter_bars, bulleted_list, all of them —
//  while the settings gear beside this button is 2.6, so no glyph in the
//  library matches it. The shape below is Twitter's own, taken from its filter
//  glyph; only the stroke and the canvas are ours, both set so the icon
//  reaches the screen at the gear's width and the gear's stroke.
//

#import "HookHelpers.h"
#import "Search/AdvancedSearchViewController.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void* kNFBAdvSearchBtnKey = &kNFBAdvSearchBtnKey;

// One grey for every icon we add, frozen to a static colour. The gear is
// dimmed to 60% opacity because its glyph refuses to be tinted, so our own
// icons use the label colour at the same 60% — the two then match exactly.
// Resolving it here also stops the theme's window tint from claiming the icon
// on a cold launch, a trap the colour work already taught us.
// Twitter's filter glyph at the settings gear's weight. Its geometry, on a
// 24-unit canvas: two rails centred on y=7 and y=17, each running from x=3 to
// x=21, crossed by a handle centred on x=15 (top) and x=9 (bottom) standing 8
// units tall. The rail is cut on the far side of each handle, leaving the 1.5
// unit gap Twitter draws. Only the stroke changes, 2 units to the gear's 2.55.
// Rail centre line, handle centre — a block cannot capture a local C array, so
// the table lives at file scope where it is simply referenced.
static const CGFloat kNFBSliderGeometry[2][2] = {{7.0, 15.0}, {17.0, 9.0}};

static UIImage* NFBSlidersGlyph(CGFloat side) {
    const CGFloat kUnit = 24.0;
    const CGFloat kThickness = 2.07;
    const CGFloat kGap = 1.5;
    const CGFloat kHandleHalfHeight = 4.0;
    CGFloat scale = side / kUnit;
    CGFloat half = kThickness / 2.0;
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [[UIColor blackColor] setFill];
            for (NSInteger i = 0; i < 2; i++) {
                CGFloat cy = kNFBSliderGeometry[i][0];
                CGFloat cx = kNFBSliderGeometry[i][1];
                CGFloat railEnd = cx - half;
                CGFloat railStart = cx + half + kGap;
                // Rail up to the handle, rail after the gap, then the handle.
                CGContextFillRect(context.CGContext,
                                  CGRectMake(3.0 * scale, (cy - half) * scale,
                                             (railEnd - 3.0) * scale,
                                             kThickness * scale));
                CGContextFillRect(context.CGContext,
                                  CGRectMake(railStart * scale, (cy - half) * scale,
                                             (21.0 - railStart) * scale,
                                             kThickness * scale));
                CGContextFillRect(context.CGContext,
                                  CGRectMake((cx - half) * scale,
                                             (cy - kHandleHalfHeight) * scale,
                                             kThickness * scale,
                                             kHandleHalfHeight * 2.0 * scale));
            }
        }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIColor* NFBBarIconGrey(UITraitCollection* traits) {
    UIColor* grey = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    if (traits && [grey respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
        return [grey resolvedColorWithTraitCollection:traits] ?: grey;
    }
    return grey;
}

%hook _TtC14T1TwitterSwift28GuideContainerViewController

%new
- (void)nfbShowAdvancedSearch {
    AdvancedSearchViewController* form = [[AdvancedSearchViewController alloc] init];
    UINavigationController* nav =
        [[UINavigationController alloc] initWithRootViewController:form];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [(UIViewController*)self presentViewController:nav
                                          animated:YES
                                        completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
        BOOL enabled = [BHTSettings boolForKey:@"advanced_search"];
        UIBarButtonItem* existingBtn =
            objc_getAssociatedObject(self, kNFBAdvSearchBtnKey);
        UINavigationItem* item = [(UIViewController*)self navigationItem];
        if (!item) {
            return;
        }
        if (!enabled) {
            // Toggle is off: remove our button if a previous appearance
            // added it, so the setting applies live on the next visit.
            if (existingBtn) {
                NSMutableArray* items =
                    [item.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
                [items removeObject:existingBtn];
                item.rightBarButtonItems = items;
                objc_setAssociatedObject(self, kNFBAdvSearchBtnKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return;
        }
        if (existingBtn) {
            return;
        }
        // 27.33 points, not the gear's 24: this shape covers 18 of its 24
        // units against the gear's 20.5, so it needs the wider canvas to
        // reach the same width on screen.
        UIImage* icon = NFBSlidersGlyph(27.33);
        UIBarButtonItem* btn =
            [[UIBarButtonItem alloc] initWithImage:icon
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(nfbShowAdvancedSearch)];
        // Muted grey, like the labels of the unselected tabs next to it.
        // Cast, never a bare self.property: this class is only forward-declared,
        // so the compiler refuses a direct message to it.
        btn.tintColor = NFBBarIconGrey(((UIViewController*)self).traitCollection);
        // Match Twitter's own settings gear, which sits flat in this bar:
        // iOS 26 gives bar buttons a shared Liquid Glass capsule, and opting
        // out is a single property. It only exists on the iOS 26 SDK, so it
        // goes through the runtime — older systems simply skip it.
        if ([btn respondsToSelector:@selector(setHidesSharedBackground:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(
                btn, @selector(setHidesSharedBackground:), YES);
        }
        NSArray* existing = item.rightBarButtonItems ?: @[];
        item.rightBarButtonItems = [existing arrayByAddingObject:btn];
        objc_setAssociatedObject(self, kNFBAdvSearchBtnKey, btn,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (id e) {
    }
}

%end
