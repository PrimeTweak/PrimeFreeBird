//
//  VideoDownloadProbe.x
//
//  MEASUREMENT ONLY — no behaviour is changed anywhere in this file. Every hook
//  calls %orig and returns its value untouched. Delete this file and the tweak
//  is exactly what it was.
//
//  THE QUESTION
//  ------------
//  His entry (« Download media ») lives in the « … » overflow menu — his own
//  setting says so. Twitter's entry (« Download Video », activity identifier
//  com.twitter.activity.DownloadVideo) lives in the long-press menu, and it now
//  shows on some videos only. Everything below exists to find out WHY, without
//  guessing a ninth time.
//
//  THE THEORIES, and what each would look like in the journal
//  ---------------------------------------------------------
//   1. The activity is created but declares itself unsupported
//        → « activité <id> isSupported=NON »
//   2. It is created and supported, but refuses these items
//        → « activité <id> canPerform=NON »
//   3. It is never created at all for that video
//        → its identifier never appears, while others do
//   4. The video's media type is not what the tweak expects
//        → « média: type=N isVideo=… isAnimatedGif=… »
//   5. The video is not in the status entities (external card, player)
//        → « média: AUCUNE entité média » on a tweet that clearly has a video
//   6. The native entry is in the overflow list too, just placed differently
//        → « actions: N item(s) … contient Download Video: OUI »
//   7. His own entry is missing from the overflow list
//        → « actions: … contient Download media: NON »
//
//  Each line is printed ONCE per distinct value, so a whole session stays
//  readable. Everything is wrapped so a probe can never take the app down.
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"
#import <objc/message.h>
#import <objc/runtime.h>

// Printed once per key, so scrolling the timeline does not flood the journal.
static BOOL NFBProbeFirstTime(NSString* key) {
    static NSMutableSet* seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        seen = [NSMutableSet set];
    });
    if (!key.length || [seen containsObject:key]) {
        return NO;
    }
    [seen addObject:key];
    return YES;
}

// Reads a string-ish property without messaging `self` directly: T1Activity is
// not declared in the project headers, so Logos only emits a @class for it and
// a direct message would not compile.
static NSString* NFBProbeStringValue(id object, NSString* selectorName) {
    if (!object || !selectorName.length) {
        return nil;
    }
    SEL sel = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:sel]) {
        return nil;
    }
    id value = ((id (*)(id, SEL))objc_msgSend)(object, sel);
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return value ? [value description] : nil;
}

// MARK: - Theories 1, 2 and 3: the activity itself

%hook T1Activity

- (BOOL)isSupported {
    BOOL supported = %orig;
    @try {
        NSString* identifier = NFBProbeStringValue((id)self, @"identifier");
        NSString* title = NFBProbeStringValue((id)self, @"title");
        NSString* key = [NSString stringWithFormat:@"sup|%@|%d", identifier, supported];
        if (NFBProbeFirstTime(key)) {
            NFBDebugLog(@"[dl] activité %@ (« %@ ») isSupported=%@",
                        identifier ?: @"?", title ?: @"?", supported ? @"OUI" : @"NON");
        }
    } @catch (id exception) {
    }
    return supported;
}

- (BOOL)canPerformWithActivityItems:(NSArray*)activityItems {
    BOOL can = %orig;
    @try {
        NSString* identifier = NFBProbeStringValue((id)self, @"identifier");
        NSString* key = [NSString stringWithFormat:@"can|%@|%d", identifier, can];
        if (NFBProbeFirstTime(key)) {
            NFBDebugLog(@"[dl] activité %@ canPerform=%@ (%lu item(s))",
                        identifier ?: @"?", can ? @"OUI" : @"NON",
                        (unsigned long)activityItems.count);
        }
    } @catch (id exception) {
    }
    return can;
}

%end

// MARK: - Theories 4 to 7: what the tweak's own hook actually sees
//
// Same selector the download feature already hooks. Two hooks on one method
// chain through %orig, so this one only observes what the other returns.

