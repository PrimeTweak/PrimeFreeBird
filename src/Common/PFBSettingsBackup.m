// Export and import of the settings as a file.

#import "Common/PFBSettingsBackup.h"
#import "Common/PFBSettings.h"

static NSString* const kPFBBackupFormat = @"PrimeFreeBird";
static const NSInteger kPFBBackupVersion = 1;

// Keys stored outside the registry: page-local picks, color and font state, muted words,
// kept languages. Left out: the daily counter and migration flags, which describe this
// install, and the send sound's name, whose file the backup does not carry.
static NSArray<NSString*>* PFBBackupExtraKeys(void) {
    return @[
        @"enable_liquid_glass", @"dark_mode_style", @"profile_initial_tab",
        @"pfb_custom_accent_hex", @"pfb_custom_is_active",
        @"pfb_color_theme_selectedColor", @"pfb_color_reset_done",
        @"pfb_font_1", @"pfb_font_2",
        @"pfb_advs_lang",
        @"pfb_muted_words", @"pfb_muted_expiry", @"pfb_muted_whole_words",
        @"pfb_muted_in_conversations", @"pfb_muted_skip_following",
        @"pfb_muted_include_reposts", @"pfb_filter_languages",
        @"pfb_tabs_visible", @"pfb_tab_registry",
    ];
}

static NSArray<NSString*>* PFBBackupKeys(void) {
    NSMutableArray<NSString*>* keys = [[PFBSettings allOptionKeys] mutableCopy];
    for (NSString* key in PFBBackupExtraKeys()) {
        if (![keys containsObject:key]) {
            [keys addObject:key];
        }
    }
    return keys;
}

// Only plist types that survive a JSON round-trip unchanged.
static BOOL PFBValueIsPortable(id value) {
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]]) {
        return YES;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        for (id element in (NSArray*)value) {
            if (!PFBValueIsPortable(element)) {
                return NO;
            }
        }
        return YES;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary* map = (NSDictionary*)value;
        for (id mapKey in map) {
            if (![mapKey isKindOfClass:[NSString class]] ||
                !PFBValueIsPortable(map[mapKey])) {
                return NO;
            }
        }
        return YES;
    }
    return NO;
}

@implementation PFBSettingsBackup

+ (NSData*)exportData {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* settings = [NSMutableDictionary dictionary];
    for (NSString* key in PFBBackupKeys()) {
        id value = [defaults objectForKey:key];
        if (value && PFBValueIsPortable(value)) {
            settings[key] = value;
        }
    }
    NSDictionary* payload = @{
        @"format": kPFBBackupFormat,
        @"version": @(kPFBBackupVersion),
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
        ![kPFBBackupFormat isEqualToString:payload[@"format"]] ||
        [payload[@"version"] integerValue] > kPFBBackupVersion) {
        return -1;
    }
    NSDictionary* settings = payload[@"settings"];
    if (![settings isKindOfClass:[NSDictionary class]]) {
        return -1;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSSet<NSString*>* known = [NSSet setWithArray:PFBBackupKeys()];
    NSInteger applied = 0;
    for (NSString* storedKey in settings) {
        // A backup saved before the PFB prefix names its keys the old way.
        NSString* key = PFBCurrentKeyForLegacyKey(storedKey) ?: storedKey;
        id value = PFBValueWithCurrentKeys(settings[storedKey]);
        if ([known containsObject:key] && PFBValueIsPortable(value)) {
            [defaults setObject:value forKey:key];
            applied++;
        }
    }
    return applied;
}

@end
