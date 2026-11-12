// The sidebar's items as Twitter's panels: their names and glyphs, the ones Twitter shows there,
// and the ones hidden from the Sidebar page.

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

// Hidden from the sidebar on the page; Grok by its own option.
+ (BOOL)isHidden:(NSInteger)panelID;
+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden;
// The panels kept out of the sidebar, Grok's shortcut aside.
+ (NSArray<NSNumber*>*)hiddenPanelIDs;
// Every item back in the sidebar.
+ (void)resetToDefault;

// Twitter's sidebar measured as Twitter shows it with nothing hidden; NO when there is no sidebar
// to rebuild yet.
+ (BOOL)measureNative;
// The panels of the last measure, in the sidebar's order: the page's tiles.
+ (NSArray<NSNumber*>*)panelsForPage;
// The panels only the unlock's gates would add to the sidebar, kept out with the hidden ones;
// none before a measure.
+ (NSArray<NSNumber*>*)unlockedPanelIDs;

// Around each update of the sidebar: the panels Twitter names while it rebuilds are the ones it
// keeps, and the drawer's list must hold every hidden panel and every unlocked one.
+ (void)beginBuildOfContent:(id)content;
+ (void)noteBuiltPanel:(NSInteger)panelID;
+ (void)endBuildOfContent:(id)content;

@end

typedef NS_ENUM(NSInteger, PFBDashMeasurement) {
    PFBDashMeasurementNoSidebar,
    PFBDashMeasurementNotRebuilt,
    PFBDashMeasurementDone,
};

// The open session's sidebar rebuilt with the items as they stand (FeatureSwitches.x).
FOUNDATION_EXPORT void PFBDashRefresh(void);
// The sidebar rebuilt once with nothing hidden, then as it stands; in between, while Twitter's
// gates still answer, the tab bar's panels and the ones Twitter named (FeatureSwitches.x).
FOUNDATION_EXPORT PFBDashMeasurement PFBDashMeasure(void (^measured)(NSArray<NSNumber*>* tabs,
                                                                     NSArray<NSNumber*>* named));
// The drawer's own list of the tab bar's panels, read from its Swift array; nil when unreadable.
FOUNDATION_EXPORT NSArray<NSNumber*>* _Nullable PFBDashSnapshot(id content);

NS_ASSUME_NONNULL_END
