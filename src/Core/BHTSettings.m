//
//  BHTSettings.m
//  PrimeFreeBird
//
//  Created by nyaathea
//

#import "Core/BHTSettings.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsPages(void) {
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
                    @{@"key": @"force_following_tab", @"default": @NO},
                    @{@"key": @"no_tab_bar_hiding", @"default": @YES},
                    @{@"key": @"show_scroll_indicator", @"default": @NO},
                    @{@"key": @"disable_rtl", @"default": @NO},
                    @{@"key": @"hide_premium_offer", @"default": @YES},
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
                      @"disabledWhen": @"enable_liquid_glass",
                      @"default": @NO},
                    @{@"key": @"custom_fonts",
                      @"default": @NO},
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"regular_font_button",
                        @"titleKey": @"REGULAR_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showRegularFontPicker:",
                        @"prefKeyForSubtitle": @"bhtwitter_font_1",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE"
                    },
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"bold_font_button",
                        @"titleKey": @"BOLD_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showBoldFontPicker:",
                        @"prefKeyForSubtitle": @"bhtwitter_font_2",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE"
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
                    @{@"key": @"color_nfb_switches",
                        @"default": @NO,
                        @"type": @"toggle"},
                    @{@"key": @"color_twitter_icon_in_top_bar",
                        @"default": @([BHTManager isTwitterBranded]),
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
                      @"default": @NO,
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
                    @{@"key": @"reading_line",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{
                        @"type": @"compactButton",
                        @"key": @"reading_diag_button",
                        @"titleKey": @"READING_DIAG_TITLE",
                        @"action": @"showReadingDiag:",
                        @"prefKeyForSubtitle": @"nfb_reading_diag",
                        @"subtitleDefaultKey": @"READING_DIAG_EMPTY"
                    },
                    @{
                        @"type": @"button",
                        @"titleKey": @"FILTERS_TITLE",
                        @"subtitleKey": @"FILTERS_DETAIL",
                        @"action": @"showMutedWords:"
                    },
                    @{@"type": @"header", @"titleKey": @"TIMELINES_GROUP_BARS"},
                    @{@"key": @"hide_spaces",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_scroll_edge_blur",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_custom_timelines",
                      @"default": @NO,
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
                        @"action": @"showUndoTimeoutPicker:"
                    },
                    @{@"key": @"tweet_confirm",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tweet_button",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"TWEETS_GROUP_ACTIONS"},
                    @{@"key": @"like_confirm",
                      @"default": @NO,
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
                        @"default": @NO,
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
                    @{@"key": @"direct_save",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"tweet_to_image",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"MEDIA_GROUP_PLAYBACK"},
                    @{
                        @"key": @"tap_to_pause",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{@"key": @"restore_video_timestamp",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"disable_video_captions",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"disable_immersive_scroll",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"disable_video_docking",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"MEDIA_GROUP_QUALITY"},
                    @{@"key": @"auto_highest_load",
                      @"default": @YES,
                      @"type": @"toggle"},
                    @{@"key": @"enable_image_preloading",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"force_tweet_full_frame",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"upload_full_hd_videos",
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
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"expand_bio",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"copy_profile_info",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"titleKey": @"PROFILE_INITIAL_TAB_TITLE",
                        @"subtitleKey": @"PROFILE_INITIAL_TAB_SUBTITLE",
                        @"action": @"showProfileTabPicker:",
                        @"type": @"button"
                    },
                    @{@"type": @"header", @"titleKey": @"PROFILES_GROUP_TABS"},
                    @{
                        @"key": @"disable_articles",
                        @"default": @YES,
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
                        @"key": @"restore_follow_button",
                        @"default": @NO,
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
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"advanced_search",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"type": @"header", @"titleKey": @"SEARCH_GROUP_TRENDS"},
                    @{@"key": @"hide_trends",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tab_foryou",
                      @"parentKey": @"hide_trends",
                      @"indented": @YES,
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tab_trending",
                      @"parentKey": @"hide_trends",
                      @"indented": @YES,
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tab_news",
                      @"parentKey": @"hide_trends",
                      @"indented": @YES,
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tab_sports",
                      @"parentKey": @"hide_trends",
                      @"indented": @YES,
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_tab_entertainment",
                      @"parentKey": @"hide_trends",
                      @"indented": @YES,
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_trend_videos",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            },
            @"branding": @{
                @"titleKey": @"MODERN_SETTINGS_BRANDING_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_BRANDING_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"APP_ICON_TITLE",
                        @"subtitleKey": @"APP_ICON_SUBTITLE",
                        @"action": @"showAppIconViewController:",
                        @"type": @"button"
                    },
                    @{
                        @"key": @"restore_twitter_names",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"refresh_pill_label",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_tweet_button",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_tweet_labels",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_refresh_sounds",
                        @"default": @YES,
                        @"type": @"toggle"
                    }
                ]
            },
            @"grok": @{
                @"titleKey": @"MODERN_SETTINGS_GROK_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_GROK_SUBTITLE",
                @"settings": @[
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
            @"lab": @{
                @"titleKey": @"MODERN_SETTINGS_LAB_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_LAB_SUBTITLE",
                @"settings": @[
                    @{@"key": @"reply_in_webview", @"default": @NO, @"type": @"toggle"},
                    @{
                        @"titleKey": @"WEB_SESSION_LOGIN_TITLE",
                        @"subtitleKey": @"WEB_SESSION_LOGIN_SUBTITLE",
                        @"action": @"showWebSessionLogin:",
                        @"type": @"button"
                    },
                    @{
                        @"titleKey": @"WEB_SESSION_CLEAR_TITLE",
                        @"subtitleKey": @"WEB_SESSION_CLEAR_SUBTITLE",
                        @"action": @"clearWebSession:",
                        @"type": @"button"
                    },
                    @{@"key": @"flex_twitter", @"default": @NO, @"type": @"toggle"},
                    @{
                        @"type": @"button",
                        @"titleKey": @"EXPORT_SETTINGS_TITLE",
                        @"subtitleKey": @"EXPORT_SETTINGS_DETAIL",
                        @"action": @"showExportSettings:"
                    },
                    @{
                        @"type": @"button",
                        @"titleKey": @"IMPORT_SETTINGS_TITLE",
                        @"subtitleKey": @"IMPORT_SETTINGS_DETAIL",
                        @"action": @"showImportSettings:"
                    }
                ]
            },
        };
    });
    return pages;
}

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsIndex(void) {
    static NSDictionary<NSString*, NSDictionary*>* index;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString*, NSDictionary*>* map =
            [NSMutableDictionary dictionary];
        for (NSDictionary* page in BHTSettingsPages().allValues) {
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

@implementation BHTSettings

#pragma mark - Migration

// One-time migration of preferences saved under the old (inconsistent) key
// names to the normalised keys, so existing installs keep their settings.
+ (void)load {
    [self migrateUndoTweetToggle];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"nfb_key_migration_v1_done"]) {
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

    [defaults setBool:YES forKey:@"nfb_key_migration_v1_done"];
}

// The Undo Tweet on/off toggle was merged into the timeout picker, where a
// timeout of 0 means off. Carry a prior "off" state across as a 0 timeout.
+ (void)migrateUndoTweetToggle {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"nfb_undo_timeout_migration_done"]) {
        return;
    }

    id oldToggle = [defaults objectForKey:@"undo_tweet"];
    if (oldToggle != nil && ![oldToggle boolValue] &&
        [defaults objectForKey:@"undo_tweet_timeout"] == nil) {
        [defaults setInteger:0 forKey:@"undo_tweet_timeout"];
    }
    [defaults removeObjectForKey:@"undo_tweet"];
    [defaults setBool:YES forKey:@"nfb_undo_timeout_migration_done"];
}

#pragma mark - Accessors

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"settings"] : nil;
}

+ (NSString*)titleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"titleKey"] : nil;
}

+ (NSString*)subtitleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"subtitleKey"] : nil;
}

+ (NSDictionary*)settingForKey:(NSString*)key {
    return key ? BHTSettingsIndex()[key] : nil;
}

+ (BOOL)boolForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value boolValue];
    }
    return [[self settingForKey:key][@"default"] boolValue];
}

+ (NSInteger)integerForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value integerValue];
    }
    return [[self settingForKey:key][@"default"] integerValue];
}

+ (NSArray<NSString*>*)allOptionKeys {
    NSMutableArray<NSString*>* keys = [NSMutableArray array];
    for (NSDictionary* page in BHTSettingsPages().allValues) {
        for (NSDictionary* setting in page[@"settings"]) {
            NSString* key = setting[@"key"];
            if (key && ![keys containsObject:key]) {
                [keys addObject:key];
            }
        }
    }
    return keys;
}

@end
