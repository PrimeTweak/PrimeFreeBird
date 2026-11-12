// The sidebar's items as Twitter's panels: their names and glyphs, the ones shown or hidden from
// the Sidebar page, and the ones Twitter built when it last rebuilt the sidebar.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when an item is hidden or shown, so the page and the sidebar follow.
FOUNDATION_EXPORT NSNotificationName const PFBSidebarItemsDidChangeNotification;

// The panel Grok's sidebar shortcut opens, hidden by its own option.
static const NSInteger PFBSidebarGrokPanel = 14;

@interface PFBSidebarItems : NSObject

// The panels Twitter's sidebar builds, in its order.
+ (NSArray<NSNumber*>*)catalog;
// Twitter's name and glyph for a panel; nil when Twitter has none.
+ (nullable NSString*)nameForPanel:(NSInteger)panelID;
+ (nullable NSString*)glyphForPanel:(NSInteger)panelID;

// Out of the sidebar as chosen on the page, or by default; Grok by its own option.
+ (BOOL)isHidden:(NSInteger)panelID;
+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden;
// The page's items kept out of the sidebar, Grok's shortcut aside.
+ (NSArray<NSNumber*>*)hiddenPanelIDs;
// Every item back to its default.
+ (void)resetToDefault;

// Twitter's own tab bar panels, in their order, as the sidebar last asked for them.
+ (void)recordTabPanelIDs:(NSArray*)panelIDs;
+ (NSArray<NSNumber*>*)tabPanelIDs;

// The page's tiles, in the sidebar's order: every item it offers, the tab bar's aside.
+ (NSArray<NSNumber*>*)panelsForPage;

// Around each update of the sidebar: the panels Twitter names while it rebuilds are the ones it
// keeps, so a hidden item must not be named and a shown one must.
+ (void)beginBuildOfContent:(id)content;
+ (void)noteBuiltPanel:(NSInteger)panelID;
+ (void)endBuildOfContent:(id)content;

@end

// The open session's sidebar rebuilt with the items as they stand (FeatureSwitches.x).
FOUNDATION_EXPORT void PFBDashRefresh(void);
// The drawer's own list of the tab bar's panels, read from its Swift array; nil when unreadable.
FOUNDATION_EXPORT NSArray<NSNumber*>* _Nullable PFBDashSnapshot(id content);

NS_ASSUME_NONNULL_END
