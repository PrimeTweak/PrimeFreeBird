// Downloads: chat videos and voice notes, voice from a video, Tweet to image, media menu.

#import "Support/HookHelpers.h"

// The glyph of the three download entries: Twitter's, or the closest system symbol.
static UIImage* PFBDownloadGlyph(void) {
    return PFBTwitterGlyphFor(@"arrow_down_circle_stroke",
                              [UIImage systemImageNamed:@"arrow.down.circle"]);
}

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

// When a tap last reached a voice note, and any message, in a conversation.
static CFAbsoluteTime gPFBVoiceTapAt = 0;
static CFAbsoluteTime gPFBMessageTapAt = 0;

// How long ago a tap came, in steps; nil past 30 s.
static NSString* PFBSinceTap(CFAbsoluteTime now, CFAbsoluteTime tapAt) {
    CFAbsoluteTime since = now - tapAt;
    return since < 1 ? @"under 1 s" : since < 5 ? @"1 to 5 s" : since < 30 ? @"5 to 30 s" : nil;
}

// For the report: a decrypted file's place under decrypted-media-v2, each name given by its
// length, the thread opening it and how long after a tap it came.
static void PFBNoteDecryptedFile(NSURL* url) {
    NSString* inside = [url.path componentsSeparatedByString:@"/decrypted-media-v2/"].lastObject;
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* part in inside.pathComponents) {
        NSString* stem = [NSString stringWithFormat:@"#%lu", (unsigned long)part.stringByDeletingPathExtension.length];
        [parts addObject:part.pathExtension.length ? [stem stringByAppendingFormat:@".%@", part.pathExtension] : stem];
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSString* voice = PFBSinceTap(now, gPFBVoiceTapAt);
    NSString* message = PFBSinceTap(now, gPFBMessageTapAt);
    NSString* when = voice     ? [voice stringByAppendingString:@" after a voice note tap"]
                     : message ? [message stringByAppendingString:@" after a message tap"]
                               : @"no tap in the 30 s before";
    NSString* line = [NSString stringWithFormat:@"%@ · %@ · %@", [parts componentsJoinedByString:@"/"],
                                                NSThread.isMainThread ? @"main thread" : @"other thread", when];
    dispatch_async(dispatch_get_main_queue(), ^{
        PFBCompatMeasure(@"voice notes", line, 8);
    });
}

%hook AVURLAsset

- (id)initWithURL:(NSURL*)url options:(NSDictionary*)options {
    if ([url.path containsString:@"/decrypted-media-v2/"]) {
        PFBCompatReach(PFBCompatPath_played_voice_note);
        gPFBLastVoiceURL = url;
        PFBNoteDecryptedFile(url);
    }
    return %orig;
}

%end

