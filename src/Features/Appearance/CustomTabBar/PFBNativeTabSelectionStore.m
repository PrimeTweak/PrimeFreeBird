// The native tab editor's saved selections; see PFBNativeTabSelectionStore.h.

#import "Features/Appearance/CustomTabBar/PFBNativeTabSelectionStore.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString* const PFBNativeTabSelectionsKey = @"pfb_native_tab_selections";

@implementation PFBNativeTabSelectionStore

+ (instancetype)sharedStore {
    static PFBNativeTabSelectionStore* store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      store = [[self alloc] init];
    });
    return store;
}

+ (BOOL)isNativeTabSettingsKey:(id)key {
    return [key isKindOfClass:[NSString class]] && [key hasPrefix:@"app-navigation-"] &&
           [key hasSuffix:@"-tab_identifiers"];
}

- (NSData*)dataForAccountID:(NSString*)accountID settingsKey:(NSString*)key {
    if (![accountID isKindOfClass:[NSString class]] || !accountID.length || ![self.class isNativeTabSettingsKey:key]) {
        return nil;
    }
    @synchronized(self) {
        id selections = [[NSUserDefaults standardUserDefaults] objectForKey:PFBNativeTabSelectionsKey];
        id account = [selections isKindOfClass:[NSDictionary class]] ? selections[accountID] : nil;
        id data = [account isKindOfClass:[NSDictionary class]] ? account[key] : nil;
        return [data isKindOfClass:[NSData class]] ? data : nil;
    }
}

- (BOOL)hasSelectionForAccountID:(NSString*)accountID {
    if (![accountID isKindOfClass:[NSString class]] || !accountID.length) {
        return NO;
    }
    @synchronized(self) {
        id selections = [[NSUserDefaults standardUserDefaults] objectForKey:PFBNativeTabSelectionsKey];
        id account = [selections isKindOfClass:[NSDictionary class]] ? selections[accountID] : nil;
        return [account isKindOfClass:[NSDictionary class]] && [(NSDictionary*)account count] > 0;
    }
}

- (void)saveData:(NSData*)data forAccountID:(NSString*)accountID settingsKey:(NSString*)key {
    if (![accountID isKindOfClass:[NSString class]] || !accountID.length || ![self.class isNativeTabSettingsKey:key] ||
        (data && ![data isKindOfClass:[NSData class]])) {
        return;
    }
    @synchronized(self) {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        id saved = [defaults objectForKey:PFBNativeTabSelectionsKey];
        NSMutableDictionary* selections =
            [saved isKindOfClass:[NSDictionary class]] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
        id savedAccount = selections[accountID];
        NSMutableDictionary* account = [savedAccount isKindOfClass:[NSDictionary class]] ? [savedAccount mutableCopy]
                                                                                          : [NSMutableDictionary dictionary];
        if (data) {
            account[key] = [data copy];
        } else {
            [account removeObjectForKey:key];
        }
        if (account.count) {
            selections[accountID] = account;
        } else {
            [selections removeObjectForKey:accountID];
        }
        [defaults setObject:selections forKey:PFBNativeTabSelectionsKey];
    }
}

- (void)removeAllSelections {
    @synchronized(self) {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        id saved = [defaults objectForKey:PFBNativeTabSelectionsKey];
        Class storeClass = objc_getClass("TFSAccountUserDefaults");
        SEL shared = @selector(sharedAccountUserDefaultsForAccountID:);
        if ([saved isKindOfClass:[NSDictionary class]] && [storeClass respondsToSelector:shared]) {
            for (id accountID in (NSDictionary*)saved) {
                id keys = ((NSDictionary*)saved)[accountID];
                if (![accountID isKindOfClass:[NSString class]] || ![keys isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                // Twitter's account store removes a key set to nil.
                id store = ((id (*)(id, SEL, id))objc_msgSend)(storeClass, shared, accountID);
                if (![store respondsToSelector:@selector(setObject:forKey:)]) {
                    continue;
                }
                for (id key in (NSDictionary*)keys) {
                    if ([self.class isNativeTabSettingsKey:key]) {
                        ((void (*)(id, SEL, id, id))objc_msgSend)(store, @selector(setObject:forKey:), nil, key);
                    }
                }
            }
        }
        [defaults removeObjectForKey:PFBNativeTabSelectionsKey];
    }
}

@end
