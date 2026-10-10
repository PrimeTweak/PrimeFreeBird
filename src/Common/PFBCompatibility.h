// Compatibility report: every option counts what it does and which of its paths ran,
// kept across tweak builds of one Twitter version, and the report checks that Twitter
// still has what each option relies on.
#import <UIKit/UIKit.h>
#import "Common/PFBCompatResult.h"

typedef NS_ENUM(NSInteger, PFBCompatOption) {
    PFBCompatOptionNone = -1,
    PFBCompat_padlock,
    PFBCompat_no_screenshot_detection,
    PFBCompat_force_following_tab,
    PFBCompat_no_focus_lost,
    PFBCompat_no_tab_bar_hiding,
    PFBCompat_show_scroll_indicator,
    PFBCompat_disable_rtl,
    PFBCompat_hide_premium_offer,
    PFBCompat_sharing_domain,
    PFBCompat_strip_url_tracking,
    PFBCompat_always_open_safari,
    PFBCompat_new_inapp_webview,
    PFBCompat_restore_tab_labels,
    PFBCompat_custom_fonts,
    PFBCompat_tab_bar_theming,
    PFBCompat_color_pfb_switches,
    PFBCompat_color_twitter_icon_in_top_bar,
    PFBCompat_hide_promoted,
    PFBCompat_hide_who_to_follow,
    PFBCompat_hide_topics_to_follow,
    PFBCompat_hide_timeline_prompts,
    PFBCompat_hide_topics,
    PFBCompat_hide_verified_tweets,
    PFBCompat_hide_blocked_retweets,
    PFBCompat_reading_line,
    PFBCompat_hide_spaces,
    PFBCompat_hide_new_tweets_pill,
    PFBCompat_hide_scroll_edge_blur,
    PFBCompat_hide_custom_timelines,
    PFBCompat_unlimited_timeline_tabs,
    PFBCompat_undo_tweet_timeout,
    PFBCompat_tweet_confirm,
    PFBCompat_hide_tweet_button,
    PFBCompat_hide_threads,
    PFBCompat_like_confirm,
    PFBCompat_hide_view_count,
    PFBCompat_hide_bookmark_button,
    PFBCompat_hide_downvote_button,
    PFBCompat_show_poll_results,
    PFBCompat_disable_sensitive_tweet_warnings,
    PFBCompat_bypass_age_verification,
    PFBCompat_reply_sorting,
    PFBCompat_restore_reply_context,
    PFBCompat_download_videos,
    PFBCompat_download_highest_quality,
    PFBCompat_direct_save,
    PFBCompat_tweet_to_image,
    PFBCompat_tap_to_pause,
    PFBCompat_restore_video_timestamp,
    PFBCompat_disable_video_captions,
    PFBCompat_disable_immersive_scroll,
    PFBCompat_disable_video_docking,
    PFBCompat_auto_highest_load,
    PFBCompat_enable_image_preloading,
    PFBCompat_force_tweet_full_frame,
    PFBCompat_disable_media_carousel,
    PFBCompat_upload_full_hd_videos,
    PFBCompat_follow_confirm,
    PFBCompat_expand_bio,
    PFBCompat_copy_profile_info,
    PFBCompat_disable_articles,
    PFBCompat_disable_highlights,
    PFBCompat_disable_videos_tab,
    PFBCompat_hide_blue_verified,
    PFBCompat_hide_follow_button,
    PFBCompat_hide_message_button,
    PFBCompat_restore_follow_button,
    PFBCompat_square_avatars,
    PFBCompat_no_history,
    PFBCompat_advanced_search,
    PFBCompat_hide_trend_videos,
    PFBCompat_hide_explore_all,
    PFBCompat_choose_explore_tabs,
    PFBCompat_hide_typing_indicator,
    PFBCompat_voice_transcription,
    PFBCompat_download_voice_messages,
    PFBCompat_voice_note_from_video,
    PFBCompat_hide_grok_analyze,
    PFBCompat_hide_grok_sidebar,
    PFBCompat_hide_grok_bot,
    PFBCompat_hide_grok_create,
    PFBCompat_disable_auto_translate,
    PFBCompat_restore_twitter_names,
    PFBCompat_refresh_pill_label,
    PFBCompat_restore_tweet_button,
    PFBCompat_restore_refresh_sounds,
    PFBCompat_reply_in_webview,
    PFBCompat_flex_twitter,
    PFBCompat_hide_notifications,
    PFBCompat_enable_liquid_glass,
    PFBCompat_dark_mode_style,
    PFBCompat_accent_color,
    PFBCompat_muted_words,
    PFBCompat_profile_initial_tab,
    PFBCompat_web_session,
    PFBCompat_unrounded_counts,
    PFBCompat_show_quote_counts,
    PFBCompat_send_sound,
    PFBCompat_show_account_location,
    PFBCompat_custom_tab_bar,
    PFBCompatOptionCount,
};

