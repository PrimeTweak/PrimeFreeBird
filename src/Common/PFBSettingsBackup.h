// Export and import of the settings as a file.

#import <Foundation/Foundation.h>

// Serializes PrimeFreeBird's state to JSON and restores it: every registry option, page-local
// picks, accent, fonts, muted words, kept languages and tab bar layout. Migration flags,
// counters and the web session are left out.
@interface PFBSettingsBackup : NSObject

// The JSON snapshot of the current state.
+ (NSData*)exportData;

// Applies a snapshot. Returns how many keys were restored, or -1 when the data
// is not a PrimeFreeBird backup or has a newer format version. Unknown keys are
// ignored.
+ (NSInteger)importData:(NSData*)data;

@end
