// Resource bundle and localized strings, Twitter's own with a bundled fallback.

#import "Common/PFBBundle.h"

@interface PFBBundle ()
@property (nonatomic, strong) NSBundle* mainBundle;
@property (nonatomic, strong) NSBundle* englishBundle;
@end

@implementation PFBBundle
+ (instancetype)sharedBundle {
    static PFBBundle* sharedBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* bundlePath = nil;
        if ([fileManager
                fileExistsAtPath:
                    @"/Library/Application Support/PFB/PrimeFreeBird.bundle"]) {
            bundlePath = [NSURL
                fileURLWithPath:@"/Library/Application Support/PFB/PrimeFreeBird.bundle"];
        } else if ([fileManager fileExistsAtPath:@"/var/jb/Library/Application "
                                                 @"Support/PFB/PrimeFreeBird.bundle"]) {
            bundlePath = [NSURL
                fileURLWithPath:
                    @"/var/jb/Library/Application Support/PFB/PrimeFreeBird.bundle"];
        } else {
            // Sideloaded builds carry the bundle at the root of the app, under the
            // same name as the jailbreak paths above.
            bundlePath = [[NSBundle mainBundle] URLForResource:@"PrimeFreeBird"
                                                 withExtension:@"bundle"];
        }

        sharedBundle = [[self alloc] initWithBundlePath:bundlePath];
    });
    return sharedBundle;
}
- (instancetype)initWithBundlePath:(NSURL*)bundlePath {
    if (self = [super init]) {
        self.mainBundle = [NSBundle bundleWithPath:[bundlePath path]];
        NSString* english = [self.mainBundle pathForResource:@"en" ofType:@"lproj"];
        self.englishBundle = english ? [NSBundle bundleWithPath:english] : nil;
    }

    return self;
}

// A miss returns the value passed in, so a marker no string uses tells a miss apart.
static NSString* const kPFBMissingString = @"<PFB missing string>";

- (NSString*)localizedStringForKey:(NSString*)key {
    NSString* text = [self.mainBundle localizedStringForKey:key value:kPFBMissingString table:nil];
    if (!text || [text isEqualToString:kPFBMissingString]) {
        text = [self.englishBundle localizedStringForKey:key value:kPFBMissingString table:nil];
    }
    return text && ![text isEqualToString:kPFBMissingString] ? text : key;
}

// Fetches one of Twitter's own strings from the tables that hold the borrowed keys. A key
// none of them has falls back to the bundled copy, filed under TW_ so it never collides
// with a PrimeFreeBird key.
- (NSString*)localizedTwitterStringForKey:(NSString*)key {
    static NSArray<NSBundle*>* tables;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSBundle*>* found = [NSMutableArray array];
        for (NSString* name in @[
                 @"T1Strings_T1Strings.bundle", @"TwitterSharedStrings_TwitterSharedStrings.bundle",
                 @"ChatCore_ChatStrings.bundle", @"LiveActivities_LiveActivityStrings.bundle",
                 @"XSettings_XSettingsStrings.bundle"
             ]) {
            NSBundle* table =
                [NSBundle bundleWithPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:name]];
            if (table) {
                [found addObject:table];
            }
        }
        tables = found.copy;
    });
    for (NSBundle* table in tables) {
        NSString* text = [table localizedStringForKey:key value:kPFBMissingString table:nil];
        if (text && ![text isEqualToString:kPFBMissingString]) {
            return text;
        }
    }
    NSString* prefixed = [@"TW_" stringByAppendingString:key];
    NSString* fallback = [self localizedStringForKey:prefixed];
    return fallback.length == 0 || [fallback isEqualToString:prefixed] ? key : fallback;
}
- (NSString*)daysLeftText:(NSInteger)days {
    if (days == 1) {
        return [self localizedStringForKey:@"DAYS_LEFT_ONE"];
    }
    return [NSString stringWithFormat:[self localizedStringForKey:@"DAYS_LEFT_FORMAT"], (long)days];
}

- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end
