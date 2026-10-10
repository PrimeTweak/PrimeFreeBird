// The download options sheet for Tweet and chat media, and the FFmpeg downloads behind it.

#import "Features/Media/PFBDownloadInlineButton.h"
#import <objc/runtime.h>
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Common/PFBCompatibility.h"

#pragma mark - Helpers
static UIWindow* KeyWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow)
                return window;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController* TopMostController(void) {
    UIViewController* top = KeyWindow().rootViewController;
    while (top.presentedViewController)
        top = top.presentedViewController;
    return top;
}

// An alert under Twitter's error title, with the tweak's message for the key.
static void PFBShowDownloadFailure(NSString* messageKey) {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                                            message:[bundle localizedStringForKey:messageKey]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [TopMostController() presentViewController:alert animated:YES completion:nil];
}

// Hands the files to Photos. Once Photos has answered for all of them: the success haptic
// and the proof, or the error haptic and an alert when it refused any.
static void PFBSaveDownloads(NSArray<NSURL*>* files, BOOL gif) {
    dispatch_group_t group = dispatch_group_create();
    __block BOOL allSaved = YES;
    for (NSURL* file in files) {
        dispatch_group_enter(group);
        [PFBManager saveToPhotos:file
                           asGIF:gif
                      completion:^(BOOL saved) {
                          allSaved = allSaved && saved;
                          dispatch_group_leave(group);
                      }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        UINotificationFeedbackGenerator* feedback = [UINotificationFeedbackGenerator new];
        if (allSaved) {
            PFBCOMPAT_ACTION(PFBCompat_direct_save, @"saved to Photos");
            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
            return;
        }
        [feedback notificationOccurred:UINotificationFeedbackTypeError];
        PFBShowDownloadFailure(@"PHOTOS_SAVE_FAILED_MESSAGE");
    });
}

#pragma mark - PFBDownloadInlineButton
@interface PFBDownloadInlineButton ()
@property (nonatomic, strong) TFNHUD* hud;
@end

// The mp4 variant with the most pixels, from the WxH its URL carries.
static NSURL* PFBLargestVideo(NSArray<NSURL*>* urls) {
    NSURL* best = urls.firstObject;
    NSInteger bestPixels = -1;
    for (NSURL* url in urls) {
        NSArray<NSString*>* size =
            [[PFBManager getVideoQuality:url.absoluteString] componentsSeparatedByString:@"x"];
        NSInteger pixels = size.count == 2 ? size[0].integerValue * size[1].integerValue : 0;
        if (pixels > bestPixels) {
            bestPixels = pixels;
            best = url;
        }
    }
    return best;
}

// The largest mp4 among a video's variants, or nil when it has none.
static NSURL* PFBLargestMP4(TFSTwitterEntityMedia* media) {
    NSMutableArray<NSURL*>* urls = [NSMutableArray new];
    for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo.variants) {
        NSURL* url = variant.url.length ? [NSURL URLWithString:variant.url] : nil;
        if (url && [variant.contentType isEqualToString:@"video/mp4"]) {
            [urls addObject:url];
        }
    }
    return urls.count ? PFBLargestVideo(urls) : nil;
}

@implementation PFBDownloadInlineButton

#pragma mark - Dry run
- (void)dryRunForMediaEntities:(NSArray*)mediaEntities {
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if (![media isKindOfClass:objc_getClass("TFSTwitterEntityMedia")] || media.mediaType != 3) {
            continue;
        }
        NSMutableArray<NSURL*>* mp4URLs = [NSMutableArray new];
        BOOL playlist = NO;
        for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo.variants) {
            NSURL* url = variant.url.length ? [NSURL URLWithString:variant.url] : nil;
            if (url && [variant.contentType isEqualToString:@"video/mp4"]) {
                [mp4URLs addObject:url];
            } else if ([variant.contentType isEqualToString:@"application/x-mpegURL"]) {
                playlist = YES;
            }
        }
        if (mp4URLs.count == 0 && !playlist) {
            PFBCompatTourLog(@"[dlvideo] dry run: no playable variant read");
            return;
        }
        NSString* found = mp4URLs.count
                              ? [NSString stringWithFormat:@"best of %lu MP4s: %@ (dry run)", (unsigned long)mp4URLs.count,
                                                           [PFBManager getVideoQuality:PFBLargestVideo(mp4URLs).absoluteString]]
                              : @"HLS only, no MP4 (dry run)";
        PFBCOMPAT_OBSERVE(PFBCompat_download_highest_quality, @"%@", found);
        PFBCOMPAT_OBSERVE(PFBCompat_direct_save, @"download path read (dry run)");
        PFBCompatTourLog(@"[dlvideo] dry run: %@", found);
        return;
    }
    PFBCompatTourLog(@"[dlvideo] dry run: no video among %lu media", (unsigned long)mediaEntities.count);
}

