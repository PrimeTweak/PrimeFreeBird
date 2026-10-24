// Settings registry: every page's rows and defaults, and the migrations of legacy keys.

#import <Foundation/Foundation.h>

// The settings registry: each page's rows (headers, toggles, buttons) with their
// defaults, and the page titles. A key set from a picker, a menu, a pill or the
// Explore bar has no row of its own.
@interface PFBSettings : NSObject

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey;
+ (NSString*)titleKeyForPage:(NSString*)pageKey;
+ (NSString*)subtitleKeyForPage:(NSString*)pageKey;

+ (BOOL)boolForKey:(NSString*)key;
+ (NSInteger)integerForKey:(NSString*)key;

// Every option key the registry declares, across all pages, with the keys a row
// carries beside its own (pillKey, tabKeys).
+ (NSArray<NSString*>*)allOptionKeys;

@end

// The current name of a key stored before the PFB prefix, or nil for any other key.
FOUNDATION_EXPORT NSString* PFBCurrentKeyForLegacyKey(NSString* key);
// The value with its dictionary keys renamed the same way.
FOUNDATION_EXPORT id PFBValueWithCurrentKeys(id value);
// The Explore tab keys, in the bar's order (For You, Trending, News, Sports, Entertainment).
FOUNDATION_EXPORT NSArray<NSString*>* PFBExploreTabKeys(void);
