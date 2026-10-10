// Quote and Retweet counts: both numbers, in full, as the title of the screen a
// Tweet's Quotes, Retweets and Likes counts open.

#import "Support/HookHelpers.h"
#import "Debug/PFBDebugger.h"

// Both counts in full, grouped the way the user's locale writes numbers.
static NSString* PFBQuoteCountsTitle(TFNTwitterStatus* status) {
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [NSString stringWithFormat:[[PFBBundle sharedBundle] localizedStringForKey:@"QUOTE_COUNTS_TITLE_FORMAT"],
                                      [formatter stringFromNumber:@(status.quoteCount)],
                                      [formatter stringFromNumber:@(status.retweetCount)]];
}

// Twitter also builds this screen without its class factory, so the Tweet is read from
// the screen's own Swift properties, which every way of building it fills.
%hook T1PostInteractionsViewController

- (void)viewDidLoad {
    %orig;
    if (![PFBSettings boolForKey:@"show_quote_counts"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_show_quote_counts, @"interactions screen opened");
        return;
    }
    Class screenClass = object_getClass(self);
    Ivar accountIvar = class_getInstanceVariable(screenClass, "account");
    Ivar statusIvar = class_getInstanceVariable(screenClass, "statusID");
    TFNTwitterAccount* account = accountIvar ? object_getIvar(self, accountIvar) : nil;
    TFNTwitterAccountModel* model = [account respondsToSelector:@selector(model)] ? account.model : nil;
    if (!statusIvar || ![model respondsToSelector:@selector(lookUpStatusForID:completionBlock:)]) {
        static BOOL said;
        if (!said) {
            said = YES;
            PFBDebugLog(@"[quotecounts] %@ gives no account model or Tweet ID: counts left out",
                        NSStringFromClass(screenClass));
        }
        return;
    }
    // A Swift Int64, stored in place.
    int64_t statusID = *(int64_t*)((uint8_t*)(__bridge void*)self + ivar_getOffset(statusIvar));
    __weak UIViewController* weakScreen = self;
    [model lookUpStatusForID:statusID
             completionBlock:^(TFNTwitterStatus* status) {
                 dispatch_block_t show = ^{
                     UIViewController* screen = weakScreen;
                     if (!screen.isViewLoaded) {
                         return;
                     }
                     if (![status respondsToSelector:@selector(quoteCount)] ||
                         ![status respondsToSelector:@selector(retweetCount)]) {
                         PFBDebugLog(@"[quotecounts] Tweet %lld not found: Twitter's title kept", statusID);
                         return;
                     }
                     screen.title = PFBQuoteCountsTitle(status);
                     PFBCOMPAT_ACTION(PFBCompat_show_quote_counts, @"counts in the title");
                 };
                 // The title is only set on the main thread, whichever thread runs the block.
                 if (NSThread.isMainThread) {
                     show();
                 } else {
                     dispatch_async(dispatch_get_main_queue(), show);
                 }
             }];
}

%end
