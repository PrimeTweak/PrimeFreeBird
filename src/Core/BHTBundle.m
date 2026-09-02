//
//  BHTBundle.m
//  PrimeFreeBird
//
//  Created by BandarHelal on 07/08/2022.
//

#import "BHTBundle.h"

@interface BHTBundle ()
@property (nonatomic, strong) NSBundle* mainBundle;
@end

@implementation BHTBundle
+ (instancetype)sharedBundle {
    static BHTBundle* sharedBundle = nil;
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
            bundlePath = [[NSBundle mainBundle] URLForResource:@NFB_PRODUCT_NAME
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

// Fetches one of Twitter's own strings, reusing the app's translations for
// every language. These flow through the terminology rename hook like any app
// string.
// Twitter 12.21 dropped Localization_Localization.bundle, and with it every key
// borrowed here: the lookup then returns the key itself and the reader sees
// CANCEL_ACTION_LABEL on a button. Measured against both IPAs - 339 .strings
// files in 12.15, 136 in 12.21, and the bundle gone. When the app no longer
// answers, our own translations do.
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
    // so a borrowed key can never collide with one of our own.
    NSString* fallback = [self
        localizedStringForKey:[NSString stringWithFormat:@"TW_%@", key]];
    return fallback.length ? fallback : key;
}
- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end
