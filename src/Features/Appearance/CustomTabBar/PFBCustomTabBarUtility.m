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

// A saved entry is kept only when its fields have the types the editor reads.
static BOOL PFBRegistryEntryIsValid(id entry) {
    if (![entry isKindOfClass:[NSDictionary class]] ||
        ![entry[PFBTabPageKey] isKindOfClass:[NSString class]]) {
        return NO;
    }
    id title = entry[PFBTabTitleKey];
    id image = entry[PFBTabImageKey];
    id panelID = entry[PFBTabPanelIDKey];
    return (!title || [title isKindOfClass:[NSString class]]) &&
           (!image || [image isKindOfClass:[NSString class]]) &&
           (!panelID || [panelID isKindOfClass:[NSNumber class]]);
}

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
        for (id entry in saved) {
            if (PFBRegistryEntryIsValid(entry)) {
                [registry addObject:entry];
            }
        }
    });
    return registry;
}

+ (void)recordTabViews:(NSArray*)tabViews {
    NSMutableArray<NSDictionary*>* registry = [self registry];
    BOOL changed = NO;

    for (T1TabView* tabView in tabViews) {
        // Each getter is asked first, so a tab Twitter describes another way is skipped.
        if (![tabView respondsToSelector:@selector(scribePage)] || ![tabView respondsToSelector:@selector(panelID)]) {
            continue;
        }
        NSString* page = tabView.scribePage;
        if (page.length == 0) {
            continue;
        }

        NSString* title = [tabView respondsToSelector:@selector(title)] && tabView.title.length ? tabView.title : page;
        NSString* image = [self imageNameForTabView:tabView] ?: @"";
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

+ (NSString*)imageNameForTabView:(T1TabView*)tabView {
    NSString* image = [tabView respondsToSelector:@selector(imageName)] ? tabView.imageName : nil;
    if (image.length) {
        return image;
    }
    // Avatar-drawn tabs (Profile) have no imageName; use the glyph the
    // native customization screen resolves for the panel.
    Class identity = NSClassFromString(@"T1PanelIdentity");
    if (![identity respondsToSelector:@selector(iconImageNameForPanelID:)] ||
        ![tabView respondsToSelector:@selector(panelID)]) {
        return nil;
    }
    return [identity iconImageNameForPanelID:tabView.panelID];
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
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSString*>*)defaultVisiblePageIDs {
    return @[@"home", @"guide", @"ntab", @"messages"];
}

@end
