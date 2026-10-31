// Compatibility sheet: what each option relies on in Twitter, its proofs, and the verdicts.
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

typedef struct {
    PFBCompatOption option;
    const char* key;
    const char* titleKey;  // localized at runtime, so renames reach the report
    const char* pageKey;
    BOOL alwaysOn;  // no toggle: the behavior is always active
} PFBCompatMeta;

static const PFBCompatMeta kMeta[] = {
    // In the settings' order, page by page. Behaviors with no toggle are always active,
    // reported so an IPA update that drops what they rely on still shows; filter_languages
    // is a toggle through its stored list, like muted words.
    {PFBCompat_padlock, "padlock", "PADLOCK_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_no_screenshot_detection, "no_screenshot_detection", "NO_SCREENSHOT_DETECTION_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_hide_premium_offer, "hide_premium_offer", "HIDE_PREMIUM_OFFER_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_show_scroll_indicator, "show_scroll_indicator", "SHOW_SCROLL_INDICATOR_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_disable_rtl, "disable_rtl", "DISABLE_RTL_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_hide_notifications, "hide_notifications", "HIDE_NOTIFICATIONS_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_new_twitter_settings, "new_twitter_settings", "NEW_TWITTER_SETTINGS_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_premium_unlock, "premium_unlock", "PREMIUM_UNLOCK_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE", YES},
    {PFBCompat_hide_upsells, "hide_upsells", "HIDE_UPSELLS_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE", YES},
    {PFBCompat_settings_entry, "settings_entry", "SETTINGS_ENTRY_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE", YES},
    {PFBCompat_sharing_domain, "sharing_domain", "SHARING_DOMAIN_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_strip_url_tracking, "strip_url_tracking", "STRIP_URL_TRACKING_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_always_open_safari, "always_open_safari", "ALWAYS_OPEN_SAFARI_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_new_inapp_webview, "new_inapp_webview", "NEW_INAPP_WEBVIEW_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE"},
    {PFBCompat_expand_tco_links, "expand_tco_links", "EXPAND_TCO_LINKS_TITLE", "MODERN_SETTINGS_LAYOUT_TITLE", YES},
    {PFBCompat_enable_liquid_glass, "enable_liquid_glass", "INTERFACE_STYLE_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_hide_scroll_edge_blur, "hide_scroll_edge_blur", "HIDE_SCROLL_EDGE_BLUR_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_custom_fonts, "custom_fonts", "CUSTOM_FONTS_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_accent_color, "accent_color", "THEME_OPTION_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_dark_mode_style, "dark_mode_style", "DARK_MODE_STYLE_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_tab_bar_theming, "tab_bar_theming", "TAB_BAR_THEMING_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_color_pfb_switches, "color_pfb_switches", "COLOR_PFB_SWITCHES_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_color_twitter_icon_in_top_bar, "color_twitter_icon_in_top_bar", "COLOR_TWITTER_ICON_IN_TOP_BAR_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_bar_repairs, "bar_repairs", "BAR_REPAIRS_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE", YES},
    {PFBCompat_custom_tab_bar, "custom_tab_bar", "CUSTOM_TAB_BAR_OPTION_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE", YES},
    {PFBCompat_restore_tab_labels, "restore_tab_labels", "RESTORE_TAB_LABELS_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_no_tab_bar_hiding, "no_tab_bar_hiding", "NO_TAB_BAR_HIDING_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_hide_bottom_fade, "hide_bottom_fade", "HIDE_BOTTOM_FADE_TITLE", "MODERN_SETTINGS_APPEARANCE_TITLE"},
    {PFBCompat_hide_promoted, "hide_promoted", "HIDE_PROMOTED_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_who_to_follow, "hide_who_to_follow", "HIDE_WHO_TO_FOLLOW_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_topics_to_follow, "hide_topics_to_follow", "HIDE_TOPICS_TO_FOLLOW_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_timeline_prompts, "hide_timeline_prompts", "HIDE_TIMELINE_PROMPTS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_videos_for_you, "hide_videos_for_you", "HIDE_VIDEOS_FOR_YOU_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_muted_words, "muted_words", "FILTERS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_filter_languages, "filter_languages", "FILTER_LANGUAGES_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE", NO},
    {PFBCompat_hide_topics, "hide_topics", "HIDE_TOPICS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_verified_tweets, "hide_verified_tweets", "HIDE_VERIFIED_TWEETS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_blocked_retweets, "hide_blocked_retweets", "HIDE_BLOCKED_RETWEETS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_quote_tweets, "hide_quote_tweets", "HIDE_QUOTE_TWEETS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_force_following_tab, "force_following_tab", "FORCE_FOLLOWING_TAB_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_no_focus_lost, "no_focus_lost", "NO_FOCUS_LOST_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_keep_reading_position, "keep_reading_position", "KEEP_READING_POSITION_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE", YES},
    {PFBCompat_reading_line, "reading_line", "READING_LINE_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_spaces, "hide_spaces", "HIDE_SPACES_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_new_tweets_pill, "hide_new_tweets_pill", "HIDE_NEW_TWEETS_PILL_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_hide_custom_timelines, "hide_custom_timelines", "HIDE_CUSTOM_TIMELINES_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_unlimited_timeline_tabs, "unlimited_timeline_tabs", "UNLIMITED_TIMELINE_TABS_TITLE", "MODERN_SETTINGS_TIMELINES_TITLE"},
    {PFBCompat_undo_tweet_timeout, "undo_tweet_timeout", "UNDO_TWEET_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_tweet_confirm, "tweet_confirm", "TWEET_CONFIRM_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_tweet_button, "hide_tweet_button", "HIDE_TWEET_BUTTON_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_send_sound, "send_sound", "SEND_SOUND_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_edit_tweet, "edit_tweet", "EDIT_TWEET_TITLE", "MODERN_SETTINGS_TWEETS_TITLE", YES},
    {PFBCompat_hide_threads, "hide_threads", "HIDE_THREADS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_like_confirm, "like_confirm", "LIKE_CONFIRM_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_view_count, "hide_view_count", "HIDE_VIEW_COUNT_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_bookmark_button, "hide_bookmark_button", "HIDE_BOOKMARK_BUTTON_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_hide_downvote_button, "hide_downvote_button", "HIDE_DOWNVOTE_BUTTON_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_poll_results, "show_poll_results", "SHOW_POLL_RESULTS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_reply_sorting, "reply_sorting", "REPLY_SORTING_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_restore_reply_context, "restore_reply_context", "RESTORE_REPLY_CONTEXT_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_quote_counts, "show_quote_counts", "SHOW_QUOTE_COUNTS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_tweet_source, "show_tweet_source", "SHOW_TWEET_SOURCE_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_show_account_location, "show_account_location", "SHOW_ACCOUNT_LOCATION_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_classic_tweet_detail, "classic_tweet_detail", "CLASSIC_TWEET_DETAIL_TITLE", "MODERN_SETTINGS_TWEETS_TITLE", YES},
    {PFBCompat_remove_related_tweets, "remove_related_tweets", "REMOVE_RELATED_TWEETS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE", YES},
    {PFBCompat_disable_sensitive_tweet_warnings, "disable_sensitive_tweet_warnings", "DISABLE_SENSITIVE_TWEET_WARNINGS_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_bypass_age_verification, "bypass_age_verification", "BYPASS_AGE_VERIFICATION_TITLE", "MODERN_SETTINGS_TWEETS_TITLE"},
    {PFBCompat_download_videos, "download_videos", "DOWNLOAD_VIDEOS_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_download_highest_quality, "download_highest_quality", "DOWNLOAD_HIGHEST_QUALITY_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_direct_save, "direct_save", "DIRECT_SAVE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_tweet_to_image, "tweet_to_image", "TWEET_TO_IMAGE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_tap_to_pause, "tap_to_pause", "TAP_TO_PAUSE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_no_auto_unmute, "no_auto_unmute", "NO_AUTO_UNMUTE_TITLE", "MODERN_SETTINGS_MEDIA_TITLE", NO},
    {PFBCompat_restore_video_timestamp, "restore_video_timestamp", "RESTORE_VIDEO_TIMESTAMP_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_video_captions, "disable_video_captions", "DISABLE_VIDEO_CAPTIONS_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_immersive_scroll, "disable_immersive_scroll", "DISABLE_IMMERSIVE_SCROLL_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_video_docking, "disable_video_docking", "DISABLE_VIDEO_DOCKING_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_auto_highest_load, "auto_highest_load", "AUTO_HIGHEST_LOAD_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_enable_image_preloading, "enable_image_preloading", "ENABLE_IMAGE_PRELOADING_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_upload_full_hd_videos, "upload_full_hd_videos", "UPLOAD_FULL_HD_VIDEOS_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_force_tweet_full_frame, "force_tweet_full_frame", "FORCE_TWEET_FULL_FRAME_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_disable_media_carousel, "disable_media_carousel", "DISABLE_MEDIA_CAROUSEL_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_hide_made_on_x, "hide_made_on_x", "HIDE_MADE_ON_X_TITLE", "MODERN_SETTINGS_MEDIA_TITLE"},
    {PFBCompat_follow_confirm, "follow_confirm", "FOLLOW_CONFIRM_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_expand_bio, "expand_bio", "EXPAND_BIO_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_copy_profile_info, "copy_profile_info", "COPY_PROFILE_INFO_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_remove_followers, "remove_followers", "REMOVE_FOLLOWERS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_unrounded_counts, "unrounded_counts", "UNROUNDED_COUNTS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE", YES},
    {PFBCompat_profile_initial_tab, "profile_initial_tab", "PROFILE_INITIAL_TAB_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_disable_articles, "disable_articles", "DISABLE_ARTICLES_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_disable_highlights, "disable_highlights", "DISABLE_HIGHLIGHTS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_disable_videos_tab, "disable_videos_tab", "DISABLE_VIDEOS_TAB_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_hide_blue_verified, "hide_blue_verified", "HIDE_BLUE_VERIFIED_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_hide_follow_button, "hide_follow_button", "HIDE_FOLLOW_BUTTON_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_hide_message_button, "hide_message_button", "HIDE_MESSAGE_BUTTON_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_restore_follow_button, "restore_follow_button", "RESTORE_FOLLOW_BUTTON_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_square_avatars, "square_avatars", "SQUARE_AVATARS_TITLE", "MODERN_SETTINGS_PROFILES_TITLE"},
    {PFBCompat_no_history, "no_history", "NO_HISTORY_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_advanced_search, "advanced_search", "ADVANCED_SEARCH_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_hide_trend_videos, "hide_trend_videos", "HIDE_TREND_VIDEOS_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_hide_explore_all, "hide_explore_all", "HIDE_EXPLORE_ALL_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_choose_explore_tabs, "choose_explore_tabs", "CHOOSE_EXPLORE_TABS_TITLE", "MODERN_SETTINGS_SEARCH_TITLE"},
    {PFBCompat_hide_typing_indicator, "hide_typing_indicator", "HIDE_TYPING_INDICATOR_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_suggested_chats, "hide_suggested_chats", "HIDE_SUGGESTED_CHATS_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_voice_transcription, "voice_transcription", "VOICE_TRANSCRIPTION_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_download_voice_messages, "download_voice_messages", "DOWNLOAD_VOICE_MESSAGES_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_voice_note_from_video, "voice_note_from_video", "VOICE_NOTE_FROM_VIDEO_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_analyze, "hide_grok_analyze", "HIDE_GROK_ANALYZE_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_sidebar, "hide_grok_sidebar", "HIDE_GROK_SIDEBAR_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_bot, "hide_grok_bot", "HIDE_GROK_BOT_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_hide_grok_create, "hide_grok_create", "HIDE_GROK_CREATE_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_disable_auto_translate, "disable_auto_translate", "DISABLE_AUTO_TRANSLATE_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE"},
    {PFBCompat_grok_translation, "grok_translation", "GROK_TRANSLATION_TITLE", "MODERN_SETTINGS_MESSAGES_TITLE", YES},
    {PFBCompat_restore_twitter_names, "restore_twitter_names", "RESTORE_TWITTER_NAMES_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_refresh_pill_label, "refresh_pill_label", "REFRESH_PILL_LABEL_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_restore_tweet_button, "restore_tweet_button", "RESTORE_TWEET_BUTTON_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_restore_refresh_sounds, "restore_refresh_sounds", "RESTORE_REFRESH_SOUNDS_TITLE", "MODERN_SETTINGS_BRANDING_TITLE"},
    {PFBCompat_launch_screen, "launch_screen", "LAUNCH_SCREEN_TITLE", "MODERN_SETTINGS_BRANDING_TITLE", YES},
    {PFBCompat_web_session, "web_session", "LAB_GROUP_SESSION", "MODERN_SETTINGS_LAB_TITLE"},
    {PFBCompat_web_login, "web_login", "WEB_LOGIN_TITLE", "MODERN_SETTINGS_LAB_TITLE", YES},
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
    {PFBCompatPath_grok_bot_upsells, PFBCompat_hide_grok_bot, "upsells"},
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
    {PFBCompatPath_starts_muted, PFBCompat_tap_to_pause, "starts muted"},
    {PFBCompatPath_replies_by_date, PFBCompat_reply_sorting, "replies by date"},
    {PFBCompatPath_native_filter_button, PFBCompat_advanced_search, "Twitter's filter button when off"},
    {PFBCompatPath_views_footer, PFBCompat_hide_view_count, "opened Tweet"},
    {PFBCompatPath_tco_requests, PFBCompat_expand_tco_links, "t.co requests"},
    {PFBCompatPath_tab_capacity, PFBCompat_custom_tab_bar, "tab bar capacity"},
    {PFBCompatPath_grok_imagine_button, PFBCompat_hide_grok_create, "Imagine button under a post"},
    {PFBCompatPath_grok_create_own_button, PFBCompat_hide_grok_create, "create-your-own button"},
    {PFBCompatPath_grok_create_own_pill, PFBCompat_hide_grok_create, "immersive create-your-own pill"},
    {PFBCompatPath_threads_popup_menu, PFBCompat_hide_threads, "pop-up menu"},
    {PFBCompatPath_threads_post_menu, PFBCompat_hide_threads, "About this post menu"},
    {PFBCompatPath_grok_post_menu, PFBCompat_hide_grok_analyze, "About this post menu"},
    {PFBCompatPath_settings_tab_bar, PFBCompat_custom_tab_bar, "Twitter settings"},
    {PFBCompatPath_native_bar_hidden, PFBCompat_enable_liquid_glass, "hidden with Twitter's bar"},
    {PFBCompatPath_rtl_checks, PFBCompat_disable_rtl, "direction checks"},
    {PFBCompatPath_click_ids, PFBCompat_expand_tco_links, "click IDs"},
    {PFBCompatPath_ad_redirect, PFBCompat_expand_tco_links, "ad redirect"},
    {PFBCompatPath_video_feed_response, PFBCompat_hide_promoted, "video feed response"},
    {PFBCompatPath_video_feed_ads, PFBCompat_hide_promoted, "ads in the video feed response"},
    {PFBCompatPath_counter_digits, PFBCompat_custom_fonts, "counter digits"},
    {PFBCompatPath_return_report, PFBCompat_no_focus_lost, "return to the app"},
    {PFBCompatPath_opened_links, PFBCompat_strip_url_tracking, "opened links"},
    {PFBCompatPath_home_retweets, PFBCompat_hide_blocked_retweets, "Home Retweets"},
    {PFBCompatPath_reply_order_set, PFBCompat_reply_sorting, "order set at opening"},
    {PFBCompatPath_reply_order_request, PFBCompat_reply_sorting, "order requested"},
    {PFBCompatPath_feather, PFBCompat_restore_tweet_button, "feather"},
    {PFBCompatPath_search_bar_frame, PFBCompat_enable_liquid_glass, "search bar frame"},
    {PFBCompatPath_bar_backdrop, PFBCompat_enable_liquid_glass, "bar backdrop"},
    {PFBCompatPath_window_tint, PFBCompat_enable_liquid_glass, "window tint"},
    {PFBCompatPath_reply_bar, PFBCompat_enable_liquid_glass, "reply bar"},
    {PFBCompatPath_home_bar_button, PFBCompat_muted_words, "Home bar button"},
    {PFBCompatPath_eye_button, PFBCompat_hide_notifications, "eye button"},
    {PFBCompatPath_notification_swipe, PFBCompat_hide_notifications, "notification swipe"},
    {PFBCompatPath_notification_tweet_menu, PFBCompat_hide_notifications, "Tweet menu"},
    {PFBCompatPath_controls_hold, PFBCompat_tap_to_pause, "controls hold"},
    {PFBCompatPath_played_voice_note, PFBCompat_download_voice_messages, "played voice note"},
    {PFBCompatPath_interface_text, PFBCompat_custom_fonts, "interface text"},
    {PFBCompatPath_results_filters_button, PFBCompat_advanced_search, "search results button"},
    {PFBCompatPath_leaving_app, PFBCompat_padlock, "leaving the app"},
    {PFBCompatPath_glass_tab_bar, PFBCompat_tab_bar_theming, "glass tab bar"},
    {PFBCompatPath_glass_tweet_button, PFBCompat_restore_tweet_button, "glass Tweet button"},
    {PFBCompatPath_glass_tabs, PFBCompat_custom_tab_bar, "glass tab bar"},
    {PFBCompatPath_glass_bottom_reserve, PFBCompat_restore_tab_labels, "bottom reserve"},
    {PFBCompatPath_native_tab_editor, PFBCompat_custom_tab_bar, "Twitter's tab editor"},
    {PFBCompatPath_navigation_bar_text, PFBCompat_custom_fonts, "navigation bar"},
    {PFBCompatPath_glass_pill, PFBCompat_restore_tab_labels, "pill height"},
    {PFBCompatPath_bottom_fade, PFBCompat_hide_bottom_fade, "fade under the tab bar"},
    {PFBCompatPath_tab_editor_page, PFBCompat_custom_tab_bar, "tab editor page"},
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
    {PFBCompat_no_focus_lost, "T1ViewControllerScribeEventObserver", "-viewControllerApplicationDidBecomeActive:"},
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
    {PFBCompat_disable_rtl, "NSString", "-tfs_plainTextShouldBeRenderedFromRight"},
    {PFBCompat_disable_rtl, "NSString", "-tfs_statusTextShouldBeRenderedFromRight"},
    {PFBCompat_disable_rtl, "NSString", "-tfs_labelTextShouldBeRenderedFromRight"},
    {PFBCompat_disable_rtl, "TFNTwitterDisplayTextModel", "-_tfn_shouldBeRenderedFromRight"},
    {PFBCompat_disable_rtl, "TFNTwitterStatus", "-shouldBeRenderedFromRight"},
    {PFBCompat_hide_premium_offer, "T1ProfileSummaryView", "-shouldShowGetVerifiedButton"},
    {PFBCompat_hide_premium_offer, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_premium_offer, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_notifications, "T1TabNavigationController", "-_t1_main_updateNavigationItemForViewController:isRoot:providingLeftBarButtonItems:rightBarButtonItems:"},
    {PFBCompat_hide_notifications, "T1NotificationsViewController", "-viewWillAppear:"},
    {PFBCompat_hide_notifications, "T1NotificationsViewController", "-viewDidAppear:"},
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
    {PFBCompat_strip_url_tracking, "T1ViewControllerNavigationHelper", "+_t1_handlerForURL:expandedURL:account:scribeContext:sourceViewController:"},
    {PFBCompat_strip_url_tracking, "T1ViewControllerNavigationHelper", "+_t1_handlerForURL:account:scribeContext:fromSourceStatus:applyAdURLTransforms:sourceViewController:"},
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
    {PFBCompat_custom_tab_bar, "T1DashContentController", "-prepareForReuse"},
    {PFBCompat_custom_tab_bar, "T1AppSplitViewController", "-private_loadDashHostView"},
    {PFBCompat_custom_tab_bar, "T1AppSplitViewController", "-dashContentController"},
    {PFBCompat_custom_tab_bar, "T1DashContentPresenter", "-dashDidSettleOpen:"},
    {PFBCompat_custom_tab_bar, "T1GenericSettingsViewController", "-viewWillAppear:"},
    {PFBCompat_custom_tab_bar, "T1GenericSettingsViewController", "-viewWillDisappear:"},
    {PFBCompat_custom_tab_bar, "T1TabBarViewController", "-setTabBarHidden:withDuration:"},
    {PFBCompat_custom_tab_bar, "T1TabView", "-scribePage"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-recalculateVisiblePanels"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-setVisibleTabEntries:"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-_t1_tabEntriesLimitedToBottomCapacity:"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-visiblePanelIDsForAppNavigation:"},
    {PFBCompat_custom_tab_bar, "T1TabbedAppNavigationViewController", "-_t1_bottomTabItemCapacity"},
    {PFBCompat_custom_tab_bar, "TFNTwitterAccount", "-canAccessXPayments"},
    {PFBCompat_custom_tab_bar, "T1ProfileUserViewModel", "-hasAccessToPayments"},
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
    {PFBCompat_custom_tab_bar, "UIViewController", "-tfn_tabBarIntegration"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-_t1_layoutForTabBar"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-setSelected:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-_t1_layoutBadgeViewMaximized"},
    {PFBCompat_restore_tab_labels, "T1TabBarHostView", "-layoutSubviews"},
    {PFBCompat_restore_tab_labels, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-_t1_updateImageViewAnimated:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-setBadgeCount:animated:"},
    {PFBCompat_restore_tab_labels, "T1TabView", "-setHasUnreadContent:animated:"},
    {PFBCompat_restore_tab_labels, "TFNCustomTabBar", "-layoutSubviews"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation10TabBarView", "-layoutSubviews"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation14TabBarItemView", "-layoutSubviews"},
    {PFBCompat_restore_tab_labels, "XDSGlass", "-setBounds:"},
    {PFBCompat_hide_bottom_fade, "_TtC13XDesignSystem19ScrollEdgeTreatment", "-layoutSubviews"},
    {PFBCompat_hide_bottom_fade, "CAGradientLayer", "-setColors:"},
    {PFBCompat_hide_bottom_fade, "CAGradientLayer", "-setLocations:"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "-viewDidLayoutSubviews"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "-viewWillAppear:"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "-viewWillDisappear:"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation19TabBarEditorBarView", "-intrinsicContentSize"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation20TabBarEditorItemView", "-layoutSubviews"},
    {PFBCompat_custom_fonts, "UIFont", "+tfn_fontWithName:size:"},
    {PFBCompat_custom_fonts, "XFontCatalog", "+tabularDigitsFontOfSize:weight:"},
    {PFBCompat_custom_fonts, "UIFontPickerViewController", "-viewWillAppear:"},
    {PFBCompat_custom_fonts, "XFontCatalog", "+contentFontWithOffset:weight:"},
    {PFBCompat_custom_fonts, "XFontCatalog", "+customFontOfSize:weight:scalesWithDynamicType:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-_t1_updateImageViewAnimated:"},
    {PFBCompat_tab_bar_theming, "_TtC10TFNUISwift25LegacySegmentedTabBarView", "-setStyle:"},
    {PFBCompat_tab_bar_theming, "_TtC10TFNUISwift26LegacySegmentedTabBarStyle", "-setHighlightBarColor:"},
    {PFBCompat_tab_bar_theming, "_TtC10TFNUISwift31LegacySegmentedHighlightBarView", "-setBackgroundColor:"},
    {PFBCompat_tab_bar_theming, "T1TabBarHostView", "-layoutSubviews"},
    {PFBCompat_tab_bar_theming, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-setBadgeCount:animated:"},
    {PFBCompat_tab_bar_theming, "T1TabView", "-setHasUnreadContent:animated:"},
    {PFBCompat_tab_bar_theming, "TFNCustomTabBar", "-layoutSubviews"},
    {PFBCompat_tab_bar_theming, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_tab_bar_theming, "_TtC11XNavigation14TabBarItemView", "-layoutSubviews"},
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
    {PFBCompat_enable_liquid_glass, "UITabBar", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "T1TabView", "-setBadgeCount:animated:"},
    {PFBCompat_enable_liquid_glass, "T1TabView", "-setHasUnreadContent:animated:"},
    {PFBCompat_enable_liquid_glass, "NSBundle", "-objectForInfoDictionaryKey:"},
    {PFBCompat_enable_liquid_glass, "T1PersistentComposeView", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "T1TabBarHostView", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "T1TabBarViewController", "-_t1_layoutTabBar"},
    {PFBCompat_enable_liquid_glass, "T1TabBarViewController", "-_t1_updateTabBarHidden"},
    {PFBCompat_enable_liquid_glass, "T1TabBarViewController", "-setTabBarCollapseRatio:"},
    {PFBCompat_enable_liquid_glass, "T1TabView", "-_t1_updateImageViewAnimated:"},
    {PFBCompat_enable_liquid_glass, "TFNTwitterAccount", "-isDummyTest1FeatureEnabled"},
    {PFBCompat_enable_liquid_glass, "TFNCustomTabBar", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "TFNNavigationBarSearchView", "-setFrame:"},
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
    {PFBCompat_enable_liquid_glass, "UINavigationBar", "-didMoveToWindow"},
    {PFBCompat_enable_liquid_glass, "UINavigationBar", "-layoutSubviews"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setLeftBarButtonItem:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setLeftBarButtonItems:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setLeftBarButtonItems:animated:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setRightBarButtonItem:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setRightBarButtonItems:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setRightBarButtonItems:animated:"},
    {PFBCompat_enable_liquid_glass, "UINavigationItem", "-setTrailingItemGroups:"},
    {PFBCompat_enable_liquid_glass, "_TtC16XFeatureSwitches18FeatureSwitchStore", "-boolForKey:"},
    // Navigation-bar repairs in NavBarIcons.x act whatever the Liquid Glass setting says.
    {PFBCompat_bar_repairs, "CALayer", "-addAnimation:forKey:"},
    {PFBCompat_bar_repairs, "CALayer", "-setOpacity:"},
    {PFBCompat_bar_repairs, "AvatarImageView", "-setImage:"},
    {PFBCompat_bar_repairs, "TFNBarButtonItemButton", "-didMoveToWindow"},
    {PFBCompat_bar_repairs, "TFNBarButtonItemButton", "-layoutSubviews"},
    {PFBCompat_bar_repairs, "TFNNavigationBar", "-setFrame:"},
    {PFBCompat_bar_repairs, "TFNNavigationController", "-_tfn_setCurrentNavigationBarSimulatedHeight:isAnimated:"},
    {PFBCompat_bar_repairs, "UIBarButtonItem", "-setImage:"},
    {PFBCompat_bar_repairs, "UIImageView", "-didMoveToWindow"},
    {PFBCompat_bar_repairs, "UIImageView", "-setImage:"},
    {PFBCompat_bar_repairs, "UINavigationBar", "-layoutSubviews"},
    {PFBCompat_bar_repairs, "UINavigationController", "-navigationBar:shouldPopItem:"},
    {PFBCompat_bar_repairs, "UINavigationController", "-popViewControllerAnimated:"},
    {PFBCompat_bar_repairs, "UINavigationController", "-pushViewController:animated:"},
    {PFBCompat_bar_repairs, "UIView", "-setAlpha:"},
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
    {PFBCompat_hide_promoted, "TNLResponseInfo", "-initWithFinalURLRequest:URLResponse:source:data:temporarySavedFile:"},
    {PFBCompat_hide_videos_for_you, "TNLResponseInfo", "-initWithFinalURLRequest:URLResponse:source:data:temporarySavedFile:"},
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
    {PFBCompat_hide_who_to_follow, "_TtC14T1TwitterSwift28URTTimelineCarouselViewModel", "$clientEventInfo"},
    {PFBCompat_hide_who_to_follow, "_TtCVOV10TFSURTCore16URTTimelineEntry7Content4Item15ClientEventInfo", "-component"},
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
    {PFBCompat_hide_quote_tweets, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_quote_tweets, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
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
    {PFBCompat_muted_words, "_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController", "-viewWillAppear:"},
    {PFBCompat_muted_words, "_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController", "-viewDidAppear:"},
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
    {PFBCompat_hide_tweet_button, "_TtC11XNavigation23TabBarAccessoryHostView", "-didMoveToWindow"},
    {PFBCompat_hide_tweet_button, "_TtC11XNavigation23TabBarAccessoryHostView", "-layoutSubviews"},
    {PFBCompat_hide_threads, "UIButton", "-setMenu:"},
    {PFBCompat_hide_threads, "UIViewController", "-t1_actionsViewControllerForStatus:account:source:options:doneBlock:"},
    {PFBCompat_hide_threads, "TFNMenuSheetViewController", "-initWithActionItems:"},
    {PFBCompat_hide_threads, "TFNActionItem", "+actionItemWithTitle:imageName:action:"},
    {PFBCompat_hide_notifications, "UIButton", "-setMenu:"},
    {PFBCompat_hide_notifications, "UITableView", "-layoutSubviews"},
    {PFBCompat_hide_notifications, "UIViewController", "-t1_actionsViewControllerForStatus:account:source:options:doneBlock:"},
    {PFBCompat_hide_notifications, "TFNMenuSheetViewController", "-initWithActionItems:"},
    {PFBCompat_hide_notifications, "TFNActionItem", "+actionItemWithTitle:imageName:action:"},
    {PFBCompat_hide_threads, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_threads, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_like_confirm, "TTAStatusInlineActionsView", "-didTapInlineActionButton:"},
    {PFBCompat_like_confirm, "_TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView", "-handleDoubleTap:"},
    {PFBCompat_hide_view_count, "TTAStatusInlineActionsView", "+_t1_inlineActionViewClassesForViewModel:options:displayType:account:"},
    {PFBCompat_hide_view_count, "T1ConversationFooterTextView", "-updateFooterTextView"},
    {PFBCompat_hide_view_count, "T1ConversationFooterTextView", "+sizeForViewModel:footerItem:maximumWidth:grokEditImageButtonConfiguration:"},
    {PFBCompat_hide_view_count, "T1ConversationFooterTextView", "-footerItem"},
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
    {PFBCompat_reply_sorting, "TFSReplySortingState", "-init"},
    {PFBCompat_reply_sorting, "TFSReplySortingState", "-sortByLikes"},
    {PFBCompat_reply_sorting, "TFSReplySortingState", "-sortByRecency"},
    {PFBCompat_reply_sorting, "TFSReplySortingState", "-sortByRelevance"},
    {PFBCompat_reply_sorting, "TFNActionItem", "+actionItemWithTitle:imageName:action:"},
    {PFBCompat_reply_sorting, "T1ConversationContainerViewController", "-navigationController"},
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
    {PFBCompat_show_tweet_source, "T1ConversationFooterTextView", "-updateFooterTextView"},
    {PFBCompat_show_tweet_source, "T1ConversationFooterTextView", "-footerItem"},
    {PFBCompat_show_tweet_source, "T1ConversationFooterTextView", "-viewModel"},
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
    {PFBCompat_hide_made_on_x, "T1StatusEditedOnXLabelAdapter", "-shouldBeVisibleForViewModel:"},
    {PFBCompat_upload_full_hd_videos, "T1LongerVideoUploadEnabledConfig", "-isUploadFullHDVideoEnabled"},
    {PFBCompat_upload_full_hd_videos, "T1LongerVideoUploadEnabledConfig", "-isUploadFullHDVideoEnabledByDefault"},
    {PFBCompat_upload_full_hd_videos, "T1VideoQualityUploadSettings", "-shouldAllowFullHdVideoUpload:"},
    {PFBCompat_follow_confirm, "TUIFollowButtonV2", "-buttonTapped"},
    {PFBCompat_follow_confirm, "TUIFollowControl", "-_followUser:event:"},
    {PFBCompat_expand_bio, "T1ProfileUserInfoView", "-isBioExpanded"},
    {PFBCompat_copy_profile_info, "XDSButtonRow", "-layoutSubviews"},
    {PFBCompat_unrounded_counts, "T1ProfileFriendsFollowingViewModel", "-_t1_followCountTextWithLabel:singularLabel:count:highlighted:"},
    {PFBCompat_remove_followers, "T1ProfileHeaderViewController", "-profileMoreActionsBaseActionItemsWithSender:"},
    {PFBCompat_remove_followers, "T1ProfileHeaderViewController", "-viewModel"},
    {PFBCompat_remove_followers, "T1ProfileUserViewModel", "-isFollowingViewer"},
    {PFBCompat_remove_followers, "TFNActionItem", "+actionItemWithTitle:imageName:action:"},
    {PFBCompat_remove_followers, "TFNActionItem", "-isDestructive"},
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
    {PFBCompat_advanced_search, "_TtC15TwitterSearchV29SearchBar", "-layoutSubviews"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setPinnedTrailingGroup:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setRightBarButtonItems:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setRightBarButtonItems:animated:"},
    {PFBCompat_advanced_search, "UINavigationItem", "-setTrailingItemGroups:"},
    {PFBCompat_advanced_search, "UIViewController", "-viewDidAppear:"},
    {PFBCompat_advanced_search, "UIViewController", "-viewWillAppear:"},
    {PFBCompat_hide_trend_videos, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_hide_trend_videos, "TFNItemsDataViewController", "-updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:"},
    {PFBCompat_hide_explore_all, "_TtC14T1TwitterSwift28GuideContainerViewController", "-tfn_navigationBarAccessoryView"},
    {PFBCompat_hide_explore_all, "_TtC14T1TwitterSwift28GuideContainerViewController", "-viewDidLoad"},
    {PFBCompat_hide_explore_all, "_TtC14T1TwitterSwift28GuideContainerViewController", "-viewWillAppear:"},
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
    {PFBCompat_choose_explore_tabs, "_TtC14T1TwitterSwift28GuideContainerViewController", "-tfn_navigationBarAccessoryView"},
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
    {PFBCompat_hide_suggested_chats, "_TtC16XFeatureSwitches18FeatureSwitchStore", "-boolForKey:"},
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
    {PFBCompat_voice_transcription, "_TtC16XFeatureSwitches18FeatureSwitchStore", "-boolForKey:"},
    {PFBCompat_download_voice_messages, "_TtC6ChatUI26MessageAttachmentAudioView", "-layoutSubviews"},
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
    {PFBCompat_hide_grok_analyze, "_TtC16XFeatureSwitches18FeatureSwitchStore", "-boolForKey:"},
    {PFBCompat_hide_grok_sidebar, "T1TabbedAppNavigationViewController", "-visiblePanelIDsForAppNavigation:"},
    {PFBCompat_hide_grok_sidebar, "T1DashContentController", "-updateVisiblePanelIDs"},
    {PFBCompat_hide_grok_sidebar, "T1DashContentController", "-prepareForReuse"},
    {PFBCompat_hide_grok_sidebar, "T1AppSplitViewController", "-private_loadDashHostView"},
    {PFBCompat_hide_grok_sidebar, "T1AppSplitViewController", "-dashContentController"},
    {PFBCompat_hide_grok_sidebar, "T1DashContentPresenter", "-dashDidSettleOpen:"},
    {PFBCompat_hide_grok_sidebar, "_TtC14T1TwitterSwift20XTabbedAppNavigation", "-visiblePanelIDs"},
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
    {PFBCompat_hide_grok_create, "T1StandardStatusDownloadGrokImagineButtonViewAdapter", "-shouldBeVisibleForViewModel:"},
    {PFBCompat_hide_grok_create, "T1StandardStatusGrokCreateOwnButtonAdapter", "-shouldBeVisibleForViewModel:"},
    {PFBCompat_hide_grok_create, "_TtC14T1TwitterSwift36ImmersiveShimmerPillButtonPluginView", "-layoutSubviews"},
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
    {PFBCompat_restore_tweet_button, "TFNExpandingButtonItemView", "-_tfn_updateIcon"},
    {PFBCompat_restore_tweet_button, "UIImage", "+tfn_vectorImageNamed:height:fillColor:"},
    {PFBCompat_restore_tweet_button, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_restore_tweet_button, "_TtC11XNavigation23TabBarAccessoryHostView", "-didMoveToWindow"},
    {PFBCompat_restore_tweet_button, "_TtC11XNavigation23TabBarAccessoryHostView", "-layoutSubviews"},
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
    {PFBCompat_reply_in_webview, "WKContentView", "-_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:"},
    {PFBCompat_flex_twitter, "T1AppDelegate", "-application:didFinishLaunchingWithOptions:"},
    {PFBCompat_flex_twitter, "T1AppDelegate", "-applicationWillResignActive:"},
    {PFBCompat_web_session, "T1WebViewController", "-updateConfiguration:"},
    {PFBCompat_web_session, "_TtC14T1TwitterSwift26PreloadedWebviewController", "-updateConfiguration:"},
    {PFBCompat_web_session, "NSURLSession", "-dataTaskWithRequest:"},
    {PFBCompat_web_session, "NSURLSession", "-dataTaskWithRequest:completionHandler:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromData:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromFile:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromData:completionHandler:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithRequest:fromFile:completionHandler:"},
    {PFBCompat_web_session, "NSURLSession", "-uploadTaskWithStreamedRequest:"},
    {PFBCompat_web_session, "NSURLSessionTask", "-resume"},
    {PFBCompat_web_login, "T1AccountsViewController", "-private_startLoginFlowWithSender:"},
    {PFBCompat_web_session, "T1AppDelegate", "-applicationDidBecomeActive:"},
    {PFBCompat_web_login, "T1HostViewController", "-makeOnboardingViewControllerWithCompletion:"},
    {PFBCompat_web_session, "T1WebViewController", "-didFinishLoadingWithError:"},
    {PFBCompat_web_session, "WKWebView", "-loadRequest:"},
    {PFBCompat_premium_unlock, "TFNTwitterAccount", "-isSubscribedTo:"},
    {PFBCompat_premium_unlock, "TFNTwitterAccount", "-isEditProfileUsernameEnabled"},
    {PFBCompat_premium_unlock, "TFNTwitterAccount", "-isPremiumTierUser"},
    {PFBCompat_premium_unlock, "TFSAccountFeatureSwitches", "-isSubscriptionsSettingsItemEnabledWithProvider:"},
    {PFBCompat_premium_unlock, "T1AppServicesManager", "-_brazeTierStringForAccount:"},
    {PFBCompat_premium_unlock, "T1TabbedAppNavigation", "-showPremiumHubManageSubscriptionWithSource:withCompletion:"},
    {PFBCompat_premium_unlock, "T1ProfileSummaryView", "-shouldShowUnderReviewButton"},
    {PFBCompat_launch_screen, "UIImage", "+imageNamed:"},
    {PFBCompat_launch_screen, "T1AnimatedLaunchScreenView", "-layoutSubviews"},
    {PFBCompat_launch_screen, "T1AnimatedLaunchScreenView", "-animateRevealWithCompletion:"},
    {PFBCompat_expand_tco_links, "TFSTwitterEntityURL", "-url"},
    {PFBCompat_expand_tco_links, "TFSTwitterEntityURL", "-expandedURL"},
    {PFBCompat_expand_tco_links, "TNUTalonUtilities", "+sendTalonRequestForAnalytics:"},
    {PFBCompat_expand_tco_links, "TNUTalonUtilities", "+verifyTalonURL:completion:"},
    {PFBCompat_expand_tco_links, "T1TwitterClickIDHandler", "+URLByAppendingTwitterClickIDIfNecessary:status:account:scribePage:scribeComponent:"},
    {PFBCompat_expand_tco_links, "T1UnifiedCardBrowserDestinationHandlerHelper", "-urlByAppendingTwitterClickIDToUrl:scribeComponent:"},
    {PFBCompat_expand_tco_links, "T1UnifiedCardXLinkDestinationHandlerHelper", "-urlByAppendingTwitterClickIDToUrl:scribeComponent:"},
    {PFBCompat_expand_tco_links, "TUCJobDetailsComponentModel", "+conditionallyApplyPromotedContentClickID:toDestination:"},
    {PFBCompat_expand_tco_links, "TFNTwitterAdsTPMIdSyncManager", "-shouldCreateRedirectURLForURL:"},
    {PFBCompat_expand_tco_links, "TFNTwitterAdsTPMIdSyncManager", "-createRedirectURLForURLIfNeeded:"},
    {PFBCompat_remove_related_tweets, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_keep_reading_position, "TFNItemsDataViewController", "-setSections:restoreScrollPosition:"},
    {PFBCompat_settings_entry, "T1GenericSettingsViewController", "-viewWillAppear:"},
    {PFBCompat_settings_entry, "T1GenericSettingsViewController", "-account"},
    {PFBCompat_settings_entry, "TFNItemsDataViewController", "-updatedSections:forStyle:"},
    {PFBCompat_settings_entry, "TFNSettingsNavigationItem", "-initWithTitle:detail:iconName:controllerFactory:"},
    {PFBCompat_settings_entry, "TFNTitleView", "+titleViewWithTitle:subtitle:"},
    {PFBCompat_settings_entry, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_settings_entry, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_new_twitter_settings, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_new_twitter_settings, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_new_twitter_settings, "_TtC9XSettings26SettingsListViewController", "-viewWillAppear:"},
    {PFBCompat_new_twitter_settings, "_TtC9XSettings26SettingsListViewController", "-viewWillDisappear:"},
    {PFBCompat_new_twitter_settings, "_TtC9XSettings26SettingsListViewController", "-viewDidDisappear:"},
    {PFBCompat_new_twitter_settings, "_TtC9XSettings26SettingsListViewController", "-viewDidLayoutSubviews"},
    {PFBCompat_accent_color, "T1GenericSettingsViewController", "-viewWillAppear:"},
    {PFBCompat_accent_color, "T1GenericSettingsViewController", "-viewDidDisappear:"},
    {PFBCompat_no_auto_unmute, "T1InlineVideoView", "-didMoveToWindow"},
    {PFBCompat_color_pfb_switches, "TAEColorSettings", "+sharedSettings"},
    {PFBCompat_color_pfb_switches, "TAEColorSettings", "-currentColorPalette"},
    {PFBCompat_color_pfb_switches, "TAETwitterColorPaletteSettingInfo", "-colorPalette"},
    {PFBCompat_download_videos, "TFSTwitterEntityMedia", "-videoInfo"},
    {PFBCompat_download_videos, "TFSTwitterEntityMedia", "-mediaType"},
    {PFBCompat_download_videos, "TFSTwitterEntityMediaVideoInfo", "-variants"},
    {PFBCompat_download_videos, "TFSTwitterEntityMediaVideoVariant", "-url"},
    {PFBCompat_download_videos, "TFSTwitterEntityMediaVideoVariant", "-contentType"},
    {PFBCompat_download_videos, "TFNHUD", "-initWithText:"},
    {PFBCompat_download_videos, "TFNActiveTextItem", "-initWithTextModel:activeRanges:"},
    {PFBCompat_download_videos, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_download_highest_quality, "TFSTwitterEntityMedia", "-videoInfo"},
    {PFBCompat_download_highest_quality, "TFSTwitterEntityMedia", "-mediaType"},
    {PFBCompat_download_highest_quality, "TFSTwitterEntityMediaVideoInfo", "-variants"},
    {PFBCompat_download_highest_quality, "TFSTwitterEntityMediaVideoVariant", "-url"},
    {PFBCompat_download_highest_quality, "TFSTwitterEntityMediaVideoVariant", "-contentType"},
    {PFBCompat_direct_save, "TFSTwitterEntityMedia", "-videoInfo"},
    {PFBCompat_direct_save, "TFSTwitterEntityMedia", "-mediaType"},
    {PFBCompat_direct_save, "TFSTwitterEntityMediaVideoInfo", "-variants"},
    {PFBCompat_direct_save, "TFSTwitterEntityMediaVideoVariant", "-url"},
    {PFBCompat_direct_save, "TFSTwitterEntityMediaVideoVariant", "-contentType"},
    {PFBCompat_custom_fonts, "TFNActiveTextItem", "-initWithTextModel:activeRanges:"},
    {PFBCompat_custom_fonts, "XNAVNavigationController", "-viewDidLoad"},
    {PFBCompat_custom_tab_bar, "T1PanelIdentity", "+iconImageNameForPanelID:"},
    {PFBCompat_custom_tab_bar, "T1PanelIdentity", "+localizedNameForPanelID:"},
    {PFBCompat_custom_tab_bar, "T1PanelIdentity", "+stringForPanelID:"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift20XTabbedAppNavigation", "-visiblePanelIDs"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation10TabBarView", "-layoutSubviews"},
    {PFBCompat_custom_tab_bar, "T1TabCustomizationConfig", "-isTabCustomizationEnabled"},
    {PFBCompat_custom_tab_bar, "T1TabCustomizationViewController", "-initWithAccount:scribeContext:"},
    {PFBCompat_custom_tab_bar, "T1TabCustomizationViewController", "-viewDidLoad"},
    {PFBCompat_custom_tab_bar, "T1TabCustomizationViewController", "-didPressSaveButton"},
    {PFBCompat_custom_tab_bar, "TFSTwitterScribeContext", "+scribeContextWithPage:"},
    {PFBCompat_custom_tab_bar, "T1HostViewController", "-appNavigation"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift34XTabbedAppNavigationViewController", "-viewDidLoad"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift34XTabbedAppNavigationViewController", "-viewDidAppear:"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift34XTabbedAppNavigationViewController", "-appNavigation"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift20XTabbedAppNavigation", "-account"},
    {PFBCompat_custom_tab_bar, "TFSAccountUserDefaults", "-setObject:forKey:"},
    {PFBCompat_custom_tab_bar, "TFSAccountUserDefaults", "-objectForKey:"},
    {PFBCompat_custom_tab_bar, "TFSAccountUserDefaults", "-accountID"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation10TabBarView", "-intrinsicContentSize"},
    {PFBCompat_restore_tab_labels, "XNAVNavigationController", "-viewWillLayoutSubviews"},
    {PFBCompat_no_tab_bar_hiding, "XNAVNavigationController", "-viewWillLayoutSubviews"},
    {PFBCompat_no_tab_bar_hiding, "_TtCC11XNavigation14CollapseEngine14ScrollObserver", "-handlePan:"},
    {PFBCompat_enable_liquid_glass, "T1PanelIdentity", "+iconImageNameForPanelID:"},
    {PFBCompat_web_session, "T1WebViewController", "-initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:"},
    {PFBCompat_advanced_search, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_tap_to_pause, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_enable_liquid_glass, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_custom_tab_bar, "UIImage", "+tfn_vectorImageNamed:fitsSize:fillColor:"},
    {PFBCompat_hide_typing_indicator, "NSURLSessionWebSocketTask", "-sendMessage:completionHandler:"},
    // Ivars read by name, as "$name"; a "|" lists the other names the code accepts.
    {PFBCompat_no_tab_bar_hiding, "XNAVNavigationController", "$appliedConfiguration"},
    {PFBCompat_no_tab_bar_hiding, "XNAVNavigationController", "$chromeFrozenScreen"},
    // A size the code relies on, as "=name>next:sizes": the bytes from one ivar to the next.
    {PFBCompat_no_tab_bar_hiding, "XNAVNavigationController", "=appliedConfiguration>chromeFrozenScreen:40,48"},
    {PFBCompat_no_tab_bar_hiding, "XNAVNavigationController", "$$__lazy_storage_$_collapseEngine"},
    {PFBCompat_no_tab_bar_hiding, "_TtC11XNavigation14CollapseEngine", "$collapseProgress"},
    {PFBCompat_restore_tab_labels, "XNAVNavigationController", "$$__lazy_storage_$_collapseEngine"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation14CollapseEngine", "$bottomChromeExtent"},
    {PFBCompat_restore_tab_labels, "_TtC11XNavigation14CollapseEngine", "$hiddenBarTravel"},
    {PFBCompat_hide_bottom_fade, "_TtC13XDesignSystem19ScrollEdgeTreatment", "$fadeMask"},
    {PFBCompat_hide_bottom_fade, "_TtC13XDesignSystem18ScrollEdgeFadeMask", "$gradientLayer"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "$messageLabel"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "$hintLabel"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "$resetButton"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "$barView"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "$picker"},
    {PFBCompat_custom_tab_bar, "_TtC11XNavigation26TabBarEditorViewController", "$tabBarFlight"},
    {PFBCompat_custom_tab_bar, "T1TabCustomizationConfig", "$migrationHelper"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift33SubscriptionsInfraMigrationHelper", "$$__lazy_storage_$_legacyConfig"},
    {PFBCompat_custom_tab_bar, "_TtC20TwitterSubscriptions31LegacySubscriptionFeatureConfig", "$isFeatureEnabled"},
    {PFBCompat_custom_tab_bar, "_TtC20TwitterSubscriptions31LegacySubscriptionFeatureConfig", "$claims"},
    {PFBCompat_custom_tab_bar, "T1TabCustomizationViewController", "$viewModel"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift25TabCustomizationViewModel", "$navigationSettings"},
    {PFBCompat_custom_tab_bar, "_TtC14T1TwitterSwift25MainAppNavigationSettings", "$$__lazy_storage_$_tabCustomizationConfig"},
    {PFBCompat_advanced_search, "_TtC15TwitterSearchV29SearchBar", "$showsFilterButton"},
    {PFBCompat_advanced_search, "_TtC15TwitterSearchV29SearchBar", "$filterButton"},
    {PFBCompat_restore_video_timestamp, "_TtC14T1TwitterSwift17VideoControlsView", "$progressLabelMode"},
    {PFBCompat_tap_to_pause, "T1InlineVideoView", "$isAutoUnmuteEnabled"},
    {PFBCompat_tap_to_pause, "T1InlineVideoView", "$playerViewIfLoaded"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift22ImmersiveVideoPageView", "$player"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift21ImmersiveCardHostView", "$audioSessionManager"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift28ImmersiveAudioSessionManager", "$isMuted"},
    {PFBCompat_tap_to_pause, "_TtC14T1TwitterSwift17ImmersiveCardView", "$singleTapRecognizer"},
    {PFBCompat_hide_promoted, "URTTimelineStatusItemViewModel", "$status"},
    {PFBCompat_hide_notifications, "URTTimelineStatusItemViewModel", "$status"},
    {PFBCompat_hide_promoted, "_TtC10TwitterURT32URTTimelineEventSummaryViewModel", "$promotedContent"},
    {PFBCompat_hide_promoted, "T1ImmersiveViewController", "$timelineCoordinator"},
    {PFBCompat_hide_promoted, "T1ImmersiveViewController", "$cardNavigator"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift28ImmersiveTimelineCoordinator", "$items"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift22ImmersiveCardNavigator", "$loadedPageRange"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift22ImmersiveCardNavigator", "$itemCount"},
    {PFBCompat_hide_promoted, "_TtC14T1TwitterSwift22ImmersiveCardViewModel", "$statusItemViewModel"},
    {PFBCompat_disable_immersive_scroll, "T1ImmersiveViewController", "$$__lazy_storage_$_panRecognizer"},
    {PFBCompat_reply_sorting, "T1ConversationContainerViewController", "$$__lazy_storage_$_timelineTransformer"},
    {PFBCompat_reply_sorting, "_TtC14T1TwitterSwift31ConversationTimelineTransformer", "$rankingMode"},
    {PFBCompat_show_quote_counts, "T1PostInteractionsViewController", "$account"},
    {PFBCompat_show_quote_counts, "T1PostInteractionsViewController", "$statusID"},
    {PFBCompat_voice_note_from_video, "T1MediaAttachmentsViewCell", "$_removeButton"},
    {PFBCompat_no_auto_unmute, "T1InlineVideoView", "$isAutoUnmuteEnabled"},
    // Options with no toggle that act inside FeatureSwitchOverrideValueForKey, reached only
    // through the feature switch accessors (FeatureSwitches.x).
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_premium_unlock, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_premium_unlock, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_upsells, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_hide_upsells, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_expand_tco_links, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_expand_tco_links, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_edit_tweet, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_edit_tweet, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_classic_tweet_detail, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_grok_translation, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_grok_translation, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-boolForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-integerForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-numberForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_launch_screen, "TFSFeatureSwitches", "-unsafePeekIntegerForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-boolForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-hasNonDefaultValueForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-integerForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-numberForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-rawValueForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-unsafePeekBoolForKey:"},
    {PFBCompat_launch_screen, "TFSInstrumentedFeatureSwitches", "-unsafePeekIntegerForKey:"},
};
static const size_t kReqCount = sizeof(kReqs) / sizeof(kReqs[0]);

typedef struct {
    PFBCompatOption option;
    const char* key;
    BOOL prefix;
} PFBCompatFlag;

// The Twitter feature switches each option answers or reads in FeatureSwitches.x. A switch
// Twitter no longer carries is one the option can no longer act through.
static const PFBCompatFlag kFlags[] = {
    {PFBCompat_settings_entry, "ios_settings_redesign_enabled", NO},
    {PFBCompat_new_twitter_settings, "ios_settings_redesign_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_sidebar_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_upsells_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_home_header_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_home_hero_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_preset_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_tab_icon_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_post_cta_enabled", NO},
    {PFBCompat_hide_grok_bot, "grok_ios_grok_bot_reply_cta_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_topics_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_generic_timelines_enabled", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_limit", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_management_pinnedsection_inline_limit", NO},
    {PFBCompat_hide_custom_timelines, "hometimeline_pinned_tabs_management_topics_inline_limit", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_topics_enabled", NO},
    {PFBCompat_unlimited_timeline_tabs, "hometimeline_pinned_tabs_generic_timelines_enabled", NO},
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
    {PFBCompat_hide_grok_create, "grok_composer_imagine_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_composer_attachment_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_timeline_preview_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_timeline_video_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_timeline_slideshow_imagine_menu_is_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_edit_photo_post_button_enabled", NO},
    {PFBCompat_hide_grok_create, "grok_ios_imagine_2_cta_enabled", NO},
    {PFBCompat_hide_grok_create, "ios_button_layout_fix", YES},
    {PFBCompat_hide_grok_analyze, "post_about_hide_grok_pills_enabled", NO},
    {PFBCompat_hide_grok_analyze, "post_about_grok_features_enabled", NO},
    {PFBCompat_hide_suggested_chats, "xchat_cold_inbox_suggestions_enabled", NO},
    {PFBCompat_hide_suggested_chats, "xchat_cold_inbox_find_friends_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ios_author_view_analyze_button_via_backend_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ios_profile_summary_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ask_grok_button_under_post_focal_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_ask_grok_button_under_post_preview_enabled", NO},
    {PFBCompat_hide_grok_analyze, "xchat_ask_grok_enabled", NO},
    {PFBCompat_hide_grok_analyze, "grok_explain_text_selection_ask_grok_enabled", NO},
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
    {PFBCompat_custom_tab_bar, "c9s_tab_visibility", NO},
    {PFBCompat_custom_tab_bar, "subscriptions_premium_hub_enabled", NO},
    {PFBCompat_custom_tab_bar, "recruiting_global_jobs_hub_enabled", NO},
    {PFBCompat_choose_explore_tabs, "ai_trends_ios_enable_news_tab", NO},
    {PFBCompat_hide_upsells, "ios_profile_analytics_upsell_enabled", NO},
    {PFBCompat_hide_upsells, "ios_profile_analytics_upsell_possible_enabled", NO},
    {PFBCompat_hide_upsells, "ios_profile_upgrade_upsell_enabled", NO},
    {PFBCompat_hide_upsells, "ios_profile_upgrade_upsell_swapper_enabled", NO},
    {PFBCompat_hide_upsells, "ios_profile_visitor_upsell_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_upsells_get_verified_profile", NO},
    {PFBCompat_hide_upsells, "subscriptions_upsells_reply_boost_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_upsells_reply_boost_popup_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_upsells_post_analytics_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_upsells_creator_support_post_conversation_enabled", NO},
    {PFBCompat_hide_upsells, "longform_notetweets_composer_upsell_enabled", NO},
    {PFBCompat_hide_upsells, "longform_notetweets_composer_auto_upsell_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_cta_on_replies_enabled", NO},
    {PFBCompat_hide_upsells, "super_follow_upsell_sticky_button_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_new_paywall_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_offers_promotional_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_gifting_premium_enabled", NO},
    {PFBCompat_hide_upsells, "subscriptions_gifting_premium_intro_copy_enabled", NO},
    {PFBCompat_hide_upsells, "ios_notifications_blue_verified_introductory_offer_visible", NO},
    {PFBCompat_hide_upsells, "ios_notifications_blue_verified_introductory_offer_prefix_visible", NO},
    {PFBCompat_hide_upsells, "dash_items_download_grok_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_timeline_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_in_tweet_composer_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_in_overflow_menu_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_in_focal_top_toolbar_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_in_focal_bottom_toolbar_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_in_focal_top_analytics_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_in_post_analytics_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_boost_again_in_top_toolbar_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_sent_tweet_toast_enabled", NO},
    {PFBCompat_hide_upsells, "ios_tweet_promote_button_third_party_boost_enabled", NO},
    {PFBCompat_hide_upsells, "thirdparty_boost_author_view_button_enabled", NO},
    {PFBCompat_premium_unlock, "subscriptions_gating_bypass", NO},
    {PFBCompat_premium_unlock, "creator_studio_nav_enabled", NO},
    {PFBCompat_premium_unlock, "creator_monetization_dashboard_enabled", NO},
    {PFBCompat_edit_tweet, "edit_tweet_ga_composition_enabled", NO},
    {PFBCompat_edit_tweet, "edit_tweet_pdp_dialog_enabled", NO},
    {PFBCompat_grok_translation, "grok_translations_bio_inline_translation_is_enabled", NO},
    {PFBCompat_grok_translation, "grok_translations_bio_translation_is_enabled", NO},
    {PFBCompat_grok_translation, "grok_translations_post_inline_translation_is_enabled", NO},
    {PFBCompat_grok_translation, "grok_translations_post_translation_is_enabled", NO},
    {PFBCompat_grok_translation, "grok_translations_community_note_translation_is_enabled", NO},
    {PFBCompat_grok_translation, "grok_translations_poll_translation_is_enabled", NO},
    {PFBCompat_launch_screen, "app_launch_animated_launch_screen_enabled", NO},
    {PFBCompat_classic_tweet_detail, "ios_tweet_detail_overflow_in_navigation_enabled", NO},
    {PFBCompat_expand_tco_links, "ad_formats_click_id_enabled", NO},
    {PFBCompat_expand_tco_links, "ad_formats_dcm_enabled", NO},
    {PFBCompat_expand_tco_links, "wcl_unified_cards_likely_open_link_prefetch_enabled", NO},
    {PFBCompat_custom_tab_bar, "recruiting_jetfuel_jobs_hub_enabled", NO},
    {PFBCompat_premium_unlock, "app_customization_custom_primary_color_enabled", NO},
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
    {PFBCompat_hide_topics, "Features/Timelines/Timeline.x", "TwitterTweetAnatomy_TwitterTweetAnatomyStrings.bundle"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "inReplyToUserID"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "isFromUserVerified"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "isReplyAndShouldShowSocialContext"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "representedFromUserFollowedByCurrentAccountState"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "representedFromUserID"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "displayAsBookmarked"},
    {PFBCompat_hide_custom_timelines, "Features/Timelines/Timeline.x", "addTabButton"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "inlineMediaInfos"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "imageURL"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "itemAtIndexPath:"},
    {PFBCompat_enable_image_preloading, "Features/Media/MediaPreload.x", "imageURL|imageURLString"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "isRetweet"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "representedFromUser"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "relationship"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "blockingCurrentAccountState"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "fromUserID"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "sharedHostViewController"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "currentAccount"},
    {PFBCompat_hide_blocked_retweets, "Features/Timelines/Timeline.x", "userID"},
    {PFBCompat_hide_quote_tweets, "Features/Timelines/Timeline.x", "isQuoteStatus"},
    {PFBCompat_hide_quote_tweets, "Features/Timelines/Timeline.x", "isReplyAndShouldShowSocialContext"},
    {PFBCompat_hide_quote_tweets, "Features/Timelines/Timeline.x", "fromUserID"},
    {PFBCompat_hide_quote_tweets, "Features/Timelines/Timeline.x", "sharedHostViewController"},
    {PFBCompat_hide_quote_tweets, "Features/Timelines/Timeline.x", "currentAccount"},
    {PFBCompat_hide_quote_tweets, "Features/Timelines/Timeline.x", "userID"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "T1Strings_T1Strings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "TwitterSharedStrings_TwitterSharedStrings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "ChatCore_ChatStrings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "LiveActivities_LiveActivityStrings.bundle"},
    {PFBCompatOptionCount, "Common/PFBBundle.m", "XSettings_XSettingsStrings.bundle"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconCell.m", "dividerColor"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconCell.m", "sharedColorManager"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconCell.m", "tfnuiColors"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconViewController.m", "textDetailsColor"},
    {PFBCompatOptionCount, "Features/Branding/AppIcon/PFBAppIconViewController.m", "tfnuiColors"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarCell.m", "imageName"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "imageName"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "title"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "_TtC11XNavigation26TabBarEditorViewController"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "messageLabel"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "hintLabel"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "resetButton"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "barView"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "picker"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBTabEditorPage.x", "tabBarFlight"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "T1HostViewController"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "appNavigation"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "_TtC14T1TwitterSwift20XTabbedAppNavigation"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "T1TabCustomizationViewController"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "TFSTwitterScribeContext"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "initWithAccount:scribeContext:"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBCustomTabBarUtility.m", "scribeContextWithPage:"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "migrationHelper"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "$__lazy_storage_$_legacyConfig"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "isFeatureEnabled"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "claims"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "viewModel"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "navigationSettings"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "$__lazy_storage_$_tabCustomizationConfig"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "_TtC14T1TwitterSwift33SubscriptionsInfraMigrationHelper"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "_TtC20TwitterSubscriptions31LegacySubscriptionFeatureConfig"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "T1TabCustomizationViewController"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "isTabCustomizationEnabled"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "appNavigation"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "account"},
    {PFBCompat_custom_tab_bar, "Features/Appearance/CustomTabBar/PFBNativeTabCustomization.x", "accountID"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBNativeTabSelectionStore.m", "TFSAccountUserDefaults"},
    {PFBCompatOptionCount, "Features/Appearance/CustomTabBar/PFBNativeTabSelectionStore.m", "sharedAccountUserDefaultsForAccountID:"},
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
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1InlineVideoFacadeView"},
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
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC15TwitterSearchV29SearchBar"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "handleFocusTap"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1StandardStatusView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "viewModel"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "fromUser"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "bio"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "userID"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1TabbedAppNavigationViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC14T1TwitterSwift34XTabbedAppNavigationViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "appNavigation"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "visiblePanelIDs"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "currentPanelID"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "setCurrentPanel:animated:completion:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "showProfileForUsername:orUserID:fromPanel:source:sourceNavigationMetadata:completion:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "dashContentController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "presenter"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "showSettings"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1ProfileHeaderViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "profileMoreActionsBaseActionItemsWithSender:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1GenericSettingsViewController"},
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
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "inReplyToStatusID"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "displayReplyCount|replyCount"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TFNTwitterAccount"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1PostInteractionsViewController"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "viewControllerWithAccount:statusID:statusUserID:initialTab:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1EditHistoryViewControllerFactory"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "viewControllerWithAccount:tweetID:scribeContext:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TFSTwitterScribeContext"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "scribeContextWithPage:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "TNUTalonUtilities"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "sendTalonRequestForAnalytics:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "verifyTalonURL:completion:"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "T1TwitterClickIDHandler"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "URLByAppendingTwitterClickIDIfNecessary:status:account:scribePage:scribeComponent:"},
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
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "deleteItemAtIndexPath:withRowAnimation:"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "dismissButton"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "fontOfSize:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "heavyFontOfSize:"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "itemAtIndexPath:"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "items"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "loadTop:"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "pullToLoadTopControl"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "scribeItem"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "sections"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "sharedSettings"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "string"},
    {PFBCompatOptionCount, "Features/General/HiddenNotifications.x", "textDetailsColor"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "aggregatedDisplayReplyCount"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "conversationID"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "inReplyToStatusID"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "replyCount"},
    {PFBCompatOptionCount, "Features/Tweets/HiddenThreads.x", "statusID"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "colorPalette"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "sharedSettings"},
    {PFBCompatOptionCount, "Features/Media/MediaDownloads.x", "inlineMediaInfos"},
    {PFBCompatOptionCount, "Features/Media/MediaDownloads.x", "status"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "setHidesSharedBackground:"},
    {PFBCompatOptionCount, "Features/Appearance/NavBarIcons.x", "setTintColor:"},
    {PFBCompatOptionCount, "Features/Profiles/Profile.x", "viewModel"},
    {PFBCompatOptionCount, "Features/Timelines/QuickMutedWords.x", "window"},
    {PFBCompatOptionCount, "Settings/Settings.x", "icon"},
    {PFBCompatOptionCount, "Settings/Settings.x", "sections"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "_t1_applyPrimaryColorOption"},
    {PFBCompatOptionCount, "Features/Appearance/Theme.x", "_t1_updateImageViewAnimated:"},
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
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "accountService"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "addAccount:"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "initWithUsername:userID:"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "saveSharedTwitter"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "sharedHostViewController"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "sharedTwitter"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "updateUserInfoAndCredentialsWithToken:secret:username:"},
    {PFBCompatOptionCount, "Sideload/PFBLoginBridge.x", "viewAccount:animated:"},
    {PFBCompatOptionCount, "Sideload/PFBWebLoginViewController.m", "webView"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "doubleValue"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "tableView"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedAddCell.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedTermCell.m", "textColor"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedWordsViewController.m", "title"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedAddCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Timelines/PFBMutedTermCell.m", "titleLabel"},
    {PFBCompatOptionCount, "Features/Search/PFBAdvancedSearchViewController.m", "openURL:options:"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsSessionCardCell.m", "primaryColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "subtext2BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsTabBarCell.m", "subtext3BoldFont"},
    {PFBCompatOptionCount, "Settings/PFBSettingsCellStyle.h", "alertColor"},
    {PFBCompatOptionCount, "Settings/PFBSettingsCellStyle.h", "dividerColor"},
    {PFBCompatOptionCount, "Settings/PFBSettingsCellStyle.h", "faintBackgroundColor"},
    {PFBCompatOptionCount, "Settings/PFBSettingsCellStyle.h", "tabBarItemColor"},
    {PFBCompatOptionCount, "Settings/PFBSettingsCellStyle.h", "textColor"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "TAEColorSettingsDidChangeUserDefaultsNotification"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "TFNDynamicColorsDidReloadNotification"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "TFNDynamicColorsWillReloadNotification"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "checked"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "imageURLString"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "mediaURL"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "profileImageMediaEntity"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "setChecked:"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "user"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "T1ColorSettingsPrimaryColorOptionKey"},
    {PFBCompatOptionCount, "Settings/PFBModernSettingsPageViewController.m", "setPrimaryColorOption:"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_layoutBadgeViewMaximized"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_layoutBadgeViewMinimized"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_layoutForTabBar"},
    {PFBCompatOptionCount, "Settings/Pages/PFBAppearanceSettingsViewController.m", "_t1_updateImageViewAnimated:"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "T1ColorSettingsPrimaryColorOptionKey"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "colorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "currentColorPalette"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "setPrimaryColorOption:"},
    {PFBCompatOptionCount, "Features/Appearance/ThemeColor/PFBColorThemeViewController.m", "sharedSettings"},
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
    {PFBCompat_bar_repairs, "Features/Appearance/NavBarIcons.x", "NavigationBarSettingsButton"},
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
    {PFBCompat_disable_immersive_scroll, "Features/Media/ImmersivePlayer.x", "$__lazy_storage_$_panRecognizer"},
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
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "imageName"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "imageView"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "title"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "setPrimaryColorOption:"},
    {PFBCompat_accent_color, "Features/Appearance/Theme.x", "sharedSettings"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "currentAccount"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "provider"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "sharedHostViewController"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "updateVisiblePanelIDs"},
    {PFBCompat_hide_grok_sidebar, "Support/FeatureSwitches.x", "dashContentController"},
    {PFBCompat_hide_message_button, "Features/Tweets/HideUI.x", "messageButton"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "cardNavigator"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "isPromoted"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "itemCount"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "items"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "loadedPageRange"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "status"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "statusItemViewModel"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "timelineCoordinator"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "ImmersiveViewerExploreMixerTimeline"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "ImmersiveProfileViewer"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "entry_id"},
    {PFBCompat_hide_videos_for_you, "Features/Timelines/Ads.x", "entry_id"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "cellForItemAtIndexPath:"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "frame"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "isHidden"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "layoutAttributesForItemAtIndexPath:"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "setHidden:"},
    {PFBCompat_hide_scroll_edge_blur, "Features/Timelines/Timeline.x", "window"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "aggregatedDisplayReplyCount"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "replyCount"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "title"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "viewModel"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "doubleValue"},
    {PFBCompat_hide_threads, "Features/Timelines/Timeline.x", "sections"},
    {PFBCompat_hide_threads, "Features/Timelines/Timeline.x", "setSections:restoreScrollPosition:"},
    {PFBCompat_web_session, "Sideload/WebCreateTweet.x", "currentAccount"},
    {PFBCompat_web_session, "Sideload/WebCreateTweet.x", "sharedHostViewController"},
    {PFBCompat_web_session, "Sideload/WebCreateTweet.x", "userID"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "adDisplayLocation"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "isPromoted"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "promotedContent"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "scribeItem"},
    {PFBCompatOptionCount, "Features/Timelines/Ads.x", "status"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "tableView"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "item"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "entryID"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "indexPathsForVisibleItems"},
    {PFBCompat_filter_languages, "Features/Timelines/Timeline.x", "language"},
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
    {PFBCompat_restore_tweet_button, "Features/Branding/Branding.x", "tintColor"},
    {PFBCompat_restore_tweet_button, "Features/Branding/Branding.x", "_TtC11XNavigation25TabBarAccessoryButtonView"},
    {PFBCompat_hide_tweet_button, "Features/Branding/Branding.x", "_TtC11XNavigation25TabBarAccessoryButtonView"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/GlassTabBar.x", "xdsDeprecated_customFontOfSize:weight:scalesWithDynamicType:"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/GlassTabBar.x", "XNAVNavigationController"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/GlassTabBar.x", "appliedConfiguration"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/GlassTabBar.x", "chromeFrozenScreen"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/GlassTabBar.x", "$__lazy_storage_$_collapseEngine"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/GlassTabBar.x", "_TtC11XNavigation14CollapseEngine"},
    {PFBCompat_no_tab_bar_hiding, "Features/Appearance/GlassTabBar.x", "collapseProgress"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/GlassTabBar.x", "bottomChromeExtent"},
    {PFBCompat_hide_bottom_fade, "Features/Appearance/GlassTabBar.x", "XDSBlur"},
    {PFBCompat_hide_bottom_fade, "Features/Appearance/GlassTabBar.x", "_TtC13XDesignSystem19ScrollEdgeTreatment"},
    {PFBCompat_hide_bottom_fade, "Features/Appearance/GlassTabBar.x", "_TtC13XDesignSystem18ScrollEdgeFadeView"},
    {PFBCompat_hide_bottom_fade, "Features/Appearance/GlassTabBar.x", "_TtC13XDesignSystem18ScrollEdgeFadeMask"},
    {PFBCompat_hide_bottom_fade, "Features/Appearance/GlassTabBar.x", "fadeMask"},
    {PFBCompat_hide_bottom_fade, "Features/Appearance/GlassTabBar.x", "gradientLayer"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/GlassTabBar.x", "hiddenBarTravel"},
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
    {PFBCompat_reply_sorting, "Features/Tweets/ReplySorting.x", "$__lazy_storage_$_timelineTransformer"},
    {PFBCompat_reply_sorting, "Features/Tweets/ReplySorting.x", "T1ConversationContainerViewController"},
    {PFBCompat_reply_sorting, "Features/Tweets/ReplySorting.x", "_TtC14T1TwitterSwift31ConversationTimelineTransformer"},
    {PFBCompat_reply_sorting, "Features/Tweets/ReplySorting.x", "rankingMode"},
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
    {PFBCompat_show_tweet_source, "Features/Tweets/AccountLocation.x", "footerItem"},
    {PFBCompat_show_tweet_source, "Features/Tweets/AccountLocation.x", "setTimeAgo:"},
    {PFBCompat_show_tweet_source, "Features/Tweets/AccountLocation.x", "statusID"},
    {PFBCompat_show_tweet_source, "Features/Tweets/AccountLocation.x", "timeAgo"},
    {PFBCompat_show_tweet_source, "Features/Tweets/AccountLocation.x", "viewModel"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "footerItem"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "fromUserName"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "setTimeAgo:"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "timeAgo"},
    {PFBCompat_show_account_location, "Features/Tweets/AccountLocation.x", "viewModel"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "imageName"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "imageView"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "setHighlightBarColor:"},
    {PFBCompat_tab_bar_theming, "Features/Appearance/Theme.x", "title"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/Theme.x", "xdsDeprecated_customFontOfSize:weight:scalesWithDynamicType:"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/Theme.x", "twitterColors"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/Theme.x", "primaryColor"},
    {PFBCompat_restore_tab_labels, "Features/Appearance/Theme.x", "textColor"},
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
    {PFBCompat_remove_followers, "Features/Profiles/Profile.x", "isFollowingViewer"},
    {PFBCompat_remove_followers, "Features/Profiles/Profile.x", "userDataSource"},
    {PFBCompat_remove_followers, "Features/Profiles/Profile.x", "userID"},
    {PFBCompat_remove_followers, "Features/Profiles/Profile.x", "username"},
    {PFBCompat_remove_followers, "Features/Profiles/Profile.x", "viewModel"},
    {PFBCompat_voice_note_from_video, "Features/Media/MediaDownloads.x", "_removeButton"},
    {PFBCompat_hide_view_count, "Features/Tweets/HideUI.x", "TTAStatusInlineAnalyticsButton"},
    {PFBCompat_hide_view_count, "Features/Tweets/HideUI.x", "footerItem"},
    {PFBCompat_hide_view_count, "Features/Tweets/HideUI.x", "setViewCount:"},
    {PFBCompat_hide_view_count, "Features/Tweets/HideUI.x", "viewCount"},
    {PFBCompat_hide_bookmark_button, "Features/Tweets/HideUI.x", "TTAStatusInlineBookmarkButton"},
    {PFBCompat_hide_downvote_button, "Features/Tweets/HideUI.x", "TTAStatusInlineDownvoteButton"},
    {PFBCompat_like_confirm, "Features/Tweets/Confirmations.x", "TTAStatusInlineFavoriteButton"},
    {PFBCompat_hide_explore_all, "Features/Tweets/HideUI.x", "_TtC14T1TwitterSwift23URTChromeViewController"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "_TtC14T1TwitterSwift36ImmersiveGoogleNativeAdCardViewModel"},
    {PFBCompat_restore_twitter_names, "Features/Branding/Branding.x", "TTAStatusBodyAttributedTextView"},
    {PFBCompat_voice_note_from_video, "Features/Media/MediaDownloads.x", "TTMAssetVoiceRecording"},
    {PFBCompatOptionCount, "Support/HookHelpers.m", "TFNDataViewItem"},
    {PFBCompat_reading_line, "Features/Timelines/Timeline.x", "latest"},
    {PFBCompat_hide_who_to_follow, "Features/Timelines/Timeline.x", "scribeComponent"},
    {PFBCompat_hide_topics_to_follow, "Features/Timelines/Timeline.x", "scribeComponent"},
    {PFBCompat_hide_who_to_follow, "Features/Timelines/Timeline.x", "entryID"},
    {PFBCompat_hide_who_to_follow, "Features/Timelines/Timeline.x", "clientEventInfo"},
    {PFBCompat_hide_who_to_follow, "Features/Timelines/Timeline.x", "component"},
    {PFBCompat_hide_verified_tweets, "Features/Timelines/Timeline.x", "entryID"},
    {PFBCompat_remove_related_tweets, "Features/Timelines/Timeline.x", "entryID"},
    {PFBCompat_hide_trend_videos, "Features/Timelines/Ads.x", "adDisplayLocation"},
    {PFBCompat_hide_promoted, "Features/Timelines/Ads.x", "scribeItem"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "conversationID"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "inReplyToStatusID"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "statusID"},
    {PFBCompat_hide_trend_videos, "Features/Timelines/Ads.x", "OTHER"},
    {PFBCompat_show_poll_results, "Features/Timelines/Timeline.x", "counts_are_final"},
    {PFBCompat_show_poll_results, "Features/Timelines/Timeline.x", "selected_choice"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "NOT_INTERESTED_IN_THIS_LABEL"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "author|user"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "username"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "text"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "chat_bubble_strikethrough_stroke"},
    {PFBCompat_hide_notifications, "Features/Tweets/HiddenThreads.x", "eye_off"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "tweetsAndRepliesEntry"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "highlightsEntry"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "articlesEntry"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "photoEntry"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "videoEntry"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "repostsEntry"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "_t1_outerTabIndexForEntry:"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "_t1_selectMainEntry:"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "contentMainEntries"},
    {PFBCompat_profile_initial_tab, "Features/Profiles/Profile.x", "currentDisplayContentProvider"},
    {PFBCompat_restore_tweet_button, "Features/Branding/Branding.x", "feather"},
    {PFBCompat_restore_tweet_button, "Features/Branding/Branding.x", "plus|compose|alt_compose|alt_compose_plus|compose_square"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "eye_off"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "close"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "status"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "URTTimelineStatusItemViewModel"},
    {PFBCompat_padlock, "Features/General/AppLifecycle.x", "lock_stroke"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "copy_stroke"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "account"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "at"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "link"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "calendar"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "news_stroke"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "location_stroke"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "globe_stroke"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "hash_stroke"},
    {PFBCompat_copy_profile_info, "Features/Profiles/Profile.x", "more_circle"},
    {PFBCompat_remove_followers, "Features/Profiles/Profile.x", "follow_close_stroke"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "settings_slider"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "filter_bars"},
    {PFBCompat_advanced_search, "Features/Search/AdvancedSearch.x", "CANCEL_ACTION_LABEL"},
    {PFBCompat_advanced_search, "Features/Search/PFBAdvancedSearchViewController.m", "openURL:options:"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "immersive_play"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "sound"},
    {PFBCompat_tap_to_pause, "Features/Media/ImmersivePlayer.x", "sound_off"},
    {PFBCompat_download_videos, "Features/Media/PFBDownloadInlineButton.m", "arrow_down_circle_stroke"},
    {PFBCompat_muted_words, "Features/Timelines/PFBMutedTermCell.m", "close_circle_fill"},
    {PFBCompat_advanced_search, "Features/Search/PFBAdvDateCell.m", "close_circle_fill"},
    {PFBCompat_voice_note_from_video, "Features/Media/MediaDownloads.x", "camera_video_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsTableViewCell.m", "chevron_right"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "settings_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "paintbrush_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "home_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "quill"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "media_tab_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "person_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "search_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "messages_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "tag_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsViewController.m", "hammer_stroke"},
    {PFBCompat_settings_entry, "Settings/PFBModernSettingsSessionCardCell.m", "person_stroke"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "fullText|tweetText|text|displayText|bodyText"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "fromUserName|screenName|authorScreenName|username|handle"},
    {PFBCompat_muted_words, "Features/Timelines/Timeline.x", "status|tweet"},
    {PFBCompat_hide_threads, "Features/Tweets/HiddenThreads.x", "status|tweet|canonicalStatus"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "entryId|entryID|identifier|notificationId|notificationID|id|sortIndex|key|itemIdentifier|scribeItemImpressionID|scribeItemImpressionId"},
    {PFBCompatOptionCount, "Features/Media/MediaDownloads.x", "DOWNLOAD_VIDEO_ACTIVITY_VIEW_LABEL"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "DM_INBOX_PILL_UNREAD_TITLE"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "CHAT_COLD_INBOX_CHAT_BUTTON_TITLE"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC20ChatConversationList24ConversationListItemCell"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "_TtC20ChatConversationList31ConversationListItemContentView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "accessoryButton"},
    {PFBCompat_download_videos, "Features/Media/MediaDownloads.x", "DOWNLOAD_ACTIVITY_VIEW_LABEL"},
};
enum { kNameCount = sizeof(kNames) / sizeof(kNames[0]) };

// Parts of Twitter class names the options look for with containsString:; each must
// still sit inside some class name. A "|" lists the other parts the code accepts.
static const PFBCompatName kClassSubstrings[] = {
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "NotificationsViewController"},
    {PFBCompat_hide_notifications, "Features/General/HiddenNotifications.x", "NotificationCell"},
    {PFBCompat_muted_words, "Features/Timelines/QuickMutedWords.x", "TimelineContainer|Timelines|Home"},
    {PFBCompat_choose_explore_tabs, "Features/Search/ExploreTabs.x", "SegmentedHighlightBarView"},
    {PFBCompat_restore_tweet_button, "Features/Branding/Branding.x", "FloatingActionButton"},
    {PFBCompat_bar_repairs, "Features/Appearance/NavBarIcons.x", "XChatDM"},
    {PFBCompat_bar_repairs, "Features/Appearance/NavBarIcons.x", "ActivityHistory|Notification"},
    {PFBCompat_bar_repairs, "Features/Appearance/NavBarIcons.x", "SelfSizingStackView"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/NavBarIcons.x", "SocialContext"},
    {PFBCompat_enable_liquid_glass, "Features/Appearance/Theme.x", "CustomTabBar"},
    {PFBCompat_color_twitter_icon_in_top_bar, "Features/Appearance/Theme.x", "HomeTimelineContainer"},
    {PFBCompat_restore_twitter_names, "Features/Appearance/Theme.x", "HomeTimelineContainer"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "ConversationListLoadingCell"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "ConversationListShimmerView"},
    {PFBCompatOptionCount, "Debug/PFBCompatibilityTour.m", "EmptyState"},
};
enum { kClassSubstringCount = sizeof(kClassSubstrings) / sizeof(kClassSubstrings[0]) };

typedef struct {
    const char* file;
    const char* className;
    const char* selector;
} PFBCompatDeclared;

// Twitter methods declared and called by PrimeFreeBird; each must stay on its class.
static const PFBCompatDeclared kDeclared[] = {
    {"Support/T1Headers.h", "T1BaseWebViewController", "webView"},
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
    {"Support/T1Headers.h", "T1TabBarViewController", "setTabBarHidden:withDuration:"},
    {"Support/T1Headers.h", "T1TabBarViewController", "tabViews"},
    {"Support/T1Headers.h", "T1TabView", "_t1_updateImageViewAnimated:"},
    {"Support/T1Headers.h", "T1TabView", "_t1_layoutForTabBar"},
    {"Support/T1Headers.h", "T1TabView", "_t1_layoutBadgeViewMaximized"},
    {"Support/T1Headers.h", "T1TabView", "badgeView"},
    {"Support/T1Headers.h", "T1TabView", "iconColor"},
    {"Support/T1Headers.h", "T1TabView", "imageName"},
    {"Support/T1Headers.h", "T1TabView", "imageView"},
    {"Support/T1Headers.h", "T1TabView", "isSelected"},
    {"Support/T1Headers.h", "T1TabView", "panelID"},
    {"Support/T1Headers.h", "T1TabView", "scribePage"},
    {"Support/T1Headers.h", "T1TabView", "title"},
    {"Support/T1Headers.h", "T1TabbedAppNavigationViewController", "recalculateVisiblePanels"},
    {"Support/T1Headers.h", "T1TabbedAppNavigationViewController", "_t1_bottomTabItemCapacity"},
    {"Support/T1Headers.h", "TAVPlaybackState", "currentTime"},
    {"Support/T1Headers.h", "TAVPlaybackState", "duration"},
    {"Support/T1Headers.h", "TAVPlaybackState", "timeControlStatus"},
    {"Support/T1Headers.h", "TAVPlayer", "isMuted"},
    {"Support/T1Headers.h", "TAVPlayer", "pause"},
    {"Support/T1Headers.h", "TAVPlayer", "playOrReplay"},
    {"Support/T1Headers.h", "TAVPlayer", "playbackState"},
    {"Support/T1Headers.h", "TAVPlayer", "seekToTime:"},
    {"Support/T1Headers.h", "TAVPlayer", "volume"},
    {"Support/T1Headers.h", "TFCCardData", "boolForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "numberForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "numberFromStringForKey:"},
    {"Support/T1Headers.h", "TFCCardData", "stringForKey:"},
    {"Support/T1Headers.h", "TTAStatusInlineActionsView", "viewModel"},
    {"Support/T1Headers.h", "TTMAssetVideoFile", "filePath"},
    {"Support/T1Headers.h", "TUIUpdateIndicator", "pillControl"},
    {"Support/T1Headers.h", "UIViewController", "tfn_tabBarIntegration"},
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
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "bodyBoldFont"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "subtext1BoldFont"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "subtext2BoldFont"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "subtext2Font"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "subtext3BoldFont"},
    {"Support/TFNHeaders.h", "TFNActionItem", "actionItemWithTitle:action:"},
    {"Support/TFNHeaders.h", "TFNActionItem", "actionItemWithTitle:imageName:action:"},
    {"Support/TFNHeaders.h", "TFNAttributedTextModel", "attributedString"},
    {"Support/TFNHeaders.h", "TFNAttributedTextModel", "initWithAttributedString:"},
    {"Support/TFNHeaders.h", "TFNDataViewController", "adDisplayLocation"},
    {"Support/TFNHeaders.h", "TFNHUD", "hide"},
    {"Support/TFNHeaders.h", "TFNHUD", "setText:"},
    {"Support/TFNHeaders.h", "TFNHUD", "show"},
    {"Support/TFNHeaders.h", "TFNItemsDataViewController", "sections"},
    {"Support/TFNHeaders.h", "TFNDataViewController", "pullToLoadTopControl"},
    {"Support/TFNHeaders.h", "TFNMenuSheetViewController", "initWithActionItems:"},
    {"Support/TFNHeaders.h", "TFNMenuSheetViewController", "tfnPresentedCustomPresentFromViewController:animated:completion:"},
    {"Support/TFNHeaders.h", "TFNPillControl", "text"},
    {"Support/TFNHeaders.h", "TFNTwitter", "accounts"},
    {"Support/TFNHeaders.h", "TFNTwitterAccount", "displayUsername"},
    {"Support/TFNHeaders.h", "TFNTwitterAccount", "isDummyTest1FeatureEnabled"},
    {"Support/TFNHeaders.h", "TFNTwitterAccount", "model"},
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
    {"Support/TFSHeaders.h", "TFSTwitterEntityMedia", "mediaType"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMedia", "videoInfo"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMediaVideoInfo", "variants"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMediaVideoVariant", "contentType"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityMediaVideoVariant", "url"},
    {"Support/TFSHeaders.h", "TFSTwitterEntitySet", "media"},
    {"Support/TFSHeaders.h", "TFSTwitterEntityURL", "expandedURL"},
    {"Support/TFSHeaders.h", "TFSTwitterMediaInfo", "mediaEntity"},
    {"Support/TFSHeaders.h", "TFSTwitterRelationship", "superFollowingState"},
    {"Support/TFSHeaders.h", "TFSReplySortingState", "sortByLikes"},
    {"Support/TFSHeaders.h", "TFSReplySortingState", "sortByRecency"},
    {"Support/TFSHeaders.h", "TFSReplySortingState", "sortByRelevance"},
    {"Features/Profiles/Avatars.x", "TFNAvatarImageView", "style"},
    {"Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.m", "TFNFloatingActionButton", "hideAnimated:completion:"},
    {"Features/Appearance/CustomTabBar/PFBCustomTabBarViewController.m", "TFNFloatingActionButton", "showAnimated:completion:"},
    {"Support/Helpers.h", "SFSafariViewController", "initialURL"},
    {"Support/T1Headers.h", "T1TabView", "setIconColor:"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "boldFontOfSize:"},
    {"Support/TAEHeaders.h", "TFNUIDefaultFontGroup", "sharedFontGroup"},
    {"Support/TFSHeaders.h", "NSNumber", "tfs_twitterAbbreviated"},
    {"Support/T1Headers.h", "T1PanelIdentity", "iconImageNameForPanelID:"},
    {"Support/T1Headers.h", "T1PanelIdentity", "localizedNameForPanelID:"},
    {"Support/T1Headers.h", "T1PanelIdentity", "stringForPanelID:"},
    {"Support/T1Headers.h", "T1WebViewController", "initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:"},
    {"Support/TFNHeaders.h", "TFNActiveTextItem", "initWithTextModel:activeRanges:"},
    {"Support/TFNHeaders.h", "TFNHUD", "initWithText:"},
    {"Support/TFNHeaders.h", "TFNSettingsNavigationItem", "initWithTitle:detail:iconName:controllerFactory:"},
    {"Features/Branding/AppIcon/PFBAppIconCell.m", "TFNDynamicColorManager", "isHighContrastForObject:withDefault:"},
    {"Features/Appearance/ThemeColor/PFBDarkModeStyle.x", "TFNSearchBar", "setSearchFieldBackgroundImage:forState:"},
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
    PFBCompat_restore_reply_context,
    PFBCompat_disable_video_captions,
    PFBCompat_voice_transcription,
    PFBCompat_new_inapp_webview,
    PFBCompat_disable_media_carousel,
    PFBCompat_hide_upsells,
    PFBCompat_edit_tweet,
    PFBCompat_grok_translation,
    PFBCompat_classic_tweet_detail,
    PFBCompat_hide_suggested_chats,
    PFBCompat_new_twitter_settings,
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
    {PFBCompat_hide_premium_offer, "URTTimelineMessageItemViewModel"},
    {PFBCompat_hide_promoted, "TwitterURT.URTTimelineGoogleNativeAdViewModel"},
    {PFBCompat_hide_promoted, "TwitterURT.URTTimelineTrendViewModel"},
    {PFBCompat_hide_promoted, "TwitterURT.URTTimelineEventSummaryViewModel"},
    {PFBCompat_remove_related_tweets, "T1ConversationContainerViewController"},
    {PFBCompat_hide_verified_tweets, "T1ConversationContainerViewController"},
    {PFBCompat_muted_words, "T1ConversationContainerViewController"},
    {PFBCompat_hide_verified_tweets, "TTSSearchContainerViewController"},
    {PFBCompat_hide_verified_tweets, "T1ProfileViewController"},
    {PFBCompat_hide_who_to_follow, "T1ProfileViewController"},
    {PFBCompat_filter_languages, "T1ProfileViewController"},
    {PFBCompat_filter_languages, "TTSSearchContainerViewController"},
    {PFBCompat_muted_words, "T1ProfileViewController"},
    {PFBCompat_muted_words, "TTSSearchContainerViewController"},
    {PFBCompat_hide_who_to_follow, "TwitterURT.URTModuleHeaderViewModel"},
    {PFBCompat_hide_who_to_follow, "TwitterURT.URTModuleFooterViewModel"},
    {PFBCompat_hide_topics_to_follow, "TwitterURT.URTModuleHeaderViewModel"},
    {PFBCompat_hide_topics_to_follow, "TwitterURT.URTModuleFooterViewModel"},
    {PFBCompat_keep_reading_position, "TwitterHomeFeatureImplementation.HomeTimelineContainerViewController"},
    {PFBCompat_hide_blocked_retweets, "TwitterHomeFeatureImplementation.HomeTimelineContainerViewController"},
    {PFBCompat_hide_quote_tweets, "TwitterHomeFeatureImplementation.HomeTimelineContainerViewController"},
    {PFBCompat_reading_line, "TwitterHomeFeatureImplementation.HomeTimelineContainerViewController"},
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
    const char* absent;    // what a tour may not meet, or why no step proves it; or NULL
} PFBCompatContract;

// Where each option must prove itself during the path tour. "launch" is judged once
// the tour ends, so the start's late proofs still count.
static const PFBCompatContract kContract[] = {
    {PFBCompat_padlock, "launch", NULL},
    {PFBCompat_no_screenshot_detection, "launch", NULL},
    {PFBCompat_force_following_tab, "tab home", NULL},
    {PFBCompat_no_focus_lost, "launch", NULL},
    {PFBCompat_no_tab_bar_hiding, "scroll", "tab bar hiding"},
    {PFBCompat_hide_bottom_fade, "tab home", NULL},
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
    {PFBCompat_hide_videos_for_you, "tab home", "Videos for you row"},
    {PFBCompat_hide_topics, "tab home", "topic Tweet"},
    {PFBCompat_hide_verified_tweets, "tab home|search", NULL},
    {PFBCompat_hide_blocked_retweets, "tab home|following timeline", "retweet"},
    {PFBCompat_hide_quote_tweets, "tab home|following timeline", "quote Tweet"},
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
    {PFBCompat_show_tweet_source, "first Tweet", NULL},
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
    {PFBCompat_hide_made_on_x, "tab home", "Made on X label"},
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
    {PFBCompat_hide_suggested_chats, "tab messages", NULL},
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
    {PFBCompat_web_session, "", "a web session proves itself when a Tweet, a Space, a mute list, a Grok request, a media upload or a web page goes through it"},
    {PFBCompat_remove_followers, "other profile", NULL},
    {PFBCompat_premium_unlock, "launch", NULL},
    {PFBCompat_hide_upsells, "launch", NULL},
    {PFBCompat_edit_tweet, "launch", NULL},
    {PFBCompat_grok_translation, "launch", NULL},
    {PFBCompat_launch_screen, "launch", NULL},
    {PFBCompat_expand_tco_links, "tab home", "Tweet carrying a link"},
    {PFBCompat_remove_related_tweets, "first Tweet", "related-Tweets module"},
    {PFBCompat_keep_reading_position, "tab home", NULL},
    {PFBCompat_classic_tweet_detail, "launch", NULL},
    {PFBCompat_web_login, "", "the web login only shows while signed out or when adding an account"},
    {PFBCompat_settings_entry, "Twitter settings", NULL},
    {PFBCompat_new_twitter_settings, "Twitter settings", NULL},
    {PFBCompat_bar_repairs, "tab guide", NULL},
    {PFBCompat_no_auto_unmute, "tab home", "inline video"},
    {PFBCompat_filter_languages, "tab home", NULL},
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
    {PFBCompatPath_verified_edit_history, "edit history"},
    {PFBCompatPath_promoted_video_feed, "video full screen"},
    {PFBCompatPath_replies_by_date, "replies"},
    {PFBCompatPath_reply_order_set, "first Tweet"},
    {PFBCompatPath_reply_order_request, "first Tweet"},
    {PFBCompatPath_native_filter_button, "search off"},
    {PFBCompatPath_tco_requests, "t.co check"},
    {PFBCompatPath_click_ids, "t.co check"},
    {PFBCompatPath_rtl_checks, "tab home"},
    {PFBCompatPath_settings_tab_bar, "Twitter settings"},
    {PFBCompatPath_feather, "tab home"},
    {PFBCompatPath_reply_bar, "first Tweet"},
    {PFBCompatPath_home_bar_button, "tab home"},
    {PFBCompatPath_eye_button, "tab ntab"},
    {PFBCompatPath_controls_hold, "video full screen"},
    {PFBCompatPath_interface_text, "tab home"},
    {PFBCompatPath_bottom_fade, "tab home"},
    {PFBCompatPath_tab_editor_page, "tab editor"},
};
static const size_t kPathStationCount = sizeof(kPathStations) / sizeof(kPathStations[0]);

// The feather and reply bar paths go through Twitter's classic views, so a station owes
// them only while Twitter's own Liquid Glass is not in use.
static BOOL pathStationOwed(const PFBCompatPathStation* entry) {
    return !PFBNativeGlassAsked() ||
           (entry->path != PFBCompatPath_feather && entry->path != PFBCompatPath_reply_bar);
}

// How the report names a tour step's screen.
static NSString* stationLabel(NSString* station) {
    static NSDictionary<NSString*, NSString*>* labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      labels = @{
          @"launch": @"the app's launch",
          @"tab guide": @"the Explore tab",
          @"tab ntab": @"the Notifications tab",
          @"tab messages": @"the Chat tab",
          @"tab home": @"the Home timeline",
          @"pull": @"a pull to refresh",
          @"first Tweet": @"an opened Tweet",
          @"Tweet interactions": @"a Tweet's interactions",
          @"edit history": @"a Tweet's edit history",
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
          @"search off": @"search with Advanced search off",
          @"conversation": @"a conversation",
          @"replies": @"a conversation sorted by Most recent replies",
          @"side menu": @"the side menu",
          @"dark mode": @"dark mode",
          @"web link": @"a web link",
          @"t.co check": @"the t.co link tracking block",
          @"Twitter settings": @"Twitter's settings",
          @"tab editor": @"Twitter's tab editor",
          @"PFB settings": @"the PrimeFreeBird settings",
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

// The start of this dylib's own UUID: a rebuild counts as a new install.
static NSString* dylibBuild(void) {
    Dl_info info;
    if (!dladdr((const void*)&dylibBuild, &info) || !info.dli_fbase) {
        return @"?";
    }
    return imageUUID((const struct mach_header_64*)info.dli_fbase);
}

NSString* PFBCompatBuildID(void) {
    return dylibBuild();
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

// This build's fingerprint of each option's code, by option key.
static NSDictionary<NSString*, NSString*>* currentFingerprints(void) {
    static NSDictionary<NSString*, NSString*>* prints;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSMutableDictionary<NSString*, NSString*>* table = [NSMutableDictionary dictionary];
      for (size_t i = 0; i < PFBOptionFingerprintCount; i++) {
          table[[NSString stringWithUTF8String:PFBOptionFingerprints[i].key]] =
              [NSString stringWithUTF8String:PFBOptionFingerprints[i].fingerprint];
      }
      prints = table;
    });
    return prints;
}

// Caller holds gLock or runs the one-time load. Adds the last build's evidence to what
// earlier builds of the same Twitter version proved, option by option: an option whose
// code changed keeps only the evidence of its new code.
static void foldIntoEarlier(void) {
    NSArray<NSString*>* kinds = @[ @"counts", @"details", @"observed", @"paths" ];
    // Fingerprints written by another build than the one folded leave every origin unknown.
    BOOL printsOfLast = [gStore[@"fingerprintsOf"] isEqual:gStore[@"identity"]];
    NSDictionary* lastPrints = printsOfLast ? storeDictionary(@"fingerprints") : @{};
    NSMutableDictionary* earlierPrints =
        printsOfLast ? [storeDictionary(@"earlierFingerprints") mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary* earlier = [storeDictionary(@"earlier") mutableCopy];
    NSMutableDictionary<NSString*, NSMutableDictionary*>* kept = [NSMutableDictionary dictionary];
    NSMutableSet<NSString*>* keys = [NSMutableSet set];
    for (NSString* kind in kinds) {
        kept[kind] = [earlier[kind] isKindOfClass:[NSDictionary class]] ? [earlier[kind] mutableCopy]
                                                                          : [NSMutableDictionary dictionary];
        [keys addObjectsFromArray:storeDictionary(kind).allKeys];
    }
    for (NSString* key in keys) {
        id last = lastPrints[key];
        if (![last isKindOfClass:[NSString class]]) {
            // No fingerprint for the folded build: its evidence joins, of unknown code.
            [earlierPrints removeObjectForKey:key];
        } else if (![last isEqual:earlierPrints[key]]) {
            for (NSString* kind in kinds) {
                [kept[kind] removeObjectForKey:key];
            }
            earlierPrints[key] = last;
        }
        for (NSString* kind in kinds) {
            id value = storeDictionary(kind)[key];
            if (!value) {
                continue;
            }
            if ([kind isEqualToString:@"counts"]) {
                kept[kind][key] = @([kept[kind][key] unsignedLongLongValue] + [value unsignedLongLongValue]);
            } else if ([kind isEqualToString:@"paths"] && [value isKindOfClass:[NSArray class]]) {
                NSMutableOrderedSet* names = [NSMutableOrderedSet orderedSetWithArray:
                    [kept[kind][key] isKindOfClass:[NSArray class]] ? kept[kind][key] : @[]];
                [names addObjectsFromArray:value];
                kept[kind][key] = names.array;
            } else if (!kept[kind][key]) {
                kept[kind][key] = value;
            }
        }
    }
    for (NSString* kind in kinds) {
        earlier[kind] = kept[kind];
    }
    gStore[@"earlier"] = earlier;
    gStore[@"earlierFingerprints"] = earlierPrints;
    if (![gStore[@"earlierSince"] isKindOfClass:[NSDate class]]) {
        gStore[@"earlierSince"] = [gStore[@"since"] isKindOfClass:[NSDate class]] ? gStore[@"since"] : [NSDate date];
    }
}

typedef NS_ENUM(NSInteger, PFBEarlierCode) {
    PFBEarlierCodeUnknown,
    PFBEarlierCodeSame,
    PFBEarlierCodeOlder,
};

// Caller holds gLock. Whether the code behind an option's earlier evidence is this build's.
static PFBEarlierCode earlierCode(NSString* key) {
    id then = storeDictionary(@"earlierFingerprints")[key];
    if (![then isKindOfClass:[NSString class]]) {
        return PFBEarlierCodeUnknown;
    }
    return [then isEqualToString:currentFingerprints()[key] ?: @""] ? PFBEarlierCodeSame : PFBEarlierCodeOlder;
}

// Loads what was counted before. A rebuild on the same Twitter keeps what earlier builds
// proved, which still counts for each option whose code is unchanged; a new Twitter version
// starts clean.
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
      NSString* identity = [NSString stringWithFormat:@"%@ \u00b7 %@", twitter, dylibBuild()];
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
              [gStore removeObjectForKey:@"earlierFingerprints"];
              gStore[@"checkDue"] = twitterBinary();
          }
          gStore[@"fingerprints"] = currentFingerprints();
          gStore[@"fingerprintsOf"] = identity;
          gStore[@"tour"] = @{};
          [gStore removeObjectForKey:@"measures"];
          gStore[@"identity"] = identity;
          gStore[@"since"] = [NSDate date];
          gStore[@"counts"] = @{};
          gStore[@"details"] = @{};
          gStore[@"observed"] = @{};
          gStore[@"paths"] = @{};
          [gStore removeObjectForKey:@"refusals"];
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

// The latest refusal is kept: it says why the option has not acted yet on this build.
void PFBCompatNoteRefusal(PFBCompatOption option, NSString* text) {
    if (option <= PFBCompatOptionNone || option >= PFBCompatOptionCount || text.length == 0) {
        return;
    }
    prepare();
    const char* key = gKeys[option];
    if (!key) {
        return;
    }
    NSString* name = [NSString stringWithUTF8String:key];
    @synchronized(gLock) {
        NSMutableDictionary* refusals = [storeDictionary(@"refusals") mutableCopy];
        if (![refusals[name] isEqual:text]) {
            refusals[name] = text;
            gStore[@"refusals"] = refusals;
            atomic_store_explicit(&gDirty, true, memory_order_relaxed);
        }
    }
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

// Caller holds gLock. Acted or noted, in stored evidence (this build's or the earlier one).
static BOOL evidenceProves(NSDictionary* store, NSString* key) {
    NSDictionary* counts = [store[@"counts"] isKindOfClass:[NSDictionary class]] ? store[@"counts"] : @{};
    NSDictionary* observed = [store[@"observed"] isKindOfClass:[NSDictionary class]] ? store[@"observed"] : @{};
    return [counts[key] unsignedLongLongValue] > 0 || [observed[key] isKindOfClass:[NSString class]];
}

// Acted or noted on this build, whether the proof is saved yet or still in memory, or on
// earlier builds of this Twitter with the option's code unchanged.
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
        return evidenceProves(gStore, name) ||
               (earlierCode(name) == PFBEarlierCodeSame && evidenceProves(storeDictionary(@"earlier"), name));
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
    NSString* name = [NSString stringWithUTF8String:meta->name];
    @synchronized(gLock) {
        id seen = storeDictionary(@"paths")[key];
        if ([seen isKindOfClass:[NSArray class]] && [seen containsObject:name]) {
            return YES;
        }
        id earlierPaths = storeDictionary(@"earlier")[@"paths"];
        id earlierSeen = [earlierPaths isKindOfClass:[NSDictionary class]] ? earlierPaths[key] : nil;
        return earlierCode(key) == PFBEarlierCodeSame && [earlierSeen isKindOfClass:[NSArray class]] &&
               [earlierSeen containsObject:name];
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
        if (meta && pathStationOwed(&kPathStations[i]) &&
            [station isEqualToString:[NSString stringWithUTF8String:kPathStations[i].station]] && !pathProven(meta)) {
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

void PFBCompatStationRecordEmpty(NSString* station, NSString* why) {
    prepare();
    @synchronized(gLock) {
        NSMutableDictionary* tour = mutableTour();
        NSMutableDictionary* stations = [tour[@"stations"] isKindOfClass:[NSDictionary class]]
                                            ? [tour[@"stations"] mutableCopy]
                                            : [NSMutableDictionary dictionary];
        stations[station] = @{@"reached": @NO, @"empty": why ?: @"", @"missed": @[]};
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

void PFBCompatMeasure(NSString* topic, NSString* line, NSUInteger cap) {
    if (!topic.length || !line.length) {
        return;
    }
    prepare();
    @synchronized(gLock) {
        NSDictionary* measures = storeDictionary(@"measures");
        NSArray* lines = [measures[topic] isKindOfClass:[NSArray class]] ? measures[topic] : @[];
        if (lines.count < cap && ![lines containsObject:line]) {
            NSMutableDictionary* updated = [measures mutableCopy];
            lines = [lines arrayByAddingObject:line];
            updated[topic] = lines;
            gStore[@"measures"] = updated;
            writeStore();
        }
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
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"HH:mm";
    id at = last[@"at"];
    return [at isKindOfClass:[NSDate class]] ? [formatter stringFromDate:at] : @"?";
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
            if (command->cmdsize < sizeof(struct segment_command_64) ||
                (command->cmdsize - sizeof(struct segment_command_64)) / sizeof(struct section_64) <
                    segment->nsects) {
                return NULL;
            }
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

// Twitter's own binaries: the app and its frameworks, this dylib left out.
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

// The kNames and kClassSubstrings entries gone from Twitter's binaries, nil when nothing
// could be read. A name matches a whole string, a substring part of a class name; an
// entry "a|b" is gone only when none of its parts is found.
static NSArray<NSString*>* scanMissingNames(NSArray<NSString*>* binaries) {
    NSMutableArray<NSString*>* exact = [NSMutableArray array];
    NSMutableArray<NSString*>* partial = [NSMutableArray array];
    NSMutableOrderedSet<NSString*>* entries = [NSMutableOrderedSet orderedSet];
    for (size_t i = 0; i < kNameCount + kClassSubstringCount; i++) {
        BOOL substring = i >= kNameCount;
        NSString* entry =
            [NSString stringWithUTF8String:substring ? kClassSubstrings[i - kNameCount].name : kNames[i].name];
        [entries addObject:entry];
        for (NSString* name in [entry componentsSeparatedByString:@"|"]) {
            NSMutableArray<NSString*>* pool = substring ? partial : exact;
            if (name.length && ![pool containsObject:name]) {
                [pool addObject:name];
            }
        }
    }
    size_t count = exact.count;
    size_t partialCount = partial.count;
    const char** names = calloc(count + 1, sizeof(char*));
    size_t* lengths = calloc(count + 1, sizeof(size_t));
    uint64_t* hashes = calloc(count + 1, sizeof(uint64_t));
    BOOL* found = calloc(count + partialCount + 1, sizeof(BOOL));
    const char** parts = calloc(partialCount + 1, sizeof(char*));
    size_t shortest = SIZE_MAX;
    size_t longest = 0;
    for (size_t i = 0; i < count; i++) {
        names[i] = exact[i].UTF8String;
        lengths[i] = strlen(names[i]);
        hashes[i] = nameHash(names[i], lengths[i]);
        shortest = MIN(shortest, lengths[i]);
        longest = MAX(longest, lengths[i]);
    }
    for (size_t i = 0; i < partialCount; i++) {
        parts[i] = partial[i].UTF8String;
    }
    // Class names sit in their own section, apart from selectors and C strings.
    static const char* const kSections[] = {"__objc_methname", "__cstring", "__objc_classname"};
    size_t matched = 0;
    size_t total = count + partialCount;
    BOOL readAny = NO;
    BOOL unreadable = NO;
    for (NSString* path in binaries) {
        if (unreadable || matched >= total) {
            break;
        }
        @autoreleasepool {
            NSData* data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            if (!data) {
                continue;
            }
            for (size_t s = 0; s < sizeof(kSections) / sizeof(kSections[0]) && matched < total; s++) {
                size_t size = 0;
                BOOL encrypted = NO;
                const char* strings = textSection(data, kSections[s], &size, &encrypted);
                if (encrypted) {
                    unreadable = YES;
                    break;
                }
                if (!strings) {
                    continue;
                }
                readAny = YES;
                BOOL classNames = s == 2;
                const char* end = strings + size;
                for (const char* p = strings; p < end && matched < total;) {
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
                    if (classNames && length > 0 && p[length] == '\0') {
                        for (size_t i = 0; i < partialCount; i++) {
                            if (!found[count + i] && strstr(p, parts[i])) {
                                found[count + i] = YES;
                                matched++;
                            }
                        }
                    }
                    p += length + 1;
                }
            }
        }
    }
    NSMutableSet<NSString*>* present = [NSMutableSet set];
    for (size_t i = 0; i < count; i++) {
        if (found[i]) {
            [present addObject:exact[i]];
        }
    }
    for (size_t i = 0; i < partialCount; i++) {
        if (found[count + i]) {
            [present addObject:partial[i]];
        }
    }
    free(names);
    free(lengths);
    free(hashes);
    free(found);
    free(parts);
    if (unreadable || !readAny || matched == 0) {
        return nil;
    }
    NSMutableArray<NSString*>* missing = [NSMutableArray array];
    for (NSString* entry in entries) {
        BOOL any = NO;
        for (NSString* name in [entry componentsSeparatedByString:@"|"]) {
            any = any || [present containsObject:name];
        }
        if (!any) {
            [missing addObject:entry];
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
} PFBLeadQuery;

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
      BOOL stop = leadStopWord(lower);
      if (lower.length > 4 && [lower hasSuffix:@"s"] && ![lower hasSuffix:@"ss"]) {
          lower = [lower substringToIndex:lower.length - 1];
      }
      if (!stop && !leadStopWord(lower) && ![words containsObject:lower]) {
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

// Scores one section's strings against the lost names of its pool. A lost name found
// intact is noted rather than scored.
static void leadScan(const char* strings, size_t size, PFBLeadPool pool, const PFBLeadQuery* queries, size_t count,
                     NSArray<NSMutableDictionary<NSString*, NSNumber*>*>* found, BOOL* present) {
    const char* end = strings + size;
    for (const char* s = strings; s < end;) {
        size_t length = strnlen(s, (size_t)(end - s));
        if (length >= 4 && length <= 90 && s + length < end && (pool != PFBLeadPoolKeys || leadIsKey(s, length))) {
            for (size_t i = 0; i < count; i++) {
                const PFBLeadQuery* query = &queries[i];
                if (query->pool != pool) {
                    continue;
                }
                if (length == query->lostLength && memcmp(s, query->lost, length) == 0) {
                    present[i] = YES;
                    continue;
                }
                NSUInteger score = 0;
                for (size_t w = 0; w < query->wordCount; w++) {
                    score += strcasestr(s, query->words[w]) != NULL;
                }
                if (score == 0 || (score < MIN((size_t)2, query->wordCount) && found[i].count >= 200)) {
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
static NSArray<NSString*>* leadRank(NSDictionary<NSString*, NSNumber*>* found, NSString* lost, const PFBLeadQuery* query,
                                    NSSet<NSString*>* settings) {
    NSUInteger best = 0;
    for (NSNumber* score in found.allValues) {
        best = MAX(best, score.unsignedIntegerValue);
    }
    if (best == 0 || (query->pool == PFBLeadPoolKeys && best < MIN((NSUInteger)2, (NSUInteger)query->wordCount))) {
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
    NSMutableIndexSet* members = [NSMutableIndexSet indexSet];
    for (NSString* path in lost) {
        NSRange space = [path rangeOfString:@" "];
        [owners addObject:path];
        if (space.location != NSNotFound) {
            [members addIndex:names.count];
        }
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
    PFBLeadQuery* queries = calloc(count, sizeof(PFBLeadQuery));
    BOOL* present = calloc(count, sizeof(BOOL));
    NSMutableArray<NSArray<NSString*>*>* wordLists = [NSMutableArray array];
    NSMutableArray<NSMutableDictionary<NSString*, NSNumber*>*>* found = [NSMutableArray array];
    BOOL wantsSettings = NO;
    for (size_t i = 0; i < count; i++) {
        // An ivar is searched by its own name, without the report's "ivar" label.
        NSString* searched = [names[i] hasPrefix:@"ivar "] ? [names[i] substringFromIndex:5] : names[i];
        NSArray<NSString*>* words = leadWords(searched);
        [wordLists addObject:words];
        [found addObject:[NSMutableDictionary dictionary]];
        // The member of a "Class member" path is a method or ivar name, whatever its underscores.
        queries[i].pool = [members containsIndex:i] ? PFBLeadPoolSelectors : leadPool(names[i]);
        queries[i].lost = strdup(names[i].UTF8String);
        queries[i].lostLength = strlen(queries[i].lost);
        queries[i].wordCount = words.count;
        for (size_t w = 0; w < words.count; w++) {
            queries[i].words[w] = strdup(words[w].UTF8String);
        }
        wantsSettings |= queries[i].pool == PFBLeadPoolKeys;
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
                    leadScan(strings, size, kSectionPools[s], queries, count, found, present);
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
        for (NSString* lead in leadRank(found[i], names[i], &queries[i], settings)) {
            if (list.count < 4 && ![list containsObject:lead]) {
                [list addObject:lead];
                if ([settings containsObject:lead]) {
                    [shipped addObject:lead];
                }
            }
        }
        free(queries[i].lost);
        for (size_t w = 0; w < queries[i].wordCount; w++) {
            free(queries[i].words[w]);
        }
    }
    free(queries);
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
            return PFBTintedLogoWanted();
        // Videos keep their sound off as long as tap to pause starts them muted.
        case PFBCompat_no_auto_unmute:
            return [PFBSettings boolForKey:@"tap_to_pause"] && [PFBSettings boolForKey:@"video_starts_muted"];
        case PFBCompat_dark_mode_style:
            return [PFBDarkModeStyle isDarkModeActive] && [PFBDarkModeStyle selectedStyle] != PFBDarkModeStyleSystem;
        case PFBCompat_accent_color:
            return [defaults objectForKey:@"pfb_color_theme_selectedColor"] != nil ||
                   [defaults objectForKey:@"pfb_custom_accent_hex"] != nil;
        case PFBCompat_muted_words: {
            id words = [defaults objectForKey:@"pfb_muted_words"];
            return [words respondsToSelector:@selector(count)] && [words count] > 0;
        }
        case PFBCompat_filter_languages: {
            id langs = [defaults objectForKey:@"pfb_filter_languages"];
            return [langs respondsToSelector:@selector(count)] && [langs count] > 0;
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
        case PFBCompat_show_tweet_source:
        case PFBCompat_show_account_location:
        case PFBCompat_remove_followers:
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
    if (selector[0] == '=') {
        // "=first>next:sizes": the bytes from one ivar to the next, one of the sizes listed.
        NSArray<NSString*>* parts = [[NSString stringWithUTF8String:selector + 1] componentsSeparatedByString:@":"];
        NSArray<NSString*>* names = [parts.firstObject componentsSeparatedByString:@">"];
        Ivar first = names.count == 2 ? class_getInstanceVariable(cls, names[0].UTF8String) : NULL;
        Ivar next = names.count == 2 ? class_getInstanceVariable(cls, names[1].UTF8String) : NULL;
        if (parts.count != 2 || !first || !next) {
            return NO;
        }
        NSString* size = [NSString stringWithFormat:@"%td", ivar_getOffset(next) - ivar_getOffset(first)];
        return [[parts[1] componentsSeparatedByString:@","] containsObject:size];
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

// A requirement as the report names it: "Class selector", "Class ivar name", or
// "Class ivar name of 40 or 48 bytes".
static NSString* reqName(const PFBCompatReq* req) {
    if (req->selector[0] == '=') {
        NSArray<NSString*>* parts = [[NSString stringWithUTF8String:req->selector + 1] componentsSeparatedByString:@":"];
        NSString* sizes = [parts.lastObject stringByReplacingOccurrencesOfString:@"," withString:@" or "];
        return [NSString stringWithFormat:@"%s ivar %@ of %@ bytes", req->className,
                                          [parts.firstObject componentsSeparatedByString:@">"].firstObject, sizes];
    }
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

// A class name, or "a|b" for names the code accepts in turn: resolved when any one is.
static BOOL classTextResolves(NSString* names) {
    for (NSString* name in [names componentsSeparatedByString:@"|"]) {
        if (name.length && NSClassFromString(name)) {
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
        if (!classTextResolves(name)) {
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
    for (size_t i = 0; i < kNameCount + kClassSubstringCount; i++) {
        const PFBCompatName* row = i < kNameCount ? &kNames[i] : &kClassSubstrings[i - kNameCount];
        if (row->option != option) {
            continue;
        }
        NSString* name = [NSString stringWithUTF8String:row->name];
        if ([gone containsObject:name] && ![counted containsObject:name]) {
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
    for (size_t i = 0; i < kNameCount + kClassSubstringCount; i++) {
        BOOL substring = i >= kNameCount;
        const PFBCompatName* row = substring ? &kClassSubstrings[i - kNameCount] : &kNames[i];
        if (row->option != PFBCompatOptionCount) {
            continue;
        }
        NSString* file = [[NSString stringWithUTF8String:row->file] lastPathComponent];
        names[file] = @(names[file].integerValue + 1);
        NSString* name = [NSString stringWithUTF8String:row->name];
        if (!nameGone[file] && [goneNames containsObject:name]) {
            nameGone[file] = [name stringByAppendingString:substring ? @" not found, matched by part of a class name"
                                                                     : @" not found, read by name"];
            nameLost[file] = name;
        }
    }
    // Classes a file resolves by name (%c, objc_getClass, NSClassFromString).
    for (size_t i = 0; i < PFBRuntimeClassCount; i++) {
        NSString* file = [[NSString stringWithUTF8String:PFBRuntimeClasses[i].file] lastPathComponent];
        names[file] = @(names[file].integerValue + 1);
        if (!nameGone[file] && !objc_getClass(PFBRuntimeClasses[i].className)) {
            nameLost[file] = [NSString stringWithUTF8String:PFBRuntimeClasses[i].className];
            nameGone[file] = [nameLost[file] stringByAppendingString:@" not found, resolved by name"];
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
        row.section = @"Internals";
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

// "paths 1/2, not seen yet: X" for an option acting through several paths. Paths seen on
// earlier builds count only when the option's code is unchanged.
static NSString* pathsNote(PFBCompatOption option, NSString* key, NSDictionary* stored,
                           NSDictionary* earlierStored, PFBEarlierCode code) {
    NSArray* saved = [stored[key] isKindOfClass:[NSArray class]] ? stored[key] : @[];
    NSArray* earlier = code == PFBEarlierCodeSame && [earlierStored[key] isKindOfClass:[NSArray class]]
                           ? earlierStored[key]
                           : @[];
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

// What earlier builds of this Twitter version proved for an option, or nil; "older code"
// when the option's code changed since, "code not compared" when that is unknown.
static NSString* earlierEvidence(NSDictionary* earlier, NSString* key, PFBEarlierCode code) {
    NSDictionary* counts = [earlier[@"counts"] isKindOfClass:[NSDictionary class]] ? earlier[@"counts"] : @{};
    NSDictionary* details = [earlier[@"details"] isKindOfClass:[NSDictionary class]] ? earlier[@"details"] : @{};
    NSDictionary* observed = [earlier[@"observed"] isKindOfClass:[NSDictionary class]] ? earlier[@"observed"] : @{};
    NSString* origin = code == PFBEarlierCodeSame    ? @"earlier build"
                       : code == PFBEarlierCodeOlder ? @"earlier build, older code"
                                                     : @"earlier build, code not compared";
    unsigned long long done = [counts[key] unsignedLongLongValue];
    if (done > 0) {
        id detail = details[key];
        return [NSString stringWithFormat:@"%@ \u00b7 %llu\u00d7 \u00b7 %@", origin, done,
                                          [detail isKindOfClass:[NSString class]] ? detail : @"-"];
    }
    id seen = observed[key];
    return [seen isKindOfClass:[NSString class]]
               ? [NSString stringWithFormat:@"%@ \u00b7 ready \u00b7 %@", origin, seen]
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
        if (!path || !pathStationOwed(&kPathStations[i]) || path->option != meta->option ||
            ![record isKindOfClass:[NSDictionary class]] || ![record[@"reached"] boolValue]) {
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
    NSString* emptyWhy = nil;
    for (NSString* station in planned) {
        NSDictionary* record = stations[station];
        if (![record isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if (![record[@"reached"] boolValue]) {
            failedAt = failedAt ?: station;
            BOOL first = [station isEqualToString:failedAt];
            closedTwitter = closedTwitter || (first && [record[@"crashed"] boolValue]);
            emptyWhy = emptyWhy ?: (first && [record[@"empty"] isKindOfClass:[NSString class]] ? record[@"empty"] : nil);
        } else if ([record[@"missed"] containsObject:key]) {
            missedAt = missedAt ?: station;
        }
    }
    if (missedAt && !absent) {
        *detail = [NSString stringWithFormat:@"Shown: %@. No proof", stationLabel(missedAt)];
        return PFBCompatVerdictNotTested;
    }
    if (planned.count == 0) {
        *detail = capitalizedFirst(absent);
    } else if (missedAt) {
        *detail = [NSString stringWithFormat:@"No %@ during the check", absent];
    } else if (failedAt && emptyWhy.length) {
        *detail = [NSString stringWithFormat:@"%@: %@ during the check", capitalizedFirst(stationLabel(failedAt)),
                                             emptyWhy];
    } else if (failedAt) {
        *detail = [NSString stringWithFormat:closedTwitter ? @"%@ closed Twitter during the check"
                                                           : @"%@: not reached during the check",
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
    NSDictionary* refusals;
    NSDictionary* earlier;
    NSMutableDictionary<NSString*, NSNumber*>* earlierCodes = [NSMutableDictionary dictionary];
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
        refusals = storeDictionary(@"refusals");
        earlier = storeDictionary(@"earlier");
        for (size_t i = 0; i < kMetaCount; i++) {
            NSString* key = [NSString stringWithUTF8String:kMeta[i].key];
            earlierCodes[key] = @(earlierCode(key));
        }
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
        PFBEarlierCode code = (PFBEarlierCode)earlierCodes[key].integerValue;
        NSString* earlierText = earlierEvidence(earlier, key, code);
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
        id refusal = refusals[key];
        if (done == 0 && [refusal isKindOfClass:[NSString class]]) {
            result.evidence = [result.evidence isEqualToString:@"not seen yet"]
                                  ? refusal
                                  : [NSString stringWithFormat:@"%@ \u00b7 %@", result.evidence, refusal];
        }
        NSDictionary* earlierPaths = [earlier[@"paths"] isKindOfClass:[NSDictionary class]] ? earlier[@"paths"] : @{};
        NSString* pathNote = pathsNote(meta->option, key, paths, earlierPaths, code);
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
            BOOL proven = done > 0 || [seen isKindOfClass:[NSString class]] ||
                          (code == PFBEarlierCodeSame && earlierText != nil);
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
        return @"Twitter switches not read";
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
        NSString* names = [NSString stringWithUTF8String:kClassTexts[i].className];
        if (!classTextResolves(names)) {
            [lost addObject:names];
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
    for (size_t i = 0; i < PFBRuntimeClassCount; i++) {
        if (!objc_getClass(PFBRuntimeClasses[i].className)) {
            [lost addObject:[NSString stringWithUTF8String:PFBRuntimeClasses[i].className]];
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
        [gStore removeObjectForKey:@"refusals"];
        gStore[@"earlier"] = @{};
        [gStore removeObjectForKey:@"earlierSince"];
        [gStore removeObjectForKey:@"earlierFingerprints"];
        gStore[@"tour"] = @{};
        [gStore removeObjectForKey:@"measures"];
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

NSDate* PFBCompatCountingSince(BOOL earlierBuilds) {
    prepare();
    id date;
    @synchronized(gLock) {
        date = gStore[earlierBuilds ? @"earlierSince" : @"since"];
    }
    return [date isKindOfClass:[NSDate class]] ? date : nil;
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

// The copied report: the install, the verdicts, the last tour's journal and the
// measurements, then the environment, hook health, decision journal and last capture.
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
    NSDictionary* measures;
    @synchronized(gLock) {
        measures = storeDictionary(@"measures");
    }
    if (measures.count) {
        [text appendString:@"\nMEASUREMENTS\n"];
        for (NSString* topic in [measures.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            id lines = measures[topic];
            for (id line in [lines isKindOfClass:[NSArray class]] ? lines : @[]) {
                [text appendFormat:@"[%@] %@\n", topic, line];
            }
        }
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

void PFBCompatSaveNow(void) {
    save();
}
