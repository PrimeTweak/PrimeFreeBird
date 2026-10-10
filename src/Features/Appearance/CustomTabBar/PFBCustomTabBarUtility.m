// Registry and helpers of the custom tab bar: panel ids, images, order.

#import "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.h"
#import "Support/T1Headers.h"

// The Home tab is the app's landing surface, so it is always kept visible and
// pinned first.
NSString* const PFBCustomTabBarHomePageID = @"home";

NSString* const PFBTabPageKey = @"page";
NSString* const PFBTabTitleKey = @"title";
NSString* const PFBTabImageKey = @"image";
NSString* const PFBTabPanelIDKey = @"panelID";

static NSString* const kVisibleKey = @"pfb_tabs_visible";
static NSString* const kRegistryKey = @"pfb_tab_registry";

// Former list of hidden tabs, superseded by the visible list (a tab not in it is
// hidden); removed whenever the selection is saved or reset.
static NSString* const kLegacyHiddenKey = @"pfb_tabs_hidden";

@implementation PFBCustomTabBarUtility

#pragma mark - Live capture

// Ordered union of every tab ever recorded, persisted across launches, so a tab
// missing from the current tab bar stays available in the editor.
+ (NSMutableArray<NSDictionary*>*)registry {
    static NSMutableArray<NSDictionary*>* registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableArray array];
        NSArray* saved =
            [[NSUserDefaults standardUserDefaults] arrayForKey:kRegistryKey];
        if (saved) {
            [registry addObjectsFromArray:saved];
        }
    });
    return registry;
}

+ (void)recordTabViews:(NSArray*)tabViews {
    NSMutableArray<NSDictionary*>* registry = [self registry];
    BOOL changed = NO;

    for (T1TabView* tabView in tabViews) {
        NSString* page = tabView.scribePage;
        if (page.length == 0) {
            continue;
        }

        NSString* title = tabView.title.length ? tabView.title : page;
        NSString* image = tabView.imageName ?: @"";
        if (image.length == 0) {
            // Avatar-drawn tabs (Profile) have no imageName; use the glyph the
            // native customization screen resolves for the panel.
            image = [NSClassFromString(@"T1PanelIdentity")
                        iconImageNameForPanelID:tabView.panelID]
                        ?: @"";
        }
        NSDictionary* entry = @{
            PFBTabPageKey: page,
            PFBTabTitleKey: title,
            PFBTabImageKey: image,
            PFBTabPanelIDKey: @(tabView.panelID)
        };

        NSInteger existing = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)registry.count; i++) {
            if ([registry[i][PFBTabPageKey] isEqualToString:page]) {
                existing = i;
                break;
            }
        }

        if (existing == NSNotFound) {
            [registry addObject:entry];
            changed = YES;
        } else if (![registry[existing] isEqualToDictionary:entry]) {
            registry[existing] = entry;
            changed = YES;
        }
    }

    if (changed) {
        [[NSUserDefaults standardUserDefaults] setObject:[registry copy]
                                                  forKey:kRegistryKey];
    }
}

+ (NSArray<NSDictionary*>*)availableTabs {
    return [[self registry] copy];
}

+ (NSDictionary*)metadataForPage:(NSString*)pageID {
    for (NSDictionary* entry in [self registry]) {
        if ([entry[PFBTabPageKey] isEqualToString:pageID]) {
            return entry;
        }
    }
    return nil;
}

#pragma mark - Selection

+ (NSArray<NSString*>*)visiblePageIDsInOrder {
    NSArray<NSString*>* visible =
        [[NSUserDefaults standardUserDefaults] stringArrayForKey:kVisibleKey];
    if (!visible) {
        return nil;
    }

    NSMutableArray<NSString*>* pageIDs = [visible mutableCopy];
    // Home is always visible and always first.
    [pageIDs removeObject:PFBCustomTabBarHomePageID];
    [pageIDs insertObject:PFBCustomTabBarHomePageID atIndex:0];
    return pageIDs;
}

+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible {
    [[NSUserDefaults standardUserDefaults] setObject:visible forKey:kVisibleKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyHiddenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)resetSelection {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVisibleKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyHiddenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSString*>*)defaultVisiblePageIDs {
    return @[@"home", @"guide", @"ntab", @"messages"];
}

@end