typedef NS_ENUM(NSInteger, PFBCompatReadState) {
    PFBCompatReadPending,
    PFBCompatReadDone,
    PFBCompatReadFailed,
};

@interface PFBCompatibilityReportViewController : UITableViewController
@end

// Posted on the main queue whenever the verdicts may have changed.
FOUNDATION_EXPORT NSNotificationName const PFBCompatDidChangeNotification;
// The preference behind the Report row's status.
FOUNDATION_EXPORT NSString* const PFBCompatStatusKey;
// Where the read of Twitter's binaries stands on this install.
FOUNDATION_EXPORT PFBCompatReadState PFBCompatReadStatus(void);

FOUNDATION_EXPORT void PFBCompatCount(PFBCompatOption option);
FOUNDATION_EXPORT BOOL PFBCompatWantsDetail(PFBCompatOption option);
FOUNDATION_EXPORT void PFBCompatSetDetail(PFBCompatOption option, NSString* detail);

FOUNDATION_EXPORT void PFBCompatReset(void);
FOUNDATION_EXPORT void PFBCompatRefreshStatus(void);
FOUNDATION_EXPORT NSArray<PFBCompatResult*>* PFBCompatResults(void);
FOUNDATION_EXPORT NSString* PFBCompatSummary(NSArray<PFBCompatResult*>* results);
FOUNDATION_EXPORT NSString* PFBCompatStatusText(void);
FOUNDATION_EXPORT NSString* PFBCompatInstallText(void);
FOUNDATION_EXPORT NSString* PFBCompatReportText(void);

// Settings Twitter reads while the debugger records, with a count of reads: they
// mark the leads Twitter actually reads.
FOUNDATION_EXPORT void PFBCompatNoteSettingRead(NSString* key);
FOUNDATION_EXPORT NSDictionary<NSString*, NSNumber*>* PFBCompatSettingsRead(void);

// Counts one action for an option. The detail is only formatted for the first
// action of an install, so the call stays cheap on paths that run constantly.
#define PFBCOMPAT_ACTION(option, ...)                                              \
    do {                                                                           \
        PFBCompatCount(option);                                                    \
        if (PFBCompatWantsDetail(option))                                          \
            PFBCompatSetDetail((option), [NSString stringWithFormat:__VA_ARGS__]); \
    } while (0)

FOUNDATION_EXPORT BOOL PFBCompatNeedsObservation(PFBCompatOption option);
FOUNDATION_EXPORT void PFBCompatObserve(PFBCompatOption option, NSString* detail);

// Notes, once per launch, that an option which is off would have acted here:
// proof that what it relies on still works, without turning it on.
#define PFBCOMPAT_OBSERVE(option, ...)                                             \
    do {                                                                           \
        if (PFBCompatNeedsObservation(option))                                     \
            PFBCompatObserve((option), [NSString stringWithFormat:__VA_ARGS__]);   \
    } while (0)

