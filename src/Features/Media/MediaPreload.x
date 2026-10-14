// Preload media, photo half: the rows Twitter's own look-ahead is about to show
// have their photos fetched into its image cache, under the identifier the
// timeline cells use. The video half sets Twitter's prefetcher in FeatureSwitches.x.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

typedef void (^PFBPreloadCompletion)(id result, NSError* error);

@interface TIPGenericImageFetchRequest : NSObject
- (instancetype)initWithImageURL:(NSURL*)imageURL
                      identifier:(NSString*)imageIdentifier
                targetDimensions:(CGSize)targetDimensions
               targetContentMode:(UIViewContentMode)targetContentMode;
@end

@interface TIPImagePipeline : NSObject
- (id)operationWithRequest:(id)request context:(id)context completion:(PFBPreloadCompletion)completion;
- (void)fetchImageWithOperation:(id)operation;
@end

// Four Tweets ahead, as chosen for the videos, in the variant single photos load.
static const NSInteger kRowsAhead = 4;
static NSString* const kPhotoVariant = @"900x900";
static const NSUInteger kRememberedPhotos = 500;

static __weak TIPImagePipeline* gPipeline;
static NSMutableSet<NSString*>* gAsked;

static NSObject* preloadLock(void) {
    static NSObject* lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      lock = [NSObject new];
      gAsked = [NSMutableSet set];
    });
    return lock;
}

// The timeline's photos all go through one pipeline; the first photo request names it.
static void notePipeline(TIPImagePipeline* pipeline, id request) {
    if (gPipeline) {
        return;
    }
    SEL selector = NSSelectorFromString(@"imageURL");
    if (![request respondsToSelector:selector]) {
        return;
    }
    NSURL* url = ((id (*)(id, SEL))objc_msgSend)(request, selector);
    if ([url isKindOfClass:[NSURL class]] && [url.host isEqualToString:@"pbs.twimg.com"] &&
        [url.path hasPrefix:@"/media/"]) {
        gPipeline = pipeline;
    }
}

// A photo's address in the Tweet's model, or nil for anything else.
static NSURL* photoAddress(id media) {
    for (NSString* name in @[ @"imageURL", @"imageURLString" ]) {
        SEL selector = NSSelectorFromString(name);
        if (![media respondsToSelector:selector]) {
            continue;
        }
        id value = ((id (*)(id, SEL))objc_msgSend)(media, selector);
        NSURL* url = [value isKindOfClass:[NSURL class]]      ? value
                     : [value isKindOfClass:[NSString class]] ? [NSURL URLWithString:value]
                                                              : nil;
        if ([url.host isEqualToString:@"pbs.twimg.com"] && [url.path hasPrefix:@"/media/"] &&
            url.pathExtension.length > 0) {
            return url;
        }
    }
    return nil;
}

// Probe: a photo preload that issued nothing, once per reason.
static BOOL gPFBProbePreloadSkipDone[3];
static void pfbProbePreloadNotIssued(NSUInteger reason) {
    if (reason > 2 || gPFBProbePreloadSkipDone[reason] || !PFBDebugIsRecording()) {
        return;
    }
    gPFBProbePreloadSkipDone[reason] = YES;
    NSString* name = @[ @"url", @"class", @"operation" ][reason];
    PFBProbeNote([@"10a#F045 not issued " stringByAppendingString:name], @"10a#F045 preload: not issued (%@)", name);
}

// Probe: the outcome of the photo preloads, from a completion handed to the operation only
// while it is wanted: the first result, then a tally of the first 30.
static const NSUInteger kPFBProbePreloadTally = 30;
static BOOL gPFBProbePreloadDone;
static BOOL gPFBProbePreloadIssued;
static PFBPreloadCompletion pfbProbePreloadCompletion(void) {
    if (gPFBProbePreloadDone || !PFBDebugIsRecording()) {
        return nil;
    }
    if (!PFBProbeWants(@"10a#F045 tally")) {
        gPFBProbePreloadDone = YES;
        return nil;
    }
    return ^(id result, NSError* error) {
        BOOL found = NO;
        long long source = PFBProbeIntegerGetter(result, @"imageSource", &found);
        if (PFBProbeWants(@"10a#F045 result")) {
            NSString* failure = error ? [NSString stringWithFormat:@"%@ %ld", error.domain, (long)error.code] : @"none";
            PFBProbeNote(@"10a#F045 result", @"10a#F045 preload: result=%@ error=%@ main=%@, image source %@",
                         result ? PFBProbeClassName(result) : @"nil", failure, NSThread.isMainThread ? @"yes" : @"no",
                         found ? [NSString stringWithFormat:@"%lld", source] : @"?");
        }
        if (result && !error) {
            PFBProbeCount(@"10a#F045 loaded");
        }
        if (found && source >= 1 && source <= 3) {
            PFBProbeCount(@"10a#F045 cached");
        }
        if (PFBProbeCount(@"10a#F045 results") == kPFBProbePreloadTally) {
            PFBProbeNote(@"10a#F045 tally",
                         @"10a#F045 preload: %lu results, %lu with an image and no error, %lu from a cache",
                         (unsigned long)kPFBProbePreloadTally, (unsigned long)PFBProbeCountValue(@"10a#F045 loaded"),
                         (unsigned long)PFBProbeCountValue(@"10a#F045 cached"));
            gPFBProbePreloadDone = YES;
        }
    };
}

