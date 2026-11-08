// Media download and save helpers, cache sweep, menu font, branding test and settings screen.

#import "Support/PFBManager.h"
#import "Support/TwitterChirpFont.h"
#import "Settings/PFBModernSettingsViewController.h"

@implementation PFBManager
+ (void)cleanCache {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager* files = [NSFileManager defaultManager];
        for (NSURL* item in [files contentsOfDirectoryAtURL:[PFBManager temporaryFolder]
                                 includingPropertiesForKeys:nil
                                                    options:0
                                                      error:nil]) {
            [files removeItemAtURL:item error:nil];
        }
    });
}
+ (NSURL*)temporaryFolder {
    NSURL* folder = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"PFB" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    return folder;
}
+ (id)sharedFontGroup {
    Class groupClass = objc_getClass("TFNUIDefaultFontGroup");
    return [groupClass respondsToSelector:@selector(sharedFontGroup)] ? [groupClass sharedFontGroup] : nil;
}
+ (UIFont*)menuTitleFont {
    return PFBFontGroupFont(@selector(headline2BoldFont), [UIFont boldSystemFontOfSize:17.0]);
}
+ (NSString*)getVideoQuality:(NSString*)url {
    NSMutableArray* q = [NSMutableArray new];
    NSArray* splits = [url componentsSeparatedByString:@"/"];
    for (NSUInteger i = 0; i < [splits count]; i++) {
        NSString* item = [splits objectAtIndex:i];
        NSArray* dir = [item componentsSeparatedByString:@"x"];
        for (NSUInteger k = 0; k < [dir count]; k++) {
            NSString* item2 = [dir objectAtIndex:k];
            if (!(item2.length == 0)) {
                if ([PFBManager doesContainDigitsOnly:item2]) {
                    if (!(item2.integerValue > 10000)) {
                        if (!(q.count == 2)) {
                            [q addObject:item2];
                        }
                    }
                }
            }
        }
    }
    if (q.count == 0) {
        return @"GIF";
    }
    return [NSString stringWithFormat:@"%@x%@", q.firstObject, q.lastObject];
}
+ (void)saveToPhotos:(NSURL*)url asGIF:(BOOL)gif completion:(void (^)(BOOL saved))completion {
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            if (gif) {
                [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
            } else {
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
            }
        }
        completionHandler:^(BOOL success, __unused NSError* error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success);
            });
        }];
}
+ (void)showSaveVC:(NSURL*)url {
    [self showSaveVCForItems:@[url]];
}
+ (void)showSaveVCForItems:(NSArray<NSURL*>*)urls {
    UIActivityViewController* acVC =
        [[UIActivityViewController alloc] initWithActivityItems:urls
                                          applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topMostController().view;
        acVC.popoverPresentationController.sourceRect =
            CGRectMake(topMostController().view.bounds.size.width / 2.0,
                       topMostController().view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topMostController() presentViewController:acVC animated:true completion:nil];
}

+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL {
    MediaInformationSession* mediaInformationSession =
        [FFprobeKit getMediaInformation:mediaURL.absoluteString];
    MediaInformation* mediaInformation =
        [mediaInformationSession getMediaInformation];
    return mediaInformation;
}
+ (NSString*)getDownloadingPercent:(float)progress {
    NSNumberFormatter* numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
    return [numberFormatter stringFromNumber:[NSNumber numberWithFloat:progress]];
}

+ (BOOL)isTwitterBranded {
    static BOOL branded = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        branded = [[[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"]
            isEqual:@"Twitter"];
    });
    return branded;
}

+ (UIViewController*)PFBSettingsWithAccount:(TFNTwitterAccount*)twAccount native:(BOOL)native {
    return [[PFBModernSettingsViewController alloc] initWithAccount:twAccount native:native];
}

// YES when the string holds nothing but decimal digits (an empty string too).
+ (BOOL)doesContainDigitsOnly:(NSString*)string {
    NSCharacterSet* nonDigits =
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

    BOOL containsDigitsOnly =
        [string rangeOfCharacterFromSet:nonDigits].location == NSNotFound;

    return containsDigitsOnly;
}

@end
