// Media download and save helpers, cache sweep, menu font, branding test and settings screen.

#import "Support/TWHeaders.h"

@interface PFBManager : NSObject
+ (void)cleanCache;
+ (NSString*)getVideoQuality:(NSString*)url;
+ (id)sharedFontGroup;
+ (UIFont*)menuTitleFont;
+ (UIViewController*)PFBSettingsWithAccount:(TFNTwitterAccount*)twAccount;
+ (void)showSaveVC:(NSURL*)url;
+ (void)showSaveVCForItems:(NSArray<NSURL*>*)urls;
// Adds a video, or a GIF as an image, to Photos. The completion runs on the main thread
// and says whether Photos took the file.
+ (void)saveToPhotos:(NSURL*)url asGIF:(BOOL)gif completion:(void (^)(BOOL saved))completion;
+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL;
+ (NSString*)getDownloadingPercent:(float)progress;

+ (BOOL)isTwitterBranded;

@end
