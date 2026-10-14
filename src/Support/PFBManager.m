// Media download and save helpers, cache sweep, menu font, branding test and settings screen.

#import "Support/PFBManager.h"
#import "Settings/PFBModernSettingsViewController.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"
#import <QuartzCore/QuartzCore.h>

// Probe (10a#F026, 05#F020, 08#F037): what the launch sweep removes, how long it takes on the
// main thread with the probe's own reads left out, and what tmp still holds; once per build.
static CFTimeInterval gPFBProbeSweepOverhead;

// Probe: a file's name, a UUID name shortened to "UUID", any other one cut at 32 characters.
static NSString* PFBProbeFileLabel(NSURL* file) {
    NSString* name = file.lastPathComponent;
    if ([[NSUUID alloc] initWithUUIDString:name.stringByDeletingPathExtension]) {
        return name.pathExtension.length ? [@"UUID." stringByAppendingString:name.pathExtension] : @"UUID";
    }
    return name.length > 32 ? [[name substringToIndex:32] stringByAppendingString:@"\u2026"] : name;
}

static NSString* PFBProbeSize(unsigned long long bytes) {
    if (bytes >= 1048576) {
        return [NSString stringWithFormat:@"%.1f MB", (double)bytes / 1048576.0];
    }
    if (bytes >= 1024) {
        return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%llu B", bytes];
}

static NSMutableArray<NSString*>* PFBProbeSweepBegin(void) {
    if (!PFBProbeWants(@"10a#F026 launch sweep")) {
        return nil;
    }
    gPFBProbeSweepOverhead = 0;
    return [NSMutableArray array];
}

// Probe: an item about to be removed, with its size, the time spent reading it set aside.
static void PFBProbeSweepRemoving(NSMutableArray<NSString*>* removed, NSURL* file, NSString* place) {
    if (!removed) {
        return;
    }
    CFTimeInterval start = CACurrentMediaTime();
    NSNumber* size = nil;
    [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    [removed addObject:[NSString stringWithFormat:@"%@ %@ %@", place, PFBProbeFileLabel(file),
                                                  [file hasDirectoryPath] ? @"(empty folder)"
                                                                          : PFBProbeSize(size.unsignedLongLongValue)]];
    gPFBProbeSweepOverhead += CACurrentMediaTime() - start;
}

// Probe: the sweep's line, with what tmp still holds read in the background.
static void PFBProbeSweepEnd(NSMutableArray<NSString*>* removed, CFTimeInterval start) {
    if (!removed) {
        return;
    }
    double took = (CACurrentMediaTime() - start - gPFBProbeSweepOverhead) * 1000.0;
    NSArray<NSString*>* gone = [removed copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
      NSFileManager* files = [NSFileManager defaultManager];
      NSArray<NSURL*>* left = [files contentsOfDirectoryAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]
                                   includingPropertiesForKeys:@[ NSURLFileSizeKey, NSURLIsDirectoryKey ]
                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        error:nil];
      NSArray<NSString*>* kinds = @[ @"gif", @"png", @"m4a", @"caf", @"json" ];
      unsigned long long bytes[6] = {0};
      NSUInteger counts[6] = {0};
      NSUInteger folders = 0;
      NSUInteger walked = 0;
      unsigned long long folderBytes = 0;
      NSMutableArray<NSDictionary*>* loose = [NSMutableArray array];
      for (NSURL* item in left) {
          NSNumber* folder = nil;
          NSNumber* size = nil;
          [item getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];
          if (folder.boolValue) {
              folders++;
              for (NSURL* inner in [files enumeratorAtURL:item includingPropertiesForKeys:@[ NSURLFileSizeKey ]
                                                  options:0
                                             errorHandler:nil]) {
                  if (++walked > 5000) {
                      break;
                  }
                  NSNumber* innerSize = nil;
                  [inner getResourceValue:&innerSize forKey:NSURLFileSizeKey error:nil];
                  folderBytes += innerSize.unsignedLongLongValue;
              }
              continue;
          }
          [item getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
          NSUInteger kind = [kinds indexOfObject:item.pathExtension.lowercaseString];
          kind = kind == NSNotFound ? kinds.count : kind;
          counts[kind]++;
          bytes[kind] += size.unsignedLongLongValue;
          [loose addObject:@{@"name": PFBProbeFileLabel(item), @"size": size ?: @0}];
      }
      NSMutableArray<NSString*>* perKind = [NSMutableArray array];
      for (NSUInteger kind = 0; kind <= kinds.count; kind++) {
          [perKind addObject:[NSString stringWithFormat:@".%@ %lu (%@)", kind < kinds.count ? kinds[kind] : @"other",
                                                        (unsigned long)counts[kind], PFBProbeSize(bytes[kind])]];
      }
      [loose sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        return [(NSNumber*)b[@"size"] compare:(NSNumber*)a[@"size"]];
      }];
      NSMutableArray<NSString*>* largest = [NSMutableArray array];
      for (NSDictionary* file in [loose subarrayWithRange:NSMakeRange(0, MIN(loose.count, (NSUInteger)3))]) {
          [largest addObject:[NSString stringWithFormat:@"%@ %@", file[@"name"],
                                                        PFBProbeSize([(NSNumber*)file[@"size"] unsignedLongLongValue])]];
      }
      NSArray<NSString*>* first = gone.count > 10 ? [gone subarrayWithRange:NSMakeRange(0, 10)] : gone;
      PFBProbeNote(@"10a#F026 launch sweep",
                   @"10a#F026/05#F020/08#F037 launch sweep: removed %lu (%@), took %.1f ms on the main thread; "
                   @"left in tmp: %@; folders %lu (%@%@); largest: %@",
                   (unsigned long)gone.count, first.count ? [first componentsJoinedByString:@", "] : @"nothing", took,
                   [perKind componentsJoinedByString:@", "], (unsigned long)folders, PFBProbeSize(folderBytes),
                   walked > 5000 ? @", first 5000 files" : @"",
                   largest.count ? [largest componentsJoinedByString:@", "] : @"none");
    });
}

