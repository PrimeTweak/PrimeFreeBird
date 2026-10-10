// The tweak's resource bundle and localized strings.

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
            // Sideloaded builds carry the bundle inside the app, found by name: the
            // folder must carry the product name, PFB_PRODUCT_NAME.bundle.
            bundlePath = [[NSBundle mainBundle] URLForResource:@PFB_PRODUCT_NAME
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

// Fetches one of Twitter's own strings, reusing the app's translations, from the tables
// that hold the borrowed keys. A key none of them has falls back to the tweak's copy,
// filed under TW_ so it can never collide with one of the tweak's own keys.
- (NSString*)localizedTwitterStringForKey:(NSString*)key {
    static NSArray<NSBundle*>* tables;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSBundle*>* found = [NSMutableArray array];
        for (NSString* name in @[
                 @"T1Strings_T1Strings.bundle", @"TwitterSharedStrings_TwitterSharedStrings.bundle",
                 @"ChatCore_ChatStrings.bundle", @"LiveActivities_LiveActivityStrings.bundle"
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
- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end
