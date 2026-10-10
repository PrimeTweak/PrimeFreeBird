// The settings model: every option with its page, type and default; defaults for
// keys without a row; migrations of renamed keys.

#import "Common/PFBSettings.h"
#import "Support/PFBManager.h"

static NSDictionary<NSString*, NSDictionary*>* PFBSettingsPages(void) {
    static NSDictionary<NSString*, NSDictionary*>* pages;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pages = @{
            @"general": @{
                @"titleKey": @"MODERN_SETTINGS_LAYOUT_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_LAYOUT_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"GENERAL_GROUP_PRIVACY"},
                    @{@"key": @"padlock", @"default": @NO},
                    @{@"key": @"no_screenshot_detection", @"default": @YES},
                    @{@"type": @"header", @"titleKey": @"GENERAL_GROUP_BEHAVIOR"},
                    @{@"key": @"force_following_tab", @"default": @YES},
                    @{@"key": @"no_focus_lost", @"default": @NO},
                    @{@"key": @"no_tab_bar_hiding", @"default": @YES},
                    @{@"key": @"show_scroll_indicator", @"default": @NO},
                    @{@"key": @"disable_rtl", @"default": @NO},
                    @{@"key": @"hide_premium_offer", @"default": @YES},
                    @{@"key": @"hide_notifications", @"default": @YES, @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"GENERAL_GROUP_LINKS"},
                    @{
                        @"type": @"compactButton",
                        @"key": @"sharing_domain",
                        @"action": @"showSharingDomainPrompt:",
                        @"prefKeyForSubtitle": @"sharing_domain",
                        @"subtitleDefault": @"x.com"
                    },
                    @{@"key": @"strip_url_tracking", @"default": @YES},
                    @{@"key": @"always_open_safari", @"default": @NO},
                    @{@"key": @"new_inapp_webview", @"default": @YES}
                ]
            },
            @"appearance": @{
                @"titleKey": @"MODERN_SETTINGS_APPEARANCE_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_APPEARANCE_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header",
                      @"titleKey": @"APPEARANCE_GROUP_INTERFACE"},
                    @{
                        @"titleKey": @"INTERFACE_STYLE_TITLE",
                        @"subtitleKey": @"INTERFACE_STYLE_SUBTITLE",
                        @"action": @"showInterfaceStylePicker:",
                        @"type": @"button"
                    },
                    @{
                        @"titleKey": @"CUSTOM_TAB_BAR_OPTION_TITLE",
                        @"subtitleKey": @"CUSTOM_TAB_BAR_OPTION_SUBTITLE",
                        @"action": @"showCustomTabBarVC:",
                        @"type": @"button"
                    },
                    @{@"key": @"restore_tab_labels",
                      @"default": @NO},
                    @{@"key": @"custom_fonts",
                      @"default": @NO},
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"regular_font_button",
                        @"titleKey": @"REGULAR_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showRegularFontPicker:",
                        @"prefKeyForSubtitle": @"pfb_font_1",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE"
                    },
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"bold_font_button",
                        @"titleKey": @"BOLD_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showBoldFontPicker:",
                        @"prefKeyForSubtitle": @"pfb_font_2",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE"
                    },
                    @{
                        @"type": @"button",
                        @"parentKey": @"custom_fonts",
                        @"key": @"default_font_button",
                        @"titleKey": @"DEFAULT_FONT_OPTION_TITLE",
                        @"action": @"useDefaultFont:",
                        @"destructive": @YES
                    },
                    @{@"type": @"header",
                      @"titleKey": @"APPEARANCE_GROUP_COLORS"},
                    @{
                        @"titleKey": @"THEME_OPTION_TITLE",
                        @"subtitleKey": @"THEME_OPTION_SUBTITLE",
                        @"action": @"showThemeViewController:",
                        @"type": @"button"
                    },
                    @{
                        @"titleKey": @"DARK_MODE_STYLE_TITLE",
                        @"subtitleKey": @"DARK_MODE_STYLE_SUBTITLE",
                        @"action": @"showDarkModeStylePicker:",
                        @"type": @"button"
                    },
                    @{@"key": @"tab_bar_theming",
                      @"default": @YES},
                    @{@"key": @"color_pfb_switches",
                        @"default": @NO,
                        @"type": @"toggle"},
                    @{@"key": @"color_twitter_icon_in_top_bar",
                        @"default": @([PFBManager isTwitterBranded]),
                        @"type": @"toggle"}
                ]
            },
            @"timelines": @{
                @"titleKey": @"MODERN_SETTINGS_TIMELINES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TIMELINES_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"TIMELINES_GROUP_SUGGESTIONS"},
                    @{@"key": @"hide_promoted",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_who_to_follow",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_topics_to_follow",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_timeline_prompts",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"TIMELINES_GROUP_CONTENT"},
                    @{@"key": @"hide_topics",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_verified_tweets",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_blocked_retweets",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"reading_line",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"type": @"button",
                        @"titleKey": @"FILTERS_TITLE",
                        @"subtitleKey": @"FILTERS_DETAIL",
                        @"action": @"showMutedWords:"
                    },
                    @{@"type": @"header", @"titleKey": @"TIMELINES_GROUP_BARS"},
                    @{@"key": @"hide_spaces",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_new_tweets_pill",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_scroll_edge_blur",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_custom_timelines",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"unlimited_timeline_tabs",
                      @"disabledWhen": @"hide_custom_timelines",
                      @"default": @YES,
                      @"type": @"toggle"}
                ]
            },
            @"tweets": @{
                @"titleKey": @"MODERN_SETTINGS_TWEETS_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TWEETS_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"TWEETS_GROUP_COMPOSING"},
                    @{
                        @"type": @"compactButton",
                        @"key": @"undo_tweet_timeout",
                        @"default": @10,
                        @"titleKey": @"UNDO_TWEET_TITLE",
                        @"menu": @"undoTimeoutMenu"
                    },
                    @{@"key": @"tweet_confirm",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tweet_button",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"send_sound",
                        @"type": @"button",
                        @"titleKey": @"SEND_SOUND_TITLE"
                    },
                    @{
                        @"type": @"buttonPair",
                        @"key": @"send_sound_actions",
                        @"firstKey": @"SEND_SOUND_IMPORT_ACTION",
                        @"secondKey": @"SEND_SOUND_REMOVE_ACTION",
                        @"firstAction": @"importSendSound:",
                        @"secondAction": @"removeSendSound:",
                        @"secondDestructive": @YES
                    },
                    @{@"type": @"header", @"titleKey": @"TWEETS_GROUP_ACTIONS"},
                    @{@"key": @"hide_threads",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"like_confirm",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_view_count",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"hide_bookmark_button",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_downvote_button",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"TWEETS_GROUP_READING"},
                    @{
                        @"key": @"show_poll_results",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{@"key": @"disable_sensitive_tweet_warnings",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"bypass_age_verification",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"reply_sorting",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"restore_reply_context",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"show_quote_counts",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"show_account_location",
                      @"default": @NO,
                      @"blockedUnless": @"web_session",
                      @"type": @"toggle"}
                ]
            },
            @"media_downloads": @{
                @"titleKey": @"MODERN_SETTINGS_MEDIA_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_MEDIA_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"MEDIA_GROUP_DOWNLOADS"},
                    @{@"key": @"download_videos",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"download_highest_quality",
                      @"default": @NO,
                      @"parentKey": @"download_videos",
                      @"type": @"toggle"},
                    @{@"key": @"direct_save",
                      @"default": @NO,
                      @"parentKey": @"download_videos",
                      @"type": @"toggle"},
                    @{@"key": @"tweet_to_image",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"MEDIA_GROUP_PLAYBACK"},
                    @{
                        @"key": @"tap_to_pause",
                        @"default": @YES,
                        @"pillKey": @"video_starts_muted",
                        @"type": @"toggle"
                    },
                    @{@"key": @"restore_video_timestamp",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"disable_video_captions",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"disable_immersive_scroll",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"disable_video_docking",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"MEDIA_GROUP_QUALITY"},
                    @{@"key": @"auto_highest_load",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"enable_image_preloading",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"upload_full_hd_videos",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"MEDIA_GROUP_LAYOUT"},
                    @{@"key": @"force_tweet_full_frame",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"disable_media_carousel",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            },
            @"profiles": @{
                @"titleKey": @"MODERN_SETTINGS_PROFILES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_PROFILES_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"PROFILES_GROUP_BEHAVIOR"},
                    @{@"key": @"follow_confirm",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"expand_bio",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{
                        @"key": @"copy_profile_info",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"titleKey": @"PROFILE_INITIAL_TAB_TITLE",
                        @"menu": @"profileTabMenu",
                        @"type": @"compactButton"
                    },
                    @{@"type": @"header", @"titleKey": @"PROFILES_GROUP_TABS"},
                    @{
                        @"key": @"disable_articles",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_highlights",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_videos_tab",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{@"type": @"header", @"titleKey": @"PROFILES_GROUP_APPEARANCE"},
                    @{
                        @"key": @"hide_blue_verified",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_follow_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_message_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_follow_button",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{@"key": @"square_avatars",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            },
            @"search": @{
                @"titleKey": @"MODERN_SETTINGS_SEARCH_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_SEARCH_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"SEARCH_GROUP_SEARCHING"},
                    @{@"key": @"no_history",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"advanced_search",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"SEARCH_GROUP_TRENDS"},
                    @{@"key": @"hide_trend_videos",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_explore_all",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"choose_explore_tabs",
                      @"default": @YES,
                      @"disabledWhen": @"hide_explore_all",
                      @"type": @"toggle"},
                    @{@"type": @"tabBar",
                      @"key": @"explore_tabs",
                      @"parentKey": @"choose_explore_tabs",
                      @"hiddenWhen": @"hide_explore_all",
                      @"captionKey": @"EXPLORE_TABS_CAPTION",
                      @"hintKey": @"EXPLORE_TABS_HINT",
                      @"tabKeys": @[
                          @"hide_tab_foryou", @"hide_tab_trending",
                          @"hide_tab_news", @"hide_tab_sports",
                          @"hide_tab_entertainment"
                      ]}
                ]
            },
            @"grok": @{
                @"titleKey": @"MODERN_SETTINGS_MESSAGES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_MESSAGES_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"MESSAGES_GROUP_CHAT"},
                    @{
                        @"key": @"hide_typing_indicator",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"voice_transcription",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"download_voice_messages",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"voice_note_from_video",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{@"type": @"header", @"titleKey": @"MESSAGES_GROUP_GROK"},
                    @{
                        @"key": @"hide_grok_analyze",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_sidebar",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_bot",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_create",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_auto_translate",
                        @"default": @NO,
                        @"inverted": @YES,
                        @"type": @"toggle"
                    }
                ]
            },
            @"branding": @{
                @"titleKey": @"MODERN_SETTINGS_BRANDING_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_BRANDING_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"BRANDING_GROUP_CLASSIC"},
                    @{
                        @"titleKey": @"APP_ICON_TITLE",
                        @"subtitleKey": @"APP_ICON_SUBTITLE",
                        @"action": @"showAppIconViewController:",
                        @"type": @"button"
                    },
                    @{
                        @"key": @"restore_twitter_names",
                        @"default": @([PFBManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"refresh_pill_label",
                        @"default": @([PFBManager isTwitterBranded]),
                        @"disabledWhen": @"hide_new_tweets_pill",
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_tweet_button",
                        @"default": @([PFBManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_refresh_sounds",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"compatibility": @{
                @"titleKey": @"COMPATIBILITY_TITLE",
                @"subtitleKey": @"COMPATIBILITY_DETAIL",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"COMPATIBILITY_GROUP_CHECKS"},
                    @{@"key": @"debug_tools",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"titleKey": @"COMPATIBILITY_RECORD_TITLE"},
                    @{
                        @"key": @"compatibility_report",
                        @"type": @"button",
                        @"titleKey": @"COMPATIBILITY_REPORT_TITLE",
                        @"prefKeyForSubtitle": @"pfb_compat_status",
                        @"subtitleDefaultKey": @"COMPATIBILITY_REPORT_DETAIL",
                        @"action": @"showCompatibilityReport:"
                    }
                ]
            },
            @"lab": @{
                @"titleKey": @"MODERN_SETTINGS_LAB_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_LAB_SUBTITLE",
                @"settings": @[
                    @{@"type": @"header", @"titleKey": @"LAB_GROUP_SESSION"},
                    @{@"type": @"sessionCard", @"key": @"web_session_card"},
                    @{@"key": @"reply_in_webview",
                      @"default": @NO,
                      @"blockedUnless": @"web_session",
                      @"type": @"toggle"},

                    @{@"type": @"header", @"titleKey": @"LAB_GROUP_BACKUP"},
                    @{
                        @"key": @"settings_backup",
                        @"type": @"button",
                        @"titleKey": @"SETTINGS_BACKUP_TITLE",
                        @"subtitleKey": @"SETTINGS_BACKUP_DETAIL"
                    },
                    @{
                        @"type": @"buttonPair",
                        @"key": @"backup_actions",
                        @"firstKey": @"EXPORT_SETTINGS_ACTION",
                        @"secondKey": @"IMPORT_SETTINGS_ACTION",
                        @"firstAction": @"showExportSettings:",
                        @"secondAction": @"showImportSettings:"
                    },

                    @{@"type": @"header", @"titleKey": @"LAB_GROUP_TOOLS"},
                    @{
                        @"key": @"compatibility",
                        @"type": @"button",
                        @"titleKey": @"COMPATIBILITY_TITLE",
                        @"subtitleKey": @"COMPATIBILITY_DETAIL",
                        @"action": @"showCompatibility:"
                    },
                    @{@"key": @"flex_twitter", @"default": @NO, @"type": @"toggle"}
                ]
            },
        };
    });
    return pages;
}

static NSDictionary<NSString*, NSDictionary*>* PFBSettingsIndex(void) {
    static NSDictionary<NSString*, NSDictionary*>* index;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString*, NSDictionary*>* map =
            [NSMutableDictionary dictionary];
        for (NSDictionary* page in PFBSettingsPages().allValues) {
            for (NSDictionary* setting in page[@"settings"]) {
                NSString* key = setting[@"key"];
                if (key) {
                    map[key] = setting;
                }
            }
        }
        index = [map copy];
    });
    return index;
}

// Keys stored before the PFB prefix, renamed the way the code names them now.
NSString* PFBCurrentKeyForLegacyKey(NSString* key) {
    if ([key isEqualToString:@"color_nfb_switches"]) {
        return @"color_pfb_switches";
    }
    for (NSString* legacy in @[@"bhtwitter_", @"nfb_", @"bh_"]) {
        if ([key hasPrefix:legacy]) {
            return [@"pfb_" stringByAppendingString:[key substringFromIndex:legacy.length]];
        }
    }
    return nil;
}

id PFBValueWithCurrentKeys(id value) {
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray* items = [NSMutableArray array];
        for (id item in (NSArray*)value) {
            [items addObject:PFBValueWithCurrentKeys(item)];
        }
        return items;
    }
    if (![value isKindOfClass:[NSDictionary class]]) {
        return value;
    }
    NSMutableDictionary* current = [NSMutableDictionary dictionary];
    [(NSDictionary*)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL* stop) {
        NSString* renamed = [key isKindOfClass:[NSString class]] ? PFBCurrentKeyForLegacyKey(key) : nil;
        current[renamed ?: key] = PFBValueWithCurrentKeys(object);
    }];
    return current;
}

