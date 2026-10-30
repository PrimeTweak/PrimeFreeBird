// Feature-switch overrides read by the app, the web login mounted in place of the
// native login screens, the skipped notification-permission onboarding step, and the
// account feature gates.

#import "Support/HookHelpers.h"
#import "Sideload/PFBWebLoginViewController.h"
#import "Debug/PFBDebugger.h"

// While set, -isSubscribedTo: (below) reports the account's genuine
// subscription state instead of the forced premium tiers, so paths that need
// the real status can read through the unlock.
static __thread BOOL ReportGenuineSubscription = NO;

// While set, the custom-navigation tab gates (below) report their real values,
// so callers can tell genuinely-held panels from ones only unlocked for the tab
// pool.
static __thread BOOL ReportGenuineTabGates = NO;

// Whether the account is really a premium subscriber, ignoring the forced
// unlock — for switch-gated surfaces that have no premium-aware seam of their
// own.
static BOOL AccountIsGenuinelyPremium(void) {
    Class hostClass = objc_getClass("T1HostViewController");
    if (![(id)hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        return NO;
    }
    id host = ((id (*)(id, SEL))objc_msgSend)(
        (id)hostClass, @selector(sharedHostViewController));
    if (![host respondsToSelector:@selector(currentAccount)]) {
        return NO;
    }
    id account = ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
    if (![account respondsToSelector:@selector(isPremiumTierUser)]) {
        return NO;
    }

    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL premium =
        ((BOOL (*)(id, SEL))objc_msgSend)(account, @selector(isPremiumTierUser));
    ReportGenuineSubscription = saved;
    return premium;
}

// MARK: - Feature switch overrides

// Whether a switch drives a Grok Bot promotion. Twitter reads a placement's switch only
// once the upsells switch is on, and the banners' only for the Ask Grok button under a
// post, so the upsells switch alone proves the option.
static BOOL pfbIsGrokBotSwitch(NSString* key) {
    if (![key hasPrefix:@"grok_ios_grok_bot_"]) {
        return NO;
    }
    static NSSet<NSString*>* keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      keys = [NSSet setWithArray:@[
          @"grok_ios_grok_bot_upsells_enabled", @"grok_ios_grok_bot_sidebar_enabled",
          @"grok_ios_grok_bot_home_header_enabled", @"grok_ios_grok_bot_home_hero_enabled",
          @"grok_ios_grok_bot_preset_enabled", @"grok_ios_grok_bot_tab_icon_enabled",
          @"grok_ios_grok_bot_post_cta_enabled", @"grok_ios_grok_bot_reply_cta_enabled"
      ]];
    });
    return [keys containsObject:key];
}

