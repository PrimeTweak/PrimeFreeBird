// Download entries: DM videos and voice messages, custom voice uploads, tweet to
// image, and the download entry in the media long-press menu.

#import "Support/HookHelpers.h"

// MARK: - DM video download

// DM media messages (ChatConversation.MessageAttachmentView) host a shared media
// view exposing its models through -inlineMediaInfos; the entities are collected
// from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    PFBEnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
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

// A voice note is decrypted to disk before playing, so its URL passes through the
// asset opened to play it. The last one seen is taken as the one under the finger.

static NSURL* gPFBLastVoiceURL = nil;

%hook AVURLAsset

- (id)initWithURL:(NSURL*)url options:(NSDictionary*)options {
    if ([url.path containsString:@"/decrypted-media-v2/"]) {
        gPFBLastVoiceURL = url;
    }
    return %orig;
}

%end

// The file is already on disk and already decrypted; copying it out under a
// fresh name is enough to hand it to the share sheet.
static void PFBSaveVoiceMessage(NSURL* sourceURL) {
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
    [PFBManager showSaveVC:destination];
}

// The audio view carries its own interaction, since it is a separate view and wins
// the touch first. It is held by association and the view addressed as a UIView:
// the class is known to the compiler only by a forward declaration.
static const void* kPFBVoiceInteractionKey = &kPFBVoiceInteractionKey;

%hook _TtC16ChatConversation26MessageAttachmentAudioView

- (void)layoutSubviews {
    %orig;
    UIView* view = (UIView*)self;
    BOOL enabled = [PFBSettings boolForKey:@"download_voice_messages"];
    if (!enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_voice_messages, @"voice note found");
    }
    if (enabled &&
        !objc_getAssociatedObject(view, kPFBVoiceInteractionKey)) {
        UIContextMenuInteraction* interaction = [[UIContextMenuInteraction alloc]
            initWithDelegate:(id<UIContextMenuInteractionDelegate>)self];
        objc_setAssociatedObject(view, kPFBVoiceInteractionKey, interaction,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view addInteraction:interaction];
        PFBCOMPAT_ACTION(PFBCompat_download_voice_messages, @"save menu on a voice note");
    }
}

%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSURL* voiceURL = gPFBLastVoiceURL;
    if (!voiceURL) {
        return nil;
    }
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                       UIAction* saveAction = [UIAction
                           actionWithTitle:[[PFBBundle sharedBundle]
                                               localizedTwitterStringForKey:
                                                   @"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                     image:PFBTwitterGlyphFor(@"arrow_down_circle_stroke", [UIImage systemImageNamed:@"square.and.arrow.down"])
                                identifier:nil
                                   handler:^(__kindof UIAction* _Nonnull action) {
                                     PFBSaveVoiceMessage(voiceURL);
                                   }];
                       return [UIMenu menuWithTitle:@"" children:@[ saveAction ]];
                     }];
}

%end

