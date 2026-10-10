// Account location: the country an author's account is based in, read from x.com's
// About this account with the web session and added after the time of an opened Tweet.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBAboutAccountURL =
    @"https://x.com/i/api/graphql/XRqGa7EeokUU5kppkh13EA/AboutAccountQuery?variables=";
static NSString* const kPFBAccountLocationNote = @"PFBAccountLocationArrived";
static const NSInteger kPFBAccountLocationTries = 3;

// By handle: the country, or an empty string once x.com gave none. Main thread only.
static NSCache<NSString*, NSString*>* gPFBLocations;
static NSMutableSet<NSString*>* gPFBLocationsAsked;
static NSMutableDictionary<NSString*, NSNumber*>* gPFBLocationFailures;

static const void* kPFBFooterTimeKey = &kPFBFooterTimeKey;
static const void* kPFBFooterRefresherKey = &kPFBFooterRefresherKey;
// Set once a country has been added to a footer, so the option turned off puts times back.
static BOOL gPFBCountryShown;

// The handle without the @ or anything else a handle cannot hold.
static NSString* PFBCleanHandle(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    static NSCharacterSet* outside;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      outside = [[NSCharacterSet
          characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"]
          invertedSet];
    });
    NSString* handle = [(NSString*)value stringByTrimmingCharactersInSet:outside];
    return handle.length ? handle : nil;
}

// The author of the footer's own Tweet, read only where the getter returns an object.
static NSString* PFBFooterHandle(T1ConversationFooterTextView* footer) {
    id model = [footer respondsToSelector:@selector(viewModel)] ? footer.viewModel : nil;
    SEL getter = @selector(fromUserName);
    if (![model respondsToSelector:getter] ||
        [model methodSignatureForSelector:getter].methodReturnType[0] != '@') {
        return nil;
    }
    return PFBCleanHandle(((id (*)(id, SEL))objc_msgSend)(model, getter));
}

// "Canada", or "Canada?" when x.com marks the place as uncertain; nil without a place.
static NSString* PFBCountryFromAnswer(NSData* data) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    for (NSString* key in @[@"data", @"user_result_by_screen_name", @"result", @"about_profile"]) {
        json = [json isKindOfClass:[NSDictionary class]] ? json[key] : nil;
    }
    id place = [json isKindOfClass:[NSDictionary class]] ? json[@"account_based_in"] : nil;
    if (![place isKindOfClass:[NSString class]] || ![place length]) {
        return nil;
    }
    id accurate = json[@"location_accurate"];
    BOOL doubtful = [accurate isKindOfClass:[NSNumber class]] && ![accurate boolValue];
    return doubtful ? [place stringByAppendingString:@"?"] : place;
}

static void PFBAskForCountry(NSString* handle);

// Main thread. A failed answer is asked again twice, then settled as no country.
static void PFBSettleCountry(NSString* handle, NSString* country, BOOL failed) {
    [gPFBLocationsAsked removeObject:handle];
    if (failed) {
        NSInteger failures = gPFBLocationFailures[handle].integerValue + 1;
        gPFBLocationFailures[handle] = @(failures);
        if (failures < kPFBAccountLocationTries) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                             PFBAskForCountry(handle);
                           });
            return;
        }
    }
    [gPFBLocationFailures removeObjectForKey:handle];
    [gPFBLocations setObject:country ?: @"" forKey:handle];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPFBAccountLocationNote
                                                        object:handle];
}

// Main thread. One question per handle at a time, none once it is settled.
static void PFBAskForCountry(NSString* handle) {
    if ([gPFBLocations objectForKey:handle] || [gPFBLocationsAsked containsObject:handle]) {
        return;
    }
    NSData* variables =
        [NSJSONSerialization dataWithJSONObject:@{@"screenName": handle} options:0 error:nil];
    NSCharacterSet* plain =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString* query = [[[NSString alloc] initWithData:variables encoding:NSUTF8StringEncoding]
        stringByAddingPercentEncodingWithAllowedCharacters:plain];
    NSMutableURLRequest* request =
        PFBWebSessionGETRequest([NSURL URLWithString:[kPFBAboutAccountURL stringByAppendingString:query]]);
    if (!request) {
        static BOOL said;
        if (!said) {
            said = YES;
            PFBDebugLog(@"[location] no web session: no country asked");
        }
        return;
    }
    // The country comes back in the language Twitter shows.
    NSString* language = [NSBundle mainBundle].preferredLocalizations.firstObject ?: @"en";
    [request setValue:[language substringToIndex:MIN((NSUInteger)2, language.length)]
        forHTTPHeaderField:@"x-twitter-client-language"];
    [gPFBLocationsAsked addObject:handle];
    [[[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                                     ? ((NSHTTPURLResponse*)response).statusCode
                                     : 0;
              NSString* country = status == 200 ? PFBCountryFromAnswer(data) : nil;
              dispatch_async(dispatch_get_main_queue(), ^{
                static BOOL answered, refused;
                if (status == 200 && !answered) {
                    answered = YES;
                    PFBDebugLog(@"[location] about-account answered: @%@ -> %@", handle,
                                country ?: @"no country");
                } else if (status != 200 && !refused) {
                    refused = YES;
                    PFBDebugLog(@"[location] about-account http=%ld%@ for @%@", (long)status,
                                error ? [@" " stringByAppendingString:error.localizedDescription] : @"",
                                handle);
                }
                PFBSettleCountry(handle, country, status != 200);
              });
          }] resume];
}