// Paths of options that act in more than one place. Each is noted when reached,
// whether the option is on or off, and the report names the ones not seen.
typedef NS_ENUM(NSInteger, PFBCompatPath) {
    PFBCompatPath_grok_bot_sidebar,
    PFBCompatPath_grok_bot_upsells,
    PFBCompatPath_grok_bot_home_header,
    PFBCompatPath_grok_bot_home_hero,
    PFBCompatPath_grok_bot_preset,
    PFBCompatPath_grok_bot_tab_icon,
    PFBCompatPath_tab_bar,
    PFBCompatPath_native_tab_bar,
    PFBCompatPath_top_tab_underline,
    PFBCompatPath_pull_sound,
    PFBCompatPath_refresh_end_sound,
    PFBCompatPath_copy_button,
    PFBCompatPath_copy_id_and_date,
    PFBCompatPath_follower_counts,
    PFBCompatPath_post_count,
    PFBCompatPath_verified_search,
    PFBCompatPath_verified_edit_history,
    PFBCompatPath_promoted_video_feed,
    PFBCompatPath_download_all,
    PFBCompatPath_web_mutes,
    PFBCompatPath_web_grok,
    PFBCompatPath_web_pages,
    PFBCompatPath_tab_badges,
    PFBCompatPathCount,
};

FOUNDATION_EXPORT void PFBCompatReach(PFBCompatPath path);
FOUNDATION_EXPORT BOOL PFBCompatPathReached(PFBCompatPath path);

// Shows Twitter's own screens one after another so the report proves the paths they
// carry, whatever the toggles say, then opens the report.
FOUNDATION_EXPORT void PFBCompatRunTour(void);
// The same tour, limited to the screens whose options this build has not proven yet.
FOUNDATION_EXPORT void PFBCompatRunTourLeft(void);
// While a tour drives the app, hooks keep it inside Twitter.
FOUNDATION_EXPORT BOOL PFBCompatTourIsRunning(void);
// The screens a full tour shows, or those still owing proofs on this build.
FOUNDATION_EXPORT NSUInteger PFBCompatTourScreens(BOOL full);
// The last tour in one line for the report, or nil when none has run on this build.
FOUNDATION_EXPORT NSString* PFBCompatTourLastRun(void);
// Asks for a tour at the next launch, as a new install would need one.
FOUNDATION_EXPORT void PFBCompatScheduleTourAtLaunch(void);

// A tour step's pending proofs on this build: option keys, and "path:" plus a path name.
FOUNDATION_EXPORT NSSet<NSString*>* PFBCompatStationPending(NSString* station);
FOUNDATION_EXPORT BOOL PFBCompatStationLeft(NSString* station);
// Whether a step showed its screen, and what it still missed then.
FOUNDATION_EXPORT void PFBCompatStationRecord(NSString* station, BOOL reached, NSSet<NSString*>* missed);
// A step during which Twitter closed: left out of the tours until a new build.
FOUNDATION_EXPORT void PFBCompatStationRecordCrash(NSString* station);
FOUNDATION_EXPORT BOOL PFBCompatStationCrashed(NSString* station);
// stop is nil for a tour that ran to its end, or says why it stopped.
FOUNDATION_EXPORT void PFBCompatTourRecord(BOOL full, NSString* stop, NSArray<NSString*>* results);
// A line of the tour's journal, kept in a file that outlives a crash, and the whole
// journal of the last tour for the report.
FOUNDATION_EXPORT void PFBCompatTourLog(NSString* format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT NSString* PFBCompatTourJournalText(void);
// This tweak build's identifier, so a stopped tour is charged to the build it ran on.
FOUNDATION_EXPORT NSString* PFBCompatBuildID(void);
// A new Twitter binary is installed and no full tour has run on it yet.
FOUNDATION_EXPORT BOOL PFBCompatCheckIsDue(void);
