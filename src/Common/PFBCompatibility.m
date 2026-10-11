// Option metadata and requirements follow the hook manifest, the feature-switch table
// follows FeatureSwitches.x, and the logic is hand-written.
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Common/PFBSettings.h"
#import "Common/PFBBundle.h"
#import <ctype.h>
#import <dlfcn.h>
#import <libkern/OSByteOrder.h>
#import <mach-o/dyld.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <os/lock.h>
#import "Support/Generated/PFBHookManifest.h"
#import "Features/Appearance/ThemeColor/PFBDarkModeStyle.h"
#import "Support/HookHelpers.h"

NSNotificationName const PFBCompatDidChangeNotification = @"PFBCompatDidChangeNotification";

// Theme.x: whether an accent color is set.
extern BOOL PFBAccentIsActive(void);

typedef struct {
    PFBCompatOption option;
    const char* key;
    const char* titleKey;  // localized at runtime, so renames reach the report
    const char* pageKey;
    BOOL alwaysOn;  // no toggle: the behavior is always active
} PFBCompatMeta;

static const PFBCompatMeta kMeta[] = {
    {PFBCompat_padlock, "padlock", "PADLOCK_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_no_screenshot_detection, "no_screenshot_detection", "NO_SCREENSHOT_DETECTION_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_force_following_tab, "force_following_tab", "FORCE_FOLLOWING_TAB_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_no_focus_lost, "no_focus_lost", "NO_FOCUS_LOST_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_no_tab_bar_hiding, "no_tab_bar_hiding", "NO_TAB_BAR_HIDING_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_show_scroll_indicator, "show_scroll_indicator", "SHOW_SCROLL_INDICATOR_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_disable_rtl, "disable_rtl", "DISABLE_RTL_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_hide_premium_offer, "hide_premium_offer", "HIDE_PREMIUM_OFFER_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_hide_notifications, "hide_notifications", "HIDE_NOTIFICATIONS_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_sharing_domain, "sharing_domain", "SHARING_DOMAIN_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_strip_url_tracking, "strip_url_tracking", "STRIP_URL_TRACKING_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_always_open_safari, "always_open_safari", "ALWAYS_OPEN_SAFARI_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_new_inapp_webview, "new_inapp_webview", "NEW_INAPP_WEBVIEW_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_custom_tab_bar, "custom_tab_bar", "CUSTOM_TAB_BAR_OPTION_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE", YES},
    {PFBCompat_restore_tab_labels, "restore_tab_labels", "RESTORE_TAB_LABELS_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_custom_fonts, "custom_fonts", "CUSTOM_FONTS_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_tab_bar_theming, "tab_bar_theming", "TAB_BAR_THEMING_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_color_pfb_switches, "color_pfb_switches", "COLOR_PFB_SWITCHES_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_color_twitter_icon_in_top_bar, "color_twitter_icon_in_top_bar", "COLOR_TWITTER_ICON_IN_TOP_BAR_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_enable_liquid_glass, "enable_liquid_glass", "INTERFACE_STYLE_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_dark_mode_style, "dark_mode_style", "DARK_MODE_STYLE_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_accent_color, "accent_color", "THEME_OPTION_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_hide_promoted, "hide_promoted", "HIDE_PROMOTED_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_who_to_follow, "hide_who_to_follow", "HIDE_WHO_TO_FOLLOW_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_topics_to_follow, "hide_topics_to_follow", "HIDE_TOPICS_TO_FOLLOW_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_timeline_prompts, "hide_timeline_prompts", "HIDE_TIMELINE_PROMPTS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_topics, "hide_topics", "HIDE_TOPICS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_verified_tweets, "hide_verified_tweets", "HIDE_VERIFIED_TWEETS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_blocked_retweets, "hide_blocked_retweets", "HIDE_BLOCKED_RETWEETS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_reading_line, "reading_line", "READING_LINE_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_spaces, "hide_spaces", "HIDE_SPACES_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_new_tweets_pill, "hide_new_tweets_pill", "HIDE_NEW_TWEETS_PILL_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_scroll_edge_blur, "hide_scroll_edge_blur", "HIDE_SCROLL_EDGE_BLUR_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_custom_timelines, "hide_custom_timelines", "HIDE_CUSTOM_TIMELINES_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_unlimited_timeline_tabs, "unlimited_timeline_tabs", "UNLIMITED_TIMELINE_TABS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_muted_words, "muted_words", "FILTERS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_undo_tweet_timeout, "undo_tweet_timeout", "UNDO_TWEET_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_tweet_confirm, "tweet_confirm", "TWEET_CONFIRM_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_tweet_button, "hide_tweet_button", "HIDE_TWEET_BUTTON_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_send_sound, "send_sound", "SEND_SOUND_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_threads, "hide_threads", "HIDE_THREADS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_like_confirm, "like_confirm", "LIKE_CONFIRM_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_view_count, "hide_view_count", "HIDE_VIEW_COUNT_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_bookmark_button, "hide_bookmark_button", "HIDE_BOOKMARK_BUTTON_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_downvote_button, "hide_downvote_button", "HIDE_DOWNVOTE_BUTTON_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_poll_results, "show_poll_results", "SHOW_POLL_RESULTS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_disable_sensitive_tweet_warnings, "disable_sensitive_tweet_warnings", "DISABLE_SENSITIVE_TWEET_WARNINGS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_bypass_age_verification, "bypass_age_verification", "BYPASS_AGE_VERIFICATION_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_reply_sorting, "reply_sorting", "REPLY_SORTING_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_restore_reply_context, "restore_reply_context", "RESTORE_REPLY_CONTEXT_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_quote_counts, "show_quote_counts", "SHOW_QUOTE_COUNTS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_account_location, "show_account_location", "SHOW_ACCOUNT_LOCATION_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_download_videos, "download_videos", "DOWNLOAD_VIDEOS_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_download_highest_quality, "download_highest_quality", "DOWNLOAD_HIGHEST_QUALITY_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_direct_save, "direct_save", "DIRECT_SAVE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_tweet_to_image, "tweet_to_image", "TWEET_TO_IMAGE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_tap_to_pause, "tap_to_pause", "TAP_TO_PAUSE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_restore_video_timestamp, "restore_video_timestamp", "RESTORE_VIDEO_TIMESTAMP_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_video_captions, "disable_video_captions", "DISABLE_VIDEO_CAPTIONS_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_immersive_scroll, "disable_immersive_scroll", "DISABLE_IMMERSIVE_SCROLL_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_video_docking, "disable_video_docking", "DISABLE_VIDEO_DOCKING_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_auto_highest_load, "auto_highest_load", "AUTO_HIGHEST_LOAD_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_enable_image_preloading, "enable_image_preloading", "ENABLE_IMAGE_PRELOADING_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_force_tweet_full_frame, "force_tweet_full_frame", "FORCE_TWEET_FULL_FRAME_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_media_carousel, "disable_media_carousel", "DISABLE_MEDIA_CAROUSEL_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_upload_full_hd_videos, "upload_full_hd_videos", "UPLOAD_FULL_HD_VIDEOS_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_follow_confirm, "follow_confirm", "FOLLOW_CONFIRM_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_expand_bio, "expand_bio", "EXPAND_BIO_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_copy_profile_info, "copy_profile_info", "COPY_PROFILE_INFO_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_unrounded_counts, "unrounded_counts", "UNROUNDED_COUNTS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE", YES},
    {PFBCompat_disable_articles, "disable_articles", "DISABLE_ARTICLES_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_disable_highlights, "disable_highlights", "DISABLE_HIGHLIGHTS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_disable_videos_tab, "disable_videos_tab", "DISABLE_VIDEOS_TAB_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_hide_blue_verified, "hide_blue_verified", "HIDE_BLUE_VERIFIED_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_hide_follow_button, "hide_follow_button", "HIDE_FOLLOW_BUTTON_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_hide_message_button, "hide_message_button", "HIDE_MESSAGE_BUTTON_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_restore_follow_button, "restore_follow_button", "RESTORE_FOLLOW_BUTTON_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_square_avatars, "square_avatars", "SQUARE_AVATARS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_profile_initial_tab, "profile_initial_tab", "PROFILE_INITIAL_TAB_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_no_history, "no_history", "NO_HISTORY_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_advanced_search, "advanced_search", "ADVANCED_SEARCH_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_hide_trend_videos, "hide_trend_videos", "HIDE_TREND_VIDEOS_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_hide_explore_all, "hide_explore_all", "HIDE_EXPLORE_ALL_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_choose_explore_tabs, "choose_explore_tabs", "CHOOSE_EXPLORE_TABS_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_hide_typing_indicator, "hide_typing_indicator", "HIDE_TYPING_INDICATOR_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_voice_transcription, "voice_transcription", "VOICE_TRANSCRIPTION_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_download_voice_messages, "download_voice_messages", "DOWNLOAD_VOICE_MESSAGES_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_voice_note_from_video, "voice_note_from_video", "VOICE_NOTE_FROM_VIDEO_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_analyze, "hide_grok_analyze", "HIDE_GROK_ANALYZE_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_sidebar, "hide_grok_sidebar", "HIDE_GROK_SIDEBAR_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_bot, "hide_grok_bot", "HIDE_GROK_BOT_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_create, "hide_grok_create", "HIDE_GROK_CREATE_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_disable_auto_translate, "disable_auto_translate", "DISABLE_AUTO_TRANSLATE_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_restore_twitter_names, "restore_twitter_names", "RESTORE_TWITTER_NAMES_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_refresh_pill_label, "refresh_pill_label", "REFRESH_PILL_LABEL_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_restore_tweet_button, "restore_tweet_button", "RESTORE_TWEET_BUTTON_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_restore_refresh_sounds, "restore_refresh_sounds", "RESTORE_REFRESH_SOUNDS_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_web_session, "web_session", "LAB_GROUP_SESSION", "MODERN_SETTINGS_LAB_TITLE"},
    {PFBCompat_reply_in_webview, "reply_in_webview", "REPLY_IN_WEBVIEW_TITLE", "MODERN_SETTINGS_LAB_TITLE"},
    {PFBCompat_flex_twitter, "flex_twitter", "FLEX_TWITTER_TITLE", "MODERN_SETTINGS_LAB_TITLE"},
};
static const size_t kMetaCount = sizeof(kMeta) / sizeof(kMeta[0]);

typedef struct {
    PFBCompatPath path;
    PFBCompatOption option;
    const char* name;
} PFBCompatPathMeta;

// Every path of an option that acts in more than one place.
static const PFBCompatPathMeta kPaths[] = {
    {PFBCompatPath_grok_bot_sidebar, PFBCompat_hide_grok_bot, "side menu row"},
    {PFBCompatPath_grok_bot_upsells, PFBCompat_hide_grok_bot, "upsells"},
    {PFBCompatPath_grok_bot_home_header, PFBCompat_hide_grok_bot, "home header"},
    {PFBCompatPath_grok_bot_home_hero, PFBCompat_hide_grok_bot, "home hero"},
    {PFBCompatPath_grok_bot_preset, PFBCompat_hide_grok_bot, "presets"},
    {PFBCompatPath_grok_bot_tab_icon, PFBCompat_hide_grok_bot, "tab icon"},
    {PFBCompatPath_tab_bar, PFBCompat_tab_bar_theming, "tab bar"},
    {PFBCompatPath_native_tab_bar, PFBCompat_tab_bar_theming, "native tab bar"},
    {PFBCompatPath_top_tab_underline, PFBCompat_tab_bar_theming, "top tab underline"},
    {PFBCompatPath_pull_sound, PFBCompat_restore_refresh_sounds, "pull"},
    {PFBCompatPath_refresh_end_sound, PFBCompat_restore_refresh_sounds, "refresh end"},
    {PFBCompatPath_copy_button, PFBCompat_copy_profile_info, "copy button"},
    {PFBCompatPath_copy_id_and_date, PFBCompat_copy_profile_info, "user ID and join date"},
    {PFBCompatPath_follower_counts, PFBCompat_unrounded_counts, "follower counts"},
    {PFBCompatPath_post_count, PFBCompat_unrounded_counts, "post count"},
    {PFBCompatPath_verified_search, PFBCompat_hide_verified_tweets, "search results"},
    {PFBCompatPath_verified_edit_history, PFBCompat_hide_verified_tweets, "edit history"},
    {PFBCompatPath_promoted_video_feed, PFBCompat_hide_promoted, "video feed"},
    {PFBCompatPath_download_all, PFBCompat_download_videos, "download all entry"},
    {PFBCompatPath_web_mutes, PFBCompat_web_session, "mute lists"},
    {PFBCompatPath_web_grok, PFBCompat_web_session, "Grok requests"},
    {PFBCompatPath_web_pages, PFBCompat_web_session, "Twitter web pages"},
    {PFBCompatPath_web_tweets, PFBCompat_web_session, "Tweets sent"},
    {PFBCompatPath_web_media, PFBCompat_web_session, "media uploads"},
    {PFBCompatPath_tab_badges, PFBCompat_enable_liquid_glass, "tab badges"},
};
static const size_t kPathCount = sizeof(kPaths) / sizeof(kPaths[0]);

typedef struct {
    PFBCompatOption option;
    const char* className;
    const char* selector;
} PFBCompatReq;

// Each entry must exist in Twitter; one that a build drops shows Broken.
static const PFBCompatReq kReqs[] = {
    {PFBCompat_padlock, "T1AppDelegate", "-applicationDidBecomeActive:"},
    {PFBCompat_padlock, "T1AppDelegate", "-applicationWillResignActive:"},
    {PFBCompat_no_screenshot_detection, "NSNotificationCenter", "-addObserver:selector:name:object:"},
    {PFBCompat_no_screenshot_detection, "NSNotificationCenter", "-addObserverForName:object:queue:usingBlock:"},
    {PFBCompat_no_screenshot_detection, "TFSAccountFeatureSwitches", "-isCustomScreenshotsEnabled"},
    {PFBCompat_no_screenshot_detection, "TFSAccountFeatureSwitches", "-isCustomScreenshotsOnHTLEnabled"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_no_screenshot_detection, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_no_screenshot_detection, "TUIFollowControlCustomScreenshot", "-didMoveToWindow"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_force_following_tab, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_force_following_tab, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-doubleForKey:"},
    {PFBCompat_no_focus_lost, "TFSFeatureSwitches", "-unsafePeekDoubleForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-doubleForKey:"},
    {PFBCompat_no_focus_lost, "TFSInstrumentedFeatureSwitches", "-unsafePeekDoubleForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_media_carousel, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_media_carousel, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_no_tab_bar_hiding, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_show_scroll_indicator, "TFSAccountFeatureSwitches", "+isShowsVerticalScrollIndicatorEnabled"},
    {PFBCompat_disable_rtl, "TFNAttributedTextModel", "-setAttributedString:"},
    {PFBCompat_hide_premium_offer, "T1ProfileSummaryView", "-shouldShowGetVerifiedButton"},
    {PFBCompat_hide_premium_offer, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_premium_offer, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_notifications, "T1TabNavigationController", "-_t1_main_updateNavigationItemForViewController:isRoot:providingLeftBarButtonItems:rightBarButtonItems:"},
    {PFBCompat_hide_notifications, "T1URTTimelineNotificationCell", "-dismissButtonWasTapped"},
    {PFBCompat_hide_notifications, "T1URTTimelineNotificationCell", "-layoutSubviews"},
    {PFBCompat_hide_notifications, "T1URTTimelineNotificationCell", "-setAlpha:"},
    {PFBCompat_hide_notifications, "T1URTViewController", "-tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:"},
    {PFBCompat_hide_notifications, "TFNDismissButton", "-layoutSubviews"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-setSections:"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-updateSections:"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-updateSections:completion:"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-updateSections:withRowAnimation:"},
    {PFBCompat_hide_notifications, "TFNItemsDataViewController", "-updateSections:withRowAnimation:completion:"},
    {PFBCompat_sharing_domain, "TFNTwitterStatus", "+twitterURLForShareWithSParam:username:statusID:"},
    {PFBCompat_sharing_domain, "TFNTwitterStatus", "-twitterURLForShareWithSParam:"},
    {PFBCompat_sharing_domain, "TFSTwitterUserReference", "-twitterURLForCopy"},
    {PFBCompat_sharing_domain, "TFSTwitterUserReference", "-twitterURLForShare"},
    {PFBCompat_sharing_domain, "T1AppDelegate", "-applicationDidBecomeActive:"},
    {PFBCompat_strip_url_tracking, "T1AppDelegate", "-applicationDidBecomeActive:"},
    {PFBCompat_strip_url_tracking, "TFNTwitterStatus", "+twitterURLForShareWithSParam:username:statusID:"},
    {PFBCompat_strip_url_tracking, "TFNTwitterStatus", "-twitterURLForShareWithSParam:"},
    {PFBCompat_strip_url_tracking, "TFSTwitterUserReference", "-twitterURLForCopy"},
    {PFBCompat_strip_url_tracking, "TFSTwitterUserReference", "-twitterURLForShare"},
    {PFBCompat_always_open_safari, "SFSafariViewController", "-viewWillAppear:"},
    {PFBCompat_always_open_safari, "T1SafariViewController", "-tfnPresentedCustomPresentFromViewController:animated:completion:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_new_inapp_webview, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_new_inapp_webview, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_custom_tab_bar, "T1DashContentController", "-updateVisiblePanelIDs"},
    {PFBCompat_custom_tab_bar, "T1TabView", "-scribePage"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-recalculateVisiblePanels"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-setVisibleTabEntries:"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-visiblePanelIDsForAppNavigation:"},
    {PFBCompat_custom_tab_bar, "TFNTwitterAccount", "-canAccessXPayments"},
    {PFBCompat_custom_tab_bar, "TFSAccountFeatureSwitches", "-birdwatchHistoryIsEnabled"},
    {PFBCompat_custom_tab_bar, "TFSAccountFeatureSwitches", "-birdwatchHomePageIsEnabled"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_custom_tab_bar, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_custom_tab_bar, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-didMoveToWindow"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-showsTitleInDisplayMode:"},
    {PFBCompat_restore_tab_labels, "T1TabBarHostView", "-layoutSubviews"},
    {PFBCompat_restore_tab_labels, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-_t1_updateImageViewAnimated:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-setBadgeCount:animated:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-setHasUnreadContent:animated:"},
    {PFBCompat_restore_tab_labels, "TFNCustomTabBar", "-layoutSubviews"},
    {PFBCompat_custom_fonts, "UIFont", "+tfn_fontWithName:size:"},
    {PFBCompat_custom_fonts, "XFontCatalog", "+tabularDigitsFontOfSize:weight:"},
    {PFBCompat_custom_fonts, "UIFontPickerViewController", "-viewWillAppear:"},
    {PFBCompat_custom_fonts, "XFontCatalog", "+contentFontWithOffset:weight:"},
    {PFBCompat_custom_fonts, "XFontCatalog", "+customFontOfSize:weight:scalesWithDynamicType:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-_t1_updateImageViewAnimated:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-_t1_updateTitleLabel"},
    {PFBCompat_tab_bar_theming, "UITabBar", "-didMoveToWindow"},
    {PFBCompat_tab_bar_theming, "UITabBar", "-layoutSubviews"},
    {PFBCompat_tab_bar_theming, "UITabBar", "-setScrollEdgeAppearance:"},
    {PFBCompat_tab_bar_theming, "UITabBar", "-setStandardAppearance:"},
    {PFBCompat_tab_bar_theming, "UITabBarItem", "-initWithTitle:image:tag:"},
    {PFBCompat_tab_bar_theming, "UITabBarItem", "-setImage:"},
    {PFBCompat_tab_bar_theming, "UITabBarItem", "-setScrollEdgeAppearance:"},
    {PFBCompat_tab_bar_theming, "UITabBarItem", "-setSelectedImage:"},
    {PFBCompat_tab_bar_theming, "UITabBarItem", "-setStandardAppearance:"},
    {PFBCompat_tab_bar_theming, "_TtC10TFNUISwift25LegacySegmentedTabBarView", "-setStyle:"},
    {PFBCompat_tab_bar_theming, "_TtC10TFNUISwift26LegacySegmentedTabBarStyle", "-setHighlightBarColor:"},
    {PFBCompat_tab_bar_theming, "_TtC10TFNUISwift31LegacySegmentedHighlightBarView", "-setBackgroundColor:"},
    {PFBCompat_tab_bar_theming, "CALayer", "-addAnimation:forKey:"},
    {PFBCompat_tab_bar_theming, "T1TabBarHostView", "-layoutSubviews"},
    {PFBCompat_tab_bar_theming, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-setBadgeCount:animated:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-setHasUnreadContent:animated:"},
    {PFBCompat_tab_bar_theming, "TFNCustomTabBar", "-layoutSubviews"},
    {PFBCompat_tab_bar_theming, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_color_twitter_icon_in_top_bar, "TAEDarkColorPalette", "-brandLogoColor"},
    {PFBCompat_color_twitter_icon_in_top_bar, "TAEDarkColorPalette", "-navigationBarLogoColor"},
    {PFBCompat_color_twitter_icon_in_top_bar, "TAELightColorPalette", "-brandLogoColor"},
    {PFBCompat_color_twitter_icon_in_top_bar, "TAELightColorPalette", "-navigationBarLogoColor"},
    {PFBCompat_color_twitter_icon_in_top_bar, "TFNUIDefaultColorPalette", "-navigationBarLogoColor"},
    {PFBCompat_color_twitter_icon_in_top_bar, "UINavigationBar", "-layoutSubviews"},
    {PFBCompat_color_twitter_icon_in_top_bar, "_TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin", "-titleView"},
    {PFBCompat_color_twitter_icon_in_top_bar, "CALayer", "-addAnimation:forKey:"},
    {PFBCompat_color_twitter_icon_in_top_bar, "UINavigationBar", "-didMoveToWindow"},
    {PFBCompat_color_twitter_icon_in_top_bar, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_enable_liquid_glass, "T1TabView", "-setBadgeCount:animated:"},
    {PFBCompat_enable_liquid_glass, "T1TabView", "-setHasUnreadContent:animated:"},
    {PFBCompat_enable_liquid_glass, "CALayer", "-setOpacity:"},
    {PFBCompat_enable_liquid_glass, "NSBundle", "-objectForInfoDictionaryKey:"},
    {PFBCompat_enable_liquid_glass, "T1AvatarImageView", "-setImage:"},
    {PFBCompat_enable_liquid_glass, "T1PersistentComposeView", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "T1TabBarHostView", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_enable_liquid_glass, "T1TabView", "-_t1_updateImageViewAnimated:"},
    {PFBCompat_enable_liquid_glass, "TFNBarButtonItemButton", "-didMoveToWindow"},
    {PFBCompat_enable_liquid_glass, "TFNBarButtonItemButton", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "TFNCustomTabBar", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "TFNNavigationBar", "-setFrame:"},
    {PFBCompat_enable_liquid_glass, "TFNNavigationBarSearchView", "-setFrame:"},
    {PFBCompat_enable_liquid_glass, "TFNNavigationController", "-_tfn_setCurrentNavigationBarSimulatedHeight:isAnimated:"},
    {PFBCompat_enable_liquid_glass, "TFNSearchBar", "-setFrame:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_enable_liquid_glass, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_enable_liquid_glass, "UIBarButtonItem", "-setImage:"},
    {PFBCompat_enable_liquid_glass, "UIImageView", "-didMoveToWindow"},
    {PFBCompat_enable_liquid_glass, "UIImageView", "-setImage:"},
    {PFBCompat_enable_liquid_glass, "UINavigationBar", "-didMoveToWindow"},
    {PFBCompat_enable_liquid_glass, "UINavigationBar", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "UINavigationController", "-navigationBar:shouldPopItem:"},
    {PFBCompat_enable_liquid_glass, "UINavigationController", "-popViewControllerAnimated:"},
    {PFBCompat_enable_liquid_glass, "UINavigationController", "-pushViewController:animated:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setLeftBarButtonItem:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setLeftBarButtonItems:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setLeftBarButtonItems:animated:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setRightBarButtonItem:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setRightBarButtonItems:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setRightBarButtonItems:animated:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setTrailingItemGroups:"},
    {PFBCompat_enable_liquid_glass, "UIView", "-setAlpha:"},
    {PFBCompat_enable_liquid_glass, "_TtC10TFNUISwift34NavigationBarMenuBarButtonItemView", "-didMoveToWindow"},
    {PFBCompat_enable_liquid_glass, "_TtC10TFNUISwift34NavigationBarMenuBarButtonItemView", "-layoutSubviews"},
    {PFBCompat_dark_mode_style, "CALayer", "-setBackgroundColor:"},
    {PFBCompat_dark_mode_style, "TAEColorSettings", "-setCurrentColorPalette:"},
    {PFBCompat_dark_mode_style, "TFNSearchBar", "-didMoveToWindow"},
    {PFBCompat_dark_mode_style, "TFNSearchBar", "-layoutSubviews"},
    {PFBCompat_dark_mode_style, "TFNSolidColorView", "-setColor:"},
    {PFBCompat_dark_mode_style, "UIView", "-setBackgroundColor:"},
    {PFBCompat_dark_mode_style, "_UITextFieldImageBackgroundView", "-setImage:"},
    {PFBCompat_accent_color, "T1AppDelegate", "-application:didFinishLaunchingWithOptions:"},
    {PFBCompat_accent_color, "T1AppDelegate", "-applicationDidBecomeActive:"},
    {PFBCompat_accent_color, "TAEColorSettings", "-primaryColorOption"},
    {PFBCompat_accent_color, "TAEColorSettings", "-setPrimaryColorOption:"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColor"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorForOption:"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorOptionBlueColor"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorOptionGreenColor"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorOptionOrangeColor"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorOptionPurpleColor"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorOptionRedColor"},
    {PFBCompat_accent_color, "TAEDarkColorPalette", "-primaryColorOptionYellowColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorForOption:"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorOptionBlueColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorOptionGreenColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorOptionOrangeColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorOptionPurpleColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorOptionRedColor"},
    {PFBCompat_accent_color, "TAELightColorPalette", "-primaryColorOptionYellowColor"},
    {PFBCompat_accent_color, "TFNMutableTwitterStatusDisplayAttributedTextModelFontOptions", "-linkTextColor"},
    {PFBCompat_accent_color, "TFNTwitterStatusDisplayAttributedTextModelFontOptions", "-linkTextColor"},
    {PFBCompat_accent_color, "TFNUIDefaultColorPalette", "-primaryColor"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_accent_color, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_accent_color, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_accent_color, "UIImageView", "-setImage:"},
    {PFBCompat_accent_color, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_accent_color, "UIWindow", "-makeKeyAndVisible"},
    {PFBCompat_hide_promoted, "TFNTwitterAPICommandContext", "-allowPromotedContent"},
    {PFBCompat_hide_promoted, "TFNTwitterAccount", "-isVideoDynamicAdEnabled"},
    {PFBCompat_hide_promoted, "TFNTwitterStatus", "-isCardHidden"},
    {PFBCompat_hide_promoted, "T1ImmersiveViewController", "-viewWillLayoutSubviews"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift21ImmersiveCardHostView", "-layoutSubviews"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_promoted, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_promoted, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_promoted, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_promoted, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_who_to_follow, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_who_to_follow, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_who_to_follow, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_topics_to_follow, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_topics_to_follow, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_timeline_prompts, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_timeline_prompts, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_topics, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_topics, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_verified_tweets, "T1EditHistoryViewControllerFactory", "+viewControllerWithAccount:tweetID:scribeContext:"},
    {PFBCompat_hide_verified_tweets, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_verified_tweets, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_blocked_retweets, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_blocked_retweets, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_reading_line, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_reading_line, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_reading_line, "TFNItemsDataViewController", "-viewWillAppear:"},
    {PFBCompat_reading_line, "TFNItemsDataViewController", "-viewWillDisappear:"},
    {PFBCompat_reading_line, "TFNTableView", "-layoutSubviews"},
    {PFBCompat_hide_spaces, "T1FleetLineHeaderController", "-_t1_shouldShowFleetLine"},
    {PFBCompat_hide_spaces, "T1FleetLineView", "-didMoveToWindow"},
    {PFBCompat_hide_spaces, "T1FleetLineView", "-intrinsicContentSize"},
    {PFBCompat_hide_spaces, "T1FleetLineView", "-layoutSubviews"},
    {PFBCompat_hide_spaces, "T1FleetLineView", "-sizeThatFits:"},
    {PFBCompat_hide_new_tweets_pill, "TUIUpdateIndicator", "-_canShowPillForContentNotification:"},
    {PFBCompat_hide_new_tweets_pill, "TUIUpdateIndicator", "-_recreatePillControlForContentNotification:hideOnScroll:"},
    {PFBCompat_hide_scroll_edge_blur, "UIScrollView", "-didMoveToWindow"},
    {PFBCompat_hide_scroll_edge_blur, "UIScrollView", "-layoutSubviews"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_custom_timelines, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_custom_timelines, "_TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository", "-updatePinnedTimelines:"},
    {PFBCompat_hide_custom_timelines, "_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController", "-pinnedTimelinesRepository:didChangeWithPinnedTimelineModels:"},
    {PFBCompat_hide_custom_timelines, "_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController", "-tfn_navigationBarAccessoryView"},
    {PFBCompat_hide_custom_timelines, "_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController", "-viewDidAppear:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_unlimited_timeline_tabs, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_muted_words, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_muted_words, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_muted_words, "TFNNavigationBar", "-layoutSubviews"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-hasAccessToUndoSend"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-isUndoSendTurnedOnForOriginalTweets"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-isUndoSendTurnedOnForPollTweets"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-isUndoSendTurnedOnForQuoteTweets"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-isUndoSendTurnedOnForReplyTweets"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-isUndoSendTurnedOnForTweetstormTweets"},
    {PFBCompat_undo_tweet_timeout, "T1UndoSendConfig", "-undoTimeInterval"},
    {PFBCompat_undo_tweet_timeout, "TFNTwitterComposition", "-undoTimeInterval"},
    {PFBCompat_undo_tweet_timeout, "TFNTwitterComposition", "-undoableSendDate"},
    {PFBCompat_tweet_confirm, "T1PersistentComposeViewController", "-_t1_sendReply"},
    {PFBCompat_tweet_confirm, "T1TweetComposeViewController", "-_t1_didTapSendButton:"},
    {PFBCompat_hide_tweet_button, "TFNFloatingActionButton", "-didMoveToWindow"},
    {PFBCompat_hide_tweet_button, "TFNFloatingActionButton", "-layoutSubviews"},
    {PFBCompat_hide_tweet_button, "TFNFloatingActionButton", "-willMoveToWindow:"},
    {PFBCompat_hide_threads, "UIButton", "-setMenu:"},
    {PFBCompat_hide_threads, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_threads, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_like_confirm, "TTAStatusInlineActionsView", "-didTapInlineActionButton:"},
    {PFBCompat_like_confirm, "_TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView", "-handleDoubleTap:"},
    {PFBCompat_hide_view_count, "TTAStatusInlineActionsView", "+_t1_inlineActionViewClassesForViewModel:options:displayType:account:"},
    {PFBCompat_hide_bookmark_button, "TTAStatusInlineActionsView", "+_t1_inlineActionViewClassesForViewModel:options:displayType:account:"},
    {PFBCompat_hide_downvote_button, "TTAStatusInlineActionsView", "+_t1_inlineActionViewClassesForViewModel:options:displayType:account:"},
    {PFBCompat_show_poll_results, "TFCCardData", "-stringForKey:"},
    {PFBCompat_show_poll_results, "TFCCardData", "-stringForKey:defaultValue:"},
    {PFBCompat_disable_sensitive_tweet_warnings, "HFHealthSafetyFeature", "+isTweetMedialInterstitialEnabled:"},
    {PFBCompat_disable_sensitive_tweet_warnings, "TFNTwitterAccount", "-isSensitiveTweetWarningsComposeEnabled"},
    {PFBCompat_disable_sensitive_tweet_warnings, "TFNTwitterAccount", "-isSensitiveTweetWarningsConsumeEnabled"},
    {PFBCompat_disable_sensitive_tweet_warnings, "TFNTwitterStatus", "-hasImageInterstitial"},
    {PFBCompat_disable_sensitive_tweet_warnings, "TFNTwitterStatus", "-imageInterstitial"},
    {PFBCompat_disable_sensitive_tweet_warnings, "TFNTwitterStatus", "-innerImageInterstitial"},
    {PFBCompat_bypass_age_verification, "TFNTwitterAccount", "-isAgeAssuranceAgeVerificationFlowEnabled"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_bypass_age_verification, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_bypass_age_verification, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_reply_sorting, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_reply_sorting, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_restore_reply_context, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_restore_reply_context, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_show_quote_counts, "T1PostInteractionsViewController", "-viewDidLoad"},
    {PFBCompat_show_account_location, "T1ConversationFooterTextView", "-updateFooterTextView"},
    {PFBCompat_show_account_location, "T1ConversationFooterTextView", "-footerItem"},
    {PFBCompat_show_account_location, "T1ConversationFooterTextView", "-viewModel"},
    {PFBCompat_download_videos, "UIMenu", "+menuWithTitle:children:"},
    {PFBCompat_download_videos, "_TtC16ChatConversation21MessageAttachmentView", "-layoutSubviews"},
    {PFBCompat_download_videos, "UIActivityViewController", "-initWithActivityItems:applicationActivities:"},
    {PFBCompat_download_videos, "UIMenu", "-menuByReplacingChildren:"},
    {PFBCompat_tweet_to_image, "TTAStatusInlineShareButton", "-didLongPressActionButton:"},
    {PFBCompat_tap_to_pause, "T1InlineVideoView", "-handleTapWithTapRecognizer:"},
    {PFBCompat_tap_to_pause, "TAVPlayer", "-play"},
    {PFBCompat_tap_to_pause, "TAVPlayer", "-playOrReplay"},
    {PFBCompat_tap_to_pause, "TAVPlayer", "-setIsMuted:"},
    {PFBCompat_tap_to_pause, "TAVPlayer", "-setVolume:"},
    {PFBCompat_tap_to_pause, "T1ImmersiveFullScreenViewController", "-viewDidAppear:"},
    {PFBCompat_tap_to_pause, "T1ImmersiveFullScreenViewController", "-dismissAnimationCancelled"},
    {PFBCompat_tap_to_pause, "T1ImmersiveFullScreenViewController", "-viewWillDisappear:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17ImmersiveCardView", "-didMoveToWindow"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17ImmersiveCardView", "-handleSingleTap:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17VideoControlsView", "-didMoveToWindow"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift22ImmersiveVideoPageView", "-player:didUpdatePlaybackState:"},
    {PFBCompat_tap_to_pause, "T1InlineVideoView", "-didMoveToWindow"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17BottomBarControls", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17ImmersiveCardView", "-setPausedByUser:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift19ImmersiveActionView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift25ImmersiveActionsStackView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift25ImmersiveStatusPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift29ImmersiveBackButtonPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift30ImmersiveAttributionPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift30ImmersiveTopGradientPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift32ImmersiveVideoTimelinePluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift33ImmersiveBottomGradientPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift34ImmersivePlayPauseButtonPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift35ImmersiveTopRightActionsPluginsView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift36ImmersiveEngagementActionsPluginView", "-setAlpha:"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift37ImmersiveScrubProgressLabelPluginView", "-setAlpha:"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift17VideoControlsView", "-layoutSubviews"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift22ImmersiveVideoPageView", "-player:didUpdatePlaybackState:"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift17ImmersiveCardView", "-didMoveToWindow"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift17ImmersiveCardView", "-handleSingleTap:"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift17VideoControlsView", "-didMoveToWindow"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_video_captions, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_video_captions, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_immersive_scroll, "T1ImmersiveViewController", "-gestureRecognizerShouldBegin:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_immersive_scroll, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_video_docking, "T1ImmersiveViewController", "-isCurrentCardDockEligible"},
    {PFBCompat_disable_video_docking, "T1ImmersiveFullScreenViewController", "-_canDockCurrentVideoToBottomSegment"},
    {PFBCompat_disable_video_docking, "_TtC14T1TwitterSwift24ImmersivePiPDropZoneView", "-didMoveToWindow"},
    {PFBCompat_auto_highest_load, "T1ImageDisplayView", "-_tfn_shouldUseHighQualityImage"},
    {PFBCompat_auto_highest_load, "T1ImageDisplayView", "-_tfn_shouldUseHighestQualityImage"},
    {PFBCompat_auto_highest_load, "TFNTwitterAccount", "-isDoubleMaxZoomFor4KImagesEnabled"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_enable_image_preloading, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_enable_image_preloading, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_enable_image_preloading, "TFNItemsDataViewController", "-tableView:prefetchRowsAtIndexPaths:"},
    {PFBCompat_enable_image_preloading, "TIPImagePipeline", "-operationWithRequest:context:completion:"},
    {PFBCompat_enable_image_preloading, "TIPImagePipeline", "-fetchImageWithOperation:"},
    {PFBCompat_enable_image_preloading, "TIPGenericImageFetchRequest",
     "-initWithImageURL:identifier:targetDimensions:targetContentMode:"},
    {PFBCompat_enable_image_preloading, "TIPImagePipeline", "-operationWithRequest:context:delegate:"},
    {PFBCompat_force_tweet_full_frame, "T1StandardStatusAttachmentViewAdapter", "-displayType"},
    {PFBCompat_upload_full_hd_videos, "T1LongerVideoUploadEnabledConfig", "-isUploadFullHDVideoEnabled"},
    {PFBCompat_upload_full_hd_videos, "T1LongerVideoUploadEnabledConfig", "-isUploadFullHDVideoEnabledByDefault"},
    {PFBCompat_upload_full_hd_videos, "T1VideoQualityUploadSettings", "-shouldAllowFullHdVideoUpload:"},
    {PFBCompat_follow_confirm, "TUIFollowButtonV2", "-buttonTapped"},
    {PFBCompat_follow_confirm, "TUIFollowControl", "-_followUser:event:"},
    {PFBCompat_expand_bio, "T1ProfileUserInfoView", "-isBioExpanded"},
    {PFBCompat_copy_profile_info, "XDSButtonRow", "-layoutSubviews"},
    {PFBCompat_unrounded_counts, "T1ProfileFriendsFollowingViewModel", "-_t1_followCountTextWithLabel:singularLabel:count:highlighted:"},
    {PFBCompat_unrounded_counts, "T1ProfileDisplayNormalMainContentProvider", "-_tweetsSubtitle"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_articles, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_articles, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_highlights, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_highlights, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_videos_tab, "T1ProfileUserViewModel", "-shouldDisplayVideosTab"},
    {PFBCompat_hide_blue_verified, "T1TwitterCoreStatusViewModelAdapter", "-isFromUserBlueVerified"},
    {PFBCompat_hide_blue_verified, "T1TwitterCoreStatusViewModelAdapter", "-isFromUserVerified"},
    {PFBCompat_hide_blue_verified, "TFSDirectMessageUser", "-isBlueVerified"},
    {PFBCompat_hide_blue_verified, "TFSDirectMessageUser", "-verified"},
    {PFBCompat_hide_blue_verified, "TFSTwitterTypeaheadUser", "-isBlueVerified"},
    {PFBCompat_hide_blue_verified, "TFSTwitterTypeaheadUser", "-verified"},
    {PFBCompat_hide_blue_verified, "TFSTwitterUser", "-isBlueVerified"},
    {PFBCompat_hide_blue_verified, "TFSTwitterUser", "-verified"},
    {PFBCompat_hide_blue_verified, "TFSTwitterUserSource", "-isBlueVerified"},
    {PFBCompat_hide_blue_verified, "TFSTwitterUserSource", "-verified"},
    {PFBCompat_hide_follow_button, "TTAStatusAuthorView", "-setFollowControlHidden:"},
    {PFBCompat_hide_message_button, "TTAStatusAuthorView", "-layoutSubviews"},
    {PFBCompat_restore_follow_button, "TFSTwitterRelationship", "-superFollowEligibleState"},
    {PFBCompat_square_avatars, "TFNAvatarImageView", "-setStyle:"},
    {PFBCompat_square_avatars, "TFNCircularAvatarShadowLayer", "-setHidden:"},
    {PFBCompat_square_avatars, "TUIAvatarImageView", "+avatarImageViewStyleWithProfileImageShape:identityType:"},
    {PFBCompat_square_avatars, "TUIAvatarImageView", "-setStyle:"},
    {PFBCompat_square_avatars, "UIImage", "-tfn_roundImageWithTargetDimensions:targetContentMode:"},
    {PFBCompat_profile_initial_tab, "T1ProfileDisplayContentProvider", "-defaultMainContentEntry"},
    {PFBCompat_profile_initial_tab, "T1ProfileDisplayContentProvider", "-initialTabIndex"},
    {PFBCompat_profile_initial_tab, "T1ProfileDisplayContentProvider", "-setInitialTabIndex:"},
    {PFBCompat_profile_initial_tab, "T1ProfileViewController", "-viewDidAppear:"},
    {PFBCompat_no_history, "TTSRecentSearchesDatastore", "-_tse_setRecentSearch:"},
    {PFBCompat_no_history, "TTSRecentSearchesDatastore", "-recentSearches"},
    {PFBCompat_advanced_search, "_TtC14T1TwitterSwift28GuideContainerViewController", "-viewWillAppear:"},
    {PFBCompat_advanced_search, "_TtC15TwitterSearchV211SearchBarV2", "-layoutSubviews"},
    {PFBCompat_advanced_search, "UIBarButtonItemGroup", "-setBarButtonItems:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setPinnedTrailingGroup:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setRightBarButtonItems:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setRightBarButtonItems:animated:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setTrailingItemGroups:"},
    {PFBCompat_advanced_search, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_advanced_search, "UIViewController", "-viewWillAppear:"},
    {PFBCompat_hide_trend_videos, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_trend_videos, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_explore_all, "CALayer", "-addAnimation:forKey:"},
    {PFBCompat_hide_explore_all, "CALayer", "-setBounds:"},
    {PFBCompat_hide_explore_all, "CALayer", "-setPosition:"},
    {PFBCompat_hide_explore_all, "UICollectionView", "-layoutSubviews"},
    {PFBCompat_hide_explore_all, "UICollectionView", "-scrollToItemAtIndexPath:atScrollPosition:animated:"},
    {PFBCompat_hide_explore_all, "UIScrollView", "-setContentOffset:animated:"},
    {PFBCompat_hide_explore_all, "_TtC10TFNUISwift25LegacySegmentedTabBarView", "-layoutSubviews"},
    {PFBCompat_hide_explore_all, "_TtC10TFNUISwift26LegacyPagingViewController", "-collectionView:numberOfItemsInSection:"},
    {PFBCompat_hide_explore_all, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewDidEndDecelerating:"},
    {PFBCompat_hide_explore_all, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewDidEndScrollingAnimation:"},
    {PFBCompat_hide_explore_all, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewDidScroll:"},
    {PFBCompat_hide_explore_all, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewWillEndDragging:withVelocity:targetContentOffset:"},
    {PFBCompat_hide_explore_all, "_TtC14T1TwitterSwift28GuideContainerViewController", "-tfn_navigationBarAccessoryView"},
    {PFBCompat_hide_explore_all, "_TtC14T1TwitterSwift28GuideContainerViewController", "-viewDidLoad"},
    {PFBCompat_choose_explore_tabs, "CALayer", "-addAnimation:forKey:"},
    {PFBCompat_choose_explore_tabs, "CALayer", "-setBounds:"},
    {PFBCompat_choose_explore_tabs, "CALayer", "-setPosition:"},
    {PFBCompat_choose_explore_tabs, "UICollectionView", "-layoutSubviews"},
    {PFBCompat_choose_explore_tabs, "UICollectionView", "-scrollToItemAtIndexPath:atScrollPosition:animated:"},
    {PFBCompat_choose_explore_tabs, "UIScrollView", "-setContentOffset:animated:"},
    {PFBCompat_choose_explore_tabs, "_TtC10TFNUISwift25LegacySegmentedTabBarView", "-layoutSubviews"},
    {PFBCompat_choose_explore_tabs, "_TtC10TFNUISwift26LegacyPagingViewController", "-collectionView:numberOfItemsInSection:"},
    {PFBCompat_choose_explore_tabs, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewDidEndDecelerating:"},
    {PFBCompat_choose_explore_tabs, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewDidEndScrollingAnimation:"},
    {PFBCompat_choose_explore_tabs, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewDidScroll:"},
    {PFBCompat_choose_explore_tabs, "_TtC10TFNUISwift26LegacyPagingViewController", "-scrollViewWillEndDragging:withVelocity:targetContentOffset:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_choose_explore_tabs, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_typing_indicator, "NSURLSession", "-webSocketTaskWithRequest:"},
    {PFBCompat_hide_typing_indicator, "NSURLSession", "-webSocketTaskWithURL:"},
    {PFBCompat_hide_typing_indicator, "NSURLSession", "-webSocketTaskWithURL:protocols:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_voice_transcription, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_voice_transcription, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_download_voice_messages, "_TtC16ChatConversation26MessageAttachmentAudioView", "-layoutSubviews"},
    {PFBCompat_download_voice_messages, "AVURLAsset", "-initWithURL:options:"},
    {PFBCompat_voice_note_from_video, "T1MediaAttachmentsViewCell", "-updateCellElements"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_grok_analyze, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_grok_sidebar, "T1TabbedAppNavigationViewController", "-visiblePanelIDsForAppNavigation:"},
    {PFBCompat_hide_grok_sidebar, "T1DashContentController", "-updateVisiblePanelIDs"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_grok_bot, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_grok_bot, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_grok_create, "T1StatusPhotoEditorHandler", "-photoEditorCanEditWithGrok:"},
    {PFBCompat_hide_grok_create, "T1TweetComposeViewController", "-photoEditorCanEditWithGrok:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_grok_create, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_grok_create, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_auto_translate, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_disable_auto_translate, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_restore_twitter_names, "NSBundle", "-localizedStringForKey:value:table:"},
    {PFBCompat_restore_twitter_names, "TFNAttributedTextView", "-setTextModel:"},
    {PFBCompat_restore_twitter_names, "TUIUpdateIndicator", "-_recreatePillControlForContentNotification:hideOnScroll:"},
    {PFBCompat_restore_twitter_names, "UINavigationBar", "-layoutSubviews"},
    {PFBCompat_restore_twitter_names, "_TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin", "-titleView"},
    {PFBCompat_restore_twitter_names, "UINavigationBar", "-didMoveToWindow"},
    {PFBCompat_restore_twitter_names, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_refresh_pill_label, "TUIUpdateIndicator", "-_recreatePillControlForContentNotification:hideOnScroll:"},
    {PFBCompat_restore_tweet_button, "TFNFloatingActionButton", "-didAddSubview:"},
    {PFBCompat_restore_tweet_button, "TFNFloatingActionButton", "-didMoveToWindow"},
    {PFBCompat_restore_tweet_button, "TFNFloatingActionButton", "-layoutSubviews"},
    {PFBCompat_restore_tweet_button, "TFNFloatingActionButton", "-willMoveToWindow:"},
    {PFBCompat_restore_tweet_button, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_restore_tweet_button, "UIImage", "+tfn_vectorImageNamed:height:fillColor:"},
    {PFBCompat_restore_tweet_button, "UIImage", "+tfn_vectorImageNamed:highContrastVariantNamed:fitsSize:fillColor:"},
    {PFBCompat_restore_tweet_button, "UIImageView", "-willMoveToWindow:"},
    {PFBCompat_restore_tweet_button, "UIVisualEffectView", "-setEffect:"},
    {PFBCompat_restore_tweet_button, "UIVisualEffectView", "-willMoveToWindow:"},
    {PFBCompat_restore_tweet_button, "UIImageView", "-setImage:"},
    {PFBCompat_restore_tweet_button, "UIVisualEffectView", "-layoutSubviews"},
    {PFBCompat_restore_refresh_sounds, "TFNItemsDataViewController", "-scrollViewDidEndDragging:willDecelerate:"},
    {PFBCompat_restore_refresh_sounds, "TFNPullToRefreshControl", "-_setStatus:fromScrolling:"},
    {PFBCompat_reply_in_webview, "T1PersistentComposeViewController", "-persistentComposeViewDidTap:"},
    {PFBCompat_reply_in_webview, "T1StatusViewInlineActionTapEventHandler", "-performReplyActionWithAccount:event:controller:scribeContext:scribeElement:parameters:originalStatus:"},
    {PFBCompat_reply_in_webview, "CALayer", "-addAnimation:forKey:"},
    {PFBCompat_flex_twitter, "T1AppDelegate", "-application:didFinishLaunchingWithOptions:"},
    {PFBCompat_flex_twitter, "T1AppDelegate", "-applicationWillResignActive:"},
    {PFBCompat_web_session, "T1WebViewController", "-updateConfiguration:"},
    {PFBCompat_web_session, "NSURLSession", "-dataTaskWithRequest:"},
    {PFBCompat_web_session, "NSURLSession", "-dataTaskWithRequest:completionHandler:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromData:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromFile:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromData:completionHandler:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromFile:completionHandler:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithStreamedRequest:"},
    {PFBCompat_web_session, "NSURLSessionTask", "-resume"},
    {PFBCompat_web_session, "T1AccountsViewController", "-private_startLoginFlowWithSender:"},
    {PFBCompat_web_session, "T1AppDelegate", "-applicationDidBecomeActive:"},
    {PFBCompat_web_session, "T1HostViewController", "-makeOnboardingViewControllerWithCompletion:"},
    {PFBCompat_web_session, "T1WebViewController", "-didFinishLoadingWithError:"},
    {PFBCompat_web_session, "WKWebView", "-loadRequest:"},
    // Ivars read by name, as "$name"; a "|" lists the other names the code accepts.
    {PFBCompat_advanced_search, "_TtC15TwitterSearchV211SearchBarV2", "$showsFilterButton"},
    {PFBCompat_advanced_search, "_TtC15TwitterSearchV211SearchBarV2", "$filterButton"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift17VideoControlsView", "$progressLabelMode"},
    {PFBCompat_tap_to_pause, "T1InlineVideoView", "$isAutoUnmuteEnabled"},
    {PFBCompat_tap_to_pause, "T1InlineVideoView", "$playerViewIfLoaded"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift22ImmersiveVideoPageView", "$player"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift21ImmersiveCardHostView", "$audioSessionManager"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift28ImmersiveAudioSessionManager", "$isMuted"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17ImmersiveCardView", "$singleTapRecognizer"},
    {PFBCompat_hide_promoted, "T1URTTimelineStatusItemViewModel", "$status"},
    {PFBCompat_hide_promoted, "_TtC10TwitterURT32URTTimelineEventSummaryViewModel", "$promotedContent"},
    {PFBCompat_hide_promoted, "T1ImmersiveViewController", "$timelineCoordinator"},
    {PFBCompat_hide_promoted, "T1ImmersiveViewController", "$cardNavigator"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift28ImmersiveTimelineCoordinator", "$items"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift22ImmersiveCardNavigator", "$loadedPageRange"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift22ImmersiveCardNavigator", "$itemCount"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift22ImmersiveCardViewModel", "$statusItemViewModel"},
    {PFBCompat_disable_immersive_scroll, "T1ImmersiveViewController", "$panRecognizer|$__lazy_storage_$_panRecognizer"},
    {PFBCompat_show_quote_counts, "T1PostInteractionsViewController", "$account"},
    {PFBCompat_show_quote_counts, "T1PostInteractionsViewController", "$statusID"},
    {PFBCompat_voice_note_from_video, "T1MediaAttachmentsViewCell", "$_removeButton"},
};
static const size_t kReqCount = sizeof(kReqs) / sizeof(kReqs[0]);

typedef struct {
    PFBCompatOption option;
    const char* key;
    BOOL prefix;
} PFBCompatFlag;

// The Twitter feature switches each option answers in FeatureSwitches.x. A switch
// Twitter no longer carries is one the option can no longer act through.
static const PFBCompatFlag kFlags[] = {
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_sidebar_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_upsells_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_home_header_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_home_hero_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_preset_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_tab_icon_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_topics_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_generic_timelines_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_sticky_warm_start_enabled", NO},
    {PFBCompat_hide_custom_timelines, "ranked_following_home_timeline_tab_enabled", NO},
    {PFBCompat_hide_custom_timelines, "super_follow_subscriptions_home_timeline_tab_sticky_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_limit", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_management_pinnedsection_inline_limit", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_management_topics_inline_limit", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_pinned_trailing_accessory_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_topics_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_generic_timelines_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_sticky_warm_start_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "ranked_following_home_timeline_tab_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "super_follow_subscriptions_home_timeline_tab_sticky_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_limit", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_management_pinnedsection_inline_limit", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_management_topics_inline_limit", NO},
    {PFBCompat_disable_auto_translate, "grok_translations_post_auto_translation_is_enabled", NO},
    {PFBCompat_disable_auto_translate, "grok_translations_bio_auto_translation_is_enabled", NO},
    {PFBCompat_disable_auto_translate, "grok_translations_community_note_auto_translation_is_enabled", NO},
    {PFBCompat_disable_auto_translate, "grok_translations_notification_auto_translation_is_enabled", NO},
    {PFBCompat_disable_auto_translate, "grok_translations_immersive_auto_translate_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_edit_with_grok_button_under_post_focal_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_edit_with_grok_button_under_post_preview_enabled", NO},
    {PFBCompat_hide_grok_create, "ios_composer_grok_button_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_imagine_composer_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_composer_imagine_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_composer_attachment_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_timeline_preview_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_timeline_video_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_timeline_slideshow_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_edit_photo_post_button_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_imagine_cta_focal_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_imagine_cta_reply_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_imagine_cta_timeline_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_imagine_2_cta_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_immersive_create_own_button_enabled", NO},
    {PFBCompat_hide_grok_create, "ios_button_layout_fix", YES},
    {PFBCompat_hide_grok_analyze, "grok_ios_author_view_analyze_button_via_backend_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ios_profile_summary_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ask_grok_button_under_post_focal_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ask_grok_button_under_post_preview_enabled", NO},
    {PFBCompat_force_following_tab, "home_timeline_non_sticky_tab_on_new_session_enabled", NO},
    {PFBCompat_no_focus_lost, "home_timeline_foreground_refresh_min_background_seconds", NO},
    {PFBCompat_disable_articles, "articles_timeline_profile_tab_enabled", NO},
    {PFBCompat_disable_highlights, "highlights_tweets_tab_ui_enabled", NO},
    {PFBCompat_bypass_age_verification, "ios_age_assurance", YES},
    {PFBCompat_bypass_age_verification, "grok_settings_age_restriction_enabled", NO},
    {PFBCompat_reply_sorting, "reply_sorting_enabled", NO},
    {PFBCompat_restore_reply_context, "ios_tweet_detail_conversation_context_removal_enabled", NO},
    {PFBCompat_disable_media_carousel, "ios_ui_multi_media_carousel_enabled", NO},
    {PFBCompat_disable_media_carousel, "ios_ui_multi_media_carousel_avatar_avoidance_enabled", NO},
    {PFBCompat_disable_media_carousel, "ios_ui_quote_tweet_multi_media_carousel_enabled", NO},
    {PFBCompat_disable_video_captions, "ios_tav_default_closed_captions_enabled", NO},
    {PFBCompat_disable_video_captions, "ios_audio_transcription_subtitles_vod_enabled", NO},
    {PFBCompat_voice_transcription, "xchat_voice_messages_transcription_enabled", NO},
    {PFBCompat_enable_image_preloading, "ios_tav_video_prefetch_batch_size", NO},
    {PFBCompat_enable_image_preloading, "ios_tav_video_prefetch_range", NO},
    {PFBCompat_enable_image_preloading, "ios_tav_video_prefetch_videos_kept_in_cache", NO},
    {PFBCompat_new_inapp_webview, "ios_in_app_article_webview_enabled", NO},
    {PFBCompat_disable_immersive_scroll, "immersive_video_auto_advance_duration_threshold", NO},
    {PFBCompat_hide_promoted, "ssp_ads_spotlight", NO},
    {PFBCompat_hide_promoted, "ssp_ads_spotlight_client_only_integration", NO},
    {PFBCompat_hide_promoted, "ssp_ads_spotlight_client_only_integration_preload", NO},
    {PFBCompat_hide_promoted, "ssp_ads_home_enabled", NO},
    {PFBCompat_hide_promoted, "ssp_ads_home_client_only_integration", NO},
    {PFBCompat_hide_promoted, "ssp_ads_profile", NO},
    {PFBCompat_hide_promoted, "ssp_ads_profile_client_only_integration_enabled", NO},
    {PFBCompat_hide_promoted, "ssp_ads_immersive", NO},
    {PFBCompat_hide_promoted, "ssp_ads_immersive_client_only_integration", NO},
    {PFBCompat_hide_promoted, "ssp_ads_tweet_details", NO},
    {PFBCompat_hide_promoted, "ssp_ads_tweet_details_client_only_integration", NO},
    {PFBCompat_hide_who_to_follow, "wtf_device_follow_nudge_turn_off_reactive_blending_enabled", NO},
    {PFBCompat_enable_liquid_glass, "ios_liquid_glass_redesign_enabled", NO},
    {PFBCompat_enable_liquid_glass, "xchat_liquid_glass_convo_header_enabled", NO},
    {PFBCompat_accent_color, "app_customization_custom_primary_color_enabled", NO},
    {PFBCompat_no_screenshot_detection, "ios_consideration_share_cooldown_max_dismisses", NO},
    {PFBCompat_no_screenshot_detection, "ios_consideration_share_cooldown_days", NO},
    {PFBCompat_no_screenshot_detection, "ios_consideration_share_cooldown_window_hours", NO},
    {PFBCompat_custom_tab_bar, "ios_tab_bar_default_show_profile", NO},
    {PFBCompat_custom_tab_bar, "ios_tab_bar_default_show_communities", NO},
    {PFBCompat_custom_tab_bar, "voice_rooms_consumption_enabled", NO},
    {PFBCompat_custom_tab_bar, "communities_enable_explore_tab", NO},
    {PFBCompat_custom_tab_bar, "subscriptions_inapp_grok", NO},
    {PFBCompat_custom_tab_bar, "ai_trends_ios_enable_news_tab", NO},
    {PFBCompat_custom_tab_bar, "media_tab_enabled", NO},
    {PFBCompat_custom_tab_bar, "c9s_tab_visibility", NO},
    {PFBCompat_custom_tab_bar, "subscriptions_premium_hub_enabled", NO},
    {PFBCompat_custom_tab_bar, "recruiting_global_jobs_hub_enabled", NO},
    {PFBCompat_choose_explore_tabs, "ai_trends_ios_enable_news_tab", NO},
};
enum { kFlagCount = sizeof(kFlags) / sizeof(kFlags[0]) };

typedef struct {
    PFBCompatOption option;  // PFBCompatOptionCount: a source file rather than an option
    const char* file;
    const char* name;
} PFBCompatName;

// Names reached as strings (selectors, ivars, keys). Each must stay in Twitter's
// binaries; the list is kept by hand.
static const PFBCompatName kNames[] = {
    {PFBCompat_like_confirm, "Features/Tweets/Confirmations.x", "displayAsFavorited"},
    {PFBCompat_follow_confirm, "Features/Tweets/Confirmations.x", "followState"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "fromUserName"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "representedFromUserName"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "representedFromUserFollowedByCurrentAccountState"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "representedStatus"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "isRetweet"},
    {PFBCompat_hide_topics, "Features/Timelines/Timeline.x", "socialContextBannerText"},
    {PFBCompat_hide_topics, "Features/Timelines/Timeline.x", "FROM_TAG_TOPIC_SOCIAL_CONTEXT_LABEL_FORMAT"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "inReplyToUserID"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "isFromUserVerified"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "isReplyAndShouldShowSocialContext"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "representedFromUserFollowedByCurrentAccountState"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "representedFromUserID"},
    {PFBCompat_hide_custom_timelines, "Features/Timelines/Timeline.x", "addTabButton"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "inlineMediaInfos"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "imageURL"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "itemAtIndexPath:"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "isRetweet"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "representedFromUser"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "relationship"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "blockingCurrentAccountState"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "T1Strings_T1Strings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "TwitterSharedStrings_TwitterSharedStrings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "ChatCore_ChatStrings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "LiveActivities_LiveActivityStrings.bundle"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconCell.m", "dividerColor"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconCell.m", "sharedColorManager"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconCell.m", "tfnuiColors"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconViewController.m", "textDetailsColor"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconViewController.m", "tfnuiColors"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconViewController.m", "title"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarCell.m", "imageName"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "imageName"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "title"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.m", "recalculateVisiblePanels"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.m", "itemColor"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.m", "navigationBarShadowColor"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.m", "subscriptionMarketingFeatureCardBackgroundColor"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.m", "tabCustomizationInactiveGridCellContainerBackgroundColor"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/CustomTabBarNativeColors.m", "twitterColors"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1Window"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_t1_currentAccount"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "selectTabAtIndex:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "username"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "pullToLoadTopControl"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_setStatus:fromScrolling:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "numberOfTabs"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "selectedIndex"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "setSelectedIndex:animated:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1StatusCell"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TTAStatusInlineActionsView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "didTapInlineActionButton:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TTAStatusInlineFavoriteButton"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "didTap"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TTAStatusInlineReplyButton"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TTAStatusInlineShareButton"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "didLongPressActionButton:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TTAStatusAuthorView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "caretButton"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_didTapCaret"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1InlineVideoView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "handleTapWithTapRecognizer:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "handleDoubleTap:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC21TweetMediaAttachments14MultiMediaView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1StatusPhotoVideoForwardView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_t1_mediaTapActionAtIndex:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_t1_imageTapAction"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TUIFollowButtonV2"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "buttonTapped"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1PersistentComposeViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "persistentComposeViewDidTap:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "sendReplyButton"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "sendButton"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_t1_didTapReply:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_t1_sendReply"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1TweetComposeViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_t1_didTapSendButton:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1AppSplitViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "presentDashFromViewController:animated:completion:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "private_dashShowContentViewControllerAnimated:completion:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "isDashOpen"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "selectedTabIndex"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC15TwitterSearchV211SearchBarV2"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "handleFocusTap"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1StandardStatusView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "viewModel"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "fromUser"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "bio"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1ImmersiveViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1ImmersiveFullScreenViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_canDockCurrentVideoToBottomSegment"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1UnifiedCardView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TAEColorSettings"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "sharedSettings"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "availableColorPalettes"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "setCurrentColorPalette:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "applyCurrentColorPalette"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "colorPaletteMatchingName:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "isDark"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "name"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "statusID"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "fromUserID"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TFNTwitterAccount"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1PostInteractionsViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "viewControllerWithAccount:statusID:statusUserID:initialTab:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "colorPalette"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "imageView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "sharedSettings"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "subtext2Font"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "tableView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityReportViewController.m", "title"},
    {PFBCompatOptionCount, "Debug/PFBTourChoicePopover.m", "title"},
    {PFBCompatOptionCount, "Debug/PFBDebugger.m", "windows"},
    {PFBCompatOptionCount, "Features/General/PFBHiddenNotificationsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Features/General/PFBHiddenNotificationsViewController.m", "title"},
    {PFBCompatOptionCount, "Features/General/PFBHiddenNotificationsViewController.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Search/AdvancedSearch.x", "setHidesSharedBackground:"},
    {PFBCompatOptionCount, "Features/Search/AdvancedSearch.x", "title"},
    {PFBCompatOptionCount, "Features/Search/AdvancedSearch.x", "window"},
    {PFBCompatOptionCount, "Features/Search/AdvancedSearch.x", "windows"},
    {PFBCompatOptionCount, "Features/General/AppLifecycle.x", "window"},
    {PFBCompatOptionCount, "Support/FeatureSwitches.x", "currentAccount"},
    {PFBCompatOptionCount, "Support/FeatureSwitches.x", "isPremiumTierUser"},
    {PFBCompatOptionCount, "Support/FeatureSwitches.x", "lastUsedAccountFeatureSwitches"},
    {PFBCompatOptionCount, "Support/FeatureSwitches.x", "sharedHostViewController"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "colorPalette"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "currentColorPalette"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "deleteItemAtIndexPath:withRowAnimation:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "dismissButton"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "fontOfSize:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "heavyFontOfSize:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "itemAtIndexPath:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "items"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "loadTop:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "pullToLoadTopControl"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "scribeItem"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "sections"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "setHidesSharedBackground:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "sharedSettings"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "string"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "textDetailsColor"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "titleLabel"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "view"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "aggregatedDisplayReplyCount"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "conversationID"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "inReplyToStatusID"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "replyCount"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "statusID"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "colorPalette"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "sharedSettings"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "window"},
    {PFBCompatOptionCount, "Features/Media/MediaDownloads.x", "inlineMediaInfos"},
    {PFBCompatOptionCount, "Features/Media/MediaDownloads.x", "status"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "setHidesSharedBackground:"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "setTintColor:"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "window"},
    {PFBCompatOptionCount, "Features/Messages/PillSwap.x", "hidesSharedBackground"},
    {PFBCompatOptionCount, "Features/Messages/PillSwap.x", "menu"},
    {PFBCompatOptionCount, "Features/Messages/PillSwap.x", "setHidesSharedBackground:"},
    {PFBCompatOptionCount, "Features/Messages/PillSwap.x", "title"},
    {PFBCompatOptionCount, "Features/Messages/PillSwap.x", "window"},
    {PFBCompatOptionCount, "Features/Profiles/Profile.x", "_t1_outerTabIndexForEntry:"},
    {PFBCompatOptionCount, "Features/Profiles/Profile.x", "_t1_selectMainEntry:"},
    {PFBCompatOptionCount, "Features/Profiles/Profile.x", "contentMainEntries"},
    {PFBCompatOptionCount, "Features/Profiles/Profile.x", "currentDisplayContentProvider"},
    {PFBCompatOptionCount, "Features/Profiles/Profile.x", "viewModel"},
    {PFBCompatOptionCount, "Features/Timelines/QuickMutedWords.x", "window"},
    {PFBCompatOptionCount, "Settings/Settings.x", "icon"},
    {PFBCompatOptionCount, "Settings/Settings.x", "sections"},
    {PFBCompatOptionCount, "Settings/Settings.x", "setSeparatorHidden:"},
    {PFBCompatOptionCount, "Settings/Settings.x", "setTopSeparatorHidden:"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "_t1_applyPrimaryColorOption"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "_t1_updateImageViewAnimated:"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "_t1_updateTitleLabel"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "applyCurrentColorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "isSelected"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "reloadDynamicColors"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "selectTabAtIndex:"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "setSelectedIndex:"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "sharedSettings"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "tabView"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "tabViews"},
    {PFBCompatOptionCount, "Features/Timelines/Timeline.x", "author"},
    {PFBCompatOptionCount, "Features/Timelines/Timeline.x", "fetchPinnedTimelinesWithThrottleEnabled:"},
    {PFBCompatOptionCount, "Features/Timelines/Timeline.x", "indexPathsForVisibleItems"},
    {PFBCompatOptionCount, "Features/Timelines/Timeline.x", "scribeComponent"},
    {PFBCompatOptionCount, "Features/Timelines/Timeline.x", "updatePinnedTimelines:"},
    {PFBCompatOptionCount, "Features/Timelines/Timeline.x", "user"},
    {PFBCompatOptionCount, "Sideload/WebCreateTweet.x", "accounts"},
    {PFBCompatOptionCount, "Sideload/WebCreateTweet.x", "rootURL"},
    {PFBCompatOptionCount, "Sideload/WebCreateTweet.x", "sharedTwitter"},
    {PFBCompatOptionCount, "Sideload/PFBWebSessionLoginViewController.m", "title"},
    {PFBCompatOptionCount, "Sideload/WebCreateTweet.x", "webView"},
    {PFBCompatOptionCount, "Sideload/WebReply.x", "openURL:options:"},
    {PFBCompatOptionCount, "Sideload/WebReply.x", "statusID"},
    {PFBCompatOptionCount, "Sideload/PFBReplyWebViewController.m", "title"},
    {PFBCompatOptionCount, "Sideload/PFBReplyWebViewController.m", "webView"},
    {PFBCompatOptionCount, "Sideload/PFBReplyWebViewController.m", "window"},
    {PFBCompatOptionCount, "Sideload/PFBIconRelay.m", "window"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "accountService"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "addAccount:"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "initWithUsername:userID:"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "saveSharedTwitter"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "sharedHostViewController"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "sharedTwitter"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "updateUserInfoAndCredentialsWithToken:secret:username:"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "viewAccount:animated:"},
    {PFBCompatOptionCount, "Sideload/PFBWebLoginViewController.m", "webView"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "doubleValue"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "subtext2Font"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedAddCell.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedTermCell.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedToggleCell.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "title"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedAddCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedTermCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvancedSearchViewController.m", "openURL:options:"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvancedSearchViewController.m", "sections"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvancedSearchViewController.m", "tableView"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvancedSearchViewController.m", "title"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvBoxCell.m", "title"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvancedSearchViewController.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvMenuCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "alertColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "alertColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "alertColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "bodyBoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "dividerColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "dividerColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "faintBackgroundColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "faintBackgroundColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "faintBackgroundColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "faintBackgroundColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "primaryColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "subtext1BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "subtext1BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "subtext1BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "subtext2BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "subtext3BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsHeaderCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsButtonPairCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsCompactButtonCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTableViewCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsToggleCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBTintedSwitch.m", "window"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "TAEColorSettingsDidChangeUserDefaultsNotification"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "TFNDynamicColorsDidReloadNotification"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "TFNDynamicColorsWillReloadNotification"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "checked"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "imageURLString"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "mediaURL"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "profileImageMediaEntity"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "setChecked:"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "tableView"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "title"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "colorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "sections"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "sharedSettings"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "subtext2Font"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsViewController.m", "title"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_layoutBadgeViewMaximized"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_layoutBadgeViewMinimized"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_layoutForTabBar"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_updateImageViewAnimated:"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_updateTitleLabel"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "title"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "titleLabel"},
    {PFBCompatOptionCount, "Settings/Pages/PFBProfilesSettingsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Settings/Pages/PFBTweetsSettingsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "T1ColorSettingsPrimaryColorOptionKey"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "colorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "setPrimaryColorOption:"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "sharedSettings"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "window"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBDarkModeStyle.x", "currentColorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBDarkModeStyle.x", "isDark"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBDarkModeStyle.x", "sharedSettings"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBPalette.m", "backgroundColor"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBPalette.m", "colorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBPalette.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBPalette.m", "sharedSettings"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "T1ColorSettingsPrimaryColorOptionKey"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "TAEColorSettingsDidChangeUserDefaultsNotification"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "TFNDynamicColorManager"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "TFNDynamicColorsDidReloadNotification"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "TFNDynamicColorsWillReloadNotification"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "reloadDynamicColors"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "sharedColorManager"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "filterButton"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "setHidesSharedBackground:"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "showsFilterButton"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "window"},
    {PFBCompat_choose_explore_tabs, "Features/Search/ExploreTabs.x", "window"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "boolValue"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "hidesSharedBackground"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "title"},
    {PFBCompat_color_twitter_icon_in_top_bar, "Features/Appearance/Theme.x", "colorPalette"},
    {PFBCompat_color_twitter_icon_in_top_bar, "Features/Appearance/Theme.x", "currentColorPalette"},
    {PFBCompat_color_twitter_icon_in_top_bar, "Features/Appearance/Theme.x", "navigationBarLogoColor"},
    {PFBCompat_color_twitter_icon_in_top_bar, "Features/Appearance/Theme.x", "setTintColor:"},
    {PFBCompat_color_twitter_icon_in_top_bar, "Features/Appearance/Theme.x", "sharedSettings"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "T1ProfileHeaderView"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "XDSButton"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "createdDate"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "rowView"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "topRightActionButtonsController"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "user"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "userDataSource"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "userID"},
    {PFBCompat_disable_immersive_scroll, "Features/Media/ImmersivePlayer.x", "panRecognizer"},
    {PFBCompat_download_videos, "Features/Media/MediaDownloads.x", "entities"},
    {PFBCompat_download_videos, "Features/Media/MediaDownloads.x", "title"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "badgeColor"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "badgeCount"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "badgeView"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "font"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "hasUnreadContent"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "overflowLimit"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "textColor"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "unreadIndicatorImageView"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "setPrimaryColorOption:"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "sharedSettings"},
    {PFBCompat_hide_explore_all, "Features/Search/ExploreTabs.x", "window"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "currentAccount"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "provider"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "sharedHostViewController"},
    {PFBCompat_hide_message_button, "Features/Tweets/HideUI.x", "messageButton"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "cardNavigator"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "isPromoted"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "itemCount"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "items"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "loadedPageRange"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "status"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "statusItemViewModel"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "timelineCoordinator"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "cellForItemAtIndexPath:"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "frame"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "isHidden"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "layoutAttributesForItemAtIndexPath:"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "setHidden:"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "window"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "aggregatedDisplayReplyCount"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "replyCount"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "title"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "titleLabel"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "viewModel"},
    {PFBCompat_hide_threads, "Features/Timelines/Timeline.x", "doubleValue"},
    {PFBCompat_hide_threads, "Features/Timelines/Timeline.x", "sections"},
    {PFBCompat_hide_threads, "Features/Timelines/Timeline.x", "setSections:restoreScrollPosition:"},
    {PFBCompat_hide_tweet_button, "Features/Branding/Branding.x", "setTintColor:"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/Theme.x", "imageName"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/Theme.x", "imageView"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/Theme.x", "title"},
    {PFBCompat_web_session, "Sideload/WebCreateTweet.x", "currentAccount"},
    {PFBCompat_web_session, "Sideload/WebCreateTweet.x", "sharedHostViewController"},
    {PFBCompat_web_session, "Sideload/WebCreateTweet.x", "userID"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "adDisplayLocation"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "isPromoted"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "promotedContent"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "scribeItem"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "status"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "setItems:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "tableView"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "item"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "entryID"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "indexPathsForVisibleItems"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "language"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "scribeSection"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "sections"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "window"},
    {PFBCompat_reply_in_webview, "Sideload/WebReply.x", "status"},
    {PFBCompat_reply_in_webview, "Sideload/WebReply.x", "statusID"},
    {PFBCompat_reply_in_webview, "Sideload/WebReply.x", "tweet"},
    {PFBCompat_restore_refresh_sounds, "Features/Branding/RefreshSounds.x", "loading"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/Theme.x", "_t1_layoutForTabBar"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/Theme.x", "window"},
    {PFBCompat_restore_tweet_button, "Features/Branding/Branding.x", "setTintColor:"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "setAttributedString:"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "T1ProfileUserInfoView"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "T1UserView"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "T1UserRecommendationView"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "T1TweetDraftsDraftCompositionView"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "T1WebCardView"},
    {PFBCompat_restore_twitter_names, "Features/Appearance/Theme.x", "colorPalette"},
    {PFBCompat_restore_twitter_names, "Features/Appearance/Theme.x", "currentColorPalette"},
    {PFBCompat_restore_twitter_names, "Features/Appearance/Theme.x", "navigationBarLogoColor"},
    {PFBCompat_restore_twitter_names, "Features/Appearance/Theme.x", "setTintColor:"},
    {PFBCompat_restore_twitter_names, "Features/Appearance/Theme.x", "sharedSettings"},
    {PFBCompat_restore_video_timestamp, "Features/Media/ImmersivePlayer.x", "handleSingleTap:"},
    {PFBCompat_restore_video_timestamp, "Features/Media/ImmersivePlayer.x", "isMuted"},
    {PFBCompat_restore_video_timestamp, "Features/Media/ImmersivePlayer.x", "player"},
    {PFBCompat_restore_video_timestamp, "Features/Media/ImmersivePlayer.x", "progressLabelMode"},
    {PFBCompat_restore_video_timestamp, "Features/Media/ImmersivePlayer.x", "singleTapRecognizer"},
    {PFBCompat_restore_video_timestamp, "Features/Media/ImmersivePlayer.x", "window"},
    {PFBCompat_send_sound, "Features/Tweets/SendSound.x", "TFNTwitterCompositionOutboxDidAddCompositionNotification"},
    {PFBCompat_send_sound, "Features/Tweets/SendSound.x", "TFNTwitterCompositionOutboxDidAddUndoableCompositionNotification"},
    {PFBCompat_send_sound, "Features/Tweets/SendSound.x", "TFNTwitterCompositionOutboxNotificationCompositionUserInfoKey"},
    {PFBCompat_send_sound, "Features/Tweets/SendSound.x", "compositions"},
    {PFBCompat_send_sound, "Features/Tweets/SendSound.x", "replyChain"},
    {PFBCompat_show_quote_counts, "Features/Tweets/QuoteCounts.x", "account"},
    {PFBCompat_show_quote_counts, "Features/Tweets/QuoteCounts.x", "lookUpStatusForID:completionBlock:"},
    {PFBCompat_show_quote_counts, "Features/Tweets/QuoteCounts.x", "model"},
    {PFBCompat_show_quote_counts, "Features/Tweets/QuoteCounts.x", "quoteCount"},
    {PFBCompat_show_quote_counts, "Features/Tweets/QuoteCounts.x", "retweetCount"},
    {PFBCompat_show_quote_counts, "Features/Tweets/QuoteCounts.x", "statusID"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "footerItem"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "fromUserName"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "setTimeAgo:"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "timeAgo"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "viewModel"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "imageName"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "imageView"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "setHighlightBarColor:"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "title"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "titleLabel"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "window"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "TAVPlayerView"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "audioSessionManager"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "handleSingleTap:"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "isAutoUnmuteEnabled"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "isMuted"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "player"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "playerViewIfLoaded"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "singleTapRecognizer"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "window"},
    {PFBCompat_tweet_to_image, "Features/Media/MediaDownloads.x", "eventHandler"},
    {PFBCompat_unrounded_counts, "Features/Profiles/Profile.x", "tweetCount"},
    {PFBCompat_voice_note_from_video, "Features/Media/MediaDownloads.x", "_removeButton"},
};
enum { kNameCount = sizeof(kNames) / sizeof(kNames[0]) };

typedef struct {
    const char* file;
    const char* className;
    const char* selector;
} PFBCompatDeclared;

// Twitter methods declared and called by PrimeFreeBird; each must stay on its class.
static const PFBCompatDeclared kDeclared[] = {
    {"Support/T1Headers.h", "T1BaseWebViewController", "webView"},
    {"Support/T1Headers.h", "T1ConversationFocalStatusView", "eventHandler"},
    {"Support/T1Headers.h", "T1ConversationFocalStatusView", "viewModel"},
    {"Support/T1Headers.h", "T1ConversationFooterItem", "setTimeAgo:"},
    {"Support/T1Headers.h", "T1ConversationFooterItem", "timeAgo"},
    {"Support/T1Headers.h", "T1GenericSettingsViewController", "account"},
    {"Support/T1Headers.h", "T1HostViewController", "currentAccount"},
    {"Support/T1Headers.h", "T1MediaAttachmentsViewCell", "attachment"},
    {"Support/T1Headers.h", "T1PersistentComposeViewController", "statusViewModel"},
    {"Support/T1Headers.h", "T1ProfileHeaderViewController", "viewModel"},
    {"Support/T1Headers.h", "T1ProfileUserViewModel", "bio"},
    {"Support/T1Headers.h", "T1ProfileUserViewModel", "fullName"},
    {"Support/T1Headers.h", "T1ProfileUserViewModel", "location"},
    {"Support/T1Headers.h", "T1ProfileUserViewModel", "url"},
    {"Support/T1Headers.h", "T1ProfileUserViewModel", "username"},
    {"Support/T1Headers.h", "T1SafariViewController", "rootURL"},
    {"Support/T1Headers.h", "T1StandardStatusAttachmentViewAdapter", "attachmentType"},
    {"Support/T1Headers.h", "T1StandardStatusView", "eventHandler"},
    {"Support/T1Headers.h", "T1TabBarViewController", "tabViews"},
    {"Support/T1Headers.h", "T1TabView", "_t1_updateImageViewAnimated:"},
    {"Support/T1Headers.h", "T1TabView", "_t1_updateTitleLabel"},
    {"Support/T1Headers.h", "T1TabView", "iconColor"},
    {"Support/T1Headers.h", "T1TabView", "imageName"},
    {"Support/T1Headers.h", "T1TabView", "imageView"},
    {"Support/T1Headers.h", "T1TabView", "isSelected"},
    {"Support/T1Headers.h", "T1TabView", "panelID"},
    {"Support/T1Headers.h", "T1TabView", "scribePage"},
    {"Support/T1Headers.h", "T1TabView", "title"},
    {"Support/T1Headers.h", "T1TabView", "titleLabel"},
    {"Support/T1Headers.h", "T1TabbedAppNavigationViewController", "recalculateVisiblePanels"},
    {"Support/T1Headers.h", "TAVPlaybackState", "currentTime"},
    {"Support/T1Headers.h", "TAVPlaybackState", "duration"},
    {"Support/T1Headers.h", "TAVPlaybackState", "timeControlStatus"},
    {"Support/T1Headers.h", "TAVPlayer", "isMuted"},
    {"Support/T1Headers.h", "TAVPlayer", "pause"},
    {"Support/T1Headers.h", "TAVPlayer", "play"},
    {"Support/T1Headers.h", "TAVPlayer", "playOrReplay"},
    {"Support/T1Headers.h", "TAVPlayer", "playbackState"},
    {"Support/T1Headers.h", "TAVPlayer", "seekToTime:"},
    {"Support/T1Headers.h", "TAVPlayer", "volume"},
    {"Support/T1Headers.h", "TFCCardData", "boolForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "numberForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "numberFromStringForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "stringForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "stringForKey:defaultValue:"},
    {"Support/T1Headers.h", "TTAStatusInlineActionsView", "viewModel"},
    {"Support/T1Headers.h", "TTMAssetVideoFile", "filePath"},
    {"Support/T1Headers.h", "TUIUpdateIndicator", "pillControl"},
    {"Support/T1Headers.h", "_TtC10TwitterURT25URTTimelineTrendViewModel", "scribeItem"},
    {"Support/T1Headers.h", "_TtC21TweetMediaAttachments14MultiMediaView", "inlineMediaInfos"},
    {"Support/TAEHeaders.h", "TAEColorSettings", "currentColorPalette"},
    {"Support/TAEHeaders.h", "TAEColorSettings", "setPrimaryColorOption:"},
    {"Support/TAEHeaders.h", "TAEColorSettings", "sharedSettings"},
    {"Support/TAEHeaders.h", "TAETwitterColorPaletteSettingInfo", "colorPalette"},
    {"Support/TAEHeaders.h", "TAETwitterColorPaletteSettingInfo", "isDark"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "fontOfSize:"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "headline2BoldFont"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "heavyFontOfSize:"},
    {"Support/TFNHeaders.h", "TFNActionItem", "actionItemWithTitle:action:"},
    {"Support/TFNHeaders.h", "TFNActionItem", "actionItemWithTitle:imageName:action:"},
    {"Support/TFNHeaders.h", "TFNAttributedTextModel", "attributedString"},
    {"Support/TFNHeaders.h", "TFNAttributedTextModel", "initWithAttributedString:"},
    {"Support/TFNHeaders.h", "TFNDataViewController", "adDisplayLocation"},
    {"Support/TFNHeaders.h", "TFNDataViewController", "tableView"},
    {"Support/TFNHeaders.h", "TFNHUD", "hide"},
    {"Support/TFNHeaders.h", "TFNHUD", "setText:"},
    {"Support/TFNHeaders.h", "TFNHUD", "show"},
    {"Support/TFNHeaders.h", "TFNItemsDataViewController", "sections"},
    {"Support/TFNHeaders.h", "TFNMenuSheetViewController", "initWithActionItems:"},
    {"Support/TFNHeaders.h", "TFNMenuSheetViewController", "tfnPresentedCustomPresentFromViewController:animated:completion:"},
    {"Support/TFNHeaders.h", "TFNPillControl", "text"},
    {"Support/TFNHeaders.h", "TFNTwitter", "accounts"},
    {"Support/TFNHeaders.h", "TFNTwitterAccount", "displayUsername"},
    {"Support/TFNHeaders.h", "TFNTwitterAccount", "model"},
    {"Support/TFNHeaders.h", "TFNTwitterAccount", "username"},
    {"Support/TFNHeaders.h", "TFNTwitterAccountModel", "lookUpStatusForID:completionBlock:"},
    {"Support/TFNHeaders.h", "TFNTwitterComposition", "replyChain"},
    {"Support/TFNHeaders.h", "TFNTwitterComposition", "undoTimeInterval"},
    {"Support/TFNHeaders.h", "TFNTwitterComposition", "undoableAddedDate"},
    {"Support/TFNHeaders.h", "TFNTwitterCompositionReplyChain", "compositions"},
    {"Support/TFNHeaders.h", "TFNTwitterStatus", "entities"},
    {"Support/TFNHeaders.h", "TFNTwitterStatus", "isPromoted"},
    {"Support/TFNHeaders.h", "TFNTwitterStatus", "quoteCount"},
    {"Support/TFNHeaders.h", "TFNTwitterStatus", "retweetCount"},
    {"Support/TFNHeaders.h", "TFNTwitterStatus", "statusID"},
    {"Support/TFNHeaders.h", "UIImage", "tfn_vectorImageNamed:height:fillColor:"},
    {"Support/TFNHeaders.h", "UIImage", "tfn_vectorImageNamed:highContrastVariantNamed:fitsSize:fillColor:"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMedia", "mediaType"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMedia", "videoInfo"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMediaVideoInfo", "variants"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMediaVideoVariant", "contentType"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMediaVideoVariant", "url"},
    {"Support/TFSHeaders.h", "TFSTwitterEntitySet", "media"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityURL", "expandedURL"},
    {"Support/TFSHeaders.h", "TFSTwitterMediaInfo", "mediaEntity"},
    {"Support/TFSHeaders.h", "TFSTwitterRelationship", "superFollowingState"},
    {"Features/Profiles/Avatars.x", "TFNAvatarImageView", "style"},
    {"Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.m", "TFNFloatingActionButton", "hideAnimated:completion:"},
    {"Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.m", "TFNFloatingActionButton", "showAnimated:completion:"},
    {"Support/Helpers.h", "SFSafariViewController", "initialURL"},
    {"Support/T1Headers.h", "T1TabView", "setIconColor:"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "boldFontOfSize:"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "sharedFontGroup"},
    {"Support/TFSHeaders.h", "NSNumber", "tfs_twitterAbbreviated"},
};
enum { kDeclaredCount = sizeof(kDeclared) / sizeof(kDeclared[0]) };

// Options that act through their feature switches alone.
static const PFBCompatOption kFlagOnly[] = {
    PFBCompat_hide_grok_bot,
    PFBCompat_unlimited_timeline_tabs,
    PFBCompat_disable_auto_translate,
    PFBCompat_hide_grok_analyze,
    PFBCompat_force_following_tab,
    PFBCompat_disable_articles,
    PFBCompat_disable_highlights,
    PFBCompat_reply_sorting,
    PFBCompat_restore_reply_context,
    PFBCompat_disable_video_captions,
    PFBCompat_voice_transcription,
    PFBCompat_new_inapp_webview,
    PFBCompat_no_focus_lost,
    PFBCompat_disable_media_carousel,
};
static const size_t kFlagOnlyCount = sizeof(kFlagOnly) / sizeof(kFlagOnly[0]);

typedef struct {
    PFBCompatOption option;
    const char* className;
} PFBCompatClassText;

// Twitter classes the options compare by name; a name that no longer resolves
// is content the option can no longer recognize.
static const PFBCompatClassText kClassTexts[] = {
    {PFBCompat_hide_timeline_prompts, "TwitterURT.URTTimelinePromptViewModel"},
    {PFBCompat_hide_who_to_follow, "T1TwitterSwift.URTTimelineCarouselViewModel"},
    {PFBCompat_hide_trend_videos, "T1TwitterSwift.URTTimelineCarouselViewModel"},
    {PFBCompat_hide_premium_offer, "T1URTTimelineMessageItemViewModel"},
    {PFBCompat_hide_promoted, "TwitterURT.URTTimelineGoogleNativeAdViewModel"},
    {PFBCompat_hide_promoted, "TwitterURT.URTTimelineTrendViewModel"},
    {PFBCompat_hide_promoted, "TwitterURT.URTTimelineEventSummaryViewModel"},
};
static const size_t kClassTextCount = sizeof(kClassTexts) / sizeof(kClassTexts[0]);

// Options whose only way to find their content is one of those names.
static const PFBCompatOption kClassOnly[] = {
    PFBCompat_hide_timeline_prompts,
    PFBCompat_hide_trend_videos,
};
static const size_t kClassOnlyCount = sizeof(kClassOnly) / sizeof(kClassOnly[0]);

typedef struct {
    PFBCompatOption option;
    const char* stations;  // the tour steps where its proof must come, separated by '|'
    const char* absent;    // what may simply not happen that day, or NULL
} PFBCompatContract;

// Where each option must prove itself during the path tour. "launch" is judged once
// the tour ends, so the start's late proofs still count.
static const PFBCompatContract kContract[] = {
    {PFBCompat_padlock, "launch", NULL},
    {PFBCompat_no_screenshot_detection, "launch", NULL},
    {PFBCompat_force_following_tab, "tab home", NULL},
    {PFBCompat_no_focus_lost, "launch", NULL},
    {PFBCompat_no_tab_bar_hiding, "scroll", "tab bar hiding"},
    {PFBCompat_show_scroll_indicator, "tab home", NULL},
    {PFBCompat_disable_rtl, "launch", NULL},
    {PFBCompat_hide_premium_offer, "own profile", NULL},
    {PFBCompat_sharing_domain, "video long press", "shared link"},
    {PFBCompat_strip_url_tracking, "video long press", "tracked link"},
    {PFBCompat_always_open_safari, "web link", NULL},
    {PFBCompat_new_inapp_webview, "launch", NULL},
    {PFBCompat_custom_tab_bar, "launch", NULL},
    {PFBCompat_restore_tab_labels, "launch", NULL},
    {PFBCompat_custom_fonts, "launch", NULL},
    {PFBCompat_tab_bar_theming, "launch", NULL},
    {PFBCompat_color_pfb_switches, "PFB settings", NULL},
    {PFBCompat_color_twitter_icon_in_top_bar, "launch", NULL},
    {PFBCompat_enable_liquid_glass, "launch", NULL},
    {PFBCompat_dark_mode_style, "dark mode", NULL},
    {PFBCompat_accent_color, "launch", NULL},
    {PFBCompat_hide_promoted, "tab home", NULL},
    {PFBCompat_hide_who_to_follow, "tab home", "Who to follow module"},
    {PFBCompat_hide_topics_to_follow, "tab home", "topic suggestions"},
    {PFBCompat_hide_timeline_prompts, "tab home", "timeline prompt"},
    {PFBCompat_hide_topics, "tab home", "topic Tweet"},
    {PFBCompat_hide_verified_tweets, "tab home|search", NULL},
    {PFBCompat_hide_blocked_retweets, "tab home|following timeline", "retweet"},
    {PFBCompat_reading_line, "following timeline", NULL},
    {PFBCompat_hide_spaces, "tab home", NULL},
    {PFBCompat_hide_new_tweets_pill, "refresh end", "new-posts pill"},
    {PFBCompat_hide_scroll_edge_blur, "tab home", NULL},
    {PFBCompat_hide_custom_timelines, "launch", NULL},
    {PFBCompat_unlimited_timeline_tabs, "launch", NULL},
    {PFBCompat_muted_words, "tab home", NULL},
    {PFBCompat_undo_tweet_timeout, "composer", "Tweet sent"},
    {PFBCompat_tweet_confirm, "composer", NULL},
    {PFBCompat_hide_tweet_button, "tab home", NULL},
    {PFBCompat_send_sound, "", "the tour never sends a Tweet"},
    {PFBCompat_hide_threads, "Tweet menu", NULL},
    {PFBCompat_like_confirm, "Tweet buttons", NULL},
    {PFBCompat_hide_view_count, "tab home", NULL},
    {PFBCompat_hide_bookmark_button, "tab home", NULL},
    {PFBCompat_hide_downvote_button, "first Tweet", "reply with a downvote button"},
    {PFBCompat_show_poll_results, "tab home", "poll"},
    {PFBCompat_disable_sensitive_tweet_warnings, "tab home", NULL},
    {PFBCompat_bypass_age_verification, "tab home", "age-restricted post"},
    {PFBCompat_reply_sorting, "first Tweet", NULL},
    {PFBCompat_restore_reply_context, "first Tweet", "opened reply"},
    {PFBCompat_show_quote_counts, "Tweet interactions", NULL},
    {PFBCompat_show_account_location, "first Tweet", NULL},
    {PFBCompat_hide_notifications, "tab ntab", "hidden notification"},
    {PFBCompat_download_videos, "video long press", NULL},
    {PFBCompat_download_highest_quality, "video long press", NULL},
    {PFBCompat_direct_save, "video long press", NULL},
    {PFBCompat_tweet_to_image, "Tweet buttons", NULL},
    {PFBCompat_tap_to_pause, "video full screen", NULL},
    {PFBCompat_restore_video_timestamp, "video full screen", NULL},
    {PFBCompat_disable_video_captions, "tab home", NULL},
    {PFBCompat_disable_immersive_scroll, "video full screen", "auto-advance decision"},
    {PFBCompat_disable_video_docking, "video full screen", "docking question"},
    {PFBCompat_auto_highest_load, "photo full screen", NULL},
    {PFBCompat_enable_image_preloading, "tab home", NULL},
    {PFBCompat_force_tweet_full_frame, "tab home", NULL},
    {PFBCompat_disable_media_carousel, "launch", NULL},
    {PFBCompat_upload_full_hd_videos, "composer", "video attached"},
    {PFBCompat_voice_note_from_video, "composer", "voice recording attached"},
    {PFBCompat_follow_confirm, "other profile", NULL},
    {PFBCompat_expand_bio, "other profile", NULL},
    {PFBCompat_copy_profile_info, "other profile", NULL},
    {PFBCompat_unrounded_counts, "other profile", NULL},
    {PFBCompat_disable_articles, "own profile", NULL},
    {PFBCompat_disable_highlights, "own profile", NULL},
    {PFBCompat_disable_videos_tab, "own profile", NULL},
    {PFBCompat_hide_blue_verified, "tab home", NULL},
    {PFBCompat_hide_follow_button, "other profile", NULL},
    {PFBCompat_hide_message_button, "tab home", "Message button in an author row"},
    {PFBCompat_restore_follow_button, "tab home", NULL},
    {PFBCompat_square_avatars, "tab home", NULL},
    {PFBCompat_profile_initial_tab, "own profile", NULL},
    {PFBCompat_no_history, "search field", NULL},
    {PFBCompat_advanced_search, "tab guide", NULL},
    {PFBCompat_hide_trend_videos, "tab guide", "trending videos"},
    {PFBCompat_hide_explore_all, "tab guide", NULL},
    {PFBCompat_choose_explore_tabs, "tab guide", NULL},
    {PFBCompat_hide_typing_indicator, "conversation", NULL},
    {PFBCompat_voice_transcription, "conversation", "voice note"},
    {PFBCompat_download_voice_messages, "conversation", "voice note"},
    {PFBCompat_hide_grok_analyze, "launch", NULL},
    {PFBCompat_hide_grok_sidebar, "side menu", NULL},
    {PFBCompat_hide_grok_bot, "launch|side menu", NULL},
    {PFBCompat_hide_grok_create, "launch", NULL},
    {PFBCompat_disable_auto_translate, "launch", NULL},
    {PFBCompat_restore_twitter_names, "launch", NULL},
    {PFBCompat_refresh_pill_label, "refresh end", "new-posts pill"},
    {PFBCompat_restore_tweet_button, "tab home", NULL},
    {PFBCompat_restore_refresh_sounds, "pull|refresh end", NULL},
    {PFBCompat_reply_in_webview, "Tweet buttons", NULL},
    {PFBCompat_flex_twitter, "launch", NULL},
    {PFBCompat_web_session, "", "a web session only proves itself by creating a Space"},
};
static const size_t kContractCount = sizeof(kContract) / sizeof(kContract[0]);

typedef struct {
    PFBCompatPath path;
    const char* station;
} PFBCompatPathStation;

// The tour step that must reach each path. Paths that hang on content, on the tab bar
// style, or on a flag Twitter reads only when its own gating allows, have none.
static const PFBCompatPathStation kPathStations[] = {
    {PFBCompatPath_pull_sound, "pull"},
    {PFBCompatPath_refresh_end_sound, "refresh end"},
    {PFBCompatPath_copy_button, "other profile"},
    {PFBCompatPath_copy_id_and_date, "other profile"},
    {PFBCompatPath_follower_counts, "other profile"},
    {PFBCompatPath_post_count, "other profile"},
    {PFBCompatPath_verified_search, "search"},
    {PFBCompatPath_promoted_video_feed, "video full screen"},
};
static const size_t kPathStationCount = sizeof(kPathStations) / sizeof(kPathStations[0]);

// How the report names a tour step's screen.
static NSString* stationLabel(NSString* station) {
    static NSDictionary<NSString*, NSString*>* labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      labels = @{
          @"launch": @"the app's launch",
          @"tab guide": @"the Explore tab",
          @"tab ntab": @"the Notifications tab",
          @"tab home": @"the Home timeline",
          @"pull": @"a pull to refresh",
          @"first Tweet": @"an opened Tweet",
          @"Tweet interactions": @"a Tweet's interactions",
          @"own profile": @"your profile",
          @"search": @"search results",
          @"refresh end": @"the end of a refresh",
          @"following timeline": @"the Following timeline",
          @"scroll": @"a scrolled timeline",
          @"Tweet buttons": @"a Tweet's buttons",
          @"Tweet menu": @"a Tweet's menu",
          @"video full screen": @"a full-screen video",
          @"video long press": @"a video's long-press menu",
          @"photo full screen": @"a full-screen photo",
          @"other profile": @"another account's profile",
          @"composer": @"the composer",
          @"search field": @"the search field",
          @"conversation": @"a conversation",
          @"side menu": @"the side menu",
          @"dark mode": @"dark mode",
          @"web link": @"a web link",
          @"PFB settings": @"the PFB settings",
      };
    });
    return labels[station] ?: station;
}

static const PFBCompatContract* contractFor(PFBCompatOption option) {
    for (size_t i = 0; i < kContractCount; i++) {
        if (kContract[i].option == option) {
            return &kContract[i];
        }
    }
    return NULL;
}

static NSArray<NSString*>* contractStations(const PFBCompatContract* contract) {
    if (!contract || !contract->stations || !contract->stations[0]) {
        return @[];
    }
    return [[NSString stringWithUTF8String:contract->stations] componentsSeparatedByString:@"|"];
}

static const PFBCompatPathMeta* pathMetaFor(PFBCompatPath path) {
    for (size_t i = 0; i < kPathCount; i++) {
        if (kPaths[i].path == path) {
            return &kPaths[i];
        }
    }
    return NULL;
}

// MARK: - Counting

static NSString* const kStoreKey = @"pfb_compat_evidence";
NSString* const PFBCompatStatusKey = @"pfb_compat_status";

// Actions since the last save, and whether this install has a detail yet.
static _Atomic(uint64_t) gHits[PFBCompatOptionCount];
static atomic_bool gHasDetail[PFBCompatOptionCount];
static atomic_bool gDirty;
static atomic_bool gObserved[PFBCompatOptionCount];
static atomic_bool gPathSeen[PFBCompatPathCount];
static NSString* gPendingObservation[PFBCompatOptionCount];
static os_unfair_lock gObservationLock = OS_UNFAIR_LOCK_INIT;

static NSObject* gLock;
static NSMutableDictionary* gStore;
static NSString* gTwitterVersion;
static const char* gKeys[PFBCompatOptionCount];

void PFBCompatCount(PFBCompatOption option) {
    if (option > PFBCompatOptionNone && option < PFBCompatOptionCount) {
        atomic_fetch_add_explicit(&gHits[option], 1, memory_order_relaxed);
    }
}

BOOL PFBCompatWantsDetail(PFBCompatOption option) {
    return option > PFBCompatOptionNone && option < PFBCompatOptionCount &&
           !atomic_load_explicit(&gHasDetail[option], memory_order_relaxed);
}

// The start of a loaded binary's UUID, which changes only when the binary is rebuilt.
static NSString* imageUUID(const struct mach_header_64* header) {
    if (!header) {
        return @"?";
    }
    const uint8_t* cursor = (const uint8_t*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command* command = (const struct load_command*)cursor;
        if (command->cmd == LC_UUID) {
            const uint8_t* uuid = ((const struct uuid_command*)command)->uuid;
            return [NSString stringWithFormat:@"%02X%02X%02X%02X", uuid[0], uuid[1], uuid[2], uuid[3]];
        }
        cursor += command->cmdsize;
    }
    return @"?";
}

// The start of PrimeFreeBird's own UUID: a rebuild counts as a new install.
static NSString* tweakBuild(void) {
    Dl_info info;
    if (!dladdr((const void*)&tweakBuild, &info) || !info.dli_fbase) {
        return @"?";
    }
    return imageUUID((const struct mach_header_64*)info.dli_fbase);
}

NSString* PFBCompatBuildID(void) {
    return tweakBuild();
}

// Twitter's own binary: the build number the install pipeline writes changes with
// every build, while this changes only with a new IPA.
static NSString* twitterBinary(void) {
    return imageUUID((const struct mach_header_64*)_dyld_get_image_header(0));
}

// Caller holds gLock or runs the one-time load.
static NSDictionary* storeDictionary(NSString* name) {
    id value = gStore[name];
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

// Caller holds gLock or runs the one-time load.
static void writeStore(void) {
    [[NSUserDefaults standardUserDefaults] setObject:[gStore copy] forKey:kStoreKey];
}

// Caller holds gLock or runs the one-time load. Adds this build's evidence to what
// earlier builds of the same Twitter version proved.
static void foldIntoEarlier(void) {
    NSMutableDictionary* earlier = [storeDictionary(@"earlier") mutableCopy];
    for (NSString* kind in @[ @"counts", @"details", @"observed", @"paths" ]) {
        NSMutableDictionary* kept = [earlier[kind] isKindOfClass:[NSDictionary class]]
                                        ? [earlier[kind] mutableCopy] : [NSMutableDictionary dictionary];
        NSDictionary* current = storeDictionary(kind);
        for (NSString* key in current) {
            id value = current[key];
            if ([kind isEqualToString:@"counts"]) {
                kept[key] = @([kept[key] unsignedLongLongValue] + [value unsignedLongLongValue]);
            } else if ([kind isEqualToString:@"paths"] && [value isKindOfClass:[NSArray class]]) {
                NSMutableOrderedSet* names = [NSMutableOrderedSet orderedSetWithArray:
                    [kept[key] isKindOfClass:[NSArray class]] ? kept[key] : @[]];
                [names addObjectsFromArray:value];
                kept[key] = names.array;
            } else if (!kept[key]) {
                kept[key] = value;
            }
        }
        earlier[kind] = kept;
    }
    gStore[@"earlier"] = earlier;
    if (![gStore[@"earlierSince"] isKindOfClass:[NSDate class]]) {
        gStore[@"earlierSince"] = [gStore[@"since"] isKindOfClass:[NSDate class]] ? gStore[@"since"] : [NSDate date];
    }
}

// Loads what was counted before. A rebuild on the same Twitter keeps what earlier builds
// proved, shown apart until seen again; a new Twitter version starts clean.
static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gLock = [NSObject new];
      for (size_t i = 0; i < kMetaCount; i++) {
          gKeys[kMeta[i].option] = kMeta[i].key;
      }
      NSDictionary* info = NSBundle.mainBundle.infoDictionary;
      gTwitterVersion = info[@"CFBundleShortVersionString"] ?: @"?";
      NSString* twitter = [NSString stringWithFormat:@"%@ (%@)", gTwitterVersion,
                                                     info[@"CFBundleVersion"] ?: @"?"];
      NSString* identity = [NSString stringWithFormat:@"%@ \u00b7 %@", twitter, tweakBuild()];
      NSDictionary* saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kStoreKey];
      gStore = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
      if (![gStore[@"identity"] isEqual:identity]) {
          id previous = gStore[@"identity"];
          id storedBinary = gStore[@"twitterBinary"];
          BOOL sameTwitter = [storedBinary isKindOfClass:[NSString class]]
              ? [storedBinary isEqualToString:twitterBinary()]
              : [previous isKindOfClass:[NSString class]] &&
                    [previous hasPrefix:[gTwitterVersion stringByAppendingString:@" ("]];
          gStore[@"twitterBinary"] = twitterBinary();
          if (sameTwitter) {
              foldIntoEarlier();
          } else {
              gStore[@"earlier"] = @{};
              [gStore removeObjectForKey:@"earlierSince"];
              gStore[@"checkDue"] = twitterBinary();
          }
          gStore[@"tour"] = @{};
          gStore[@"identity"] = identity;
          gStore[@"since"] = [NSDate date];
          gStore[@"counts"] = @{};
          gStore[@"details"] = @{};
          gStore[@"observed"] = @{};
          gStore[@"paths"] = @{};
          [gStore removeObjectForKey:@"flags"];
          writeStore();
      }
      NSDictionary* details = storeDictionary(@"details");
      for (size_t i = 0; i < kMetaCount; i++) {
          if (details[[NSString stringWithUTF8String:kMeta[i].key]]) {
              atomic_store_explicit(&gHasDetail[kMeta[i].option], true, memory_order_relaxed);
          }
      }
    });
}

void PFBCompatSetDetail(PFBCompatOption option, NSString* detail) {
    if (option <= PFBCompatOptionNone || option >= PFBCompatOptionCount || detail.length == 0) {
        return;
    }
    prepare();
    const char* key = gKeys[option];
    if (!key) {
        return;
    }
    NSString* name = [NSString stringWithUTF8String:key];
    @synchronized(gLock) {
        NSMutableDictionary* details = [storeDictionary(@"details") mutableCopy];
        if (!details[name]) {
            details[name] = detail;
            gStore[@"details"] = details;
            atomic_store_explicit(&gDirty, true, memory_order_relaxed);
        }
    }
    atomic_store_explicit(&gHasDetail[option], true, memory_order_relaxed);
}

BOOL PFBCompatNeedsObservation(PFBCompatOption option) {
    return (size_t)option < PFBCompatOptionCount &&
           !atomic_load_explicit(&gObserved[option], memory_order_relaxed);
}

// Held in memory until the next save: this runs on hot paths, some of them
// reached while the store itself is being read.
void PFBCompatObserve(PFBCompatOption option, NSString* detail) {
    if ((size_t)option >= PFBCompatOptionCount ||
        atomic_exchange_explicit(&gObserved[option], true, memory_order_relaxed)) {
        return;
    }
    os_unfair_lock_lock(&gObservationLock);
    gPendingObservation[option] = detail.length ? detail : @"-";
    os_unfair_lock_unlock(&gObservationLock);
}

// Once per launch per path, cheap enough for the hot paths it sits on.
void PFBCompatReach(PFBCompatPath path) {
    if ((size_t)path >= PFBCompatPathCount ||
        atomic_load_explicit(&gPathSeen[path], memory_order_relaxed) ||
        atomic_exchange_explicit(&gPathSeen[path], true, memory_order_relaxed)) {
        return;
    }
    atomic_store_explicit(&gDirty, true, memory_order_relaxed);
}

BOOL PFBCompatPathReached(PFBCompatPath path) {
    return (size_t)path < PFBCompatPathCount &&
           atomic_load_explicit(&gPathSeen[path], memory_order_relaxed);
}

static NSString* pendingObservation(PFBCompatOption option, BOOL take) {
    os_unfair_lock_lock(&gObservationLock);
    NSString* detail = gPendingObservation[option];
    if (take) {
        gPendingObservation[option] = nil;
    }
    os_unfair_lock_unlock(&gObservationLock);
    return detail;
}

static void clearObservations(void) {
    os_unfair_lock_lock(&gObservationLock);
    for (size_t i = 0; i < PFBCompatOptionCount; i++) {
        gPendingObservation[i] = nil;
        atomic_store_explicit(&gObserved[i], false, memory_order_relaxed);
    }
    os_unfair_lock_unlock(&gObservationLock);
}

// Folds the live counts into the stored ones and writes them out.
static void save(void) {
    prepare();
    @synchronized(gLock) {
        NSMutableDictionary* counts = [storeDictionary(@"counts") mutableCopy];
        NSMutableDictionary* observed = [storeDictionary(@"observed") mutableCopy];
        NSMutableDictionary* paths = [storeDictionary(@"paths") mutableCopy];
        BOOL changed = atomic_exchange_explicit(&gDirty, false, memory_order_relaxed);
        for (size_t i = 0; i < kPathCount; i++) {
            const char* owner = gKeys[kPaths[i].option];
            if (!owner || !atomic_load_explicit(&gPathSeen[kPaths[i].path], memory_order_relaxed)) {
                continue;
            }
            NSString* key = [NSString stringWithUTF8String:owner];
            NSString* name = [NSString stringWithUTF8String:kPaths[i].name];
            NSArray* seen = [paths[key] isKindOfClass:[NSArray class]] ? paths[key] : @[];
            if (![seen containsObject:name]) {
                paths[key] = [seen arrayByAddingObject:name];
                changed = YES;
            }
        }
        for (size_t i = 0; i < kMetaCount; i++) {
            NSString* seen = pendingObservation(kMeta[i].option, YES);
            if (seen) {
                NSString* name = [NSString stringWithUTF8String:kMeta[i].key];
                if (!observed[name]) {
                    observed[name] = seen;
                }
                changed = YES;
            }
            uint64_t hits = atomic_exchange_explicit(&gHits[kMeta[i].option], 0, memory_order_relaxed);
            if (hits == 0) {
                continue;
            }
            NSString* name = [NSString stringWithUTF8String:kMeta[i].key];
            counts[name] = @([counts[name] unsignedLongLongValue] + hits);
            changed = YES;
        }
        if (!changed) {
            return;
        }
        gStore[@"counts"] = counts;
        gStore[@"observed"] = observed;
        gStore[@"paths"] = paths;
        writeStore();
    }
}

// MARK: - Tour stations

// Acted or noted on this build, whether the proof is saved yet or still in memory.
static BOOL optionProven(PFBCompatOption option) {
    if ((size_t)option >= PFBCompatOptionCount) {
        return NO;
    }
    if (atomic_load_explicit(&gHits[option], memory_order_relaxed) > 0 ||
        atomic_load_explicit(&gObserved[option], memory_order_relaxed)) {
        return YES;
    }
    prepare();
    const char* key = gKeys[option];
    if (!key) {
        return NO;
    }
    NSString* name = [NSString stringWithUTF8String:key];
    @synchronized(gLock) {
        return [storeDictionary(@"counts")[name] unsignedLongLongValue] > 0 ||
               [storeDictionary(@"observed")[name] isKindOfClass:[NSString class]];
    }
}

static BOOL pathProven(const PFBCompatPathMeta* meta) {
    if (atomic_load_explicit(&gPathSeen[meta->path], memory_order_relaxed)) {
        return YES;
    }
    const char* owner = gKeys[meta->option];
    if (!owner) {
        return NO;
    }
    NSString* key = [NSString stringWithUTF8String:owner];
    @synchronized(gLock) {
        id seen = storeDictionary(@"paths")[key];
        return [seen isKindOfClass:[NSArray class]] &&
               [seen containsObject:[NSString stringWithUTF8String:meta->name]];
    }
}

NSSet<NSString*>* PFBCompatStationPending(NSString* station) {
    prepare();
    NSMutableSet<NSString*>* pending = [NSMutableSet set];
    for (size_t i = 0; i < kContractCount; i++) {
        if ([contractStations(&kContract[i]) containsObject:station] && !optionProven(kContract[i].option) &&
            gKeys[kContract[i].option]) {
            [pending addObject:[NSString stringWithUTF8String:gKeys[kContract[i].option]]];
        }
    }
    for (size_t i = 0; i < kPathStationCount; i++) {
        const PFBCompatPathMeta* meta = pathMetaFor(kPathStations[i].path);
        if (meta && [station isEqualToString:[NSString stringWithUTF8String:kPathStations[i].station]] &&
            !pathProven(meta)) {
            [pending addObject:[@"path:" stringByAppendingString:[NSString stringWithUTF8String:meta->name]]];
        }
    }
    return pending;
}

BOOL PFBCompatStationLeft(NSString* station) {
    return PFBCompatStationPending(station).count > 0;
}

// Caller holds gLock.
static NSMutableDictionary* mutableTour(void) {
    return [storeDictionary(@"tour") mutableCopy];
}

void PFBCompatStationRecord(NSString* station, BOOL reached, NSSet<NSString*>* missed) {
    prepare();
    @synchronized(gLock) {
        NSMutableDictionary* tour = mutableTour();
        NSMutableDictionary* stations = [tour[@"stations"] isKindOfClass:[NSDictionary class]]
                                            ? [tour[@"stations"] mutableCopy]
                                            : [NSMutableDictionary dictionary];
        stations[station] = @{
            @"reached": @(reached),
            @"missed": reached ? (missed.allObjects ?: @[]) : @[],
        };
        tour[@"stations"] = stations;
        gStore[@"tour"] = tour;
        writeStore();
    }
}

void PFBCompatStationRecordCrash(NSString* station) {
    prepare();
    @synchronized(gLock) {
        NSMutableDictionary* tour = mutableTour();
        NSMutableDictionary* stations = [tour[@"stations"] isKindOfClass:[NSDictionary class]]
                                            ? [tour[@"stations"] mutableCopy]
                                            : [NSMutableDictionary dictionary];
        stations[station] = @{@"reached": @NO, @"crashed": @YES, @"missed": @[]};
        tour[@"stations"] = stations;
        NSMutableArray* crashed = [tour[@"crashed"] isKindOfClass:[NSArray class]] ? [tour[@"crashed"] mutableCopy]
                                                                                   : [NSMutableArray array];
        if (![crashed containsObject:station]) {
            [crashed addObject:station];
        }
        tour[@"crashed"] = crashed;
        gStore[@"tour"] = tour;
        writeStore();
    }
}

BOOL PFBCompatStationCrashed(NSString* station) {
    prepare();
    @synchronized(gLock) {
        id crashed = storeDictionary(@"tour")[@"crashed"];
        return [crashed isKindOfClass:[NSArray class]] && [crashed containsObject:station];
    }
}

void PFBCompatTourRecord(BOOL full, NSString* stop, NSArray<NSString*>* results) {
    prepare();
    @synchronized(gLock) {
        NSMutableDictionary* tour = mutableTour();
        NSMutableDictionary* last = [@{@"full": @(full), @"results": results ?: @[], @"at": [NSDate date]} mutableCopy];
        if (stop.length) {
            last[@"stop"] = stop;
        }
        tour[@"last"] = last;
        gStore[@"tour"] = tour;
        // A full tour answers the question a new Twitter raises, whatever it found.
        if (full && !stop.length) {
            [gStore removeObjectForKey:@"checkDue"];
        }
        writeStore();
    }
    PFBCompatRefreshStatus();
}

BOOL PFBCompatCheckIsDue(void) {
    prepare();
    id due;
    @synchronized(gLock) {
        due = gStore[@"checkDue"];
    }
    return [due isKindOfClass:[NSString class]] && [due isEqualToString:twitterBinary()];
}

// The last tour's record, or nil before the first one on this build.
static NSDictionary* lastTour(void) {
    prepare();
    @synchronized(gLock) {
        id last = storeDictionary(@"tour")[@"last"];
        return [last isKindOfClass:[NSDictionary class]] ? last : nil;
    }
}

static NSString* tourTime(NSDictionary* last) {
    NSDateFormatter* formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm";
    id at = last[@"at"];
    return [at isKindOfClass:[NSDate class]] ? [formatter stringFromDate:at] : @"?";
}

NSString* PFBCompatTourLastRun(void) {
    NSDictionary* last = lastTour();
    if (!last) {
        return nil;
    }
    NSArray* results = [last[@"results"] isKindOfClass:[NSArray class]] ? last[@"results"] : @[];
    NSUInteger reached = 0;
    for (NSString* result in results) {
        reached += [result isKindOfClass:[NSString class]] && ![result hasSuffix:@" not reached"] ? 1 : 0;
    }
    NSString* stop = [last[@"stop"] isKindOfClass:[NSString class]] ? last[@"stop"] : nil;
    if (stop) {
        return [NSString stringWithFormat:@"Stopped at %@ (%@) \u00b7 %lu of %lu screens reached", tourTime(last), stop,
                                          (unsigned long)reached, (unsigned long)results.count];
    }
    return [NSString stringWithFormat:@"%@ at %@ \u00b7 %lu of %lu screens reached",
                                      [last[@"full"] boolValue] ? @"Full tour" : @"Remaining", tourTime(last),
                                      (unsigned long)reached, (unsigned long)results.count];
}

// MARK: - Twitter's feature switches, read from its binaries

// One __TEXT section of a Mach-O file, or NULL. An encrypted file reads as noise,
// so it is reported instead of searched.
static const char* textSection(NSData* data, const char* name, size_t* size, BOOL* encrypted) {
    const uint8_t* bytes = data.bytes;
    size_t length = data.length;
    if (length < sizeof(struct mach_header_64)) {
        return NULL;
    }
    size_t base = 0;
    uint32_t magic = *(const uint32_t*)bytes;
    if (magic == FAT_CIGAM || magic == FAT_MAGIC) {
        const struct fat_header* fat = (const struct fat_header*)bytes;
        uint32_t count = OSSwapBigToHostInt32(fat->nfat_arch);
        const struct fat_arch* archs = (const struct fat_arch*)(fat + 1);
        base = SIZE_MAX;
        for (uint32_t i = 0; i < count; i++) {
            if ((const uint8_t*)(archs + i + 1) > bytes + length) {
                break;
            }
            if ((cpu_type_t)OSSwapBigToHostInt32((uint32_t)archs[i].cputype) == CPU_TYPE_ARM64) {
                base = OSSwapBigToHostInt32(archs[i].offset);
                break;
            }
        }
        if (base == SIZE_MAX || base + sizeof(struct mach_header_64) > length) {
            return NULL;
        }
        magic = *(const uint32_t*)(bytes + base);
    }
    if (magic != MH_MAGIC_64) {
        return NULL;
    }
    const struct mach_header_64* header = (const struct mach_header_64*)(bytes + base);
    size_t offset = base + sizeof(struct mach_header_64);
    const char* found = NULL;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (offset + sizeof(struct load_command) > length) {
            return NULL;
        }
        const struct load_command* command = (const struct load_command*)(bytes + offset);
        if (command->cmdsize == 0 || offset + command->cmdsize > length) {
            return NULL;
        }
        if (command->cmd == LC_ENCRYPTION_INFO_64 &&
            ((const struct encryption_info_command_64*)command)->cryptid != 0) {
            *encrypted = YES;
            return NULL;
        }
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* segment = (const struct segment_command_64*)command;
            const struct section_64* sections = (const struct section_64*)(segment + 1);
            for (uint32_t j = 0; j < segment->nsects; j++) {
                const struct section_64* section = &sections[j];
                if (strncmp(section->segname, "__TEXT", 16) == 0 &&
                    strncmp(section->sectname, name, 16) == 0 &&
                    base + section->offset + section->size <= length) {
                    found = (const char*)(bytes + base + section->offset);
                    *size = (size_t)section->size;
                }
            }
        }
        offset += command->cmdsize;
    }
    return found;
}

// Twitter's own binaries: the app and its frameworks, PrimeFreeBird's dylib left out.
static NSArray<NSString*>* twitterBinaries(void) {
    NSMutableArray<NSString*>* binaries = [NSMutableArray array];
    NSString* main = NSBundle.mainBundle.executablePath;
    if (main) {
        [binaries addObject:main];
    }
    Dl_info own;
    NSString* ownPath = nil;
    if (dladdr((const void*)&twitterBinaries, &own) && own.dli_fname) {
        ownPath = [[NSString stringWithUTF8String:own.dli_fname] stringByResolvingSymlinksInPath];
    }
    NSString* frameworks = NSBundle.mainBundle.privateFrameworksPath;
    for (NSString* name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:frameworks error:nil]) {
        if (![name.pathExtension isEqualToString:@"framework"]) {
            continue;
        }
        NSString* path = [[frameworks stringByAppendingPathComponent:name]
            stringByAppendingPathComponent:name.stringByDeletingPathExtension];
        if (ownPath && [[path stringByResolvingSymlinksInPath] isEqualToString:ownPath]) {
            continue;
        }
        [binaries addObject:path];
    }
    return binaries;
}

// The switches Twitter no longer carries, matched as whole strings and read from
// disk, so a framework that loads with its screen counts too. Nil when the answer
// cannot be trusted.
static NSArray<NSString*>* scanMissingFlags(NSArray<NSString*>* binaries) {
    size_t lengths[kFlagCount];
    size_t shortest = SIZE_MAX;
    for (size_t i = 0; i < kFlagCount; i++) {
        lengths[i] = strlen(kFlags[i].key);
        shortest = MIN(shortest, lengths[i]);
    }
    BOOL found[kFlagCount] = {NO};
    size_t matched = 0;
    for (NSString* path in binaries) {
        @autoreleasepool {
            NSData* data = [NSData dataWithContentsOfFile:path
                                                  options:NSDataReadingMappedIfSafe
                                                    error:nil];
            if (!data) {
                continue;
            }
            size_t size = 0;
            BOOL encrypted = NO;
            const char* strings = textSection(data, "__cstring", &size, &encrypted);
            if (encrypted) {
                return nil;
            }
            if (!strings) {
                continue;
            }
            const char* end = strings + size;
            for (const char* s = strings; s < end && matched < kFlagCount;) {
                size_t length = strnlen(s, (size_t)(end - s));
                if (length >= shortest) {
                    for (size_t i = 0; i < kFlagCount; i++) {
                        if (found[i] || length < lengths[i] ||
                            (!kFlags[i].prefix && length != lengths[i])) {
                            continue;
                        }
                        if (memcmp(s, kFlags[i].key, lengths[i]) == 0) {
                            found[i] = YES;
                            matched++;
                        }
                    }
                }
                s += length + 1;
            }
        }
    }
    if (matched == 0) {
        return nil;
    }
    NSMutableOrderedSet<NSString*>* missing = [NSMutableOrderedSet orderedSet];
    for (size_t i = 0; i < kFlagCount; i++) {
        if (!found[i]) {
            [missing addObject:[NSString stringWithUTF8String:kFlags[i].key]];
        }
    }
    return missing.array;
}

// A 64-bit FNV-style hash: the wanted names are few and the section strings many.
static uint64_t nameHash(const char* s, size_t length) {
    uint64_t hash = 1469598103934665603ULL;
    for (size_t i = 0; i < length; i++) {
        hash ^= (uint8_t)s[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

// The kNames entries no longer in Twitter's method names or strings; nil when
// nothing could be read.
static NSArray<NSString*>* scanMissingNames(NSArray<NSString*>* binaries) {
    const char* names[kNameCount];
    size_t lengths[kNameCount];
    uint64_t hashes[kNameCount];
    BOOL found[kNameCount];
    size_t count = 0;
    size_t shortest = SIZE_MAX;
    size_t longest = 0;
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    for (size_t i = 0; i < kNameCount; i++) {
        NSString* name = [NSString stringWithUTF8String:kNames[i].name];
        if ([seen containsObject:name]) {
            continue;
        }
        [seen addObject:name];
        names[count] = kNames[i].name;
        lengths[count] = strlen(kNames[i].name);
        hashes[count] = nameHash(names[count], lengths[count]);
        found[count] = NO;
        shortest = MIN(shortest, lengths[count]);
        longest = MAX(longest, lengths[count]);
        count++;
    }
    // Class names sit in their own section, apart from selectors and C strings.
    static const char* const kSections[] = {"__objc_methname", "__cstring", "__objc_classname"};
    size_t matched = 0;
    BOOL readAny = NO;
    for (NSString* path in binaries) {
        @autoreleasepool {
            NSData* data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            if (!data) {
                continue;
            }
            for (size_t s = 0; s < sizeof(kSections) / sizeof(kSections[0]) && matched < count; s++) {
                size_t size = 0;
                BOOL encrypted = NO;
                const char* strings = textSection(data, kSections[s], &size, &encrypted);
                if (encrypted) {
                    return nil;
                }
                if (!strings) {
                    continue;
                }
                readAny = YES;
                const char* end = strings + size;
                for (const char* p = strings; p < end && matched < count;) {
                    size_t length = strnlen(p, (size_t)(end - p));
                    if (length >= shortest && length <= longest) {
                        uint64_t hash = nameHash(p, length);
                        for (size_t i = 0; i < count; i++) {
                            if (!found[i] && hashes[i] == hash && lengths[i] == length &&
                                memcmp(p, names[i], length) == 0) {
                                found[i] = YES;
                                matched++;
                            }
                        }
                    }
                    p += length + 1;
                }
            }
        }
    }
    if (!readAny || matched == 0) {
        return nil;
    }
    NSMutableArray<NSString*>* missing = [NSMutableArray array];
    for (size_t i = 0; i < count; i++) {
        if (!found[i]) {
            [missing addObject:[NSString stringWithUTF8String:names[i]]];
        }
    }
    return missing;
}

// MARK: - Settings Twitter reads while the debugger records

static os_unfair_lock gReadLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString*, NSNumber*>* gSettingsRead;

void PFBCompatNoteSettingRead(NSString* key) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    os_unfair_lock_lock(&gReadLock);
    if (!gSettingsRead) {
        gSettingsRead = [NSMutableDictionary dictionary];
    }
    gSettingsRead[key] = @YES;
    os_unfair_lock_unlock(&gReadLock);
}

static NSDictionary<NSString*, NSNumber*>* PFBCompatSettingsRead(void) {
    os_unfair_lock_lock(&gReadLock);
    NSDictionary<NSString*, NSNumber*>* read = [gSettingsRead copy] ?: @{};
    os_unfair_lock_unlock(&gReadLock);
    return read;
}

// MARK: - Leads: where a lost path may have moved

typedef NS_ENUM(NSInteger, PFBLeadPool) {
    PFBLeadPoolKeys,       // snake_case strings: settings, module and text keys
    PFBLeadPoolSelectors,  // Objective-C method names
    PFBLeadPoolClasses,    // class names, Swift ones mangled
};

// One lost name as the scan compares it: its pool and its distinctive words.
typedef struct {
    PFBLeadPool pool;
    char* lost;
    size_t lostLength;
    char* words[4];
    size_t wordCount;
} PFBLeadProbe;

static BOOL leadStopWord(NSString* word) {
    static NSSet<NSString*>* stops;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      stops = [NSSet setWithArray:@[
          @"ios", @"android", @"enabled", @"enable", @"blue", @"and", @"the", @"for", @"with", @"client",
          @"feature", @"new", @"tfn", @"tfs", @"tta", @"tui", @"tae", @"urt", @"twitter", @"swift", @"view",
          @"model", @"controller", @"cell", @"item", @"timeline", @"status", @"data", @"adapter", @"did",
          @"will", @"should", @"index", @"path", @"color", @"key", @"type", @"table"
      ]];
    });
    return word.length < 3 || [stops containsObject:word];
}

// A name's distinctive words: split at underscores, dots, colons, digits and case
// changes, lowercased, a plural's s dropped, common words left out, four at most.
static NSArray<NSString*>* leadWords(NSString* name) {
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    NSMutableString* word = [NSMutableString string];
    void (^flush)(void) = ^{
      NSString* lower = word.lowercaseString;
      if (lower.length > 4 && [lower hasSuffix:@"s"] && ![lower hasSuffix:@"ss"]) {
          lower = [lower substringToIndex:lower.length - 1];
      }
      if (!leadStopWord(lower) && ![words containsObject:lower]) {
          [words addObject:lower];
      }
      [word setString:@""];
    };
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (c > 127 || !isalpha((int)c)) {
            flush();
            continue;
        }
        unichar previous = i > 0 ? [name characterAtIndex:i - 1] : 0;
        unichar next = i + 1 < name.length ? [name characterAtIndex:i + 1] : 0;
        if (isupper((int)c) && word.length > 0 && previous < 128 &&
            (islower((int)previous) || (isupper((int)previous) && next < 128 && islower((int)next)))) {
            flush();
        }
        [word appendFormat:@"%C", c];
    }
    flush();
    NSArray<NSString*>* longest = [words sortedArrayUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
      return a.length == b.length ? NSOrderedSame : (a.length > b.length ? NSOrderedAscending : NSOrderedDescending);
    }];
    return [longest subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, longest.count))];
}

static PFBLeadPool leadPool(NSString* name) {
    if ([name hasPrefix:@"_Tt"]) {
        return PFBLeadPoolClasses;
    }
    if ([name containsString:@"_"]) {
        return PFBLeadPoolKeys;
    }
    unichar first = name.length ? [name characterAtIndex:0] : 0;
    return (first >= 'A' && first <= 'Z' && ![name containsString:@":"]) ? PFBLeadPoolClasses
                                                                          : PFBLeadPoolSelectors;
}

// A snake_case string: letters, digits and at least one underscore.
static BOOL leadIsKey(const char* s, size_t length) {
    BOOL underscore = NO;
    for (size_t i = 0; i < length; i++) {
        if (s[i] == '_') {
            underscore = YES;
        } else if (!isalnum((unsigned char)s[i])) {
            return NO;
        }
    }
    return underscore;
}

// Scores one section's strings against the probes of its pool. A probe's own
// name found intact is noted rather than scored.
static void leadScan(const char* strings, size_t size, PFBLeadPool pool, const PFBLeadProbe* probes, size_t count,
                     NSArray<NSMutableDictionary<NSString*, NSNumber*>*>* found, BOOL* present) {
    const char* end = strings + size;
    for (const char* s = strings; s < end;) {
        size_t length = strnlen(s, (size_t)(end - s));
        if (length >= 4 && length <= 90 && s + length < end && (pool != PFBLeadPoolKeys || leadIsKey(s, length))) {
            for (size_t i = 0; i < count; i++) {
                const PFBLeadProbe* probe = &probes[i];
                if (probe->pool != pool) {
                    continue;
                }
                if (length == probe->lostLength && memcmp(s, probe->lost, length) == 0) {
                    present[i] = YES;
                    continue;
                }
                NSUInteger score = 0;
                for (size_t w = 0; w < probe->wordCount; w++) {
                    score += strcasestr(s, probe->words[w]) != NULL;
                }
                if (score == 0 || (score < MIN((size_t)2, probe->wordCount) && found[i].count >= 200)) {
                    continue;
                }
                NSString* candidate = [[NSString alloc] initWithBytes:s length:length encoding:NSUTF8StringEncoding];
                if (candidate) {
                    found[i][candidate] = @(score);
                }
            }
        }
        s += length + 1;
    }
}

static NSUInteger leadSuffix(NSString* a, NSString* b) {
    NSUInteger n = 0;
    while (n < a.length && n < b.length && [a characterAtIndex:a.length - 1 - n] == [b characterAtIndex:b.length - 1 - n]) {
        n++;
    }
    return n;
}

// Swift classes appear mangled; the Module.Name form reads better in a report.
static NSString* leadDisplayName(NSString* name) {
    if (![name hasPrefix:@"_TtC"]) {
        return name;
    }
    const char* s = name.UTF8String + 4;
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    while (*s && parts.count < 2) {
        char* rest = NULL;
        long length = strtol(s, &rest, 10);
        if (rest == s || length <= 0 || (size_t)length > strlen(rest)) {
            break;
        }
        [parts addObject:[[NSString alloc] initWithBytes:rest length:(NSUInteger)length encoding:NSUTF8StringEncoding]];
        s = rest + length;
    }
    return parts.count == 2 ? [parts componentsJoinedByString:@"."] : name;
}

// The best leads: most shared words, then shipped settings, the closest ending and
// the shortest name. A setting key needs two shared words to count.
static NSArray<NSString*>* leadRank(NSDictionary<NSString*, NSNumber*>* found, NSString* lost, const PFBLeadProbe* probe,
                                    NSSet<NSString*>* settings) {
    NSUInteger best = 0;
    for (NSNumber* score in found.allValues) {
        best = MAX(best, score.unsignedIntegerValue);
    }
    if (best == 0 || (probe->pool == PFBLeadPoolKeys && best < MIN((NSUInteger)2, (NSUInteger)probe->wordCount))) {
        return @[];
    }
    NSSet<NSString*>* top = [found keysOfEntriesPassingTest:^BOOL(NSString* key, NSNumber* score, BOOL* stop) {
      return score.unsignedIntegerValue == best;
    }];
    NSArray<NSString*>* ranked = [top.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
      BOOL shippedA = [settings containsObject:a];
      BOOL shippedB = [settings containsObject:b];
      if (shippedA != shippedB) {
          return shippedA ? NSOrderedAscending : NSOrderedDescending;
      }
      NSUInteger endA = leadSuffix(a, lost);
      NSUInteger endB = leadSuffix(b, lost);
      if (endA != endB) {
          return endA > endB ? NSOrderedAscending : NSOrderedDescending;
      }
      if (a.length != b.length) {
          return a.length < b.length ? NSOrderedAscending : NSOrderedDescending;
      }
      return [a compare:b];
    }];
    NSMutableArray<NSString*>* leads = [NSMutableArray array];
    for (NSString* name in ranked) {
        if (leads.count == 3) {
            break;
        }
        [leads addObject:leadDisplayName(name)];
    }
    return leads;
}

// The settings Twitter ships defaults for: a lead found there is a real setting.
static NSSet<NSString*>* shippedSettings(void) {
    NSString* path = [NSBundle.mainBundle pathForResource:@"fs_embedded_defaults_production" ofType:@"json"];
    NSData* data = path ? [NSData dataWithContentsOfFile:path] : nil;
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    id config = [root isKindOfClass:[NSDictionary class]] ? root[@"default"] : nil;
    config = [config isKindOfClass:[NSDictionary class]] ? config[@"config"] : nil;
    return [config isKindOfClass:[NSDictionary class]] ? [NSSet setWithArray:[config allKeys]] : [NSSet set];
}

// Methods of a class that still exists and share a lost method's words.
static NSArray<NSString*>* sameClassLeads(NSString* className, NSArray<NSString*>* words) {
    Class cls = objc_getClass(className.UTF8String);
    if (!cls || words.count == 0) {
        return @[];
    }
    unsigned int count = 0;
    Method* methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString*>* leads = [NSMutableArray array];
    for (unsigned int i = 0; i < count && leads.count < 2; i++) {
        NSString* name = NSStringFromSelector(method_getName(methods[i]));
        for (NSString* word in words) {
            if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [leads addObject:[NSString stringWithFormat:@"%@.%@", className, name]];
                break;
            }
        }
    }
    free(methods);
    return leads;
}

// Leads for each lost path, from the names in Twitter's binaries. A lost hook
// ("Class selector") also gets its class's methods sharing its words, and a note
// when the same method still exists elsewhere in Twitter.
static NSDictionary<NSString*, NSArray<NSString*>*>* findLeads(NSArray<NSString*>* binaries, NSArray<NSString*>* lost,
                                                                NSSet<NSString*>** settingsOut) {
    NSMutableArray<NSString*>* owners = [NSMutableArray array];
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (NSString* path in lost) {
        NSRange space = [path rangeOfString:@" "];
        [owners addObject:path];
        [names addObject:space.location == NSNotFound ? path : [path substringFromIndex:NSMaxRange(space)]];
        NSString* className = space.location == NSNotFound ? nil : [path substringToIndex:space.location];
        if (className && !objc_getClass(className.UTF8String)) {
            [owners addObject:path];
            [names addObject:className];
        }
    }
    size_t count = names.count;
    *settingsOut = [NSSet set];
    if (count == 0) {
        return @{};
    }
    PFBLeadProbe* probes = calloc(count, sizeof(PFBLeadProbe));
    BOOL* present = calloc(count, sizeof(BOOL));
    NSMutableArray<NSArray<NSString*>*>* wordLists = [NSMutableArray array];
    NSMutableArray<NSMutableDictionary<NSString*, NSNumber*>*>* found = [NSMutableArray array];
    BOOL wantsSettings = NO;
    for (size_t i = 0; i < count; i++) {
        NSArray<NSString*>* words = leadWords(names[i]);
        [wordLists addObject:words];
        [found addObject:[NSMutableDictionary dictionary]];
        probes[i].pool = leadPool(names[i]);
        probes[i].lost = strdup(names[i].UTF8String);
        probes[i].lostLength = strlen(probes[i].lost);
        probes[i].wordCount = words.count;
        for (size_t w = 0; w < words.count; w++) {
            probes[i].words[w] = strdup(words[w].UTF8String);
        }
        wantsSettings |= probes[i].pool == PFBLeadPoolKeys;
    }
    static const char* const kSections[] = {"__cstring", "__objc_methname", "__objc_classname"};
    static const PFBLeadPool kSectionPools[] = {PFBLeadPoolKeys, PFBLeadPoolSelectors, PFBLeadPoolClasses};
    for (NSString* file in binaries) {
        @autoreleasepool {
            NSData* data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
            for (size_t s = 0; data && s < 3; s++) {
                size_t size = 0;
                BOOL encrypted = NO;
                const char* strings = textSection(data, kSections[s], &size, &encrypted);
                if (strings) {
                    leadScan(strings, size, kSectionPools[s], probes, count, found, present);
                }
            }
        }
    }
    NSSet<NSString*>* settings = wantsSettings ? shippedSettings() : [NSSet set];
    NSMutableDictionary<NSString*, NSMutableArray<NSString*>*>* leads = [NSMutableDictionary dictionary];
    NSMutableSet<NSString*>* shipped = [NSMutableSet set];
    for (size_t i = 0; i < count; i++) {
        NSString* owner = owners[i];
        NSMutableArray<NSString*>* list = leads[owner] ?: [NSMutableArray array];
        leads[owner] = list;
        NSRange space = [owner rangeOfString:@" "];
        if (space.location != NSNotFound && [names[i] isEqualToString:[owner substringFromIndex:NSMaxRange(space)]]) {
            if (present[i]) {
                [list addObject:@"same method still in Twitter"];
            }
            [list addObjectsFromArray:sameClassLeads([owner substringToIndex:space.location], wordLists[i])];
        }
        for (NSString* lead in leadRank(found[i], names[i], &probes[i], settings)) {
            if (list.count < 4 && ![list containsObject:lead]) {
                [list addObject:lead];
                if ([settings containsObject:lead]) {
                    [shipped addObject:lead];
                }
            }
        }
        free(probes[i].lost);
        for (size_t w = 0; w < probes[i].wordCount; w++) {
            free(probes[i].words[w]);
        }
    }
    free(probes);
    free(present);
    *settingsOut = shipped;
    NSMutableDictionary<NSString*, NSArray<NSString*>*>* result = [NSMutableDictionary dictionary];
    [leads enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSMutableArray<NSString*>* list, BOOL* stop) {
      if (list.count > 0) {
          result[key] = [list copy];
      }
    }];
    return result;
}

// Leads as the report writes them: a shipped setting and one Twitter read while
// recording are marked, which turns a lead into a measurement.
static NSString* markLeads(NSArray<NSString*>* names, NSSet<NSString*>* settings, NSDictionary<NSString*, NSNumber*>* read) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSString* name in names) {
        NSMutableArray<NSString*>* marks = [NSMutableArray array];
        if ([settings containsObject:name]) {
            [marks addObject:@"setting"];
        }
        if (read[name]) {
            [marks addObject:@"read"];
        }
        [parts addObject:marks.count ? [NSString stringWithFormat:@"%@ (%@)", name, [marks componentsJoinedByString:@", "]]
                                     : name];
    }
    return [parts componentsJoinedByString:@", "];
}

static NSString* leadsText(NSString* lost, NSDictionary* leads, NSSet<NSString*>* settings,
                           NSDictionary<NSString*, NSNumber*>* read) {
    NSArray* found = lost ? leads[lost] : nil;
    if (![found isKindOfClass:[NSArray class]] || found.count == 0) {
        return @"";
    }
    return [@" \u00b7 leads: " stringByAppendingString:markLeads(found, settings, read)];
}

// MARK: - Verdicts

// On is on, except where the option has nothing to act on: an empty domain, no
// chosen font, no accent, or a sibling switch that takes over.
static BOOL optionEnabled(const PFBCompatMeta* meta) {
    if (meta->alwaysOn) {
        return YES;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* key = [NSString stringWithUTF8String:meta->key];
    switch (meta->option) {
        case PFBCompat_sharing_domain:
            return [defaults stringForKey:key].length > 0;
        case PFBCompat_undo_tweet_timeout:
            return [PFBSettings integerForKey:key] > 0;
        case PFBCompat_send_sound:
            return PFBSendSoundIsSet();
        case PFBCompat_custom_fonts:
            return [PFBSettings boolForKey:key] &&
                   ([defaults stringForKey:@"pfb_font_1"].length > 0 ||
                    [defaults stringForKey:@"pfb_font_2"].length > 0);
        case PFBCompat_unlimited_timeline_tabs:
            return [PFBSettings boolForKey:key] && ![PFBSettings boolForKey:@"hide_custom_timelines"];
        case PFBCompat_refresh_pill_label:
            return [PFBSettings boolForKey:key] && ![PFBSettings boolForKey:@"hide_new_tweets_pill"];
        case PFBCompat_choose_explore_tabs:
            return [PFBSettings boolForKey:key] && ![PFBSettings boolForKey:@"hide_explore_all"];
        case PFBCompat_tab_bar_theming:
            return PFBThemedTabBarWanted();
        case PFBCompat_color_twitter_icon_in_top_bar:
            return [PFBSettings boolForKey:key] && PFBAccentIsActive();
        case PFBCompat_dark_mode_style:
            return [PFBDarkModeStyle isDarkModeActive] && [PFBDarkModeStyle selectedStyle] != PFBDarkModeStyleSystem;
        case PFBCompat_accent_color: {
            NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
            return [defs objectForKey:@"pfb_color_theme_selectedColor"] != nil ||
                   [defs objectForKey:@"pfb_custom_accent_hex"] != nil;
        }
        case PFBCompat_muted_words: {
            id words = [defaults objectForKey:@"pfb_muted_words"];
            return [words respondsToSelector:@selector(count)] && [words count] > 0;
        }
        case PFBCompat_profile_initial_tab:
            return [PFBSettings integerForKey:key] > 0;
        case PFBCompat_disable_auto_translate:
            // An inverted switch: shown On while the stored key is off.
            return ![PFBSettings boolForKey:key];
        case PFBCompat_download_highest_quality:
        case PFBCompat_direct_save:
            return [PFBSettings boolForKey:key] && [PFBSettings boolForKey:@"download_videos"];
        case PFBCompat_web_session:
            return PFBHasUsableWebCredentials();
        case PFBCompat_show_account_location:
            return [PFBSettings boolForKey:key] && PFBHasUsableWebCredentials();
        default:
            return [PFBSettings boolForKey:key];
    }
}

static NSString* localized(const char* key) {
    return [[PFBBundle sharedBundle] localizedStringForKey:[NSString stringWithUTF8String:key]];
}

static BOOL methodPresent(const char* className, const char* selector) {
    Class cls = objc_getClass(className);
    if (!cls) {
        return NO;
    }
    if (selector[0] == '$') {
        for (NSString* name in [[NSString stringWithUTF8String:selector + 1] componentsSeparatedByString:@"|"]) {
            if (name.length && class_getInstanceVariable(cls, name.UTF8String)) {
                return YES;
            }
        }
        return NO;
    }
    SEL sel = sel_registerName(selector + 1);
    if (selector[0] == '+') {
        return class_getClassMethod(cls, sel) != NULL || [cls respondsToSelector:sel];
    }
    return class_getInstanceMethod(cls, sel) != NULL || [cls instancesRespondToSelector:sel];
}

// A requirement as the report names it: "Class selector", or "Class ivar name".
static NSString* reqName(const PFBCompatReq* req) {
    NSString* entry = [[NSString stringWithUTF8String:req->selector + 1] componentsSeparatedByString:@"|"].firstObject;
    return req->selector[0] == '$' ? [NSString stringWithFormat:@"%s ivar %@", req->className, entry]
                                   : [NSString stringWithFormat:@"%s %@", req->className, entry];
}

// The first requirement missing for this option, or nil when all are present.
static NSString* firstMissing(PFBCompatOption option) {
    for (size_t i = 0; i < kReqCount; i++) {
        if (kReqs[i].option != option) {
            continue;
        }
        if (!methodPresent(kReqs[i].className, kReqs[i].selector)) {
            return reqName(&kReqs[i]);
        }
    }
    return nil;
}

static BOOL flagOnly(PFBCompatOption option) {
    for (size_t i = 0; i < kFlagOnlyCount; i++) {
        if (kFlagOnly[i] == option) {
            return YES;
        }
    }
    return NO;
}

// How many of the option's switches Twitter no longer carries, and the first.
static NSUInteger flagsGone(PFBCompatOption option, NSSet<NSString*>* missing,
                            NSUInteger* total, NSString** first) {
    NSUInteger gone = 0;
    *total = 0;
    for (size_t i = 0; i < kFlagCount; i++) {
        if (kFlags[i].option != option) {
            continue;
        }
        (*total)++;
        NSString* key = [NSString stringWithUTF8String:kFlags[i].key];
        if ([missing containsObject:key]) {
            if (gone == 0) {
                *first = key;
            }
            gone++;
        }
    }
    return gone;
}

static BOOL classOnly(PFBCompatOption option) {
    for (size_t i = 0; i < kClassOnlyCount; i++) {
        if (kClassOnly[i] == option) {
            return YES;
        }
    }
    return NO;
}

// How many of the option's class names no longer resolve, and the first.
static NSUInteger classTextsGone(PFBCompatOption option, NSUInteger* total, NSString** first) {
    NSUInteger gone = 0;
    *total = 0;
    for (size_t i = 0; i < kClassTextCount; i++) {
        if (kClassTexts[i].option != option) {
            continue;
        }
        (*total)++;
        NSString* name = [NSString stringWithUTF8String:kClassTexts[i].className];
        if (!NSClassFromString(name)) {
            if (gone == 0) {
                *first = name;
            }
            gone++;
        }
    }
    return gone;
}

// How many of the option's string-reached names are gone from Twitter, and the first.
static NSUInteger namesGone(PFBCompatOption option, NSSet<NSString*>* gone, NSString** first) {
    NSMutableSet<NSString*>* counted = [NSMutableSet set];
    for (size_t i = 0; i < kNameCount; i++) {
        NSString* name = [NSString stringWithUTF8String:kNames[i].name];
        if (kNames[i].option == option && [gone containsObject:name] && ![counted containsObject:name]) {
            if (counted.count == 0) {
                *first = name;
            }
            [counted addObject:name];
        }
    }
    return counted.count;
}

static BOOL hookPresent(const char* className, const char* methodName) {
    Class cls = objc_getClass(className);
    if (!cls || !methodName) {
        return cls != Nil;
    }
    SEL selector = sel_registerName(methodName);
    return class_getInstanceMethod(cls, selector) != NULL || class_getClassMethod(cls, selector) != NULL ||
           [cls instancesRespondToSelector:selector] || [cls respondsToSelector:selector];
}

static NSString* hookPath(const char* className, const char* methodName) {
    return methodName ? [NSString stringWithFormat:@"%s %s", className, methodName]
                      : [NSString stringWithUTF8String:className];
}

// One row per hooked source file, from the hook manifest: its hooks, and the names it
// reaches outside any option, so a dropped class or method shows even where no option names it.
static void appendInternals(NSMutableArray<PFBCompatResult*>* results, NSSet<NSString*>* goneNames, NSDictionary* leads,
                            NSSet<NSString*>* leadSettings, NSDictionary<NSString*, NSNumber*>* read) {
    NSMutableDictionary<NSString*, NSNumber*>* hooks = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSNumber*>* names = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSMutableArray<NSString*>*>* gone = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSString*>* nameGone = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString*, NSString*>* nameLost = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < PFBHookRecordCount; i++) {
        PFBHookRecord record = PFBHookRecords[i];
        NSString* file = [[NSString stringWithUTF8String:record.file] lastPathComponent];
        if (!gone[file]) {
            gone[file] = [NSMutableArray array];
        }
        hooks[file] = @(hooks[file].integerValue + 1);
        if (!hookPresent(record.className, record.methodName)) {
            [gone[file] addObject:hookPath(record.className, record.methodName)];
        }
    }
    for (size_t i = 0; i < kNameCount; i++) {
        if (kNames[i].option != PFBCompatOptionCount) {
            continue;
        }
        NSString* file = [[NSString stringWithUTF8String:kNames[i].file] lastPathComponent];
        names[file] = @(names[file].integerValue + 1);
        NSString* name = [NSString stringWithUTF8String:kNames[i].name];
        if (!nameGone[file] && [goneNames containsObject:name]) {
            nameGone[file] = [name stringByAppendingString:@" not found, read by name"];
            nameLost[file] = name;
        }
    }
    for (size_t i = 0; i < kDeclaredCount; i++) {
        NSString* file = [[NSString stringWithUTF8String:kDeclared[i].file] lastPathComponent];
        names[file] = @(names[file].integerValue + 1);
        if (!nameGone[file] && !hookPresent(kDeclared[i].className, kDeclared[i].selector)) {
            nameLost[file] = [NSString stringWithFormat:@"%s %s", kDeclared[i].className, kDeclared[i].selector];
            nameGone[file] = [nameLost[file] stringByAppendingString:@" not found"];
        }
    }
    NSMutableSet<NSString*>* files = [NSMutableSet setWithArray:hooks.allKeys];
    [files addObjectsFromArray:names.allKeys];
    for (NSString* file in [files.allObjects sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        PFBCompatResult* row = [PFBCompatResult new];
        row.section = @"Tweak internals";
        row.title = file;
        row.internal = YES;
        NSInteger hookTotal = hooks[file].integerValue;
        NSInteger nameTotal = names[file].integerValue;
        NSArray<NSString*>* missing = gone[file];
        if (missing.count > 0) {
            row.verdict = PFBCompatVerdictBroken;
            row.detail = [[NSString stringWithFormat:@"Path lost: %lu of %ld hooks not found, including %@",
                                                     (unsigned long)missing.count, (long)hookTotal, missing.firstObject]
                stringByAppendingString:leadsText(missing.firstObject, leads, leadSettings, read)];
        } else if (nameGone[file]) {
            row.verdict = PFBCompatVerdictBroken;
            row.detail = [[@"Path lost: " stringByAppendingString:nameGone[file]]
                stringByAppendingString:leadsText(nameLost[file], leads, leadSettings, read)];
        } else {
            row.verdict = PFBCompatVerdictOK;
            NSMutableArray<NSString*>* parts = [NSMutableArray array];
            if (hookTotal > 0) {
                [parts addObject:[NSString stringWithFormat:@"%ld hook%@", (long)hookTotal, hookTotal == 1 ? @"" : @"s"]];
            }
            if (nameTotal > 0) {
                [parts addObject:[NSString stringWithFormat:@"%ld name%@", (long)nameTotal, nameTotal == 1 ? @"" : @"s"]];
            }
            row.detail = [[parts componentsJoinedByString:@" \u00b7 "] stringByAppendingString:@" present"];
        }
        [results addObject:row];
    }
}

// "paths 1/2, not seen yet: X" for an option acting through several paths.
static NSString* pathsNote(PFBCompatOption option, NSString* key, NSDictionary* stored,
                           NSDictionary* earlierStored) {
    NSArray* saved = [stored[key] isKindOfClass:[NSArray class]] ? stored[key] : @[];
    NSArray* earlier = [earlierStored[key] isKindOfClass:[NSArray class]] ? earlierStored[key] : @[];
    NSMutableArray<NSString*>* missing = [NSMutableArray array];
    NSUInteger total = 0;
    NSUInteger fromEarlier = 0;
    for (size_t i = 0; i < kPathCount; i++) {
        if (kPaths[i].option != option) {
            continue;
        }
        total++;
        NSString* name = [NSString stringWithUTF8String:kPaths[i].name];
        if (atomic_load_explicit(&gPathSeen[kPaths[i].path], memory_order_relaxed) ||
            [saved containsObject:name]) {
            continue;
        }
        if ([earlier containsObject:name]) {
            fromEarlier++;
        } else {
            [missing addObject:name];
        }
    }
    if (total == 0) {
        return nil;
    }
    NSString* note = [NSString stringWithFormat:@"paths %lu/%lu", (unsigned long)(total - missing.count),
                                                (unsigned long)total];
    if (fromEarlier > 0) {
        note = [note stringByAppendingFormat:@" (%lu from an earlier build)", (unsigned long)fromEarlier];
    }
    return missing.count ? [note stringByAppendingFormat:@", not seen yet: %@",
                                                         [missing componentsJoinedByString:@", "]]
                         : note;
}

// What earlier builds of this Twitter version proved for an option, or nil.
static NSString* earlierEvidence(NSDictionary* earlier, NSString* key) {
    NSDictionary* counts = [earlier[@"counts"] isKindOfClass:[NSDictionary class]] ? earlier[@"counts"] : @{};
    NSDictionary* details = [earlier[@"details"] isKindOfClass:[NSDictionary class]] ? earlier[@"details"] : @{};
    NSDictionary* observed = [earlier[@"observed"] isKindOfClass:[NSDictionary class]] ? earlier[@"observed"] : @{};
    unsigned long long done = [counts[key] unsignedLongLongValue];
    if (done > 0) {
        id detail = details[key];
        return [NSString stringWithFormat:@"earlier build \u00b7 %llu\u00d7 \u00b7 %@", done,
                                          [detail isKindOfClass:[NSString class]] ? detail : @"-"];
    }
    id seen = observed[key];
    return [seen isKindOfClass:[NSString class]] ? [@"earlier build \u00b7 ready \u00b7 " stringByAppendingString:seen]
                                                 : nil;
}

static NSString* capitalizedFirst(NSString* text) {
    return text.length ? [[[text substringToIndex:1] uppercaseString] stringByAppendingString:[text substringFromIndex:1]]
                       : text;
}

// The verdict of an option whose path is intact. What the tour showed without its proof
// stays not tested, with what was shown: only a name missing from Twitter's binaries
// proves a path lost.
static PFBCompatVerdict tourVerdict(const PFBCompatMeta* meta, NSString* key, BOOL proven, NSDictionary* stations,
                                    NSString** detail) {
    for (size_t i = 0; i < kPathStationCount; i++) {
        const PFBCompatPathMeta* path = pathMetaFor(kPathStations[i].path);
        NSString* station = [NSString stringWithUTF8String:kPathStations[i].station];
        NSDictionary* record = stations[station];
        if (!path || path->option != meta->option || ![record isKindOfClass:[NSDictionary class]] ||
            ![record[@"reached"] boolValue]) {
            continue;
        }
        NSString* name = [NSString stringWithUTF8String:path->name];
        if ([record[@"missed"] containsObject:[@"path:" stringByAppendingString:name]] && !pathProven(path)) {
            *detail = [NSString stringWithFormat:@"Shown: %@. Path not reached: %@", stationLabel(station), name];
            return PFBCompatVerdictNotTested;
        }
    }
    if (proven) {
        return PFBCompatVerdictOK;
    }
    const PFBCompatContract* contract = contractFor(meta->option);
    NSString* absent = contract && contract->absent ? [NSString stringWithUTF8String:contract->absent] : nil;
    NSArray<NSString*>* planned = contractStations(contract);
    NSString* missedAt = nil;
    NSString* failedAt = nil;
    BOOL closedTwitter = NO;
    for (NSString* station in planned) {
        NSDictionary* record = stations[station];
        if (![record isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if (![record[@"reached"] boolValue]) {
            failedAt = failedAt ?: station;
            closedTwitter = closedTwitter || ([station isEqualToString:failedAt] && [record[@"crashed"] boolValue]);
        } else if ([record[@"missed"] containsObject:key]) {
            missedAt = missedAt ?: station;
        }
    }
    if (missedAt && !absent) {
        *detail = [NSString stringWithFormat:@"Shown: %@. No proof within 6 s", stationLabel(missedAt)];
        return PFBCompatVerdictNotTested;
    }
    if (planned.count == 0) {
        *detail = capitalizedFirst(absent);
    } else if (missedAt) {
        *detail = [NSString stringWithFormat:@"No %@ during the check", absent];
    } else if (failedAt) {
        *detail = [NSString stringWithFormat:closedTwitter ? @"%@ closed Twitter during the check"
                                                           : @"%@ was not reached during the check",
                                             capitalizedFirst(stationLabel(failedAt))];
    } else {
        *detail = @"Not checked on this build yet";
    }
    return PFBCompatVerdictNotTested;
}

NSArray<PFBCompatResult*>* PFBCompatResults(void) {
    prepare();
    NSDictionary* counts;
    NSDictionary* details;
    NSDictionary* observed;
    NSDictionary* paths;
    NSDictionary* earlier;
    NSDictionary* stations;
    NSSet<NSString*>* missingFlags;
    NSSet<NSString*>* missingNames;
    NSDictionary* leads;
    NSSet<NSString*>* leadSettings;
    @synchronized(gLock) {
        counts = storeDictionary(@"counts");
        details = storeDictionary(@"details");
        observed = storeDictionary(@"observed");
        paths = storeDictionary(@"paths");
        earlier = storeDictionary(@"earlier");
        id storedStations = storeDictionary(@"tour")[@"stations"];
        stations = [storedStations isKindOfClass:[NSDictionary class]] ? storedStations : @{};
        NSArray* missing = storeDictionary(@"flags")[@"missing"];
        NSArray* names = storeDictionary(@"flags")[@"names"];
        missingNames = [NSSet setWithArray:[names isKindOfClass:[NSArray class]] ? names : @[]];
        missingFlags = [NSSet setWithArray:[missing isKindOfClass:[NSArray class]] ? missing : @[]];
        id storedLeads = storeDictionary(@"flags")[@"leads"];
        id storedSettings = storeDictionary(@"flags")[@"leadSettings"];
        leads = [storedLeads isKindOfClass:[NSDictionary class]] ? storedLeads : @{};
        leadSettings = [NSSet setWithArray:[storedSettings isKindOfClass:[NSArray class]] ? storedSettings : @[]];
    }
    NSDictionary<NSString*, NSNumber*>* read = PFBCompatSettingsRead();
    NSMutableArray<PFBCompatResult*>* results = [NSMutableArray array];
    for (size_t i = 0; i < kMetaCount; i++) {
        const PFBCompatMeta* meta = &kMeta[i];
        NSString* key = [NSString stringWithUTF8String:meta->key];
        PFBCompatResult* result = [PFBCompatResult new];
        result.section = localized(meta->pageKey);
        result.title = localized(meta->titleKey);
        uint64_t done = [counts[key] unsignedLongLongValue] +
                        atomic_load_explicit(&gHits[meta->option], memory_order_relaxed);
        NSString* missing = firstMissing(meta->option);
        NSUInteger total = 0;
        NSString* firstGone = nil;
        NSUInteger gone = flagsGone(meta->option, missingFlags, &total, &firstGone);
        BOOL flagDead = total > 0 && gone == total && flagOnly(meta->option);
        NSUInteger classTotal = 0;
        NSString* classGone = nil;
        NSUInteger classMissing = classTextsGone(meta->option, &classTotal, &classGone);
        BOOL classDead = classTotal > 0 && classMissing == classTotal && classOnly(meta->option);
        // Part of the option's path lost while it keeps other ways to act.
        NSString* leftover = nil;
        if (gone > 0 && !flagDead) {
            leftover = gone == 1 ? [NSString stringWithFormat:@"Part of the path lost: setting %@ not found", firstGone]
                                 : [NSString stringWithFormat:@"Part of the path lost: %lu settings not found, including %@",
                                                              (unsigned long)gone, firstGone];
        } else if (classMissing > 0 && !classDead) {
            leftover = [NSString stringWithFormat:@"Part of the path lost: class %@ not found", classGone ?: @"?"];
        }
        result.enabled = optionEnabled(meta);
        result.alwaysOn = meta->alwaysOn;
        id seen = observed[key] ?: pendingObservation(meta->option, NO);
        NSString* earlierText = earlierEvidence(earlier, key);
        if (done > 0) {
            id detail = details[key];
            result.evidence = [NSString stringWithFormat:@"%llu\u00d7 \u00b7 %@", (unsigned long long)done,
                                                         [detail isKindOfClass:[NSString class]] ? detail : @"-"];
        } else if ([seen isKindOfClass:[NSString class]]) {
            result.evidence = [@"ready \u00b7 " stringByAppendingString:seen];
        } else if (earlierText) {
            result.evidence = earlierText;
        } else {
            result.evidence = @"not seen yet";
        }
        NSDictionary* earlierPaths = [earlier[@"paths"] isKindOfClass:[NSDictionary class]] ? earlier[@"paths"] : @{};
        NSString* pathNote = pathsNote(meta->option, key, paths, earlierPaths);
        if (pathNote) {
            result.evidence = [NSString stringWithFormat:@"%@ \u00b7 %@", result.evidence, pathNote];
        }
        NSString* goneName = nil;
        NSUInteger nameCount = namesGone(meta->option, missingNames, &goneName);
        // Broken means the option's path is lost, not that the feature left Twitter.
        NSString* lostPath = nil;
        if (missing) {
            result.verdict = PFBCompatVerdictBroken;
            result.detail = [NSString stringWithFormat:@"Path lost: %@ not found", missing];
            lostPath = missing;
        } else if (nameCount > 0) {
            result.verdict = PFBCompatVerdictBroken;
            result.detail = nameCount == 1
                                ? [NSString stringWithFormat:@"Path lost: %@ not found, read by name", goneName]
                                : [NSString stringWithFormat:@"Path lost: %@ and %lu more not found, read by name",
                                                             goneName, (unsigned long)(nameCount - 1)];
            lostPath = goneName;
        } else if (flagDead) {
            result.verdict = PFBCompatVerdictBroken;
            result.detail = [NSString stringWithFormat:@"Path lost: setting %@ not found", firstGone ?: @"?"];
            lostPath = firstGone;
        } else if (classDead) {
            result.verdict = PFBCompatVerdictBroken;
            result.detail = [NSString stringWithFormat:@"Path lost: class %@ not found", classGone ?: @"?"];
            lostPath = classGone;
        } else {
            NSString* judged = nil;
            BOOL proven = done > 0 || [seen isKindOfClass:[NSString class]];
            result.verdict = tourVerdict(meta, key, proven, stations, &judged);
            result.detail = judged;
            // A part of the path lost while the option still acts is named, not judged.
            if (leftover) {
                result.detail = judged.length ? [NSString stringWithFormat:@"%@ \u00b7 %@", judged, leftover] : leftover;
                lostPath = gone > 0 ? firstGone : classGone;
            }
        }
        if (lostPath) {
            result.detail = [result.detail stringByAppendingString:leadsText(lostPath, leads, leadSettings, read)];
        }
        [results addObject:result];
    }
    appendInternals(results, missingNames, leads, leadSettings, read);
    return results;
}

static NSInteger countVerdict(NSArray<PFBCompatResult*>* results, PFBCompatVerdict verdict) {
    NSInteger n = 0;
    for (PFBCompatResult* r in results) {
        if (r.verdict == verdict && (!r.internal || verdict == PFBCompatVerdictBroken)) {
            n++;
        }
    }
    return n;
}

static NSString* PFBCompatSummary(NSArray<PFBCompatResult*>* results) {
    return [NSString stringWithFormat:@"%ld broken \u00b7 %ld not tested \u00b7 %ld OK",
                                      (long)countVerdict(results, PFBCompatVerdictBroken),
                                      (long)countVerdict(results, PFBCompatVerdictNotTested),
                                      (long)countVerdict(results, PFBCompatVerdictOK)];
}

PFBCompatReadState PFBCompatReadStatus(void) {
    prepare();
    id flags;
    @synchronized(gLock) {
        flags = gStore[@"flags"];
    }
    if (![flags isKindOfClass:[NSDictionary class]]) {
        return PFBCompatReadPending;
    }
    return [((NSDictionary*)flags)[@"missing"] isKindOfClass:[NSArray class]] ? PFBCompatReadDone : PFBCompatReadFailed;
}

static NSString* PFBCompatStatusText(void) {
    PFBCompatReadState state = PFBCompatReadStatus();
    if (state == PFBCompatReadPending) {
        return @"Checking\u2026";
    }
    NSArray<PFBCompatResult*>* results = PFBCompatResults();
    NSInteger broken = countVerdict(results, PFBCompatVerdictBroken);
    if (broken > 0) {
        return [NSString stringWithFormat:@"%ld problem%@", (long)broken, broken == 1 ? @"" : @"s"];
    }
    if (state == PFBCompatReadFailed) {
        return @"Settings not read";
    }
    if (PFBCompatCheckIsDue()) {
        return @"Not checked yet";
    }
    NSInteger notTested = countVerdict(results, PFBCompatVerdictNotTested);
    if (notTested > 0) {
        return [NSString stringWithFormat:@"%ld not tested", (long)notTested];
    }
    return @"Compatible";
}

void PFBCompatRefreshStatus(void) {
    [[NSUserDefaults standardUserDefaults] setObject:PFBCompatStatusText() forKey:PFBCompatStatusKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PFBCompatDidChangeNotification
                                                        object:nil];
}

// Every path the verdicts can find lost, named as the report names them.
static NSArray<NSString*>* lostPaths(NSArray<NSString*>* missingFlags, NSArray<NSString*>* missingNames) {
    NSMutableOrderedSet<NSString*>* lost = [NSMutableOrderedSet orderedSetWithArray:missingFlags];
    [lost addObjectsFromArray:missingNames];
    for (size_t i = 0; i < kClassTextCount; i++) {
        if (!objc_getClass(kClassTexts[i].className)) {
            [lost addObject:[NSString stringWithUTF8String:kClassTexts[i].className]];
        }
    }
    for (size_t i = 0; i < kReqCount; i++) {
        if (!methodPresent(kReqs[i].className, kReqs[i].selector)) {
            [lost addObject:reqName(&kReqs[i])];
        }
    }
    for (size_t i = 0; i < PFBHookRecordCount; i++) {
        if (!hookPresent(PFBHookRecords[i].className, PFBHookRecords[i].methodName)) {
            [lost addObject:hookPath(PFBHookRecords[i].className, PFBHookRecords[i].methodName)];
        }
    }
    for (size_t i = 0; i < kDeclaredCount; i++) {
        if (!hookPresent(kDeclared[i].className, kDeclared[i].selector)) {
            [lost addObject:[NSString stringWithFormat:@"%s %s", kDeclared[i].className, kDeclared[i].selector]];
        }
    }
    return lost.array;
}

static void scanThenJudge(void) {
    BOOL cached;
    @synchronized(gLock) {
        cached = gStore[@"flags"] != nil;
    }
    if (cached) {
        PFBCompatRefreshStatus();
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      NSArray<NSString*>* binaries = twitterBinaries();
      NSArray<NSString*>* missing = scanMissingFlags(binaries);
      NSArray<NSString*>* gone = missing ? scanMissingNames(binaries) : nil;
      NSSet<NSString*>* leadSettings = [NSSet set];
      NSDictionary* leads = (missing && gone) ? findLeads(binaries, lostPaths(missing, gone), &leadSettings) : @{};
      @synchronized(gLock) {
          gStore[@"flags"] = (missing && gone) ? @{
              @"missing": missing,
              @"names": gone,
              @"leads": leads,
              @"leadSettings": leadSettings.allObjects
          }
                                               : @{};
          writeStore();
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        PFBCompatRefreshStatus();
      });
    });
}

void PFBCompatReset(void) {
    prepare();
    @synchronized(gLock) {
        for (size_t i = 0; i < kMetaCount; i++) {
            atomic_store_explicit(&gHits[kMeta[i].option], 0, memory_order_relaxed);
            atomic_store_explicit(&gHasDetail[kMeta[i].option], false, memory_order_relaxed);
        }
        gStore[@"since"] = [NSDate date];
        gStore[@"counts"] = @{};
        gStore[@"details"] = @{};
        gStore[@"observed"] = @{};
        gStore[@"paths"] = @{};
        gStore[@"earlier"] = @{};
        [gStore removeObjectForKey:@"earlierSince"];
        gStore[@"tour"] = @{};
        // Twitter's binaries are read again at the next launch, as on a new install.
        [gStore removeObjectForKey:@"flags"];
        for (size_t i = 0; i < PFBCompatPathCount; i++) {
            atomic_store_explicit(&gPathSeen[i], false, memory_order_relaxed);
        }
        clearObservations();
        writeStore();
    }
    PFBCompatRefreshStatus();
}

static NSString* PFBCompatInstallText(void) {
    prepare();
    id since;
    id earlierSince;
    @synchronized(gLock) {
        since = gStore[@"since"];
        earlierSince = gStore[@"earlierSince"];
    }
    if (![since isKindOfClass:[NSDate class]]) {
        return @"";
    }
    NSDateFormatter* formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSString* text = [@"Counting since " stringByAppendingString:[formatter stringFromDate:since]];
    if ([earlierSince isKindOfClass:[NSDate class]]) {
        text = [text stringByAppendingFormat:@", earlier builds since %@", [formatter stringFromDate:earlierSince]];
    }
    return text;
}

static NSString* markFor(PFBCompatVerdict verdict) {
    if (verdict == PFBCompatVerdictBroken) {
        return @"[XX]";
    }
    return verdict == PFBCompatVerdictNotTested ? @"[--]" : @"[OK]";
}

// The copied report: the install, the verdicts, then the environment, hook
// health, decision journal and last capture.
NSString* PFBCompatReportText(void) {
    NSArray<PFBCompatResult*>* results = PFBCompatResults();
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    id identity;
    id flags;
    @synchronized(gLock) {
        identity = gStore[@"identity"];
        flags = gStore[@"flags"];
    }
    NSMutableString* text = [NSMutableString
        stringWithFormat:@"PrimeFreeBird Compatibility \u00b7 Twitter %@ \u00b7 iOS %@\n%@ \u00b7 install %@\n%@\n",
                         info[@"CFBundleShortVersionString"], UIDevice.currentDevice.systemVersion,
                         PFBCompatInstallText(), identity, PFBCompatSummary(results)];
    NSArray* missing = [flags isKindOfClass:[NSDictionary class]] ? ((NSDictionary*)flags)[@"missing"] : nil;
    if (![flags isKindOfClass:[NSDictionary class]]) {
        [text appendString:@"Twitter settings: not checked yet\n"];
    } else if (![missing isKindOfClass:[NSArray class]]) {
        [text appendString:@"Twitter settings: could not be read\n"];
    } else {
        [text appendFormat:@"Settings not found: %@\n",
                           missing.count ? [missing componentsJoinedByString:@", "] : @"none"];
    }
    NSDictionary* last = lastTour();
    if (last) {
        NSArray* steps = [last[@"results"] isKindOfClass:[NSArray class]] ? last[@"results"] : @[];
        NSString* stop = [last[@"stop"] isKindOfClass:[NSString class]] ? last[@"stop"] : nil;
        [text appendFormat:@"Path tour: %@ \u00b7 %@%@ \u00b7 %@\n", tourTime(last), [last[@"full"] boolValue] ? @"full" : @"partial",
                           stop ? [@", stopped: " stringByAppendingString:stop] : @"", [steps componentsJoinedByString:@", "]];
    }
    if (PFBCompatCheckIsDue()) {
        [text appendString:@"Check: this Twitter version is not checked yet\n"];
    }
    NSString* section = nil;
    for (PFBCompatResult* r in results) {
        if (![r.section isEqualToString:section]) {
            section = r.section;
            [text appendFormat:@"\n%@\n", section];
        }
        NSMutableArray<NSString*>* parts = [NSMutableArray array];
        if (!r.internal && !r.enabled) {
            [parts addObject:@"Off"];
        } else if (r.alwaysOn) {
            [parts addObject:@"Always on"];
        }
        if (r.detail.length) {
            [parts addObject:r.detail];
        }
        if (r.evidence.length) {
            [parts addObject:r.evidence];
        }
        [text appendFormat:@"%@ %@ - %@\n", markFor(r.verdict), r.title, [parts componentsJoinedByString:@" \u00b7 "]];
    }
    NSString* journal = PFBCompatTourJournalText();
    if (journal) {
        [text appendFormat:@"\nLAST TOUR\n%@\n", journal];
    }
    [text appendFormat:@"\n%@", PFBDebuggerReport()];
    return text;
}

static dispatch_source_t gSaveTimer;

// Counting runs from load and is saved when the app leaves, when it ends, and
// every two minutes, so a crash keeps what came before it. The verdicts wait
// for Twitter's frameworks, some of which only load with their screen.
void PFBCompatStart(void) {
    prepare();
    if (PFBCompatReadStatus() == PFBCompatReadPending) {
        [[NSUserDefaults standardUserDefaults] setObject:PFBCompatStatusText() forKey:PFBCompatStatusKey];
    }
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[ UIApplicationDidEnterBackgroundNotification,
                                       UIApplicationWillTerminateNotification ]) {
        [center addObserverForName:name
                            object:nil
                             queue:nil
                        usingBlock:^(__unused NSNotification* note) {
                          save();
                        }];
    }
    gSaveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(gSaveTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)),
                              (uint64_t)(120 * NSEC_PER_SEC), (uint64_t)(10 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gSaveTimer, ^{
      save();
    });
    dispatch_resume(gSaveTimer);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     scanThenJudge();
                   });
}