// Moves each legacy key to its current name. Runs at every launch, before any setting is read.
static void PFBMigrateLegacyKeys(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* domain = NSBundle.mainBundle.bundleIdentifier;
    NSDictionary* stored = domain ? [defaults persistentDomainForName:domain] : nil;
    for (NSString* key in stored) {
        NSString* current = PFBCurrentKeyForLegacyKey(key);
        if (!current) {
            continue;
        }
        if (!stored[current]) {
            [defaults setObject:PFBValueWithCurrentKeys(stored[key]) forKey:current];
        }
        [defaults removeObjectForKey:key];
    }
}

@implementation PFBSettings

#pragma mark - Migration

// Runs the key migrations before any setting is read. The renames below run once,
// so existing installs keep the settings saved under the old key names.
+ (void)load {
    PFBMigrateLegacyKeys();
    [self migrateUndoTweetToggle];
    [self migrateExploreTrendsSplit];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"pfb_key_migration_v1_done"]) {
        return;
    }

    NSDictionary<NSString*, NSString*>* renamedKeys = @{
        @"dis_rtl": @"disable_rtl",
        @"showScollIndicator": @"show_scroll_indicator",
        @"en_font": @"custom_fonts",
        @"dw_v": @"download_videos",
        @"video_layer_caption": @"disable_video_captions",
        @"autoHighestLoad": @"auto_highest_load",
        @"follow_con": @"follow_confirm",
        @"CopyProfileInfo": @"copy_profile_info",
        @"disableArticles": @"disable_articles",
        @"disableHighlights": @"disable_highlights",
        @"TweetToImage": @"tweet_to_image",
        @"like_con": @"like_confirm",
        @"tweet_con": @"tweet_confirm",
        @"disableSensitiveTweetWarnings": @"disable_sensitive_tweet_warnings",
        @"no_his": @"no_history",
        @"openInBrowser": @"always_open_safari",
        @"reply_sorting_enabled": @"reply_sorting",
        @"ios_in_app_article_webview_enabled": @"new_inapp_webview",
        @"tweet_url_host": @"sharing_domain",
    };

    // These old names double as Twitter's own feature-switch keys, so copy the
    // value across but leave the original in place rather than risk removing it.
    NSSet<NSString*>* sharedWithTwitter = [NSSet setWithArray:@[
        @"reply_sorting_enabled",
        @"ios_in_app_article_webview_enabled",
    ]];

    [renamedKeys enumerateKeysAndObjectsUsingBlock:^(
                     NSString* oldKey, NSString* newKey, BOOL* stop) {
        id value = [defaults objectForKey:oldKey];
        if (value == nil) {
            return;
        }
        if ([defaults objectForKey:newKey] == nil) {
            [defaults setObject:value forKey:newKey];
        }
        if (![sharedWithTwitter containsObject:oldKey]) {
            [defaults removeObjectForKey:oldKey];
        }
    }];

    [defaults setBool:YES forKey:@"pfb_key_migration_v1_done"];
}

