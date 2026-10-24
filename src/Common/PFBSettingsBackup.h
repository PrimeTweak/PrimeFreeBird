// Export and import of the settings as a file.

#import <Foundation/Foundation.h>

// Serializes the settings to JSON and restores them: every registry option, page-local
// picks, accent, fonts, muted words, kept languages and tab bar layout. Migration flags,
// counters and the web session are left out.
@interface PFBSettingsBackup : NSObject

// The JSON snapshot of the current state.
+ (NSData*)exportData;

// The settings a snapshot holds, or nil when the data is not a PrimeFreeBird backup or
// has a newer format version.
+ (NSDictionary*)settingsInData:(NSData*)data;

// Makes the stored settings exactly the snapshot's: each key it holds takes its value,
// every other one goes back to its default. Unknown keys are ignored.
+ (void)applySettings:(NSDictionary*)settings;

@end
