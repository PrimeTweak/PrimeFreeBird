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
        btn.tintColor = [UIColor secondaryLabelColor];
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
