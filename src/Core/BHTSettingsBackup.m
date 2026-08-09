//
//  BHTSettingsBackup.m
//  PrimeFreeBird
//

#import "Core/BHTSettingsBackup.h"
#import "Core/BHTSettings.h"

static NSString* const kNFBBackupFormat = @"PrimeFreeBird";
static const NSInteger kNFBBackupVersion = 1;

// Keys stored outside the registry: page-local picks, the colour and font
// state, and the muted-words store. The daily counter and the migration
// flags stay out — they describe this install, not the user's choices.
static NSArray<NSString*>* NFBBackupExtraKeys(void) {
    return @[
        @"enable_liquid_glass", @"dark_mode_style", @"profile_initial_tab",
        @"bh_custom_accent_hex", @"bh_custom_is_active",
        @"bhtwitter_font_1", @"bhtwitter_font_2",
        @"nfb_advs_lang",
        @"nfb_muted_words", @"nfb_muted_expiry", @"nfb_muted_whole_words",
        @"nfb_muted_in_conversations", @"nfb_muted_skip_following",
        @"nfb_muted_include_reposts",
        @"bh_tabs_visible", @"bh_tab_registry",
    ];
}

static NSArray<NSString*>* NFBBackupKeys(void) {
    NSMutableArray<NSString*>* keys = [[BHTSettings allOptionKeys] mutableCopy];
    for (NSString* key in NFBBackupExtraKeys()) {
        if (![keys containsObject:key]) {
            [keys addObject:key];
        }
    }
    return keys;
}

// Only plist types that survive a JSON round-trip unchanged.
static BOOL NFBValueIsPortable(id value) {
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]]) {
        return YES;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        for (id element in (NSArray*)value) {
            if (!NFBValueIsPortable(element)) {
                return NO;
            }
        }
        return YES;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary* map = (NSDictionary*)value;
        for (id mapKey in map) {
            if (![mapKey isKindOfClass:[NSString class]] ||
                !NFBValueIsPortable(map[mapKey])) {
                return NO;
            }
        }
        return YES;
    }
    return NO;
}

@implementation BHTSettingsBackup

+ (NSData*)exportData {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* settings = [NSMutableDictionary dictionary];
    for (NSString* key in NFBBackupKeys()) {
        id value = [defaults objectForKey:key];
        if (value && NFBValueIsPortable(value)) {
            settings[key] = value;
        }
    }
    NSDictionary* payload = @{
        @"format": kNFBBackupFormat,
        @"version": @(kNFBBackupVersion),
        @"settings": settings,
    };
    return [NSJSONSerialization dataWithJSONObject:payload
                                           options:NSJSONWritingPrettyPrinted |
                                                   NSJSONWritingSortedKeys
                                             error:NULL];
}

+ (NSInteger)importData:(NSData*)data {
    if (!data) {
        return -1;
    }
    id payload = [NSJSONSerialization JSONObjectWithData:data
                                                 options:0
                                                   error:NULL];
    if (![payload isKindOfClass:[NSDictionary class]] ||
        ![kNFBBackupFormat isEqualToString:payload[@"format"]] ||
        [payload[@"version"] integerValue] > kNFBBackupVersion) {
        return -1;
    }
    NSDictionary* settings = payload[@"settings"];
    if (![settings isKindOfClass:[NSDictionary class]]) {
        return -1;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSSet<NSString*>* known = [NSSet setWithArray:NFBBackupKeys()];
    NSInteger applied = 0;
    for (NSString* key in settings) {
        id value = settings[key];
        if ([known containsObject:key] && NFBValueIsPortable(value)) {
            [defaults setObject:value forKey:key];
            applied++;
        }
    }
    return applied;
}

@end