// Runs once: a stored hide_trends = YES becomes choose_explore_tabs on and
// hide_explore_all off when any Explore tab is struck, the reverse when none is;
// hide_trends is then removed.
+ (void)migrateExploreTrendsSplit {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"pfb_explore_split_migration_done"]) {
        return;
    }
    id stored = [defaults objectForKey:@"hide_trends"];
    if (stored != nil && [stored boolValue]) {
        BOOL anyTabStruck = NO;
        for (NSString* tabKey in @[
                 @"hide_tab_foryou", @"hide_tab_trending", @"hide_tab_news",
                 @"hide_tab_sports", @"hide_tab_entertainment"
             ]) {
            if ([self boolForKey:tabKey]) {
                anyTabStruck = YES;
                break;
            }
        }
        [defaults setBool:anyTabStruck forKey:@"choose_explore_tabs"];
        [defaults setBool:!anyTabStruck forKey:@"hide_explore_all"];
    }
    [defaults removeObjectForKey:@"hide_trends"];
    [defaults setBool:YES forKey:@"pfb_explore_split_migration_done"];
}

// Runs once: a stored undo_tweet = NO becomes undo_tweet_timeout = 0, which means
// off, unless a timeout is already stored; undo_tweet is then removed.
+ (void)migrateUndoTweetToggle {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"pfb_undo_timeout_migration_done"]) {
        return;
    }

    id oldToggle = [defaults objectForKey:@"undo_tweet"];
    if (oldToggle != nil && ![oldToggle boolValue] &&
        [defaults objectForKey:@"undo_tweet_timeout"] == nil) {
        [defaults setInteger:0 forKey:@"undo_tweet_timeout"];
    }
    [defaults removeObjectForKey:@"undo_tweet"];
    [defaults setBool:YES forKey:@"pfb_undo_timeout_migration_done"];
}