%hook UIViewController

- (NSArray*)_t1_actionItemsForStatus:(__unsafe_unretained id)status
                             account:(__unsafe_unretained id)account
                     shareableEntity:(__unsafe_unretained id)shareableEntity
                           entityURL:(__unsafe_unretained id)entityURL
                              source:(__unsafe_unretained id)source
                             options:(NSUInteger)options
                     scribeComponent:(__unsafe_unretained id)scribeComponent
                           doneBlock:(__unsafe_unretained id)doneBlock {
    NSArray* items = %orig;
    @try {
        // --- the media the tweak inspects to decide whether to add its entry
        NSMutableString* shape = [NSMutableString string];
        NSArray* media = nil;
        if ([status respondsToSelector:@selector(entities)]) {
            id entities = ((id (*)(id, SEL))objc_msgSend)(status, @selector(entities));
            if ([entities respondsToSelector:@selector(media)]) {
                id maybe = ((id (*)(id, SEL))objc_msgSend)(entities, @selector(media));
                if ([maybe isKindOfClass:[NSArray class]]) {
                    media = maybe;
                }
            }
        }
        if (!media.count) {
            [shape appendString:@"AUCUNE entité média"];
        }
        for (id entry in media) {
            NSInteger type = -1;
            SEL typeSel = NSSelectorFromString(@"mediaType");
            if ([entry respondsToSelector:typeSel]) {
                type = ((NSInteger (*)(id, SEL))objc_msgSend)(entry, typeSel);
            }
            // The semantic accessors the binary exposes, next to the raw number
            // the tweak currently compares against 2 and 3.
            NSString* isVideo = @"?";
            SEL videoSel = NSSelectorFromString(@"isVideo");
            if ([entry respondsToSelector:videoSel]) {
                isVideo = ((BOOL (*)(id, SEL))objc_msgSend)(entry, videoSel) ? @"oui" : @"non";
            }
            NSString* isGif = @"?";
            SEL gifSel = NSSelectorFromString(@"isAnimatedGif");
            if ([entry respondsToSelector:gifSel]) {
                isGif = ((BOOL (*)(id, SEL))objc_msgSend)(entry, gifSel) ? @"oui" : @"non";
            }
            [shape appendFormat:@"type=%ld isVideo=%@ isGif=%@ · ", (long)type, isVideo, isGif];
        }

        // --- what the finished list contains
        BOOL hasNative = NO;
        BOOL hasOurs = NO;
        NSMutableString* titles = [NSMutableString string];
        for (id item in items) {
            NSString* title = NFBProbeStringValue(item, @"title");
            if (!title.length) {
                title = NFBProbeStringValue(item, @"actionTitle");
            }
            if (!title.length) {
                continue;
            }
            if ([title containsString:@"Download Video"]) {
                hasNative = YES;
            }
            if ([title containsString:@"Download media"]) {
                hasOurs = YES;
            }
            if (titles.length < 160) {
                [titles appendFormat:@"%@ | ", title];
            }
        }

        NSString* key = [NSString stringWithFormat:@"act|%@|%d%d|%lu",
                         shape, hasNative, hasOurs, (unsigned long)items.count];
        if (NFBProbeFirstTime(key)) {
            NFBDebugLog(@"[dl] média: %@", shape.length ? shape : @"(vide)");
            NFBDebugLog(@"[dl] actions: %lu item(s) · natif « Download Video »=%@ · le tien « Download media »=%@",
                        (unsigned long)items.count,
                        hasNative ? @"OUI" : @"NON",
                        hasOurs ? @"OUI" : @"NON");
            NFBDebugLog(@"[dl] titres: %@", titles.length ? titles : @"(aucun lisible)");
        }
    } @catch (id exception) {
        NFBDebugLog(@"[dl] sonde interrompue — sans conséquence");
    }
    return items;
}

%end