static NSNumber* FeatureSwitchOverrideValueForKey(NSString* key) {
    if (![key isKindOfClass:[NSString class]]) {
        return nil;
    }
    PFBCompatNoteSettingRead(key);
    // Unlock Twitter's native premium color themes, so the accent the user picks
    // is applied everywhere (links, buttons, highlights) by Twitter itself.
    if ([key isEqualToString:@"app_customization_custom_primary_color_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_premium_unlock, @"premium colors unlocked");
        return @YES;
    }

    // Twitter carries its own Liquid Glass redesign behind this switch, with the bar
    // geometry that goes with it. Asking for it beats lying to UIKit, which leaves the
    // app laying out for a design it was never told of.
    if ([key isEqualToString:@"ios_liquid_glass_redesign_enabled"] ||
        [key isEqualToString:@"xchat_liquid_glass_convo_header_enabled"]) {
        return [PFBSettings boolForKey:@"enable_liquid_glass"] ? @YES : nil;
    }

    // Twitter's new settings menu has no PrimeFreeBird row, so the classic one is kept; the
    // tour lets Twitter's own answer through once, to measure the new menu.
    if ([key isEqualToString:@"ios_settings_redesign_enabled"]) {
        if (PFBCompatTourWantsNewSettings()) {
            return nil;
        }
        PFBCOMPAT_ACTION(PFBCompat_settings_entry, @"classic settings menu kept");
        return @NO;
    }

    // Grok Bot, a separate app, is promoted from the side menu, the home timeline, the
    // presets, the tab icon and banners under posts and replies, each behind its own switch.
    if (pfbIsGrokBotSwitch(key)) {
        if ([key isEqualToString:@"grok_ios_grok_bot_upsells_enabled"]) {
            PFBCompatReach(PFBCompatPath_grok_bot_upsells);
        }
        if ([PFBSettings boolForKey:@"hide_grok_bot"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_bot, @"Grok Bot promotion off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_bot, @"read by Twitter");
        return nil;
    }

    // Screenshot share sheet: the prompt goes on cooldown after max_dismisses
    // dismissals. The max is forced to infinity so the cooldown never triggers and
    // the duration to 0 so any active one clears.
    if (![PFBSettings boolForKey:@"no_screenshot_detection"]) {
        if ([key isEqualToString:@"ios_consideration_share_cooldown_max_dismisses"]) {
            return @(1000000);
        }
        if ([key isEqualToString:@"ios_consideration_share_cooldown_days"]) {
            return @0;
        }
        if ([key isEqualToString:@"ios_consideration_share_cooldown_window_hours"]) {
            return @0;
        }
    }

    // Two switches meet here. Hiding always wins, since with the strip gone the tab
    // options are moot. Otherwise unlimited_timeline_tabs unlocks every tab type and
    // lifts the pin limit, or returns nil for Twitter's own server values.
    BOOL hideCustomTimelines = [PFBSettings boolForKey:@"hide_custom_timelines"];
    BOOL unlimitedTabs = [PFBSettings boolForKey:@"unlimited_timeline_tabs"];
    if ([key isEqualToString:@"hometimeline_pinned_tabs_topics_enabled"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_generic_timelines_enabled"]) {
        if (hideCustomTimelines) {
            PFBCOMPAT_ACTION(PFBCompat_hide_custom_timelines, @"pinned tab gate off");
            PFBCOMPAT_OBSERVE(PFBCompat_unlimited_timeline_tabs, @"read by Twitter, Hide custom timelines answers first");
            return @NO;
        }
        if (unlimitedTabs) {
            PFBCOMPAT_ACTION(PFBCompat_unlimited_timeline_tabs, @"every tab type allowed");
            return @YES;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_unlimited_timeline_tabs, @"read by Twitter");
        return nil;
    }

    if ([key isEqualToString:@"hometimeline_pinned_tabs_limit"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_management_pinnedsection_"
                             @"inline_limit"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_management_topics_inline_limit"]) {
        if (hideCustomTimelines) {
            PFBCOMPAT_ACTION(PFBCompat_hide_custom_timelines, @"pin limit 0");
            PFBCOMPAT_OBSERVE(PFBCompat_unlimited_timeline_tabs, @"read by Twitter, Hide custom timelines answers first");
            return @0;
        }
        if (unlimitedTabs) {
            PFBCOMPAT_ACTION(PFBCompat_unlimited_timeline_tabs, @"pin limit lifted");
            return @100;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_unlimited_timeline_tabs, @"read by Twitter");
        return nil;
    }

    // Edit tweet
    if ([key isEqualToString:@"edit_tweet_ga_composition_enabled"] ||
        [key isEqualToString:@"edit_tweet_pdp_dialog_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_edit_tweet, @"edit allowed");
        return @YES;
    }

    // Restore the animated launch screen (AppLifecycle.x strips its X-shaped
    // reveal mask)
    if ([key isEqualToString:@"app_launch_animated_launch_screen_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_launch_screen, @"animated launch screen kept");
        return @YES;
    }

    // Translate button: Twitter's translation entry on posts, bios, Community Notes and
    // polls, on for every account.
    if ([key isEqualToString:
                 @"grok_translations_bio_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_bio_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_post_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_post_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_community_note_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_poll_translation_is_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_grok_translation, @"translate allowed");
        return @YES;
    }

    // Checked before the per-language preference, so turning these off stops all
    // auto translation while manual translate stays.
    if ([key isEqualToString:
                 @"grok_translations_post_auto_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_bio_auto_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_community_note_auto_translation_"
                             @"is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_notification_auto_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_immersive_auto_translate_is_enabled"]) {
        if ([PFBSettings boolForKey:@"disable_auto_translate"]) {
            PFBCOMPAT_ACTION(PFBCompat_disable_auto_translate, @"auto translation off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_disable_auto_translate, @"read by Twitter");
        return nil;
    }

    // Grok buttons
    if ([key isEqualToString:@"grok_ask_grok_button_under_post_focal_enabled"] ||
        [key
            isEqualToString:@"grok_ask_grok_button_under_post_preview_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_analyze"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_analyze, @"Ask Grok button off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_analyze, @"read by Twitter");
        return @YES;
    }

    if ([key isEqualToString:
                 @"grok_edit_with_grok_button_under_post_focal_enabled"] ||
        [key isEqualToString:
                 @"grok_edit_with_grok_button_under_post_preview_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_create"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_create, @"Grok creation tool off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_create, @"read by Twitter");
        return @YES;
    }

    // Grok creation surfaces: the composer's Grok and Imagine entries, Imagine menus on
    // media, Edit with Grok on photo posts and the Imagine call to action.
    if ([key isEqualToString:@"ios_composer_grok_button_enabled"] ||
        [key isEqualToString:@"grok_composer_imagine_is_enabled"] ||
        [key isEqualToString:
                 @"grok_composer_attachment_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_timeline_preview_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_timeline_video_imagine_menu_is_enabled"] ||
        [key
            isEqualToString:@"grok_timeline_slideshow_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_ios_edit_photo_post_button_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_2_cta_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_create"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_create, @"Grok creation tool off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_create, @"read by Twitter");
        return nil;
    }

    // Disguised switch family for the Grok edit-photo and create-own buttons,
    // read only by Grok.GrokFeatureAccess.
    if ([key hasPrefix:@"ios_button_layout_fix"] && [key hasSuffix:@"_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_create"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_create, @"Grok creation tool off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_create, @"read by Twitter");
        return nil;
    }

    // Grok analyze: every tweet-side show decision gates on this backend switch
    // before consulting the per-tweet flag.
    if ([key isEqualToString:
                 @"grok_ios_author_view_analyze_button_via_backend_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_analyze"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_analyze, @"Grok analyze off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_analyze, @"read by Twitter");
        return nil;
    }

    // The profile header's analyze (summary) button bottoms out in this switch on
    // both header variants, one of which reads it through a direct Swift call.
    if ([key isEqualToString:@"grok_ios_profile_summary_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_analyze"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_analyze, @"Grok analyze off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_analyze, @"read by Twitter");
        return @YES;
    }

    // The "About this post" menu's Grok pills ("Ask Grok", "Is this true?",
    // "Explain this"): Twitter's own switch hides them when on, so it is forced on.
    if ([key isEqualToString:@"post_about_hide_grok_pills_enabled"]) {
        PFBCompatReach(PFBCompatPath_grok_post_menu);
        if ([PFBSettings boolForKey:@"hide_grok_analyze"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_analyze, @"Grok pills off in the post menu");
            return @YES;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_analyze, @"read by Twitter");
        return nil;
    }

    // The same menu's summary of the post, above the pills, behind its own switch.
    if ([key isEqualToString:@"post_about_grok_features_enabled"]) {
        PFBCompatReach(PFBCompatPath_grok_post_menu);
        if ([PFBSettings boolForKey:@"hide_grok_analyze"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_analyze, @"Grok summary off in the post menu");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_analyze, @"read by Twitter");
        return nil;
    }

    // Ask Grok inside a chat and in the menu of selected text, each behind its own switch.
    if ([key isEqualToString:@"xchat_ask_grok_enabled"] ||
        [key isEqualToString:@"grok_explain_text_selection_ask_grok_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_grok_analyze"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_grok_analyze, @"Ask Grok off in chats and selected text");
            // Each switch proven on its own: the sheet shows only an option's first proof.
            static BOOL chatNoted, selectionNoted;
            BOOL chat = [key hasPrefix:@"xchat"];
            BOOL* noted = chat ? &chatNoted : &selectionNoted;
            if (!*noted) {
                *noted = YES;
                PFBCompatMeasure(@"grok", chat ? @"Ask Grok off in chats" : @"Ask Grok off in selected text", 2);
            }
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_analyze, @"read by Twitter");
        return nil;
    }

    // The "Suggested" list in an empty Chat inbox and its "Find friends" row, behind
    // Twitter's own switches, which Chat reads from its own store (hooked below).
    if ([key isEqualToString:@"xchat_cold_inbox_suggestions_enabled"] ||
        [key isEqualToString:@"xchat_cold_inbox_find_friends_enabled"]) {
        BOOL off = [PFBSettings boolForKey:@"hide_suggested_chats"];
        // Each switch proven on its own: the sheet shows only an option's first proof.
        static BOOL listNoted, friendsNoted;
        BOOL friends = [key containsString:@"find_friends"];
        BOOL* noted = friends ? &friendsNoted : &listNoted;
        if (!*noted) {
            *noted = YES;
            PFBCompatMeasure(@"suggested chats",
                             [NSString stringWithFormat:@"%@ read by Twitter, %@", friends ? @"Find friends" : @"Suggested list",
                                                        off ? @"turned off" : @"left on"],
                             4);
        }
        if (off) {
            PFBCOMPAT_ACTION(PFBCompat_hide_suggested_chats, @"suggested chats off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_suggested_chats, @"read by Twitter");
        return nil;
    }

    // Which tab Home opens on: the choice natively survives 12 hours, then a new
    // session snaps back to For You. Answering NO removes the expiry; off, nothing
    // is answered and the native rule applies.
    if ([key isEqualToString:@"home_timeline_non_sticky_tab_on_new_session_enabled"]) {
        if ([PFBSettings boolForKey:@"force_following_tab"]) {
            PFBCOMPAT_ACTION(PFBCompat_force_following_tab, @"Home kept on its tab");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_force_following_tab, @"read by Twitter");
        return nil;
    }

    // How long the app must stay in the background before Home refreshes on its
    // return. Ten years keeps the timeline where it was; off, the native delay.
    if ([key isEqualToString:@"home_timeline_foreground_refresh_min_background_seconds"]) {
        if ([PFBSettings boolForKey:@"no_focus_lost"]) {
            PFBCOMPAT_ACTION(PFBCompat_no_focus_lost, @"return refresh held");
            return @(315360000.0);
        }
        PFBCOMPAT_OBSERVE(PFBCompat_no_focus_lost, @"read by Twitter");
        return nil;
    }

    // Profile tabs
    if ([key isEqualToString:@"articles_timeline_profile_tab_enabled"]) {
        if ([PFBSettings boolForKey:@"disable_articles"]) {
            PFBCOMPAT_ACTION(PFBCompat_disable_articles, @"Articles tab off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_disable_articles, @"read by Twitter");
        return @YES;
    }

    if ([key isEqualToString:@"highlights_tweets_tab_ui_enabled"]) {
        if ([PFBSettings boolForKey:@"disable_highlights"]) {
            PFBCOMPAT_ACTION(PFBCompat_disable_highlights, @"Highlights tab off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_disable_highlights, @"read by Twitter");
        return @YES;
    }

    // Age verification bypass
    if ([key hasPrefix:@"ios_age_assurance"] ||
        [key isEqualToString:@"grok_settings_age_restriction_enabled"]) {
        if ([PFBSettings boolForKey:@"bypass_age_verification"]) {
            PFBCOMPAT_ACTION(PFBCompat_bypass_age_verification, @"age check skipped");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_bypass_age_verification, @"read by Twitter");
        return nil;
    }

    // Full links: no click ID or DoubleClick redirect on promoted links, no card link
    // fetched before a tap.
    if ([key isEqualToString:@"ad_formats_click_id_enabled"] || [key isEqualToString:@"ad_formats_dcm_enabled"] ||
        [key isEqualToString:@"wcl_unified_cards_likely_open_link_prefetch_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_expand_tco_links, @"link tracking switch off");
        return @NO;
    }

    // Conversation / tweet detail: the sort control stays, so a conversation's order can
    // change from the one Sort replies opened it in.
    if ([key isEqualToString:@"reply_sorting_enabled"]) {
        return @YES;
    }

    // Classic Tweet page: the overflow menu stays on the Tweet, not in the navigation bar.
    if ([key
            isEqualToString:@"ios_tweet_detail_overflow_in_navigation_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_classic_tweet_detail, @"overflow kept in place");
        return @NO;
    }

    if ([key isEqualToString:
                 @"ios_tweet_detail_conversation_context_removal_enabled"]) {
        if ([PFBSettings boolForKey:@"restore_reply_context"]) {
            PFBCOMPAT_ACTION(PFBCompat_restore_reply_context, @"reply context kept");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_restore_reply_context, @"read by Twitter");
        return @YES;
    }

    // The carousel is Twitter's newer layout for several photos in one Tweet;
    // NO on all three keys brings back the grid, quoted Tweets included.
    if ([key isEqualToString:@"ios_ui_multi_media_carousel_enabled"] ||
        [key isEqualToString:@"ios_ui_multi_media_carousel_avatar_avoidance_enabled"] ||
        [key isEqualToString:@"ios_ui_quote_tweet_multi_media_carousel_enabled"]) {
        if ([PFBSettings boolForKey:@"disable_media_carousel"]) {
            PFBCOMPAT_ACTION(PFBCompat_disable_media_carousel, @"media grid kept");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_disable_media_carousel, @"read by Twitter");
        return nil;
    }

    // Video captions
    if ([key isEqualToString:@"ios_tav_default_closed_captions_enabled"] ||
        [key isEqualToString:@"ios_audio_transcription_subtitles_vod_enabled"]) {
        if ([PFBSettings boolForKey:@"disable_video_captions"]) {
            PFBCOMPAT_ACTION(PFBCompat_disable_video_captions, @"captions off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_disable_video_captions, @"read by Twitter");
        return nil;
    }

    // Voice notes: the transcript is rendered under the waveform, so a message
    // can be read instead of played.
    if ([key isEqualToString:@"xchat_voice_messages_transcription_enabled"]) {
        if ([PFBSettings boolForKey:@"voice_transcription"]) {
            PFBCOMPAT_ACTION(PFBCompat_voice_transcription, @"transcript shown");
            return @YES;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_voice_transcription, @"read by Twitter");
        return nil;
    }

    // Preload media, video half: Twitter's own prefetcher looks four Tweets ahead,
    // loads two videos at a time and keeps two in cache.
    NSNumber* prefetch = [key isEqualToString:@"ios_tav_video_prefetch_range"]                  ? @4
                         : [key isEqualToString:@"ios_tav_video_prefetch_batch_size"]           ? @2
                         : [key isEqualToString:@"ios_tav_video_prefetch_videos_kept_in_cache"] ? @2
                                                                                                : nil;
    if (prefetch) {
        if ([PFBSettings boolForKey:@"enable_image_preloading"]) {
            PFBCOMPAT_ACTION(PFBCompat_enable_image_preloading, @"video prefetch set");
            return prefetch;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_enable_image_preloading, @"read by Twitter");
        return nil;
    }

    // Per-panel tab gates, forced on so every panel exists for the editor to offer.
    // The tab bar hook keeps them out of the bar and the dash spoof below keeps them
    // out of the side drawer.
    if ([key isEqualToString:@"ios_tab_bar_default_show_profile"] ||
        [key isEqualToString:@"ios_tab_bar_default_show_communities"]) {
        return @YES;
    }

    // Spaces, Communities-in-Explore and Grok are enabled outright for every
    // account (Custom Navigation needs their panels to exist).
    if ([key isEqualToString:@"voice_rooms_consumption_enabled"] ||
        [key isEqualToString:@"communities_enable_explore_tab"] ||
        [key isEqualToString:@"subscriptions_inapp_grok"]) {
        return @YES;
    }

    // The Explore News tab's server gate is forced on unconditionally: Custom
    // Navigation needs the panel to exist, and the Explore remap requires a stable
    // five-tab population.
    if ([key isEqualToString:@"ai_trends_ios_enable_news_tab"]) {
        return @YES;
    }

    // 0 hides the Communities tab, 1 is contextual-only; anything else shows it.
    if ([key isEqualToString:@"c9s_tab_visibility"]) {
        return @2;
    }

    if (!ReportGenuineTabGates) {
        if ([key isEqualToString:@"subscriptions_premium_hub_enabled"] ||
            [key isEqualToString:@"recruiting_global_jobs_hub_enabled"]) {
            return @YES;
        }
    }

    // The Connect tab stays on its native gate (fresh accounts only): its drawer
    // row doesn't consult the tab bar, so forcing it would grow a row that can't
    // be hidden.

    // In-app article webview
    if ([key isEqualToString:@"ios_in_app_article_webview_enabled"]) {
        if ([PFBSettings boolForKey:@"new_inapp_webview"]) {
            PFBCOMPAT_ACTION(PFBCompat_new_inapp_webview, @"new browser on");
            return @YES;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_new_inapp_webview, @"read by Twitter");
        return @NO;
    }

    // A negative threshold disables immersive auto-advance and removes its row
    // from the player's settings sheet.
    if ([key
            isEqualToString:@"immersive_video_auto_advance_duration_threshold"]) {
        if ([PFBSettings boolForKey:@"disable_immersive_scroll"]) {
            PFBCOMPAT_ACTION(PFBCompat_disable_immersive_scroll, @"auto-advance off");
            return @(-1);
        }
        PFBCOMPAT_OBSERVE(PFBCompat_disable_immersive_scroll, @"read by Twitter");
        return nil;
    }

    if ([key isEqualToString:@"ssp_ads_spotlight"] ||
        [key isEqualToString:@"ssp_ads_spotlight_client_only_integration"] ||
        [key isEqualToString:
                 @"ssp_ads_spotlight_client_only_integration_preload"] ||
        [key isEqualToString:@"ssp_ads_home_enabled"] ||
        [key isEqualToString:@"ssp_ads_home_client_only_integration"] ||
        [key isEqualToString:@"ssp_ads_profile"] ||
        [key isEqualToString:
                 @"ssp_ads_profile_client_only_integration_enabled"] ||
        [key isEqualToString:@"ssp_ads_immersive"] ||
        [key isEqualToString:@"ssp_ads_immersive_client_only_integration"] ||
        [key isEqualToString:@"ssp_ads_tweet_details"] ||
        [key isEqualToString:
                 @"ssp_ads_tweet_details_client_only_integration"]) {
        if ([PFBSettings boolForKey:@"hide_promoted"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_promoted, @"ad slot off");
            return @NO;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_promoted, @"read by Twitter");
        return nil;
    }

    // Reactive blending: likes and follows make the timeline request fresh
    // who-to-follow suggestions and splice them in; this switch turns it off.
    if ([key isEqualToString:@"wtf_device_follow_nudge_turn_off_reactive_blending_enabled"]) {
        if ([PFBSettings boolForKey:@"hide_who_to_follow"]) {
            PFBCOMPAT_ACTION(PFBCompat_hide_who_to_follow, @"follow suggestions off");
            return @YES;
        }
        PFBCOMPAT_OBSERVE(PFBCompat_hide_who_to_follow, @"read by Twitter");
        return nil;
    }

    // Premium features gate on subscriptions_enabled || (gating bypass && premium
    // tier).
    if ([key isEqualToString:@"subscriptions_gating_bypass"]) {
        PFBCOMPAT_ACTION(PFBCompat_premium_unlock, @"premium gate opened");
        return @YES;
    }

    // Premium and verification upsells. Not all gate on !isPremiumTierUser, so every
    // upsell surface is disabled here.
    if ([key isEqualToString:@"ios_profile_analytics_upsell_enabled"] ||
        [key isEqualToString:@"ios_profile_analytics_upsell_possible_enabled"] ||
        [key isEqualToString:@"ios_profile_upgrade_upsell_enabled"] ||
        [key isEqualToString:@"ios_profile_upgrade_upsell_swapper_enabled"] ||
        [key isEqualToString:@"ios_profile_visitor_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_get_verified_profile"] ||
        [key isEqualToString:@"subscriptions_upsells_reply_boost_enabled"] ||
        [key
            isEqualToString:@"subscriptions_upsells_reply_boost_popup_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_post_analytics_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_creator_support_post_"
                             @"conversation_enabled"] ||
        [key isEqualToString:@"longform_notetweets_composer_upsell_enabled"] ||
        [key isEqualToString:
                 @"longform_notetweets_composer_auto_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_cta_on_replies_enabled"] ||
        [key isEqualToString:@"super_follow_upsell_sticky_button_enabled"] ||
        [key isEqualToString:@"subscriptions_new_paywall_enabled"] ||
        [key isEqualToString:@"subscriptions_offers_promotional_enabled"] ||
        [key isEqualToString:@"subscriptions_gifting_premium_enabled"] ||
        [key isEqualToString:
                 @"subscriptions_gifting_premium_intro_copy_enabled"] ||
        [key isEqualToString:
                 @"ios_notifications_blue_verified_introductory_offer_visible"] ||
        [key isEqualToString:@"ios_notifications_blue_verified_introductory_"
                             @"offer_prefix_visible"] ||
        [key isEqualToString:@"dash_items_download_grok_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_upsells, @"upsell off");
        return @NO;
    }

    // Boost (quick promote) button and its upsells. Each placement reads its own
    // switch rather than the root one, so all of them are disabled.
    if ([key isEqualToString:@"ios_tweet_promote_button_enabled"] ||
        [key isEqualToString:@"ios_tweet_promote_button_timeline_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_tweet_composer_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_overflow_menu_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_top_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_bottom_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_top_analytics_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_post_analytics_enabled"] ||
        [key
            isEqualToString:
                @"ios_tweet_promote_button_boost_again_in_top_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_sent_tweet_toast_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_third_party_boost_enabled"] ||
        [key isEqualToString:@"thirdparty_boost_author_view_button_enabled"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_upsells, @"Boost button off");
        return @NO;
    }

    // The Premium settings row is handled in the subscriptions hook below. Creator
    // purchases and the subscriber-only profile tab gate on real creator
    // eligibility, which the forced tier does not affect.

    // Creator Studio / Monetization entries gate purely on these switches with no
    // premium check, so follow the genuine status: a real subscriber keeps them
    // while the spoof hides them.
    if ([key isEqualToString:@"creator_studio_nav_enabled"] ||
        [key isEqualToString:@"creator_monetization_dashboard_enabled"]) {
        if (!AccountIsGenuinelyPremium()) {
            return @NO;
        }
    }

    return nil;
}

// Every feature switch facade but Chat's bottoms out in TFSFeatureSwitches, but instances
// can be wrapped in TFSInstrumentedFeatureSwitches, which implements its own
// typed getters, so both classes need the same hooks.

%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (id)rawValueForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (double)doubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

// Some reads, like the default captions setup, only consult the value when the
// switch reports a non-default one.
- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    return FeatureSwitchOverrideValueForKey(key) ? YES : %orig;
}

%end

%hook TFSInstrumentedFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (id)rawValueForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (double)doubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    return FeatureSwitchOverrideValueForKey(key) ? YES : %orig;
}

%end

// Chat's switches come from this store, which never asks TFSFeatureSwitches. Only
// the keys named here get the answers above.
static BOOL pfbChatStoreKey(NSString* key) {
    static NSSet<NSString*>* keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      keys = [NSSet setWithArray:@[
          @"xchat_cold_inbox_suggestions_enabled", @"xchat_cold_inbox_find_friends_enabled",
          @"xchat_voice_messages_transcription_enabled",
          @"xchat_liquid_glass_convo_header_enabled", @"xchat_ask_grok_enabled"
      ]];
    });
    return [keys containsObject:key];
}

%hook _TtC16XFeatureSwitches18FeatureSwitchStore

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = pfbChatStoreKey(key) ? FeatureSwitchOverrideValueForKey(key) : nil;
    return override ? override.boolValue : %orig;
}

%end

// MARK: - Typed feature switch accessors

%hook TFSAccountFeatureSwitches

// Sets the scroll indicator in -[TFNDataViewController loadView]; the read
// bypasses the boolForKey: funnels above via a Swift access-once provider.
+ (BOOL)isShowsVerticalScrollIndicatorEnabled {
    if ([PFBSettings boolForKey:@"show_scroll_indicator"]) {
        PFBCOMPAT_ACTION(PFBCompat_show_scroll_indicator, @"scroll bar shown");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_show_scroll_indicator, @"read by Twitter");
    return %orig;
}

// Premium row in Settings. Its own gate is on for everyone as an upsell, so %orig
// cannot hide it: the answer is short-circuited to NO unless the provider reports a
// genuinely premium account.
- (BOOL)isSubscriptionsSettingsItemEnabledWithProvider:(id)provider {
    if (![provider respondsToSelector:@selector(isPremiumTierUser)]) {
        return %orig;
    }

    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL genuinePremium =
        ((BOOL (*)(id, SEL))objc_msgSend)(provider, @selector(isPremiumTierUser));
    ReportGenuineSubscription = saved;

    if (!genuinePremium) {
        return NO;
    }
    return %orig;
}

// Custom navigation: tab gates read as typed accessors instead of through the
// keyed funnels, forced on like the keyed gates so their panels' entries build.
- (BOOL)birdwatchHomePageIsEnabled {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

- (BOOL)birdwatchHistoryIsEnabled {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

%end

// MARK: - Override the login screens

%hook T1AccountsViewController

- (void)private_startLoginFlowWithSender:(id)sender {
    PFBDebugLog(@"[login-entry] startLoginFlow -> web login presented");
    [PFBWebLoginViewController presentFrom:(UIViewController*)self];
    PFBCOMPAT_ACTION(PFBCompat_web_login, @"web login shown to add an account");
}

%end

%hook T1HostViewController

- (void)makeOnboardingViewControllerWithCompletion:(void (^)(id))completion {
    if (completion == nil) {
        %orig;
        return;
    }
    PFBDebugLog(@"[login-entry] makeOnboardingViewController -> web login as root");
    completion([PFBWebLoginViewController rootNavigationController]);
    PFBCOMPAT_ACTION(PFBCompat_web_login, @"web login shown signed out");
}

%end

// MARK: - High quality images

// Whether auto_highest_load is on. The Compatibility sheet counts an action when it
// is, and notes the read when it is not.
static BOOL pfbForcesHighestQuality(void) {
    if ([PFBSettings boolForKey:@"auto_highest_load"]) {
        PFBCOMPAT_ACTION(PFBCompat_auto_highest_load, @"best quality image");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_auto_highest_load, @"read by Twitter");
    return NO;
}

%hook T1ImageDisplayView

- (BOOL)_tfn_shouldUseHighestQualityImage {
    if (pfbForcesHighestQuality()) {
        return YES;
    }
    return %orig;
}

- (BOOL)_tfn_shouldUseHighQualityImage {
    if (pfbForcesHighestQuality()) {
        return YES;
    }
    return %orig;
}

%end

// MARK: - Promoted content

// Whether hide_promoted is on. The Compatibility sheet counts an action when it is,
// and notes the read when it is not.
static BOOL pfbHidesPromoted(void) {
    if ([PFBSettings boolForKey:@"hide_promoted"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_promoted, @"ad slot off");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_hide_promoted, @"read by Twitter");
    return NO;
}

// API commands copy this off their context when building requests.
%hook TFNTwitterAPICommandContext

- (BOOL)allowPromotedContent {
    if (pfbHidesPromoted()) {
        return NO;
    }
    return %orig;
}

%end

// MARK: - Account feature gates

// Whether disable_sensitive_tweet_warnings is on. The Compatibility sheet counts an
// action when it is, and notes the read when it is not.
static BOOL pfbSkipsSensitiveWarnings(void) {
    if ([PFBSettings boolForKey:@"disable_sensitive_tweet_warnings"]) {
        PFBCOMPAT_ACTION(PFBCompat_disable_sensitive_tweet_warnings, @"warning skipped");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_disable_sensitive_tweet_warnings, @"read by Twitter");
    return NO;
}

%hook TFNTwitterAccount

// Every account-level premium check funnels through -isSubscribedTo:
// (isPremiumTierUser checks tiers 0/7/8, isVerifiedPremiumTierUser 0/8), so
// forcing those tiers here unlocks premium from one stable seam.
- (BOOL)isSubscribedTo:(NSUInteger)tier {
    if (!ReportGenuineSubscription && (tier == 0 || tier == 7 || tier == 8)) {
        PFBCOMPAT_ACTION(PFBCompat_premium_unlock, @"premium tier granted");
        return YES;
    }
    return %orig;
}

// Part of Premium unlocked: the account's username editing gate answers yes.
- (BOOL)isEditProfileUsernameEnabled {
    return YES;
}

- (BOOL)isSensitiveTweetWarningsComposeEnabled {
    if (pfbSkipsSensitiveWarnings()) {
        return NO;
    }
    return %orig;
}

- (BOOL)isSensitiveTweetWarningsConsumeEnabled {
    if (pfbSkipsSensitiveWarnings()) {
        return NO;
    }
    return %orig;
}

- (BOOL)isAgeAssuranceAgeVerificationFlowEnabled {
    if ([PFBSettings boolForKey:@"bypass_age_verification"]) {
        PFBCOMPAT_ACTION(PFBCompat_bypass_age_verification, @"age check skipped");
        return NO;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_bypass_age_verification, @"read by Twitter");
    return %orig;
}

- (BOOL)isVideoDynamicAdEnabled {
    if (pfbHidesPromoted()) {
        return NO;
    }
    return %orig;
}

- (BOOL)isDoubleMaxZoomFor4KImagesEnabled {
    if (pfbForcesHighestQuality()) {
        return YES;
    }
    return %orig;
}

// Custom navigation: the Money tab's gate, granted per account/region by the
// server, forced on like the switch-keyed tab gates so the panel's entry
// builds.
- (BOOL)canAccessXPayments {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

%end

// The profile's Pay button asks for the viewer's Money access: it gets the real answer,
// so the gate forced above only offers the Money tab.
%hook T1ProfileUserViewModel

- (BOOL)hasAccessToPayments {
    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL access = %orig;
    ReportGenuineTabGates = saved;
    if (!access) {
        PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"profile Pay button follows the real Money access");
    }
    return access;
}

%end

// MARK: - Genuine subscription status

// A few paths report subscription status outward (to marketing) or expose real
// subscription management; run them against the genuine status so a forced
// unlock is never announced as premium.

%hook T1AppServicesManager

// Sets the account's tier as a Braze attribute on every activation.
- (id)_brazeTierStringForAccount:(id)account {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    id result = %orig;
    ReportGenuineSubscription = saved;
    return result;
}

%end

%hook T1TabbedAppNavigation

// Opens the real subscription management flow; its premium check should see the
// genuine status so a forced unlock stops here.
- (void)showPremiumHubManageSubscriptionWithSource:(NSInteger)source
                                    withCompletion:(id)completion {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    %orig;
    ReportGenuineSubscription = saved;
}

%end

%hook T1ProfileSummaryView

// The "under review" prompt shows for a verified-premium user not yet
// blue-verified — a state the forced tier fabricates for a non-subscriber, so
// read it against the genuine status.
- (BOOL)shouldShowUnderReviewButton {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL result = %orig;
    ReportGenuineSubscription = saved;
    return result;
}

%end

// MARK: - Custom navigation - genuine panel availability

// Whether a panel would be tab-eligible without the forced gates: the tab bar
// editor only offers genuine panels, and the dash spoof keeps the rest out of
// the drawer.

static id accountFeatureSwitches(void) {
    Class switchesClass = objc_getClass("TFSAccountFeatureSwitches");
    if (![(id)switchesClass
            respondsToSelector:@selector(lastUsedAccountFeatureSwitches)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(
        (id)switchesClass, @selector(lastUsedAccountFeatureSwitches));
}

static BOOL genuineTabGateFlag(id receiver, SEL selector) {
    if (![receiver respondsToSelector:selector]) {
        return NO;
    }

    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
    ReportGenuineTabGates = saved;
    return value;
}

static id featureSwitchesProvider(void) {
    id accountSwitches = accountFeatureSwitches();
    if (![accountSwitches respondsToSelector:@selector(provider)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(accountSwitches, @selector(provider));
}

static BOOL genuineSwitchBool(NSString* key) {
    id provider = featureSwitchesProvider();
    if (![provider respondsToSelector:@selector(boolForKey:)]) {
        return NO;
    }

    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL value = ((BOOL (*)(id, SEL, NSString*))objc_msgSend)(
        provider, @selector(boolForKey:), key);
    ReportGenuineTabGates = saved;
    return value;
}

BOOL PFBPanelIsGenuinelyAvailable(long long panelID) {
    switch (panelID) {
        case 13: { // Community Notes
            id switches = accountFeatureSwitches();
            return genuineTabGateFlag(switches,
                                      @selector(birdwatchHomePageIsEnabled)) &&
                   genuineTabGateFlag(switches, @selector(birdwatchHistoryIsEnabled));
        }
        case 15: // Premium hub
            return genuineSwitchBool(@"subscriptions_premium_hub_enabled");
        case 16: // Jobs
            return genuineSwitchBool(@"recruiting_global_jobs_hub_enabled") ||
                   genuineSwitchBool(@"recruiting_jetfuel_jobs_hub_enabled");
        case 17: { // Money
            id hostClass = (id)objc_getClass("T1HostViewController");
            if (![hostClass respondsToSelector:@selector(sharedHostViewController)]) {
                return NO;
            }
            id host = ((id (*)(id, SEL))objc_msgSend)(hostClass, @selector(sharedHostViewController));
            if (![host respondsToSelector:@selector(currentAccount)]) {
                return NO;
            }
            id account =
                ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
            return genuineTabGateFlag(account, @selector(canAccessXPayments));
        }
        default: // Panels the app builds, or the unlock enables, for everyone
            return YES;
    }
}

// MARK: - Custom navigation - side drawer rows

// The drawer builds a row for each panel absent from the tab bar, from a snapshot
// taken in updateVisiblePanelIDs. Extra panels are injected only there, scoped by a
// flag, so other readers see the real tab state.

static __thread BOOL DashPanelIDQuery = NO;

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    DashPanelIDQuery = YES;
    %orig;
    DashPanelIDQuery = NO;
}

%end

BOOL PFBDashAnswerApplies(void) {
    return DashPanelIDQuery;
}

// The last answer given to the drawer and when, read by the app return probe.
static NSString* gPFBDashFacts;
static CFTimeInterval gPFBDashFactsAt;

NSString* PFBDashPanelFacts(void) {
    return gPFBDashFacts ? [NSString stringWithFormat:@"%@, %.1f s before", gPFBDashFacts,
                                                      CACurrentMediaTime() - gPFBDashFactsAt]
                         : @"never asked";
}

// The tab bar's panels as the drawer reads them, with the panels it must not offer.
static NSArray* PFBDashPanelIDs(NSArray* panelIDs) {
    if (![panelIDs isKindOfClass:[NSArray class]]) {
        return panelIDs;
    }
    NSMutableArray* spoofed = [panelIDs mutableCopy];
    void (^claim)(NSNumber*) = ^(NSNumber* panelID) {
        if (![spoofed containsObject:panelID]) {
            [spoofed addObject:panelID];
        }
    };

    NSMutableArray<NSNumber*>* unavailable = [NSMutableArray array];
    for (NSNumber* panelID in @[@13, @15, @16, @17]) {
        if (!PFBPanelIsGenuinelyAvailable(panelID.longLongValue)) {
            claim(panelID);
            [unavailable addObject:panelID];
        }
    }

    if ([PFBSettings boolForKey:@"hide_grok_sidebar"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_grok_sidebar, @"Grok panel hidden");
        claim(@14);
    } else {
        PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_sidebar, @"Grok panel found");
    }

    BOOL premium = AccountIsGenuinelyPremium();
    if (!premium) {
        claim(@15);
    }

    gPFBDashFacts = [NSString
        stringWithFormat:@"Twitter gave [%@], PrimeFreeBird gave [%@] (not genuinely available [%@], Grok hidden %@, "
                         @"Premium %@)",
                         [panelIDs componentsJoinedByString:@", "], [spoofed componentsJoinedByString:@", "],
                         [unavailable componentsJoinedByString:@", "],
                         [PFBSettings boolForKey:@"hide_grok_sidebar"] ? @"yes" : @"no", premium ? @"yes" : @"no"];
    gPFBDashFactsAt = CACurrentMediaTime();
    return spoofed;
}

%hook T1TabbedAppNavigationViewController

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    NSArray* panelIDs = %orig;
    return DashPanelIDQuery ? PFBDashPanelIDs(panelIDs) : panelIDs;
}

%end

@interface _TtC14T1TwitterSwift20XTabbedAppNavigation : NSObject
- (NSArray*)visiblePanelIDs;
@end

// Twitter's native glass navigation answers the drawer itself. Its list also gives the
// Customize tabs editor Twitter's panels; the glass bar is built from Twitter's own tab
// settings, not from this list.
%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (NSArray*)visiblePanelIDs {
    NSArray* panelIDs = %orig;
    if (DashPanelIDQuery) {
        return PFBDashPanelIDs(panelIDs);
    }
    [PFBCustomTabBarUtility recordPanelIDs:panelIDs];
    return panelIDs;
}

%end

// MARK: - Grok creation - photo editor

// The photo editor's Edit with Grok entry has no feature switch of its own;
// both delegates hardcode YES.

// Whether hide_grok_create is on. The Compatibility sheet counts an action when it
// is, and notes the read when it is not.
static BOOL pfbHidesGrokCreate(void) {
    if ([PFBSettings boolForKey:@"hide_grok_create"]) {
        PFBCOMPAT_ACTION(PFBCompat_hide_grok_create, @"Grok creation tool off");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_hide_grok_create, @"read by Twitter");
    return NO;
}

%hook T1TweetComposeViewController

- (BOOL)photoEditorCanEditWithGrok:(id)photoEditor {
    if (pfbHidesGrokCreate()) {
        return NO;
    }
    return %orig;
}

%end

%hook T1StatusPhotoEditorHandler

- (BOOL)photoEditorCanEditWithGrok:(id)photoEditor {
    if (pfbHidesGrokCreate()) {
        return NO;
    }
    return %orig;
}

%end

// MARK: - Grok creation - buttons without a switch

// The Imagine button under posts, the create-your-own button and the immersive
// player's create-your-own pill read no switch: their own visibility is turned down.
%hook T1StandardStatusDownloadGrokImagineButtonViewAdapter

- (BOOL)shouldBeVisibleForViewModel:(id)viewModel {
    PFBCompatReach(PFBCompatPath_grok_imagine_button);
    if (pfbHidesGrokCreate()) {
        return NO;
    }
    return %orig;
}

%end

%hook T1StandardStatusGrokCreateOwnButtonAdapter

- (BOOL)shouldBeVisibleForViewModel:(id)viewModel {
    PFBCompatReach(PFBCompatPath_grok_create_own_button);
    if (pfbHidesGrokCreate()) {
        return NO;
    }
    return %orig;
}

%end

%hook _TtC14T1TwitterSwift36ImmersiveShimmerPillButtonPluginView

- (void)layoutSubviews {
    %orig;
    PFBCompatReach(PFBCompatPath_grok_create_own_pill);
    if (pfbHidesGrokCreate()) {
        ((UIView*)self).hidden = YES;
    }
}

%end

// MARK: - Sensitive media warnings

%hook TFNTwitterStatus

- (BOOL)hasImageInterstitial {
    if (pfbSkipsSensitiveWarnings()) {
        return NO;
    }
    return %orig;
}

- (id)imageInterstitial {
    if (pfbSkipsSensitiveWarnings()) {
        return nil;
    }
    return %orig;
}

- (id)innerImageInterstitial {
    if (pfbSkipsSensitiveWarnings()) {
        return nil;
    }
    return %orig;
}

%end

%hook HFHealthSafetyFeature

+ (BOOL)isTweetMedialInterstitialEnabled:(id)featureSwitches {
    if (pfbSkipsSensitiveWarnings()) {
        return NO;
    }
    return %orig;
}

%end

// MARK: - Video upload quality

// Full-HD uploads are gated by three getters on two classes; answering yes to all
// three lets the composer send 1080p instead of the compressed default.

// Whether upload_full_hd_videos is on. The Compatibility sheet counts an action when
// it is, and notes the read when it is not.
static BOOL pfbAllowsFullHDUpload(void) {
    if ([PFBSettings boolForKey:@"upload_full_hd_videos"]) {
        PFBCOMPAT_ACTION(PFBCompat_upload_full_hd_videos, @"Full HD upload allowed");
        return YES;
    }
    PFBCOMPAT_OBSERVE(PFBCompat_upload_full_hd_videos, @"read by Twitter");
    return NO;
}

%hook T1VideoQualityUploadSettings

- (BOOL)shouldAllowFullHdVideoUpload:(long long)upload {
    if (pfbAllowsFullHDUpload()) {
        return YES;
    }
    return %orig;
}

%end

%hook T1LongerVideoUploadEnabledConfig

- (BOOL)isUploadFullHDVideoEnabled {
    if (pfbAllowsFullHDUpload()) {
        return YES;
    }
    return %orig;
}

- (BOOL)isUploadFullHDVideoEnabledByDefault {
    if (pfbAllowsFullHDUpload()) {
        return YES;
    }
    return %orig;
}

%end