// Probe: the first operation issued with the probe's completion attached, or none issued.
static void pfbProbePreloadIssue(BOOL issued, BOOL watched) {
    if (!issued) {
        pfbProbePreloadNotIssued(2);
    } else if (watched && !gPFBProbePreloadIssued) {
        gPFBProbePreloadIssued = YES;
        PFBProbeNote(@"10a#F045 issued", @"10a#F045 preload: first photo fetch issued with a completion to watch");
    }
}

static void fetchPhoto(TIPImagePipeline* pipeline, NSURL* address, NSString* identifier) {
    NSURLComponents* components = [NSURLComponents new];
    components.scheme = @"https";
    components.host = @"pbs.twimg.com";
    components.path = address.path.stringByDeletingPathExtension;
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"format" value:address.pathExtension],
        [NSURLQueryItem queryItemWithName:@"name" value:kPhotoVariant]
    ];
    Class requestClass = objc_getClass("TIPGenericImageFetchRequest");
    if (!components.URL || !requestClass) {
        pfbProbePreloadNotIssued(requestClass ? 0 : 1);
        return;
    }
    TIPGenericImageFetchRequest* request = [[requestClass alloc] initWithImageURL:components.URL
                                                                         identifier:identifier
                                                                   targetDimensions:CGSizeZero
                                                                  targetContentMode:UIViewContentModeScaleAspectFill];
    // Probe: nil outside the measurement, as before.
    PFBPreloadCompletion probeCompletion = pfbProbePreloadCompletion();
    id operation = [pipeline operationWithRequest:request context:nil completion:probeCompletion];
    pfbProbePreloadIssue(operation != nil, probeCompletion != nil);
    if (operation) {
        [pipeline fetchImageWithOperation:operation];
    }
}

// The photos of one row, each asked for once, under the address the cells use.
static NSUInteger preloadPhotos(id item, TIPImagePipeline* pipeline) {
    id status = PFBUnwrapDataViewItem(item);
    SEL selector = NSSelectorFromString(@"inlineMediaInfos");
    if (![status respondsToSelector:selector]) {
        return 0;
    }
    NSArray* medias = ((id (*)(id, SEL))objc_msgSend)(status, selector);
    if (![medias isKindOfClass:[NSArray class]]) {
        return 0;
    }
    NSUInteger asked = 0;
    for (id media in medias) {
        NSURL* address = photoAddress(media);
        if (!address) {
            continue;
        }
        NSString* identifier = [@"https://pbs.twimg.com" stringByAppendingString:address.path];
        BOOL fresh = NO;
        @synchronized(preloadLock()) {
            if (![gAsked containsObject:identifier]) {
                if (gAsked.count >= kRememberedPhotos) {
                    [gAsked removeAllObjects];
                }
                [gAsked addObject:identifier];
                fresh = YES;
            }
        }
        if (fresh) {
            fetchPhoto(pipeline, address, identifier);
            asked++;
        }
    }
    return asked;
}

%hook TFNItemsDataViewController

- (void)tableView:(UITableView*)tableView prefetchRowsAtIndexPaths:(NSArray<NSIndexPath*>*)indexPaths {
    %orig;
    if (![PFBSettings boolForKey:@"enable_image_preloading"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_enable_image_preloading, @"look-ahead seen");
        return;
    }
    TIPImagePipeline* pipeline = gPipeline;
    NSIndexPath* lastShown = tableView.indexPathsForVisibleRows.lastObject;
    SEL itemSelector = NSSelectorFromString(@"itemAtIndexPath:");
    if (!pipeline || !lastShown || ![self respondsToSelector:itemSelector]) {
        return;
    }
    NSUInteger asked = 0;
    for (NSIndexPath* indexPath in indexPaths) {
        NSInteger ahead = indexPath.row - lastShown.row;
        if (indexPath.section != lastShown.section || ahead < 1 || ahead > kRowsAhead) {
            continue;
        }
        id item = ((id (*)(id, SEL, NSIndexPath*))objc_msgSend)(self, itemSelector, indexPath);
        asked += preloadPhotos(item, pipeline);
    }
    if (asked > 0) {
        PFBCOMPAT_ACTION(PFBCompat_enable_image_preloading, @"photos preloaded");
    }
}

%end

%hook TIPImagePipeline

- (id)operationWithRequest:(id)request context:(id)context delegate:(id)delegate {
    notePipeline(self, request);
    return %orig;
}

- (id)operationWithRequest:(id)request context:(id)context completion:(id)completion {
    notePipeline(self, request);
    return %orig;
}

%end
