// Send sound: an imported sound, kept as a 16-bit PCM CAF file, plays once for each
// Tweet or thread handed to Twitter's outbox for sending.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

// Longest sound accepted, in seconds.
static const NSTimeInterval kPFBSendSoundLongest = 7.0;

// The imported file's own name, for display only.
static NSString* const kPFBSendSoundNameKey = @"pfb_send_sound_name";

// Marks a composition already handed to the outbox, so its later passes stay silent:
// the end of the undo delay, Send now and the retries.
static char kPFBSendSoundHandedKey;

// The userInfo key the outbox files the composition under.
static NSString* gPFBCompositionKey;

// The stored file as a system sound, kept until the file changes; 0 when there is none
// or it could not be created. Used on the main thread only.
static SystemSoundID gPFBSendSound;
static BOOL gPFBSendSoundLoaded;

static NSURL* PFBSendSoundFolder(void) {
    NSURL* support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@PFB_PRODUCT_NAME isDirectory:YES];
}

static NSURL* PFBSendSoundFile(void) {
    return [PFBSendSoundFolder() URLByAppendingPathComponent:@"send-sound.caf"];
}

BOOL PFBSendSoundIsSet(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:PFBSendSoundFile().path];
}

NSString* PFBSendSoundName(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kPFBSendSoundNameKey];
}

// Drops the system sound and creates it again from the stored file, when there is one.
static void PFBSendSoundReload(void) {
    if (gPFBSendSound) {
        AudioServicesDisposeSystemSoundID(gPFBSendSound);
        gPFBSendSound = 0;
    }
    gPFBSendSoundLoaded = YES;
    if (PFBSendSoundIsSet() &&
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)PFBSendSoundFile(), &gPFBSendSound) !=
            kAudioServicesNoError) {
        gPFBSendSound = 0;
        PFBDebugLog(@"[sendsound] the stored sound could not be loaded");
    }
}

static BOOL PFBSendSoundPlay(void) {
    if (!gPFBSendSoundLoaded) {
        PFBSendSoundReload();
    }
    if (gPFBSendSound) {
        AudioServicesPlaySystemSound(gPFBSendSound);
    }
    return gPFBSendSound != 0;
}

// Every frame of the input, written as 16-bit interleaved PCM in a CAF file. AVFAudio
// reports some faults as exceptions; they count as a failure here.
static BOOL PFBSendSoundDecode(AVAudioFile* input, NSURL* destination) {
    AVAudioFormat* format = input.processingFormat;
    NSDictionary* settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(format.sampleRate),
        AVNumberOfChannelsKey: @(format.channelCount),
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
    };
    AVAudioFramePosition written = 0;
    @try {
        // The writer completes its file when it is released, at the end of the pool.
        @autoreleasepool {
            AVAudioFile* output = [[AVAudioFile alloc] initForWriting:destination settings:settings error:nil];
            AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:4096];
            while (output && buffer && [input readIntoBuffer:buffer error:nil] && buffer.frameLength > 0) {
                if (![output writeFromBuffer:buffer error:nil]) {
                    return NO;
                }
                written += buffer.frameLength;
            }
        }
    } @catch (__unused NSException* exception) {
        return NO;
    }
    return written > 0;
}

// Nil once the sound is stored, else the string key of the reason it was refused.
static NSString* PFBSendSoundStore(NSURL* source) {
    AVAudioFile* input = [[AVAudioFile alloc] initForReading:source error:nil];
    AVAudioFormat* format = input.processingFormat;
    // More than two channels would need a channel layout to be written.
    if (!input || input.length <= 0 || format.sampleRate <= 0 || format.channelCount > 2) {
        return @"SEND_SOUND_UNREADABLE";
    }
    if (input.length / format.sampleRate > kPFBSendSoundLongest) {
        return @"SEND_SOUND_TOO_LONG";
    }
    NSFileManager* files = [NSFileManager defaultManager];
    NSURL* partial = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"caf"]];
    BOOL stored = PFBSendSoundDecode(input, partial) &&
                  [files createDirectoryAtURL:PFBSendSoundFolder()
                      withIntermediateDirectories:YES
                                       attributes:nil
                                            error:nil];
    if (stored) {
        [files removeItemAtURL:PFBSendSoundFile() error:nil];
        stored = [files moveItemAtURL:partial toURL:PFBSendSoundFile() error:nil];
    }
    if (!stored) {
        [files removeItemAtURL:partial error:nil];
    }
    return stored ? nil : @"SEND_SOUND_UNREADABLE";
}