%hook _TtC16ChatConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) PFBDownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    BOOL enabled = [PFBSettings boolForKey:@"download_videos"];
    if (enabled && self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
        PFBCOMPAT_ACTION(PFBCompat_download_videos, @"save menu on chat media");
    } else if (!enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_videos, @"chat media found");
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
                                 [[PFBBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:PFBTwitterGlyphFor(@"arrow_down_circle_stroke", [UIImage systemImageNamed:@"square.and.arrow.down"])
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(PFBDownloadInlineButton) new];
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
    BOOL enabled = [PFBSettings boolForKey:@"voice_note_from_video"];
    if (isVoiceRecording) {
        if (enabled) {
            PFBCOMPAT_ACTION(PFBCompat_voice_note_from_video, @"upload button on a voice note");
        } else {
            PFBCOMPAT_OBSERVE(PFBCompat_voice_note_from_video, @"voice note attached");
        }
    }

    if (enabled && isVoiceRecording && self.uploadButton == nil) {
        // Read from the ivar: a key-value read of a name Twitter dropped would throw.
        Ivar removeIvar = class_getInstanceVariable(object_getClass(self), "_removeButton");
        TFNButton* removeButton = removeIvar ? object_getIvar(self, removeIvar) : nil;
        if (![removeButton isKindOfClass:[UIView class]]) {
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

    self.uploadButton.hidden = !(isVoiceRecording && enabled);
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
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
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
    if ([PFBSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            PFBCOMPAT_ACTION(PFBCompat_tweet_to_image, @"Tweet saved as image");
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
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan &&
        ![PFBSettings boolForKey:@"tweet_to_image"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_tweet_to_image, @"long press on share");
    }
    return %orig;
}
%end

// MARK: - Tweet media download, in the media long-press menu

// That menu has no Objective-C builder, so the only point on its path is the
// two-argument +[UIMenu menuWithTitle:children:]. The tweet comes from the
// T1ActivityItemProvider built shortly before.

// T1ActivityItemProvider is not declared in src/Support, so a declaration
// shim is used purely as a cast target. It is never instantiated and never
// messaged as a class, so no class symbol is referenced and linking is safe.
@interface PFBVMDProviderShim : NSObject
- (id)status;
@end

// Freshness window between the share sheet and the menu; past it nothing is added,
// since no entry is better than the wrong media.
static const NSTimeInterval kPFBVMDFreshness = 3.0;

// The added entry is told apart by identifier: the app's own entry can carry the
// very same title.
static NSString* const kPFBVMDActionIdentifier = @"com.primefreebird.download-video";

static id                    gPFBVMDStatus;        // tweet under the long press
static NSTimeInterval        gPFBVMDStatusTime;
static PFBDownloadInlineButton* gPFBVMDDownloader;    // reused downloader instance

// A Tweet's media when one of them is a video or a GIF (mediaType 2 or 3), else nil.
static NSArray* PFBVMDVideoEntities(id status) {
    if (![status respondsToSelector:@selector(entities)]) {
        return nil;
    }
    NSArray* mediaEntities = [[status entities] media];
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            return mediaEntities;
        }
    }
    return nil;
}

%hook UIActivityViewController

- (id)initWithActivityItems:(NSArray*)activityItems
      applicationActivities:(NSArray*)applicationActivities {
    id result = %orig;
    @try {
        for (id item in activityItems) {
            if (![item respondsToSelector:@selector(status)]) {
                continue;
            }
            id status = [(PFBVMDProviderShim*)item status];
            if (!status) {
                continue;
            }
            gPFBVMDStatus = status;
            gPFBVMDStatusTime = [NSDate timeIntervalSinceReferenceDate];
            break;
        }
    } @catch (id exception) {
    }
    return result;
}

%end

// The captured Tweet's video media while still fresh; nil otherwise.
static NSArray* PFBVMDFreshVideoEntities(void) {
    NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - gPFBVMDStatusTime;
    if (!gPFBVMDStatus || age < 0 || age > kPFBVMDFreshness) {
        return nil;
    }
    return PFBVMDVideoEntities(gPFBVMDStatus);
}

// The title comes from Twitter's own strings, so it matches the native entry; the bundled
// TW_ copy covers a miss. The lookup returns the key itself when both miss, hence the
// explicit fallback.
static NSString* PFBVMDMenuTitle(void) {
    NSString* key = @"DOWNLOAD_VIDEO_ACTIVITY_VIEW_LABEL";
    NSString* title = [[PFBBundle sharedBundle] localizedTwitterStringForKey:key];
    if (title.length == 0 || [title isEqualToString:key]) {
        return @"Download Video";
    }
    return title;
}

// A download entry by its title: the added one, which the app's video entry also shows,
// the app's generic one, or a raw key when the app shows one.
static BOOL PFBVMDTitleIsDownload(NSString* title, NSString* ours,
                                  NSString* generic) {
    if ([title isEqualToString:ours] ||
        (generic.length > 0 && [title isEqualToString:generic])) {
        return YES;
    }
    NSString* upper = title.uppercaseString;
    return [upper containsString:@"DOWNLOAD"] &&
           [upper containsString:@"ACTIVITY_VIEW_LABEL"];
}

static BOOL PFBVMDIsOurs(id element) {
    return [element isKindOfClass:[UIAction class]] &&
           [((UIAction*)element).identifier isEqualToString:kPFBVMDActionIdentifier];
}

// Guards against adding the entry twice when a menu is rebuilt.
static BOOL PFBVMDAlreadyHasOurs(NSArray* children) {
    for (id element in children) {
        if (PFBVMDIsOurs(element)) {
            return YES;
        }
    }
    return NO;
}

static UIImage* PFBVMDGlyph(void) {
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

// The app's own download entries leave a menu that holds the added entry, so one entry
// remains; without it, the app's stay untouched.
static NSArray* PFBVMDWithoutNativeDownload(NSArray* children) {
    NSString* ours = PFBVMDMenuTitle();
    NSString* generic = [[PFBBundle sharedBundle]
                            localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"];
    NSMutableArray* kept = nil;
    for (id element in children) {
        if (PFBVMDIsOurs(element) || ![element respondsToSelector:@selector(title)]) {
            continue;
        }
        NSString* title = [element title];
        if (title.length == 0 || !PFBVMDTitleIsDownload(title, ours, generic)) {
            continue;
        }
        if (!kept) {
            kept = [children mutableCopy];
        }
        [kept removeObject:element];
    }
    return kept ?: children;
}

// The children to install: the added entry before the last item ("Share via..."), in
// place of the app's own; unchanged without a fresh video Tweet or with the option off.
static NSArray* PFBVMDMenuChildren(NSArray* children) {
    if (children.count == 0) {
        return children;
    }
    if (PFBVMDAlreadyHasOurs(children)) {
        return PFBVMDWithoutNativeDownload(children);
    }
    NSArray* mediaEntities = PFBVMDFreshVideoEntities();
    if (mediaEntities.count == 0) {
        return children;
    }
    if (!gPFBVMDDownloader) {
        gPFBVMDDownloader = [%c(PFBDownloadInlineButton) new];
    }
    PFBDownloadInlineButton* downloader = gPFBVMDDownloader;
    // A path tour reads the download path without downloading anything.
    if (PFBCompatTourIsRunning()) {
        [downloader dryRunForMediaEntities:mediaEntities];
    }
    if (![PFBSettings boolForKey:@"download_videos"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_videos, @"video menu found");
        return children;
    }
    PFBCOMPAT_ACTION(PFBCompat_download_videos, @"download entry in a video menu");

    UIAction* action = [UIAction actionWithTitle:PFBVMDMenuTitle()
                                           image:PFBVMDGlyph()
                                      identifier:kPFBVMDActionIdentifier
                                         handler:^(UIAction* sender) {
        [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
    }];
    NSMutableArray* augmented = [PFBVMDWithoutNativeDownload(children) mutableCopy];
    [augmented insertObject:action atIndex:augmented.count ? augmented.count - 1 : 0];
    return augmented;
}

%hook UIMenu

+ (id)menuWithTitle:(NSString*)title children:(NSArray*)children {
    NSArray* finalChildren = children;
    @try {
        finalChildren = PFBVMDMenuChildren(children);
    } @catch (id exception) {
        finalChildren = children;
    }
    return %orig(title, finalChildren);
}

// The app appends its own entry after the menu is first built.
- (UIMenu*)menuByReplacingChildren:(NSArray*)children {
    NSArray* finalChildren = children;
    @try {
        if (PFBVMDAlreadyHasOurs(children)) {
            finalChildren = PFBVMDWithoutNativeDownload(children);
        }
    } @catch (id exception) {
        finalChildren = children;
    }
    return %orig(finalChildren);
}

%end
