//
//  BHTSettingsBackup.h
//  PrimeFreeBird
//

#import <Foundation/Foundation.h>

// Serialises the tweak's state to a JSON file and restores it: every registry
// option, the page-local picks, the accent, the fonts, the muted words and the tab
// bar layout. Migration flags, counters and the web session are left out.
@interface BHTSettingsBackup : NSObject

// The JSON snapshot of the current state.
+ (NSData*)exportData;

// Applies a snapshot. Returns how many keys were restored, or -1 when the
// data is not a PrimeFreeBird backup. Unknown keys are ignored, so a file
// from a newer version degrades instead of failing.
+ (NSInteger)importData:(NSData*)data;

@end