void PFBSendSoundImport(NSURL* source, void (^completion)(NSString* failureKey)) {
    NSString* name = source.lastPathComponent;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString* failureKey = PFBSendSoundStore(source);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!failureKey) {
                [[NSUserDefaults standardUserDefaults] setObject:name forKey:kPFBSendSoundNameKey];
            }
            PFBSendSoundReload();
            completion(failureKey);
        });
    });
}

void PFBSendSoundRemove(void) {
    [[NSFileManager defaultManager] removeItemAtURL:PFBSendSoundFile() error:nil];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPFBSendSoundNameKey];
    PFBSendSoundReload();
}

// Marks a composition and the rest of its thread, whose Tweets the outbox hands over one
// at a time, so a thread plays once.
static void PFBSendSoundMark(TFNTwitterComposition* composition) {
    objc_setAssociatedObject(composition, &kPFBSendSoundHandedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TFNTwitterCompositionReplyChain* chain =
        [composition respondsToSelector:@selector(replyChain)] ? composition.replyChain : nil;
    if (![chain respondsToSelector:@selector(compositions)]) {
        return;
    }
    for (id member in chain.compositions) {
        objc_setAssociatedObject(member, &kPFBSendSoundHandedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// The outbox posts DidAddUndoable once per batch held for Undo Tweet, with its first
// Tweet, and DidAdd for each Tweet it sends at once, a held one again when its delay ends.
// Runs on the posting thread, so the poster never waits for the main thread.
static void PFBSendSoundHanded(NSNotification* note, BOOL held) {
    TFNTwitterComposition* composition = note.userInfo[gPFBCompositionKey];
    if (!composition) {
        static BOOL said;
        if (!said) {
            said = YES;
            PFBDebugLog(@"[sendsound] %@ carries no composition", note.name);
        }
        return;
    }
    if (!held && objc_getAssociatedObject(composition, &kPFBSendSoundHandedKey)) {
        return;
    }
    PFBSendSoundMark(composition);
    dispatch_block_t sound = ^{
        if (!PFBSendSoundIsSet()) {
            PFBCOMPAT_OBSERVE(PFBCompat_send_sound, @"Tweet handed to Twitter");
            return;
        }
        if (PFBSendSoundPlay()) {
            PFBCOMPAT_ACTION(PFBCompat_send_sound, @"send sound played");
        }
    };
    if (NSThread.isMainThread) {
        sound();
    } else {
        dispatch_async(dispatch_get_main_queue(), sound);
    }
}

// An outbox constant read from Twitter's exported symbol, or the symbol's name, which is
// also its value, when the symbol cannot be found.
static NSString* PFBOutboxName(const char* symbol) {
    NSString* const* exported = (NSString* const*)dlsym(RTLD_DEFAULT, symbol);
    return exported && *exported ? *exported : @(symbol);
}

void PFBSendSoundStart(void) {
    gPFBCompositionKey = PFBOutboxName("TFNTwitterCompositionOutboxNotificationCompositionUserInfoKey");
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:PFBOutboxName("TFNTwitterCompositionOutboxDidAddUndoableCompositionNotification")
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification* note) {
                        PFBSendSoundHanded(note, YES);
                    }];
    [center addObserverForName:PFBOutboxName("TFNTwitterCompositionOutboxDidAddCompositionNotification")
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification* note) {
                        PFBSendSoundHanded(note, NO);
                    }];
}
