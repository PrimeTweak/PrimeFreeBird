// Settings registry: every page's rows and defaults, and the migrations of legacy keys.

#import <Foundation/Foundation.h>

// The settings registry: each page's rows (headers, toggles, buttons) with their
// defaults, and the page titles. Keys set from a picker, a pill, the Explore bar or
// the profile tab menu have no row of their own.
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
// The Explore tab keys, in the bar's order (Explore, Trending, News, Sports, Entertainment).
FOUNDATION_EXPORT NSArray<NSString*>* PFBExploreTabKeys(void);