@implementation PFBManager
+ (void)cleanCache {
    // Probe: what the sweep removes and how long it takes, written once per build.
    NSMutableArray<NSString*>* probeRemoved = PFBProbeSweepBegin();
    CFTimeInterval probeStart = probeRemoved ? CACurrentMediaTime() : 0;
    NSArray<NSURL*>* DocumentFiles = [[NSFileManager defaultManager]
          contentsOfDirectoryAtURL:
              [NSURL
                  fileURLWithPath:NSSearchPathForDirectoriesInDomains(
                                      NSDocumentDirectory, NSUserDomainMask, true)
                                      .firstObject]
        includingPropertiesForKeys:@[]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];

    for (NSURL* file in DocumentFiles) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            // Probe: noted before its removal.
            PFBProbeSweepRemoving(probeRemoved, file, @"Documents");
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
    }

    NSArray<NSURL*>* TempFiles = [[NSFileManager defaultManager]
          contentsOfDirectoryAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]
        includingPropertiesForKeys:@[]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];

    for (NSURL* file in TempFiles) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            // Probe: noted before its removal.
            PFBProbeSweepRemoving(probeRemoved, file, @"tmp");
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
        if ([file.pathExtension.lowercaseString isEqualToString:@"mov"]) {
            // Probe: noted before its removal.
            PFBProbeSweepRemoving(probeRemoved, file, @"tmp");
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
        if ([file.pathExtension.lowercaseString isEqualToString:@"tmp"]) {
            // Probe: noted before its removal.
            PFBProbeSweepRemoving(probeRemoved, file, @"tmp");
            [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
        }
        if ([file hasDirectoryPath]) {
            if ([PFBManager isEmpty:file]) {
                // Probe: noted before its removal.
                PFBProbeSweepRemoving(probeRemoved, file, @"tmp");
                [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
            }
        }
    }
    // Probe: the sweep's line.
    PFBProbeSweepEnd(probeRemoved, probeStart);
}
+ (BOOL)isEmpty:(NSURL*)url {
    NSArray* FolderFiles = [[NSFileManager defaultManager]
          contentsOfDirectoryAtURL:url
        includingPropertiesForKeys:@[]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];
    if (FolderFiles.count == 0) {
        return true;
    } else {
        return false;
    }
}
+ (id)sharedFontGroup {
    // Twitter's shared font group.
    return [objc_getClass("TFNUIDefaultFontGroup") sharedFontGroup];
}
+ (UIFont*)menuTitleFont {
    UIFont* font = [[self sharedFontGroup] headline2BoldFont];
    if (!font)
        font = [UIFont boldSystemFontOfSize:17.0];
    return font;
}
+ (NSString*)getVideoQuality:(NSString*)url {
    NSMutableArray* q = [NSMutableArray new];
    NSArray* splits = [url componentsSeparatedByString:@"/"];
    for (int i = 0; i < [splits count]; i++) {
        NSString* item = [splits objectAtIndex:i];
        NSArray* dir = [item componentsSeparatedByString:@"x"];
        for (int k = 0; k < [dir count]; k++) {
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

+ (UIViewController*)PFBSettingsWithAccount:(TFNTwitterAccount*)twAccount {
    return [[PFBModernSettingsViewController alloc] initWithAccount:twAccount];
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
