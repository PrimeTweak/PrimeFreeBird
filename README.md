<div align="center">
    <img src="icon_rounded.png" alt="PrimeFreeBird" width="130" height="130">

  # PrimeFreeBird
  <i>A Twitter/X tweak.</i>

</div>

<br>

| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|<img width="1604" alt="Screenshot 1" src="1.png">|<img width="1604" alt="Screenshot 2" src="2.png">|<img width="1604" alt="Screenshot 3" src="3.png">|

<sub>Everything below is new in this fork, on top of NeoFreeBird.</sub>

# What's new

## Liquid Glass

- **Liquid Glass, enabled** — the stock app opts out of iOS 26's redesign; this switches it back on, or keeps the flat look.
- **No blurred edge** — the redesign makes iOS draw a strip under every bar; a switch puts the stock look back.
- **Bar icons that match** — the settings gear, the search filters and the muted-words icon share one grey and keep it.

## Colour theme

- **Any colour you want** — a *Custom accent colour* row opens the native iOS picker instead of a fixed set of presets.
- **Applied everywhere** — the bird, links, @mentions, #hashtags, buttons and the settings switches all follow it.
- **Predictable reset** — resetting returns to stock and stays there, across restarts and re-picks.
- **Dark shades** — choose System, Dim, Gray or Blackout for Twitter's dark backgrounds.

## Explore &amp; search

- **Per-tab control** — hide any of For You, Trending, News, Sports or Entertainment, rather than the whole page.
- **Advanced search** — X ships this form on the web only; here it is native, with results in Twitter's own search.

## Muted words

- **One list for everything** — a word, a phrase or an @account; the type is recognised from what you type.
- **Quick access from the feed** — an icon in the timeline's top bar adds or removes a filter without leaving your scroll.
- **Filters that expire** — give a word 24 hours, 7 days or 30 days, or keep it for good.
- **Precise by default** — whole-word matching, so "cat" never catches "concatenate".
- **Scope you decide** — filter replies inside conversations too, spare the people you follow, and choose whether reposts count.
- **A quiet tally** — the page keeps a small count of what it filtered out today.

## Timeline

- **Unlimited timeline tabs** — pin far more lists and topics than X allows, and unlock advanced tabs like Ranked Following.
- **Hide topics** — topic posts and the "Topics to follow" carousel both go.
- **Open in Following** — start on the Following tab instead of For You, and stay there.
- **Preload media** — images and videos are ready the moment you scroll to them.
- **Clean screenshots** — an on/off switch for Twitter's screenshot detection.

## Media

- **Full HD uploads** — send your own videos in 1080p.
- **Tap to pause** — tap a video to stop it, rather than reaching for the button.
- **No mini player** — full-screen videos no longer shrink into a floating player when you drag them away.

## Tweets

- **Poll results before voting** — each option carries its share of the vote, so you can read a poll without joining it.
- **Hide the Tweet button** — remove the compose button from the timeline.
- **Classic compose button** — or bring back the bird on a coloured circle instead of the native "+".

## Profiles

- **Bios in full** — long bios open expanded, with no *Show more* to tap.
- **Open profiles where you want** — land on Replies, Highlights, Articles, Media, Videos or Reposts instead of Posts.
- **Hide the Videos tab** — alongside the existing switches for Articles and Highlights.
- **Profile URL** — added to the copy-profile-details button.

## Reply in Web View

- **One-time web login** — sign in once in Settings → Lab; the session is saved on-device and cleared in one tap.
- **Native icon bar** — the composer's toolbar is a real iOS bar that follows the keyboard.

## Elsewhere

- **Grouped settings** — every page is split into labelled groups instead of one long list.
- **Clean shared links** — tracking parameters stripped when you copy *or* share, profiles included.
- **Full French localization** — every string, including the new screens.

# Fixes

- **Tab labels are centred** — restored labels no longer sit off-centre after a cold launch.
- **The video timestamp shows up** — the option now actually reveals the elapsed time in full-screen videos.
- **"Open in Following" is honoured** — the setting was silently overridden; the tab you pick survives a new session.
- **No black frame at launch** — the splash dissolves into the timeline instead of cutting to an empty window.
- **Pull-to-refresh sound works again** — rebuilt for current Twitter versions, where the old hook no longer exists.
- **Reply composer sits still** — no keyboard bounce, no doubled insets, no login wall.
- **The settings sheet has a real header** — under Liquid Glass the list showed through beside the search field; the header is a solid bar again, down past the field.

<sub>…on top of the full BHTwitter and NeoFreeBird toolkit.</sub>

# Credits

- [**BHTwitter**](https://github.com/BandarHL/BHTwitter) by BandarHL — the foundation this is built on.
- The [**NeoFreeBird**](https://github.com/NeoFreeBird) project — the base this fork tracks.
- [**scar**](https://github.com/theacrat/scar) by theacrat — the fixes pipeline.
