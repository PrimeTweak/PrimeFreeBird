// Tweet source and account location, added after the time in an opened Tweet's footer.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBAboutAccountURL =
    @"https://x.com/i/api/graphql/XRqGa7EeokUU5kppkh13EA/AboutAccountQuery?variables=";
static NSString* const kPFBFooterLabelNote = @"PFBFooterLabelArrived";
static const NSInteger kPFBFooterLabelTries = 3;

static const void* kPFBFooterTimeKey = &kPFBFooterTimeKey;
static const void* kPFBFooterRefresherKey = &kPFBFooterRefresherKey;
// Set once a label has been added to a footer, so the options turned off put times back.
static BOOL gPFBLabelShown;

// One kind of label by key, a handle or a Tweet ID: the answers (an empty string once
// x.com gave none), the keys being asked and the failed tries. Main thread only.
@interface PFBFooterLabels : NSObject
@property (nonatomic, copy) NSString* name;
@property (nonatomic, strong) NSCache<NSString*, NSString*>* answers;
@property (nonatomic, strong) NSMutableSet<NSString*>* asked;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSNumber*>* failures;
@property (nonatomic) NSMutableURLRequest* (*request)(NSString* key);
@property (nonatomic) NSString* (*label)(NSData* data, NSString* key);
@property (nonatomic) BOOL refusalTold;
@property (nonatomic) PFBCompatOption option;
@end

@implementation PFBFooterLabels
@end

static PFBFooterLabels* gPFBCountries;
static PFBFooterLabels* gPFBSources;

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

// The ID of the footer's own Tweet, read as the integer or the object the getter returns.
static NSString* PFBFooterTweetID(T1ConversationFooterTextView* footer) {
    id model = [footer respondsToSelector:@selector(viewModel)] ? footer.viewModel : nil;
    SEL getter = @selector(statusID);
    NSMethodSignature* signature =
        [model respondsToSelector:getter] ? [model methodSignatureForSelector:getter] : nil;
    char type = signature ? signature.methodReturnType[0] : 0;
    long long value = 0;
    if (type == 'q' || type == 'Q' || type == 'l' || type == 'L') {
        value = ((long long (*)(id, SEL))objc_msgSend)(model, getter);
    } else if (type == '@') {
        id object = ((id (*)(id, SEL))objc_msgSend)(model, getter);
        value = [object respondsToSelector:@selector(longLongValue)] ? [object longLongValue] : 0;
    }
    return value > 0 ? [NSString stringWithFormat:@"%lld", value] : nil;
}

// The About this account question for a handle.
static NSMutableURLRequest* PFBCountryRequest(NSString* handle) {
    NSData* variables =
        [NSJSONSerialization dataWithJSONObject:@{@"screenName": handle} options:0 error:nil];
    NSCharacterSet* plain =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString* query = [[[NSString alloc] initWithData:variables encoding:NSUTF8StringEncoding]
        stringByAddingPercentEncodingWithAllowedCharacters:plain];
    NSMutableURLRequest* request =
        PFBWebSessionGETRequest([NSURL URLWithString:[kPFBAboutAccountURL stringByAppendingString:query]]);
    // The country comes back in the language Twitter shows.
    NSString* language = [NSBundle mainBundle].preferredLocalizations.firstObject ?: @"en";
    [request setValue:[language substringToIndex:MIN((NSUInteger)2, language.length)]
        forHTTPHeaderField:@"x-twitter-client-language"];
    return request;
}

