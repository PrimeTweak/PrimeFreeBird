// The tweak's resource bundle and localized strings, with a fallback for the
// app strings that newer builds no longer ship.

#import <Foundation/Foundation.h>
@interface BHTBundle : NSObject
+ (instancetype)sharedBundle;
- (NSString*)localizedStringForKey:(NSString*)key;
- (NSString*)localizedTwitterStringForKey:(NSString*)key;
- (NSURL*)pathForFile:(NSString*)fileName;

@property (nonatomic, strong, readonly) NSBundle* mainBundle;

@end
