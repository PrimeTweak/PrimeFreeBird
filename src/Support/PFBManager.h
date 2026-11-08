// Media download and save helpers, cache sweep, menu font, branding test and settings screen.

#import "Support/TWHeaders.h"

@interface PFBManager : NSObject
// Empties the tweak's folder in tmp/, off the main thread.
+ (void)cleanCache;
// The tweak's folder in tmp/, created when asked for. Every file the tweak writes on its way
// to a share sheet, to Photos or to its final place goes there.
+ (NSURL*)temporaryFolder;
+ (NSString*)getVideoQuality:(NSString*)url;
+ (id)sharedFontGroup;
+ (UIFont*)menuTitleFont;
// The PrimeFreeBird settings; native gives them the look of Twitter's new settings.
+ (UIViewController*)PFBSettingsWithAccount:(TFNTwitterAccount*)twAccount native:(BOOL)native;
+ (void)showSaveVC:(NSURL*)url;
+ (void)showSaveVCForItems:(NSArray<NSURL*>*)urls;
// Adds a video, or a GIF as an image, to Photos. The completion runs on the main thread
// and says whether Photos took the file.
+ (void)saveToPhotos:(NSURL*)url asGIF:(BOOL)gif completion:(void (^)(BOOL saved))completion;
+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL;
+ (NSString*)getDownloadingPercent:(float)progress;

+ (BOOL)isTwitterBranded;

@end