#pragma mark - Accessors

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey {
    return pageKey ? PFBSettingsPages()[pageKey][@"settings"] : nil;
}

+ (NSString*)titleKeyForPage:(NSString*)pageKey {
    return pageKey ? PFBSettingsPages()[pageKey][@"titleKey"] : nil;
}

+ (NSString*)subtitleKeyForPage:(NSString*)pageKey {
    return pageKey ? PFBSettingsPages()[pageKey][@"subtitleKey"] : nil;
}

+ (NSDictionary*)settingForKey:(NSString*)key {
    return key ? PFBSettingsIndex()[key] : nil;
}

// Defaults for options set from a page of their own, which have no row in the
// registry. Without an entry here settingForKey: returns nil and the fallback reads
// @"default" from nil, yielding NO or 0 by accident rather than by decision.
static NSDictionary* PFBKeylessDefaults(void) {
    static NSDictionary* map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"enable_liquid_glass": @YES,
            @"color_twitter_icon_in_top_bar": @YES,
            // Carried by a pill rather than a row of its own, so the registry
            // holds no default for it.
            @"video_starts_muted": @YES,
            // Carried by the Explore bar replica, same reason. Only the two that
            // default to YES are named; the rest default to NO on their own.
            @"hide_tab_trending": @YES,
            @"hide_tab_entertainment": @YES,
        };
    });
    return map;
}