// Whether an attachment slot shows a voice note view.
static BOOL PFBShowsVoiceNote(UIView* view, NSInteger depth) {
    Class voiceClass = objc_getClass("_TtC6ChatUI26MessageAttachmentAudioView");
    if (!voiceClass || depth > 3) {
        return NO;
    }
    for (UIView* sub in view.subviews) {
        if ([sub isKindOfClass:voiceClass] ? !sub.hidden && sub.alpha > 0.01 : PFBShowsVoiceNote(sub, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

// Taps on an attachment and on a message, timed for the decrypted file lines.
%hook _TtC16ChatConversation26MessageAttachmentStackView

- (void)handleTap:(UITapGestureRecognizer*)recognizer {
    if ([recognizer isKindOfClass:[UIGestureRecognizer class]] && PFBShowsVoiceNote(recognizer.view, 0)) {
        gPFBVoiceTapAt = CFAbsoluteTimeGetCurrent();
    }
    %orig;
}

%end

%hook _TtC16ChatConversation18MessageContentView

- (void)handleCellTap {
    gPFBMessageTapAt = CFAbsoluteTimeGetCurrent();
    %orig;
}

%end

// The file is already on disk and already decrypted; copying it out under a
// fresh name is enough to hand it to the share sheet.
static void PFBSaveVoiceMessage(NSURL* sourceURL) {
    if (!sourceURL.isFileURL) {
        return;
    }
    NSString* extension = sourceURL.pathExtension.length ? sourceURL.pathExtension : @"m4a";
    NSURL* destination = [[PFBManager temporaryFolder]
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

%hook _TtC6ChatUI26MessageAttachmentAudioView

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
    // The interaction stays on views laid out while the option was on; off, it opens nothing.
    NSURL* voiceURL = gPFBLastVoiceURL;
    if (!voiceURL || ![PFBSettings boolForKey:@"download_voice_messages"]) {
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
                                     image:PFBDownloadGlyph()
                                identifier:nil
                                   handler:^(__kindof UIAction* _Nonnull action) {
                                     PFBSaveVoiceMessage(voiceURL);
                                   }];
                       return [UIMenu menuWithTitle:@"" children:@[ saveAction ]];
                     }];
}

%end

%hook _TtC16ChatConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* pfbDownloadMenuInteraction;
%property (nonatomic, strong) PFBDownloadInlineButton* pfbDownloadHandler;
- (void)layoutSubviews {
    %orig;

    BOOL enabled = [PFBSettings boolForKey:@"download_videos"];
    if (enabled && self.pfbDownloadMenuInteraction == nil) {
        self.pfbDownloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.pfbDownloadMenuInteraction];
    } else if (!enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_download_videos, @"chat media found");
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    if (![PFBSettings boolForKey:@"download_videos"]) {
        return nil;
    }
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    PFBCOMPAT_ACTION(PFBCompat_download_videos, @"save menu on chat media");
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[PFBBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:PFBDownloadGlyph()
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.pfbDownloadHandler == nil) {
                                             self.pfbDownloadHandler = [%c(PFBDownloadInlineButton) new];
                                         }
                                         [self.pfbDownloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// MARK: - Upload custom voice

// The video is copied into the tweak's folder first and only then swapped in for the
// recording, so a failed copy leaves the recording as it was.
static void PFBReplaceVoiceRecording(NSURL* videoURL, NSString* recordingPath) {
    if (!videoURL.isFileURL || recordingPath.length == 0) {
        return;
    }
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* recordingURL = [NSURL fileURLWithPath:recordingPath];
    NSURL* staged = [[PFBManager temporaryFolder] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![fileManager copyItemAtURL:videoURL toURL:staged error:nil]) {
        return;
    }
    BOOL swapped = [fileManager fileExistsAtPath:recordingPath]
                       ? [fileManager replaceItemAtURL:recordingURL
                                         withItemAtURL:staged
                                        backupItemName:nil
                                               options:0
                                      resultingItemURL:nil
                                                 error:nil]
                       : [fileManager moveItemAtURL:staged toURL:recordingURL error:nil];
    if (!swapped) {
        [fileManager removeItemAtURL:staged error:nil];
    }
}

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* pfbUploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];
    BOOL enabled = [PFBSettings boolForKey:@"voice_note_from_video"];
    if (isVoiceRecording && !enabled) {
        PFBCOMPAT_OBSERVE(PFBCompat_voice_note_from_video, @"voice note attached");
    }

    if (enabled && isVoiceRecording && self.pfbUploadButton == nil) {
        // Read from the ivar: a key-value read of a name Twitter dropped would throw.
        Ivar removeIvar = class_getInstanceVariable(object_getClass(self), "_removeButton");
        TFNButton* removeButton = removeIvar ? object_getIvar(self, removeIvar) : nil;
        if (![removeButton isKindOfClass:[UIView class]]) {
            return;
        }

        // Twitter's video glyph in white on the dark circle, like the remove button beside it.
        self.pfbUploadButton = [PFBHitButton buttonWithType:UIButtonTypeCustom];
        UIImage* videoGlyph = PFBTwitterGlyphFor(@"camera_video_stroke", [UIImage systemImageNamed:@"video"]);
        [self.pfbUploadButton setImage:videoGlyph forState:UIControlStateNormal];
        [self.pfbUploadButton addTarget:self
                                 action:@selector(pfbHandleUploadButton:)
                       forControlEvents:UIControlEventTouchUpInside];
        [self.pfbUploadButton setTintColor:[UIColor whiteColor]];
        [self.pfbUploadButton setBackgroundColor:[UIColor blackColor]];
        [self.pfbUploadButton.layer setCornerRadius:29 / 2.0];
        self.pfbUploadButton.accessibilityLabel =
            [[PFBBundle sharedBundle] localizedStringForKey:@"VOICE_NOTE_FROM_VIDEO_BUTTON"];
        [self.pfbUploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.pfbUploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.pfbUploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                                constant:-10],
            [self.pfbUploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.pfbUploadButton.widthAnchor constraintEqualToConstant:29],
            [self.pfbUploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.pfbUploadButton.hidden = !(isVoiceRecording && enabled);
    if (isVoiceRecording && enabled && self.pfbUploadButton) {
        PFBCOMPAT_ACTION(PFBCompat_voice_note_from_video, @"upload button on a voice note");
    }
}
%new
- (void)pfbHandleUploadButton:(UIButton*)sender {
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    TTMAssetVoiceRecording* attachment = self.attachment;
    PFBReplaceVoiceRecording(info[UIImagePickerControllerMediaURL], attachment.filePath);
    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

// Set when the tweak took the start of the share long press in progress.
static BOOL gPFBShareStartTaken;

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    UIGestureRecognizerState state = gestureRecognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        gPFBShareStartTaken = NO;
    } else if (gPFBShareStartTaken &&
               (state == UIGestureRecognizerStateChanged || state == UIGestureRecognizerStateEnded)) {
        static dispatch_once_t noted;
        dispatch_once(&noted, ^{
            PFBCompatMeasure(@"save as image", @"Twitter's share long press got its end without its start", 2);
        });
    }
    if ([PFBSettings boolForKey:@"tweet_to_image"]) {
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
            NSURL* pngURL = [[PFBManager temporaryFolder]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.bounds;
            }
            [topMostController() presentViewController:acVC
                                              animated:true
                                            completion:^{
                                              PFBCOMPAT_ACTION(PFBCompat_tweet_to_image, @"Tweet image offered");
                                            }];
            gPFBShareStartTaken = YES;
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
static NSString* const kPFBVMDActionIdentifier = @"com.primetweak.primefreebird.download-video";

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
            // A status that is not an object is skipped: read through the shim it
            // would be retained as a pointer.
            Method statusMethod = class_getInstanceMethod(object_getClass(item), @selector(status));
            char returnType[2] = {0};
            if (statusMethod) {
                method_getReturnType(statusMethod, returnType, sizeof(returnType));
            }
            if (statusMethod && returnType[0] != '@') {
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
// TW_ copy covers a miss.
static NSString* PFBVMDMenuTitle(void) {
    return [[PFBBundle sharedBundle] localizedTwitterStringForKey:@"DOWNLOAD_VIDEO_ACTIVITY_VIEW_LABEL"];
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

// A media menu shows one of Twitter's own media entries (Post Video, Copy Video Link, React
// with Video, Add to Offline) or one of its download entries.
static BOOL PFBVMDIsMediaMenu(NSArray* children) {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSMutableSet<NSString*>* titles = [NSMutableSet set];
    for (NSString* key in @[@"TWEET_VIDEO_ACTIVITY_VIEW_LABEL", @"COPY_VIDEO_LINK_ACTIVITY_VIEW_LABEL",
                            @"REACT_WITH_VIDEO", @"OFFLINE_ADD_TO_OFFLINE_BUTTON_TITLE"]) {
        [titles addObject:[bundle localizedTwitterStringForKey:key]];
    }
    NSString* ours = PFBVMDMenuTitle();
    NSString* generic = [bundle localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"];
    for (id element in children) {
        if (![element respondsToSelector:@selector(title)]) {
            continue;
        }
        NSString* title = [element title];
        if (title.length > 0 && ([titles containsObject:title] || PFBVMDTitleIsDownload(title, ours, generic))) {
            return YES;
        }
    }
    return NO;
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
    if (!PFBVMDIsMediaMenu(children)) {
        id first = children.firstObject;
        NSString* name = [first respondsToSelector:@selector(title)] ? [first title] : nil;
        PFBCompatMeasure(@"download video",
                         [NSString stringWithFormat:@"Download Video added to an unrelated menu: %@",
                                                    name.length > 0 ? name : NSStringFromClass([first class])],
                         2);
    }

    UIAction* action = [UIAction actionWithTitle:PFBVMDMenuTitle()
                                           image:PFBDownloadGlyph()
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
