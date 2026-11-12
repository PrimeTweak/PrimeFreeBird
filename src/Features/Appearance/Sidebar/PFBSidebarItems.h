// The sidebar's items as Twitter's panels: their names and glyphs, the ones hidden from the
// Sidebar page, and what the open sidebar was last read showing.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Posted when an item is hidden or shown, so the page and the sidebar follow.
FOUNDATION_EXPORT NSNotificationName const PFBSidebarItemsDidChangeNotification;

// The panel Grok's sidebar shortcut opens, hidden by its own option.
static const NSInteger PFBSidebarGrokPanel = 14;

@interface PFBSidebarItems : NSObject

// Every panel the sidebar can list, in its order.
+ (NSArray<NSNumber*>*)catalog;
// Twitter's name and glyph for a panel; nil when Twitter has none.
+ (nullable NSString*)nameForPanel:(NSInteger)panelID;
+ (nullable NSString*)glyphForPanel:(NSInteger)panelID;

+ (BOOL)isHidden:(NSInteger)panelID;
+ (void)setPanel:(NSInteger)panelID hidden:(BOOL)hidden;
// The panels hidden from the page, Grok's shortcut aside.
+ (NSArray<NSNumber*>*)hiddenPanelIDs;
// Every item shown again, and Grok's shortcut back to its default.
+ (void)resetToDefault;

// Twitter's own tab bar panels, as the sidebar last asked for them.
+ (void)recordTabPanelIDs:(NSArray*)panelIDs;
+ (NSArray<NSNumber*>*)tabPanelIDs;

// The page's tiles: what the sidebar was seen showing and what is hidden from it, or the
// panels it can list beside the tab bar until it has been read; tab bar panels apart.
+ (NSArray<NSNumber*>*)panelsForPage;

// Reads the open sidebar's rows: what it shows, and whether a hidden item still shows.
+ (void)readOpenSidebar;
// The last reading: its labels, the panels they name and where they were read.
+ (NSDictionary*)lastReading;

@end

// The open session's sidebar rebuilt with the items as they stand (FeatureSwitches.x).
FOUNDATION_EXPORT void PFBDashRefresh(void);

NS_ASSUME_NONNULL_END
