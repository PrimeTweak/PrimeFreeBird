// The selection saved by Twitter's own tab editor, kept per account in its encoded form: Twitter
// clears its copy at launch for an account without the subscription, so the copy kept here is
// handed back whenever Twitter reads it.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PFBNativeTabSelectionStore : NSObject

+ (instancetype)sharedStore;

// Whether a key of Twitter's account store holds a tab selection.
+ (BOOL)isNativeTabSettingsKey:(id)key;

- (nullable NSData*)dataForAccountID:(NSString*)accountID settingsKey:(NSString*)key;

// Whether a selection is kept for the account.
- (BOOL)hasSelectionForAccountID:(nullable NSString*)accountID;

// nil is Twitter's own save of its default layout, and removes the kept copy.
- (void)saveData:(nullable NSData*)data forAccountID:(NSString*)accountID settingsKey:(NSString*)key;

// Drops every kept selection and Twitter's own copy of each, as on a new install.
- (void)removeAllSelections;

@end

NS_ASSUME_NONNULL_END
