// Preload media, photo half: the rows Twitter's own look-ahead is about to show
// have their photos fetched into its image cache, under the identifier the
// timeline cells use. The video half sets Twitter's prefetcher in FeatureSwitches.x.

#import "Support/HookHelpers.h"

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
        return;
    }
    TIPGenericImageFetchRequest* request = [[requestClass alloc] initWithImageURL:components.URL
                                                                         identifier:identifier
                                                                   targetDimensions:CGSizeZero
                                                                  targetContentMode:UIViewContentModeScaleAspectFill];
    id operation = [pipeline operationWithRequest:request context:nil completion:nil];
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