// The footer's time with the country after it. The time as Twitter wrote it is kept on
// the item, so a second pass never adds the country twice.
static BOOL PFBComposeFooterTime(T1ConversationFooterItem* item, NSString* country) {
    NSString* current = item.timeAgo;
    if (!current.length) {
        return NO;
    }
    NSArray<NSString*>* pair = objc_getAssociatedObject(item, kPFBFooterTimeKey);
    NSString* original = [pair.lastObject isEqualToString:current] ? pair.firstObject : current;
    NSString* composed =
        country.length ? [NSString stringWithFormat:@"%@ · %@", original, country] : original;
    if (![composed isEqualToString:current]) {
        [item setTimeAgo:composed];
    }
    objc_setAssociatedObject(item, kPFBFooterTimeKey, @[original, composed],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (country.length) {
        gPFBCountryShown = YES;
    }
    return country.length > 0;
}

// Puts back the time as Twitter wrote it on an item that still shows a country.
static void PFBRestoreFooterTime(T1ConversationFooterItem* item) {
    NSArray<NSString*>* pair = item ? objc_getAssociatedObject(item, kPFBFooterTimeKey) : nil;
    if (!pair) {
        return;
    }
    if ([pair.lastObject isEqualToString:item.timeAgo]) {
        [item setTimeAgo:pair.firstObject];
    }
    objc_setAssociatedObject(item, kPFBFooterTimeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Lives as long as its footer and redraws it when its author's country arrives.
@interface PFBFooterRefresher : NSObject
@property (nonatomic, weak) T1ConversationFooterTextView* footer;
@property (nonatomic, copy) NSString* handle;
@property (nonatomic, strong) id token;
@end

@implementation PFBFooterRefresher

- (void)dealloc {
    if (_token) {
        [[NSNotificationCenter defaultCenter] removeObserver:_token];
    }
}

@end

static void PFBRefreshFooterOnArrival(T1ConversationFooterTextView* footer, NSString* handle) {
    PFBFooterRefresher* refresher = objc_getAssociatedObject(footer, kPFBFooterRefresherKey);
    if (!refresher) {
        refresher = [PFBFooterRefresher new];
        refresher.footer = footer;
        __weak PFBFooterRefresher* weakRefresher = refresher;
        refresher.token = [[NSNotificationCenter defaultCenter]
            addObserverForName:kPFBAccountLocationNote
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
                        PFBFooterRefresher* strong = weakRefresher;
                        T1ConversationFooterTextView* view = strong.footer;
                        if (view && [note.object isEqual:strong.handle]) {
                            [view updateFooterTextView];
                            [view setNeedsLayout];
                        }
                    }];
        objc_setAssociatedObject(footer, kPFBFooterRefresherKey, refresher,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    refresher.handle = handle;
}

%hook T1ConversationFooterTextView

// The footer text is rebuilt from the item's time here, so the country goes in first.
- (void)updateFooterTextView {
    if (![PFBSettings boolForKey:@"show_account_location"]) {
        if (gPFBCountryShown && [self respondsToSelector:@selector(footerItem)] &&
            [self.footerItem isKindOfClass:%c(T1ConversationFooterItem)]) {
            PFBRestoreFooterTime(self.footerItem);
        }
        PFBCOMPAT_OBSERVE(PFBCompat_show_account_location, @"Tweet footer found");
        %orig;
        return;
    }
    NSString* handle = PFBFooterHandle(self);
    T1ConversationFooterItem* item =
        [self respondsToSelector:@selector(footerItem)] ? self.footerItem : nil;
    if (!handle || ![item isKindOfClass:%c(T1ConversationFooterItem)]) {
        %orig;
        return;
    }
    PFBRefreshFooterOnArrival(self, handle);
    NSString* country = [gPFBLocations objectForKey:handle];
    if (!country) {
        PFBAskForCountry(handle);
    }
    // With the option on, only a country shown proves it. Without a web session the
    // sheet counts the option as off, and the footer reached is its proof.
    if (PFBComposeFooterTime(item, country)) {
        PFBCOMPAT_ACTION(PFBCompat_show_account_location, @"country after the time");
    } else if (!PFBHasUsableWebCredentials()) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_account_location, @"Tweet footer found");
    }
    %orig;
}

%end

%ctor {
    gPFBLocations = [NSCache new];
    gPFBLocations.countLimit = 500;
    gPFBLocationsAsked = [NSMutableSet set];
    gPFBLocationFailures = [NSMutableDictionary dictionary];
    %init;
}
