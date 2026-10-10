// The tweak's resource bundle and localized strings, with a fallback for the
// app strings that newer builds no longer ship.

#import <Foundation/Foundation.h>
@interface PFBBundle : NSObject
+ (instancetype)sharedBundle;
// The tweak's text in the app's language, else in English, else the key itself.
- (NSString*)localizedStringForKey:(NSString*)key;
// Twitter's own text for one of its keys, else the tweak's copy of it, else the key.
- (NSString*)localizedTwitterStringForKey:(NSString*)key;
- (NSURL*)pathForFile:(NSString*)fileName;

@property (nonatomic, strong, readonly) NSBundle* mainBundle;
// The English strings alone, for the keys a partial translation lacks.
@property (nonatomic, strong, readonly) NSBundle* englishBundle;

@end
