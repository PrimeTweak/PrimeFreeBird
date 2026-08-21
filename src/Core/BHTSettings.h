//
//  BHTSettings.h
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import <Foundation/Foundation.h>

// Single source of truth for every user setting: per-page toggle lists,
// page titles and the default value used when a key was never toggled.
@interface BHTSettings : NSObject

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey;
+ (NSString*)titleKeyForPage:(NSString*)pageKey;
+ (NSString*)subtitleKeyForPage:(NSString*)pageKey;
+ (NSDictionary*)settingForKey:(NSString*)key;

// The declared default for a key: its registry row when it has one, otherwise
// the table of keys that are set from a page of their own.
+ (id)declaredDefaultForKey:(NSString*)key;
+ (BOOL)boolForKey:(NSString*)key;
+ (NSInteger)integerForKey:(NSString*)key;

// Every option key the registry declares, across all pages. Rows that only
// identify a button are included; they simply never carry a stored value.
+ (NSArray<NSString*>*)allOptionKeys;

@end
