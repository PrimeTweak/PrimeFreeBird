// The tweak's resource bundle and localized strings.

#import "Common/PFBBundle.h"

@interface PFBBundle ()
@property (nonatomic, strong) NSBundle* mainBundle;
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
            // Sideloaded builds carry the bundle inside the app, so it is
            // looked up by name — it must match the renamed bundle.
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
    }

    return self;
}

- (NSString*)localizedStringForKey:(NSString*)key {
    return [self.mainBundle localizedStringForKey:key value:key table:nil];
}

// Fetches one of Twitter's own strings, reusing the app's translations. When the
// app does not ship the key, the lookup returns the key itself and the tweak's own
// translation answers instead.
- (NSString*)localizedTwitterStringForKey:(NSString*)key {
    static NSBundle* twitterBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* path =
            [[NSBundle mainBundle] pathForResource:@"Localization_Localization"
                                            ofType:@"bundle"];
        twitterBundle = path ? [NSBundle bundleWithPath:path] : nil;
    });
    NSString* result =
        twitterBundle ? [twitterBundle localizedStringForKey:key value:key table:nil] : key;
    if (![result isEqualToString:key]) {
        return result;
    }
    // The app gave nothing back. Ours is keyed the same way, with a TW_ prefix
    // so a borrowed key can never collide with one of the tweak's own. A lookup
    // that misses returns the key it was given, so that case yields the plain key.
    NSString* prefixed = [NSString stringWithFormat:@"TW_%@", key];
    NSString* fallback = [self localizedStringForKey:prefixed];
    if (fallback.length == 0 || [fallback isEqualToString:prefixed]) {
        return key;
    }
    return fallback;
}
- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end
