//
//  BHTSettingsBackup.h
//  PrimeFreeBird
//

#import <Foundation/Foundation.h>

// Serialises the tweak's state to a JSON file and restores it. Covered: every
// registry option, the page-local picks (interface style, dark shade, profile
// tab), the custom accent, the two fonts, the advanced-search language, the
// muted words with their expirations, and the custom tab bar layout. Left out
// on purpose: internal migration flags, the daily muted counter, and the web
// session — authentication cookies do not belong in a shareable file.
@interface BHTSettingsBackup : NSObject

// The JSON snapshot of the current state.
+ (NSData*)exportData;

// Applies a snapshot. Returns how many keys were restored, or -1 when the
// data is not a PrimeFreeBird backup. Unknown keys are ignored, so a file
// from a newer version degrades instead of failing.
+ (NSInteger)importData:(NSData*)data;

@end