// "Canada", or "Canada?" when x.com marks the place as uncertain; nil without a place.
static NSString* PFBCountryFromAnswer(NSData* data, NSString* handle) {
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

// The conversation of one Tweet, which carries the app it was sent from.
static NSMutableURLRequest* PFBSourceRequest(NSString* tweetID) {
    NSString* address = [NSString
        stringWithFormat:@"https://x.com/i/api/2/timeline/conversation/%@.json?tweet_mode=extended&count=1",
                         tweetID];
    return PFBWebSessionGETRequest([NSURL URLWithString:address]);
}

// The visible name in the source markup, as "Twitter for iPhone" in <a href=...>Twitter for iPhone</a>.
static NSString* PFBSourceFromMarkup(id markup) {
    if (![markup isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange open = [markup rangeOfString:@">"];
    NSRange close = [markup rangeOfString:@"</a>"];
    if (open.location == NSNotFound || close.location == NSNotFound || open.location + 1 >= close.location) {
        return nil;
    }
    NSString* name = [[markup substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name.length ? name : nil;
}

// The app a Tweet was sent from, in either form x.com answers the conversation with.
static NSString* PFBSourceFromAnswer(NSData* data, NSString* tweetID) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id tweets = json[@"globalObjects"];
    tweets = [tweets isKindOfClass:[NSDictionary class]] ? tweets[@"tweets"] : nil;
    id tweet = [tweets isKindOfClass:[NSDictionary class]] ? tweets[tweetID] : nil;
    if ([tweet isKindOfClass:[NSDictionary class]]) {
        return PFBSourceFromMarkup(tweet[@"source"]);
    }
    id conversation = json[@"data"];
    conversation = [conversation isKindOfClass:[NSDictionary class]]
                       ? conversation[@"threaded_conversation_with_injections_v2"]
                       : nil;
    id instructions = [conversation isKindOfClass:[NSDictionary class]] ? conversation[@"instructions"] : nil;
    for (id instruction in [instructions isKindOfClass:[NSArray class]] ? instructions : @[]) {
        id entries = [instruction isKindOfClass:[NSDictionary class]] ? instruction[@"entries"] : nil;
        for (id entry in [entries isKindOfClass:[NSArray class]] ? entries : @[]) {
            id result = entry;
            for (NSString* key in @[@"content", @"itemContent", @"tweet_results", @"result"]) {
                result = [result isKindOfClass:[NSDictionary class]] ? result[key] : nil;
            }
            id inner = [result isKindOfClass:[NSDictionary class]] ? result[@"tweet"] : nil;
            id found = [inner isKindOfClass:[NSDictionary class]] ? inner : result;
            if ([found isKindOfClass:[NSDictionary class]] && [found[@"rest_id"] isEqual:tweetID]) {
                return PFBSourceFromMarkup(found[@"source"]);
            }
        }
    }
    return nil;
}

static void PFBAskForLabel(PFBFooterLabels* labels, NSString* key);

// Main thread. A failed answer is asked again twice, then settled as no label; a request
// x.com still refuses then is recorded on the option with its HTTP status.
static void PFBSettleLabel(PFBFooterLabels* labels, NSString* key, NSString* label, NSInteger status) {
    [labels.asked removeObject:key];
    if (status != 200) {
        NSInteger failures = labels.failures[key].integerValue + 1;
        labels.failures[key] = @(failures);
        if (failures < kPFBFooterLabelTries) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                             PFBAskForLabel(labels, key);
                           });
            return;
        }
        if (status > 0) {
            PFBCompatNoteRefusal(labels.option,
                                 [NSString stringWithFormat:@"x.com refused the request (HTTP %ld)", (long)status]);
        }
    }
    [labels.failures removeObjectForKey:key];
    [labels.answers setObject:label ?: @"" forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPFBFooterLabelNote object:key];
}

// Main thread. One question per key at a time, none once it is settled.
static void PFBAskForLabel(PFBFooterLabels* labels, NSString* key) {
    if ([labels.answers objectForKey:key] || [labels.asked containsObject:key]) {
        return;
    }
    NSMutableURLRequest* request = labels.request(key);
    if (!request) {
        static BOOL said;
        if (!said) {
            said = YES;
            PFBDebugLog(@"[footer] no web session: no label asked");
        }
        return;
    }
    [labels.asked addObject:key];
    NSString* (*parse)(NSData*, NSString*) = labels.label;
    [[[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                                     ? ((NSHTTPURLResponse*)response).statusCode
                                     : 0;
              NSString* label = status == 200 ? parse(data, key) : nil;
              dispatch_async(dispatch_get_main_queue(), ^{
                if (status != 200 && !labels.refusalTold) {
                    labels.refusalTold = YES;
                    PFBDebugLog(@"[footer] %@ http=%ld%@ for %@", labels.name, (long)status,
                                error ? [@" " stringByAppendingString:error.localizedDescription] : @"",
                                key);
                }
                PFBSettleLabel(labels, key, label, status);
              });
          }] resume];
}

// The settled label for a key, asked for once while none is known.
static NSString* PFBLabelFor(PFBFooterLabels* labels, NSString* key) {
    NSString* label = [labels.answers objectForKey:key];
    if (!label) {
        PFBAskForLabel(labels, key);
    }
    return label;
}

// The footer's time with the labels after it. The time as Twitter wrote it is kept on
// the item, so a second pass never adds a label twice.
static void PFBComposeFooterTime(T1ConversationFooterItem* item, NSArray<NSString*>* labels) {
    NSString* current = item.timeAgo;
    if (!current.length) {
        return;
    }
    NSArray<NSString*>* pair = objc_getAssociatedObject(item, kPFBFooterTimeKey);
    NSString* original = [pair.lastObject isEqualToString:current] ? pair.firstObject : current;
    NSMutableString* composed = [original mutableCopy];
    for (NSString* label in labels) {
        if (label.length) {
            [composed appendFormat:@" · %@", label];
            gPFBLabelShown = YES;
        }
    }
    if (![composed isEqualToString:current]) {
        [item setTimeAgo:composed];
    }
    objc_setAssociatedObject(item, kPFBFooterTimeKey, @[original, [composed copy]],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Puts back the time as Twitter wrote it on an item that still shows a label.
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

// Lives as long as its footer and redraws it when one of its labels arrives.
@interface PFBFooterRefresher : NSObject
@property (nonatomic, weak) T1ConversationFooterTextView* footer;
@property (nonatomic, copy) NSString* handle;
@property (nonatomic, copy) NSString* tweetID;
@property (nonatomic, strong) id token;
@end

@implementation PFBFooterRefresher

- (void)dealloc {
    if (_token) {
        [[NSNotificationCenter defaultCenter] removeObserver:_token];
    }
}

@end

static void PFBRefreshFooterOnArrival(T1ConversationFooterTextView* footer, NSString* handle,
                                      NSString* tweetID) {
    PFBFooterRefresher* refresher = objc_getAssociatedObject(footer, kPFBFooterRefresherKey);
    if (!refresher) {
        refresher = [PFBFooterRefresher new];
        refresher.footer = footer;
        __weak PFBFooterRefresher* weakRefresher = refresher;
        refresher.token = [[NSNotificationCenter defaultCenter]
            addObserverForName:kPFBFooterLabelNote
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* note) {
                        PFBFooterRefresher* strong = weakRefresher;
                        T1ConversationFooterTextView* view = strong.footer;
                        if (view && ([note.object isEqual:strong.handle] || [note.object isEqual:strong.tweetID])) {
                            [view updateFooterTextView];
                            [view setNeedsLayout];
                        }
                    }];
        objc_setAssociatedObject(footer, kPFBFooterRefresherKey, refresher,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    refresher.handle = handle;
    refresher.tweetID = tweetID;
}

%hook T1ConversationFooterTextView

// The footer text is rebuilt from the item's time here, so the labels go in first.
- (void)updateFooterTextView {
    BOOL wantsSource = [PFBSettings boolForKey:@"show_tweet_source"];
    BOOL wantsCountry = [PFBSettings boolForKey:@"show_account_location"];
    T1ConversationFooterItem* item =
        [self respondsToSelector:@selector(footerItem)] ? self.footerItem : nil;
    if (![item isKindOfClass:%c(T1ConversationFooterItem)]) {
        item = nil;
    }
    if (!wantsSource) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_tweet_source, @"Tweet footer found");
    }
    if (!wantsCountry) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_account_location, @"Tweet footer found");
    }
    if (!wantsSource && !wantsCountry) {
        if (gPFBLabelShown && item) {
            PFBRestoreFooterTime(item);
        }
        %orig;
        return;
    }
    NSString* tweetID = wantsSource ? PFBFooterTweetID(self) : nil;
    NSString* handle = wantsCountry ? PFBFooterHandle(self) : nil;
    if (!item || (!tweetID && !handle)) {
        %orig;
        return;
    }
    PFBRefreshFooterOnArrival(self, handle, tweetID);
    NSString* source = tweetID ? PFBLabelFor(gPFBSources, tweetID) : nil;
    NSString* country = handle ? PFBLabelFor(gPFBCountries, handle) : nil;
    PFBComposeFooterTime(item, @[source ?: @"", country ?: @""]);
    // With an option on, only its label shown proves it. Without a web session the
    // sheet counts the option as off, and the footer reached is its proof.
    BOOL session = PFBHasUsableWebCredentials();
    if (source.length) {
        PFBCOMPAT_ACTION(PFBCompat_show_tweet_source, @"source after the time");
    } else if (wantsSource && !session) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_tweet_source, @"Tweet footer found");
    }
    if (country.length) {
        PFBCOMPAT_ACTION(PFBCompat_show_account_location, @"country after the time");
    } else if (wantsCountry && !session) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_account_location, @"Tweet footer found");
    }
    %orig;
}

%end

static PFBFooterLabels* PFBMakeFooterLabels(NSString* name, PFBCompatOption option,
                                            NSMutableURLRequest* (*request)(NSString*),
                                            NSString* (*label)(NSData*, NSString*)) {
    PFBFooterLabels* labels = [PFBFooterLabels new];
    labels.name = name;
    labels.option = option;
    labels.answers = [NSCache new];
    labels.answers.countLimit = 500;
    labels.asked = [NSMutableSet set];
    labels.failures = [NSMutableDictionary dictionary];
    labels.request = request;
    labels.label = label;
    return labels;
}

%ctor {
    gPFBSources = PFBMakeFooterLabels(@"conversation", PFBCompat_show_tweet_source, PFBSourceRequest,
                                      PFBSourceFromAnswer);
    gPFBCountries = PFBMakeFooterLabels(@"about-account", PFBCompat_show_account_location, PFBCountryRequest,
                                        PFBCountryFromAnswer);
    %init;
}