#pragma mark - Download handler
- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities {
    @try {
        NSAttributedString* titleString = [[NSAttributedString alloc]
            initWithString:[[PFBBundle sharedBundle]
                               localizedStringForKey:@"DOWNLOAD_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [PFBManager menuTitleFont],
                    NSForegroundColorAttributeName: UIColor.labelColor
                }];
        TFNActiveTextItem* title = [[objc_getClass("TFNActiveTextItem") alloc]
            initWithTextModel:[[objc_getClass("TFNAttributedTextModel") alloc]
                                  initWithAttributedString:titleString]
                 activeRanges:nil];

        void (^showHUD)(NSString*) = ^(NSString* text) {
            self.hud = [[objc_getClass("TFNHUD") alloc] initWithText:text];
            [self.hud show];
        };
        void (^dismissHUD)(void) = ^{
            [self.hud hide];
        };

        // Every download runs through FFmpeg: mp4s stream-copied, GIFs palette-encoded, HLS-only
        // resolutions re-encoded with VideoToolbox; progress is processed time over probed duration.
        // With a collect block the file is handed over instead of saved, nil on failure.
        NSString* downloadingText = [[PFBBundle sharedBundle]
            localizedTwitterStringForKey:@"DOWNLOAD_LIVE_ACTIVITY_DOWNLOADING"];
        void (^ffmpegDownload)(NSString*, NSString*, double, void (^)(NSURL*)) = ^(
            NSString* args, NSString* ext, double durationMs, void (^collect)(NSURL*)) {
            showHUD(downloadingText);
            NSURL* outFile = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.%@",
                                                                 NSUUID.UUID
                                                                     .UUIDString,
                                                                 ext]];
            [FFmpegKit
                executeAsync:[NSString stringWithFormat:@"%@ %@", args, outFile.path]
                withCompleteCallback:^(FFmpegSession* session) {
                    ReturnCode* returnCode = [session getReturnCode];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        dismissHUD();
                        BOOL succeeded = [ReturnCode isSuccess:returnCode];
                        if (succeeded && collect) {
                            collect(outFile);
                        } else if (succeeded) {
                            if (![PFBSettings boolForKey:@"direct_save"]) {
                                PFBCOMPAT_OBSERVE(PFBCompat_direct_save, @"save sheet shown");
                                [PFBManager showSaveVC:outFile];
                            } else {
                                PFBSaveDownloads(@[ outFile ], [ext isEqualToString:@"gif"]);
                            }
                        } else {
                            [[UINotificationFeedbackGenerator new]
                                notificationOccurred:UINotificationFeedbackTypeError];
                            PFBShowDownloadFailure(@"UNKNOWN_ERROR");
                            if (collect) {
                                collect(nil);
                            }
                        }
                    });
                }
                withLogCallback:nil
                withStatisticsCallback:^(Statistics* statistics) {
                    NSString* detail;
                    if (durationMs > 0) {
                        detail = [PFBManager
                            getDownloadingPercent:MIN([statistics getTime] / durationMs,
                                                      1.0)];
                    } else if ([statistics getSize] > 0) {
                        detail = [NSByteCountFormatter
                            stringFromByteCount:[statistics getSize]
                                     countStyle:NSByteCountFormatterCountStyleFile];
                    } else {
                        return;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.hud
                            setText:[NSString stringWithFormat:@"%@ %@", downloadingText,
                                                               detail]];
                    });
                }];
        };

        // Variant builders
        TFNActionItem* (^makeMP4Item)(NSURL*, double, NSString*) =
            ^TFNActionItem*(NSURL* url, double durationMs, NSString* itemTitle) {
                return [objc_getClass("TFNActionItem")
                    actionItemWithTitle:itemTitle
                              imageName:@"arrow_down_circle_stroke"
                                 action:^{
                                     ffmpegDownload(
                                         [NSString stringWithFormat:@"-i %@ -c copy",
                                                                    url.absoluteString],
                                         @"mp4", durationMs, nil);
                                 }];
            };

        TFNActionItem* (^makeGIFItem)(NSURL*, double) = ^TFNActionItem*(
            NSURL* url, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:
                    [[PFBBundle sharedBundle]
                        localizedStringForKey:@"DOWNLOAD_AS_GIF_OPTION_TITLE"]
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 ffmpegDownload(
                                     [NSString
                                         stringWithFormat:@"-i %@ -an -vf "
                                                          @"split[a][b];[a]palettegen["
                                                          @"p];[b][p]paletteuse",
                                                          url.absoluteString],
                                     @"gif", durationMs, nil);
                             }];
        };

        TFNActionItem* (^makeHLSItem)(NSURL*, NSString*, double) = ^TFNActionItem*(
            NSURL* url, NSString* resolution, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:resolution
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 ffmpegDownload(
                                     [NSString
                                         stringWithFormat:
                                             @"-i %@ -vf scale=%@:flags=lanczos -c:v "
                                             @"h264_videotoolbox -b:v 2M -c:a copy",
                                             url.absoluteString, resolution],
                                     @"mp4", durationMs, nil);
                             }];
        };

        // videoInfo.variants backs both video and GIF; photos carry none. Probing
        // the playlist supplies the duration and any HLS-only resolutions. mp4
        // variants win at equal resolution, and media without a playlist skips it.
        void (^buildVariantItems)(TFSTwitterEntityMedia*, void (^)(NSArray*)) = ^(
            TFSTwitterEntityMedia* media, void (^done)(NSArray*)) {
            NSMutableArray<NSURL*>* mp4URLs = [NSMutableArray new];
            NSURL* m3u8URL = nil;
            for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo
                     .variants) {
                NSURL* url =
                    variant.url.length ? [NSURL URLWithString:variant.url] : nil;
                if (!url)
                    continue;

                if ([variant.contentType isEqualToString:@"video/mp4"])
                    [mp4URLs addObject:url];
                else if ([variant.contentType
                             isEqualToString:@"application/x-mpegURL"] &&
                         !m3u8URL)
                    m3u8URL = url;
            }

            // A video with best quality on skips the menu: its mp4 with the most
            // pixels is copied as is, never a re-encoded HLS stream.
            if (media.mediaType == 3 && mp4URLs.count > 0) {
                if ([PFBSettings boolForKey:@"download_highest_quality"]) {
                    PFBCOMPAT_ACTION(PFBCompat_download_highest_quality, @"best quality saved");
                    ffmpegDownload([NSString stringWithFormat:@"-i %@ -c copy",
                                                              PFBLargestVideo(mp4URLs).absoluteString],
                                   @"mp4", 0, nil);
                    return;
                }
                PFBCOMPAT_OBSERVE(PFBCompat_download_highest_quality, @"quality menu built");
            }

            NSMutableArray* items = [NSMutableArray new];
            NSMutableSet<NSString*>* offered = [NSMutableSet new];
            void (^appendMP4Items)(double) = ^(double durationMs) {
                BOOL isGIF = media.mediaType == 2;
                for (NSURL* url in mp4URLs) {
                    NSString* itemTitle =
                        isGIF ? [[PFBBundle sharedBundle]
                                    localizedStringForKey:@"DOWNLOAD_AS_MP4_OPTION_TITLE"]
                              : [PFBManager getVideoQuality:url.absoluteString];
                    [offered addObject:[PFBManager getVideoQuality:url.absoluteString]];
                    [items addObject:makeMP4Item(url, durationMs, itemTitle)];
                    if (isGIF)
                        [items addObject:makeGIFItem(url, durationMs)];
                }
            };

            if (!m3u8URL) {
                appendMP4Items(0);
                done(items);
                return;
            }

            showHUD([[PFBBundle sharedBundle]
                localizedStringForKey:@"FETCHING_PROGRESS_TITLE"]);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                MediaInformation* info = [PFBManager getM3U8Information:m3u8URL];
                double durationMs = [info getDuration].doubleValue * 1000.0;

                dispatch_async(dispatch_get_main_queue(), ^{
                    dismissHUD();
                    appendMP4Items(durationMs);
                    for (StreamInformation* stream in [info getStreams]) {
                        NSNumber* width = [stream getWidth];
                        NSNumber* height = [stream getHeight];
                        if (width == nil || height == nil)
                            continue;

                        NSString* resolution =
                            [NSString stringWithFormat:@"%@x%@", width, height];
                        if ([offered containsObject:resolution])
                            continue;

                        [offered addObject:resolution];
                        [items addObject:makeHLSItem(m3u8URL, resolution, durationMs)];
                    }
                    done(items);
                });
            });
        };

        // Filter to video/GIF so grouping keys off the real video count, not the
        // raw media count.
        NSMutableArray<TFSTwitterEntityMedia*>* videoEntities =
            [NSMutableArray new];
        for (TFSTwitterEntityMedia* media in mediaEntities) {
            if ((media.mediaType == 2 || media.mediaType == 3) &&
                media.videoInfo.variants.count > 0) {
                [videoEntities addObject:media];
            }
        }

        void (^presentSheet)(NSArray*) = ^(NSArray* items) {
            NSMutableArray* actions = [NSMutableArray arrayWithObject:title];
            [actions addObjectsFromArray:items];

            TFNMenuSheetViewController* sheet =
                [[objc_getClass("TFNMenuSheetViewController") alloc]
                    initWithActionItems:actions.copy];
            [sheet tfnPresentedCustomPresentFromViewController:TopMostController()
                                                      animated:YES
                                                    completion:nil];
        };

        if (videoEntities.count > 1) {
            NSMutableArray* groups = [NSMutableArray new];
            [videoEntities enumerateObjectsUsingBlock:^(TFSTwitterEntityMedia* media,
                                                        NSUInteger idx, BOOL* stop) {
                [groups
                    addObject:[objc_getClass("TFNActionItem")
                                  actionItemWithTitle:
                                      [NSString
                                          stringWithFormat:
                                              [[PFBBundle sharedBundle]
                                                  localizedStringForKey:
                                                      @"DOWNLOAD_VIDEO_NUMBER_TITLE"],
                                              (unsigned long)idx + 1]
                                            imageName:@"arrow_down_circle_stroke"
                                               action:^{
                                                   buildVariantItems(media, presentSheet);
                                               }]];
            }];

            // One entry saves the largest mp4 of every video. The downloads run one
            // after the other, as they share the HUD, then are saved together.
            BOOL allVideos = YES;
            for (TFSTwitterEntityMedia* media in videoEntities) {
                allVideos = allVideos && media.mediaType == 3;
            }
            if (allVideos) {
                PFBCompatReach(PFBCompatPath_download_all);
                NSArray<TFSTwitterEntityMedia*>* queue = videoEntities.copy;
                void (^downloadAll)(void) = ^{
                    NSMutableArray<NSURL*>* files = [NSMutableArray new];
                    __block void (^downloadNext)(NSUInteger);
                    downloadNext = ^(NSUInteger index) {
                        if (index >= queue.count) {
                            // Releasing this block releases what it holds, so the list is
                            // taken out first.
                            NSArray<NSURL*>* finished = files.copy;
                            downloadNext = nil;
                            if (finished.count == 0) {
                                return;
                            }
                            if (![PFBSettings boolForKey:@"direct_save"]) {
                                PFBCOMPAT_OBSERVE(PFBCompat_direct_save, @"save sheet shown");
                                [PFBManager showSaveVCForItems:finished];
                                return;
                            }
                            PFBSaveDownloads(finished, NO);
                            return;
                        }
                        NSURL* url = PFBLargestMP4(queue[index]);
                        if (!url) {
                            downloadNext(index + 1);
                            return;
                        }
                        ffmpegDownload([NSString stringWithFormat:@"-i %@ -c copy", url.absoluteString], @"mp4", 0,
                                       ^(NSURL* file) {
                                           if (file) {
                                               [files addObject:file];
                                           }
                                           downloadNext(index + 1);
                                       });
                    };
                    downloadNext(0);
                };
                [groups insertObject:[objc_getClass("TFNActionItem")
                                         actionItemWithTitle:[[PFBBundle sharedBundle]
                                                                 localizedStringForKey:
                                                                     @"DOWNLOAD_ALL_VIDEOS_OPTION_TITLE"]
                                                   imageName:@"arrow_down_circle_stroke"
                                                      action:downloadAll]
                             atIndex:0];
            }
            presentSheet(groups);
        } else {
            buildVariantItems(videoEntities.firstObject, presentSheet);
        }
    } @catch (__unused NSException* ex) {
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[PFBBundle sharedBundle]
                    localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                             message:[[PFBBundle sharedBundle]
                                         localizedStringForKey:@"UNKNOWN_ERROR"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                             actionWithTitle:[[PFBBundle sharedBundle]
                                                 localizedTwitterStringForKey:
                                                     @"OK_ACTION_LABEL"]
                                       style:UIAlertActionStyleDefault
                                     handler:nil]];
        [TopMostController() presentViewController:alert
                                          animated:YES
                                        completion:nil];
    }
}

@end
