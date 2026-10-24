// Registry and helpers of the custom tab bar: panel ids, images, order.

#import <UIKit/UIKit.h>

@class T1TabView;

NS_ASSUME_NONNULL_BEGIN

// pageID of the Home tab, which is always kept visible and pinned first.
extern NSString* const PFBCustomTabBarHomePageID;

// Registry keys for a captured tab's metadata.
extern NSString* const PFBTabPageKey; // scribePage identifier
extern NSString* const
    PFBTabTitleKey;                      // display title (already localized by the app)
extern NSString* const PFBTabImageKey;   // vector image name
extern NSString* const PFBTabPanelIDKey; // T1 panel ID (NSNumber)

@interface PFBCustomTabBarUtility : NSObject

// Records the tabs the app builds so the editor can display real titles and
// icons without hardcoding them. Called from the tab bar hook with the live tab
// views.
+ (void)recordTabViews:(NSArray*)tabViews;

// The glyph name of a tab: its imageName, or for a tab drawn from an avatar (Profile),
// the glyph Twitter's own customization screen gives its panel. Nil when there is none.
+ (nullable NSString*)imageNameForTabView:(T1TabView*)tabView;

// Every tab recorded so far, kept across launches and never pruned, in the
// order first seen.
+ (NSArray<NSDictionary*>*)availableTabs;

// Metadata for a single tab, or nil if it has never been seen.
+ (nullable NSDictionary*)metadataForPage:(NSString*)pageID;

// The visible tabs in the user's chosen order (Home first). Returns nil when
// the user has never customized the bar, so callers can fall back to the
// default.
+ (nullable NSArray<NSString*>*)visiblePageIDsInOrder;

// Persists the editor's selection; every other tab is hidden.
+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible;

// Clears the user's selection, reverting to the default layout.
+ (void)resetSelection;

// The tabs shown until the user customizes the bar: Home, Search, Notifications
// and Chats. Everything else the app offers is available in the editor but
// hidden.
+ (NSArray<NSString*>*)defaultVisiblePageIDs;

@end

NS_ASSUME_NONNULL_END
