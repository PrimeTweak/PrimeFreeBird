//
//  AdvancedSearch.x
//  PrimeFreeBird
//
//  Entry point for the native Advanced Search form, on the Explore screen: a
//  filters button (slider.horizontal.3) added to the guide container's
//  navigation item. BEST-EFFORT by design — if this build's Explore chrome
//  ignores standard bar button items, nothing appears and nothing breaks; the
//  Settings → Search → Advanced search row remains the guaranteed entry.
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
        UIImage* icon = [UIImage systemImageNamed:@"slider.horizontal.3"];
        if (!icon) {
            return;
        }
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
