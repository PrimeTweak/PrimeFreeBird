// Resource bundle and localized strings, Twitter's own with a bundled fallback.

#import <Foundation/Foundation.h>
@interface PFBBundle : NSObject
+ (instancetype)sharedBundle;
// A PrimeFreeBird string in the app's language, else in English, else the key itself.
- (NSString*)localizedStringForKey:(NSString*)key;
// Twitter's own text for one of its keys, else the bundled copy of it, else the key.
- (NSString*)localizedTwitterStringForKey:(NSString*)key;
// "1 day left", or the count in "%ld days left".
- (NSString*)daysLeftText:(NSInteger)days;
- (NSURL*)pathForFile:(NSString*)fileName;

@property (nonatomic, strong, readonly) NSBundle* mainBundle;
// The English strings alone, for the keys a partial translation lacks.
@property (nonatomic, strong, readonly) NSBundle* englishBundle;

@end