// The declared default for a key: its registry row when it has one, otherwise
// the table above.
+ (id)declaredDefaultForKey:(NSString*)key {
    id row = [self settingForKey:key][@"default"];
    return row ?: PFBKeylessDefaults()[key];
}

+ (BOOL)boolForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value boolValue];
    }
    return [[self declaredDefaultForKey:key] boolValue];
}

+ (NSInteger)integerForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value integerValue];
    }
    return [[self declaredDefaultForKey:key] integerValue];
}

+ (NSArray<NSString*>*)allOptionKeys {
    NSMutableArray<NSString*>* keys = [NSMutableArray array];
    for (NSDictionary* page in PFBSettingsPages().allValues) {
        for (NSDictionary* setting in page[@"settings"]) {
            NSMutableArray<NSString*>* rowKeys = [NSMutableArray array];
            if (setting[@"key"]) {
                [rowKeys addObject:setting[@"key"]];
            }
            if (setting[@"pillKey"]) {
                [rowKeys addObject:setting[@"pillKey"]];
            }
            [rowKeys addObjectsFromArray:setting[@"tabKeys"] ?: @[]];
            for (NSString* key in rowKeys) {
                if (![keys containsObject:key]) {
                    [keys addObject:key];
                }
            }
        }
    }
    return keys;
}

@end
