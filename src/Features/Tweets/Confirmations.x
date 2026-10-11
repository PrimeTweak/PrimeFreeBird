// Confirmation alerts before tweeting, following and liking, and the undo window
// after a tweet.

#import "Support/HookHelpers.h"

// Asks before an action, with a title that names it and a button that does it.
static void ShowConfirmation(NSString* titleKey, NSString* actionKey, void (^confirmed)(void)) {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:titleKey]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    UIAlertAction* confirm = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:actionKey]
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction* action) {
                                                        confirmed();
                                                    }];
    [alert addAction:confirm];
    alert.preferredAction = confirm;
    [topMostController() presentViewController:alert animated:YES completion:nil];
}

// MARK: - Tweet confirm

// All send paths funnel through this. Some callers send no argument, so the
// button register can hold garbage and must not be retained.
%hook T1TweetComposeViewController

- (void)_t1_didTapSendButton:(__unsafe_unretained UIButton*)sendButton {
    if (![PFBSettings boolForKey:@"tweet_confirm"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_tweet_confirm, @"Tweet sent");
        return %orig;
    }
    PFBCOMPAT_ACTION(PFBCompat_tweet_confirm, @"compose send");
    ShowConfirmation(@"CONFIRM_TWEET_TITLE", @"CONFIRM_TWEET_ACTION", ^{
        %orig;
    });
}

%end

// The profile page uses this button, and it also drives unfollow, which Twitter
// confirms on its own. Only a tap that will follow (state 0 = not following) is
// confirmed here.
%hook TUIFollowButtonV2

- (void)buttonTapped {
    id button = (id)self;
    SEL stateSel = @selector(followState);
    NSInteger state = ([button respondsToSelector:stateSel])
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(button, stateSel) : -1;
    if (![PFBSettings boolForKey:@"follow_confirm"] || state != 0) {
        return %orig;
    }
    PFBCOMPAT_ACTION(PFBCompat_follow_confirm, @"profile button");
    ShowConfirmation(@"CONFIRM_FOLLOW_TITLE", @"CONFIRM_FOLLOW_ACTION", ^{
        %orig;
    });
}

%end

// Replies sent from the bar under a Tweet go through this rather than the
// compose screen's send button, so the confirmation is wired here too.
%hook T1PersistentComposeViewController

- (void)_t1_sendReply {
    if (![PFBSettings boolForKey:@"tweet_confirm"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_tweet_confirm, @"Tweet sent");
        return %orig;
    }
    PFBCOMPAT_ACTION(PFBCompat_tweet_confirm, @"reply bar");
    ShowConfirmation(@"CONFIRM_TWEET_TITLE", @"CONFIRM_TWEET_ACTION", ^{
        %orig;
    });
}

%end

// MARK: - Follow confirm

%hook TUIFollowControl

- (void)_followUser:(id)sender event:(id)event {
    if ([PFBSettings boolForKey:@"follow_confirm"]) {
        PFBCOMPAT_ACTION(PFBCompat_follow_confirm, @"tweet button");
    }
    if (![PFBSettings boolForKey:@"follow_confirm"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_follow_confirm, @"follow tapped");
        return %orig;
    }

    ShowConfirmation(@"CONFIRM_FOLLOW_TITLE", @"CONFIRM_FOLLOW_ACTION", ^{
        %orig;
    });
}

%end

// MARK: - Like confirm

// Whether the Tweet already shows as liked, read only when its view model answers with
// a BOOL.
static BOOL PFBShowsAsLiked(id viewModel) {
    SEL liked = NSSelectorFromString(@"displayAsFavorited");
    if (![viewModel respondsToSelector:liked] ||
        strcmp([viewModel methodSignatureForSelector:liked].methodReturnType, @encode(BOOL)) != 0) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(viewModel, liked);
}

// didTap on every inline action button routes through this delegate method,
// so only intercept the favorite button. Taking a like back is not asked about.
%hook TTAStatusInlineActionsView

- (void)didTapInlineActionButton:(UIView*)button {
    if (![button isKindOfClass:%c(TTAStatusInlineFavoriteButton)]) {
        return %orig;
    }
    if (![PFBSettings boolForKey:@"like_confirm"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_like_confirm, @"like tapped");
        return %orig;
    }
    if (PFBShowsAsLiked(self.viewModel)) {
        return %orig;
    }

    PFBCOMPAT_ACTION(PFBCompat_like_confirm, @"inline like");
    ShowConfirmation(@"CONFIRM_LIKE_TITLE", @"CONFIRM_LIKE_ACTION", ^{
        %orig;
    });
}

%end

// Double tap to like in the immersive video player; the gesture never unlikes.
%hook _TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView

- (void)handleDoubleTap:(id)gesture {
    if (![PFBSettings boolForKey:@"like_confirm"]) {
        return %orig;
    }

    ShowConfirmation(@"CONFIRM_LIKE_TITLE", @"CONFIRM_LIKE_ACTION", ^{
        %orig;
    });
}

%end

// MARK: - Undo tweet

// A timeout of 0 disables undo; any positive value is the delay in seconds.
static BOOL UndoTweetEnabled(void) {
    return [PFBSettings integerForKey:@"undo_tweet_timeout"] > 0;
}

// The undo delay: YES with the timeout in seconds written to `interval` when undo is
// on, counted as the option acting; NO when it is off, with the read noted.
static BOOL PFBUndoTweetInterval(double* interval) {
    if (UndoTweetEnabled()) {
        NSInteger seconds = [PFBSettings integerForKey:@"undo_tweet_timeout"];
        PFBCOMPAT_ACTION(PFBCompat_undo_tweet_timeout, @"%ld s to undo", (long)seconds);
        *interval = (double)seconds;
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_undo_tweet_timeout, @"read by Twitter");
    return NO;
}

// Forces every composition onto the premium undo path, an outbox timer with no cap,
// where the free path is a toast capped at 10 s. Config access and the per-type
// toggles mark it undoable, and undoTimeInterval becomes the send delay.
%hook T1UndoSendConfig

- (BOOL)hasAccessToUndoSend {
    if (UndoTweetEnabled()) {
        PFBCOMPAT_ACTION(PFBCompat_undo_tweet_timeout, @"undo access given");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_undo_tweet_timeout, @"read by Twitter");
    return %orig;
}

- (double)undoTimeInterval {
    double interval;
    if (PFBUndoTweetInterval(&interval)) {
        return interval;
    }
    return %orig;
}

- (BOOL)isUndoSendTurnedOnForOriginalTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForReplyTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForQuoteTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForTweetstormTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForPollTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

%end

// The composer bakes the config's interval onto the composition; override the
// read too so the coordinator's send timer uses the chosen value.
%hook TFNTwitterComposition

- (double)undoTimeInterval {
    double interval;
    if (PFBUndoTweetInterval(&interval)) {
        return interval;
    }
    return %orig;
}

// The original computes this from the interval directly, bypassing the getter.
- (NSDate*)undoableSendDate {
    if (!UndoTweetEnabled()) {
        return %orig;
    }
    NSDate* added = [self undoableAddedDate];
    return added ? [added dateByAddingTimeInterval:[self undoTimeInterval]] : nil;
}

%end
