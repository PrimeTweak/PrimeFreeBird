//
//  MediaDownloads.x
//  PrimeFreeBird
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// MARK: - DM video download

// The DM UI is Swift now: media messages live in DMConversation.MessageAttachmentView,
// which hosts a shared TweetMediaAttachments media view exposing its models through
// -inlineMediaInfos. Collect the entities from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    EnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

// MARK: - Voice messages
//
// A voice note is decrypted to disk before playing, so its URL passes through
// the asset opened to play it. The last one seen is the one under the finger:
// the view that would answer a long press has no reference to it, and the
// attachment view above cannot serve this menu — the audio view sits on its
// own and takes the touch first.

static NSURL* gNFBLastVoiceURL = nil;

%hook AVURLAsset

- (id)initWithURL:(NSURL*)url options:(NSDictionary*)options {
    if ([url.path containsString:@"/decrypted-media-v2/"]) {
        gNFBLastVoiceURL = url;
    }
    return %orig;
}

%end

// The file is already on disk and already decrypted; copying it out under a
// fresh name is enough to hand it to the share sheet.
static void NFBSaveVoiceMessage(NSURL* sourceURL) {
    if (!sourceURL.isFileURL) {
        return;
    }
    NSString* extension = sourceURL.pathExtension.length ? sourceURL.pathExtension : @"m4a";
    NSURL* destination = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",
                                                              NSUUID.UUID.UUIDString,
                                                              extension]];
    NSError* copyError = nil;
    [[NSFileManager defaultManager] copyItemAtURL:sourceURL
                                            toURL:destination
                                            error:&copyError];
    if (copyError) {
        return;
    }
    [BHTManager showSaveVC:destination];
}

// The audio view carries its own interaction rather than sharing the
// attachment view's: it is a separate view and wins the touch first.
// The interaction is held by association and the view is addressed as a
// UIView: this class is known to the compiler only by a forward declaration,
// so nothing can be added to its interface and no message can be sent to it
// directly.
static const void* kNFBVoiceInteractionKey = &kNFBVoiceInteractionKey;

%hook _TtC13DMAttachments24AttachmentAssetAudioView

- (void)layoutSubviews {
    %orig;
    UIView* view = (UIView*)self;
    if ([BHTSettings boolForKey:@"download_voice_messages"] &&
        !objc_getAssociatedObject(view, kNFBVoiceInteractionKey)) {
        UIContextMenuInteraction* interaction = [[UIContextMenuInteraction alloc]
            initWithDelegate:(id<UIContextMenuInteractionDelegate>)self];
        objc_setAssociatedObject(view, kNFBVoiceInteractionKey, interaction,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view addInteraction:interaction];
    }
}

%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSURL* voiceURL = gNFBLastVoiceURL;
    if (!voiceURL) {
        return nil;
    }
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                       UIAction* saveAction = [UIAction
                           actionWithTitle:[[BHTBundle sharedBundle]
                                               localizedTwitterStringForKey:
                                                   @"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                     image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                identifier:nil
                                   handler:^(__kindof UIAction* _Nonnull action) {
                                     NFBSaveVoiceMessage(voiceURL);
                                   }];
                       return [UIMenu menuWithTitle:@"" children:@[ saveAction ]];
                     }];
}

%end

%hook _TtC14DMConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) DownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    if ([BHTSettings boolForKey:@"download_videos"] && self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(DownloadInlineButton) new];
                                         }
                                         [self.downloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// MARK: - 12.21: DM attachments moved to the ChatConversation module
//
// The DMAttachments module is gone from 12.21 and DMConversation lost its
// attachment view; both now live in ChatConversation. Same bodies, new names.

%hook _TtC16ChatConversation26MessageAttachmentAudioView

- (void)layoutSubviews {
    %orig;
    UIView* view = (UIView*)self;
    if ([BHTSettings boolForKey:@"download_voice_messages"] &&
        !objc_getAssociatedObject(view, kNFBVoiceInteractionKey)) {
        UIContextMenuInteraction* interaction = [[UIContextMenuInteraction alloc]
            initWithDelegate:(id<UIContextMenuInteractionDelegate>)self];
        objc_setAssociatedObject(view, kNFBVoiceInteractionKey, interaction,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view addInteraction:interaction];
    }
}

%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSURL* voiceURL = gNFBLastVoiceURL;
    if (!voiceURL) {
        return nil;
    }
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                       UIAction* saveAction = [UIAction
                           actionWithTitle:[[BHTBundle sharedBundle]
                                               localizedTwitterStringForKey:
                                                   @"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                     image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                identifier:nil
                                   handler:^(__kindof UIAction* _Nonnull action) {
                                     NFBSaveVoiceMessage(voiceURL);
                                   }];
                       return [UIMenu menuWithTitle:@"" children:@[ saveAction ]];
                     }];
}

%end

%hook _TtC16ChatConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) DownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    if ([BHTSettings boolForKey:@"download_videos"] && self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(DownloadInlineButton) new];
                                         }
                                         [self.downloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// MARK: - Upload custom voice

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* uploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];

    if (isVoiceRecording && self.uploadButton == nil) {
        TFNButton* removeButton = [self valueForKey:@"_removeButton"];
        if (removeButton == nil) {
            return;
        }

        self.uploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImageSymbolConfiguration* smallConfig =
            [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
        UIImage* arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
        [self.uploadButton setImage:arrowUpImage forState:UIControlStateNormal];
        [self.uploadButton addTarget:self
                              action:@selector(handleUploadButton:)
                    forControlEvents:UIControlEventTouchUpInside];
        [self.uploadButton setTintColor:UIColor.labelColor];
        [self.uploadButton setBackgroundColor:[UIColor blackColor]];
        [self.uploadButton.layer setCornerRadius:29 / 2];
        [self.uploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.uploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.uploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                             constant:-10],
            [self.uploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.uploadButton.widthAnchor constraintEqualToConstant:29],
            [self.uploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.uploadButton.hidden = !isVoiceRecording;
}
%new
- (void)handleUploadButton:(UIButton*)sender {
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    NSURL* videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording* attachment = self.attachment;
    NSURL* recorder_url = [NSURL fileURLWithPath:attachment.filePath];

    if (recorder_url != nil) {
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSError* error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
            if (error) {
            }
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
        if (error) {
        }
    }

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([BHTSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: - Tweet media download -- entry in the media long-press menu
//
// The entry no longer lives in the "..." overflow menu: the hook on
// _t1_actionItemsForStatus: was removed. It is added here, in the media
// long-press menu, for every video and GIF.
//
// Binary facts this block relies on (Twitter 12.15):
//
//   - The media long-press menu is not built by an Objective-C method. Its
//   builder sits in a gap of the T1Twitter IMP table (between 0x2f7df8 and
//   0x314818), so there is nothing to hook there. The only Objective-C point
//   on that path is `+[UIMenu menuWithTitle:children:]`, the two-argument
//   factory. The "..." overflow menu uses the five-argument one instead.
//
//   - The native "Download Video" entry is gated in T1Twitter by a `cbz` on
//   `[[media entityURL] networkURL]` (0x30d530). A nil URL skips the whole
//   download block: neither "Download Video" nor the generic "Download".
//   That gate, not Premium and not `allowDownload`, is why the native entry
//   appears on some videos only.
//
//   - About 0.4 s before the menu is assembled, Twitter builds a
//   `UIActivityViewController` whose single activity item is a
//   `T1ActivityItemProvider`, which exposes `-status`. That object supplies
//   the tweet: without it, the entry would download another tweet's media.
//
// The decision to add the entry never depends on English menu titles. It
// depends on the freshly captured status and its video or GIF media
// (mediaType 2 or 3). Titles are compared only to avoid a duplicate when the
// native entry is already present.

// T1ActivityItemProvider is not declared in src/Headers, so a declaration
// shim is used purely as a cast target. It is never instantiated and never
// messaged as a class, so no class symbol is referenced and linking is safe.
@interface NFBVMDProviderShim : NSObject
- (id)status;
@end

// Freshness window between the share sheet and the menu. Measured at 0.4 s.
// Past this delay nothing is added: no entry is better than the wrong media.
static const NSTimeInterval kNFBVMDFreshness = 3.0;

static id                    gNFBVMDStatus;        // tweet under the long press
static NSTimeInterval        gNFBVMDStatusTime;
static DownloadInlineButton* gNFBVMDDownloader;    // reused downloader instance

%hook UIActivityViewController

- (id)initWithActivityItems:(NSArray*)activityItems
      applicationActivities:(NSArray*)applicationActivities {
    id result = %orig;
    @try {
        for (id item in activityItems) {
            if (![item respondsToSelector:@selector(status)]) {
                continue;
            }
            id status = [(NFBVMDProviderShim*)item status];
            if (!status) {
                continue;
            }
            gNFBVMDStatus = status;
            gNFBVMDStatusTime = [NSDate timeIntervalSinceReferenceDate];
            break;
        }
    } @catch (id exception) {
    }
    return result;
}

%end

// Same media test as the rest of this file: mediaType 2 is a GIF, 3 a video.
static NSArray* NFBVMDFreshVideoEntities(void) {
    if (!gNFBVMDStatus) {
        return nil;
    }
    NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - gNFBVMDStatusTime;
    if (age < 0 || age > kNFBVMDFreshness) {
        return nil;
    }
    if (![gNFBVMDStatus respondsToSelector:@selector(entities)]) {
        return nil;
    }
    NSArray* mediaEntities = [[gNFBVMDStatus entities] media];
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            return mediaEntities;
        }
    }
    return nil;
}

// The title comes from Twitter's own bundle, so it matches the native entry
// exactly and is translated in every language without adding a string. This
// mirrors the DOWNLOAD_ACTIVITY_VIEW_LABEL lookup used earlier in this file.
// localizedStringForKey:value:key returns the key itself when it is missing,
// hence the explicit fallback.
static NSString* NFBVMDMenuTitle(void) {
    NSString* key = @"DOWNLOAD_VIDEO_ACTIVITY_VIEW_LABEL";
    NSString* title = [[BHTBundle sharedBundle] localizedTwitterStringForKey:key];
    if (title.length == 0 || [title isEqualToString:key]) {
        return @"Download Video";
    }
    return title;
}

// Detects a download entry that is already present. This avoids duplicating
// the native entry when it appears, and avoids adding the custom one twice if
// the menu is rebuilt.
static BOOL NFBVMDAlreadyHasDownload(NSArray* children) {
    NSString* ours = NFBVMDMenuTitle();
    NSString* generic = [[BHTBundle sharedBundle]
                            localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"];
    for (id element in children) {
        if (![element respondsToSelector:@selector(title)]) {
            continue;
        }
        NSString* title = [element title];
        if (title.length == 0) {
            continue;
        }
        if ([title isEqualToString:ours] ||
            (generic.length > 0 && [title isEqualToString:generic])) {
            return YES;
        }
    }
    return NO;
}

static UIImage* NFBVMDGlyph(void) {
    UIImage* glyph = nil;
    if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        glyph = [UIImage tfn_vectorImageNamed:@"arrow_down_circle_stroke"
                                     fitsSize:CGSizeMake(24.0, 24.0)
                                    fillColor:[UIColor labelColor]];
    }
    if (!glyph) {
        glyph = [UIImage systemImageNamed:@"arrow.down.circle"];
    }
    return glyph;
}

// Returns the children array to install: unchanged, or with the download
// entry inserted before the last item ("Share via...").
static NSArray* NFBVMDAugmentedChildren(NSArray* children) {
    if (children.count == 0) {
        return children;
    }
    if (![BHTSettings boolForKey:@"download_videos"]) {
        return children;
    }
    if (NFBVMDAlreadyHasDownload(children)) {
        return children;
    }
    NSArray* mediaEntities = NFBVMDFreshVideoEntities();
    if (mediaEntities.count == 0) {
        return children;
    }

    if (!gNFBVMDDownloader) {
        gNFBVMDDownloader = [%c(DownloadInlineButton) new];
    }
    DownloadInlineButton* downloader = gNFBVMDDownloader;

    UIAction* action = [UIAction actionWithTitle:NFBVMDMenuTitle()
                                           image:NFBVMDGlyph()
                                      identifier:nil
                                         handler:^(UIAction* sender) {
        [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
    }];
    if (!action) {
        return children;
    }

    NSMutableArray* augmented = [children mutableCopy];
    [augmented insertObject:action atIndex:augmented.count - 1];
    NFBDebugLog(@"[dlvideo] entry added to media menu (%lu -> %lu items)",
                (unsigned long)children.count, (unsigned long)augmented.count);
    return augmented;
}

%hook UIMenu

+ (id)menuWithTitle:(NSString*)title children:(NSArray*)children {
    NSArray* finalChildren = children;
    @try {
        finalChildren = NFBVMDAugmentedChildren(children);
    } @catch (id exception) {
        finalChildren = children;
    }
    return %orig(title, finalChildren);
}

%end

%ctor {
    NFBDebugLog(@"[dlvideo] media menu download entry armed");
}
