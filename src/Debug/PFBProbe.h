// The measurement probe: each measurement is noted once per PrimeFreeBird build, kept
// across launches and printed in the report's PROBE section, numbered as the probe's
// twelve questions. Inert unless debug_tools is on.

#import <UIKit/UIKit.h>

// Whether a key has not been noted yet on this build. Cheap enough for hot paths.
FOUNDATION_EXPORT BOOL PFBProbeWants(NSString* key);
// Notes a line under the key, once per build; a tour step in front is named with it.
FOUNDATION_EXPORT void PFBProbeNote(NSString* key, NSString* format, ...) NS_FORMAT_FUNCTION(2, 3);
// The report's PROBE section.
FOUNDATION_EXPORT NSString* PFBProbeReportText(void);

// The tour step whose screen is up, read on the main thread (PFBCompatibilityTour.m).
FOUNDATION_EXPORT NSString* PFBProbeTourStep(void);
// "absent", "hidden" or "shown": the stethoscope's state (PFBDebugger.m).
FOUNDATION_EXPORT NSString* PFBProbeTriggerState(void);

// 1. Each timeline once: its scribe section, whether Home holds it, so whether the
// reading marker can show there.
FOUNDATION_EXPORT BOOL PFBProbeTimelineWanted(UIViewController* timeline);
FOUNDATION_EXPORT void PFBProbeTimeline(UIViewController* timeline, BOOL inHome, BOOL followingSection);

// 2. Chronological replies switched for one conversation of the tour, then put back;
// a tour Twitter closed meanwhile puts it back at the next launch.
FOUNDATION_EXPORT void PFBProbeSwitchReplySorting(void);
FOUNDATION_EXPORT void PFBProbeRestoreReplySorting(NSString* when);
FOUNDATION_EXPORT void PFBProbeRestoreAtLaunch(void);
// Each answer given to Twitter's reply_sorting_enabled, once.
FOUNDATION_EXPORT void PFBProbeReplySortingRead(BOOL answer);

// 3. What Explore and search lists carry: item class, ad location, place in the list.
FOUNDATION_EXPORT void PFBProbeExploreSections(UIViewController* timeline, NSArray* sections, NSString* location);

// 4. Voice notes: the media files opened, the audio view, the long-press menu's answer.
FOUNDATION_EXPORT void PFBProbeAsset(NSURL* url, BOOL keptAsVoiceNote);
FOUNDATION_EXPORT void PFBProbeVoiceView(BOOL voiceFileKnown);
FOUNDATION_EXPORT void PFBProbeVoiceMenu(BOOL offered);

// 5. Each screen where Twitter shows an author row's Follow button.
FOUNDATION_EXPORT void PFBProbeFollowControl(UIView* authorRow, BOOL hidden);

// 7. The video feed's two counts, before and after promoted cards are removed.
FOUNDATION_EXPORT void PFBProbeVideoFeed(long long listCount, long long navigatorCount, long long loadedEnd,
                                         long long firstPromoted, BOOL enabled);
FOUNDATION_EXPORT void PFBProbeVideoFeedEdited(long long listBefore, long long listAfter, long long navigatorBefore,
                                               long long navigatorAfter);

// 8. A new image Twitter sets on a bar icon PrimeFreeBird repaints.
FOUNDATION_EXPORT void PFBProbeBarIcon(UIView* view, UIImage* original, UIImage* incoming);
FOUNDATION_EXPORT void PFBProbeBarItem(UIImage* incoming);

// 9. The psst decision at a finger's release, against the refresh Twitter starts.
FOUNDATION_EXPORT void PFBProbePullReleased(UIScrollView* list, BOOL psst);
FOUNDATION_EXPORT void PFBProbeRefreshStarted(void);

// 10. A Filters button replaced by the advanced search one, and on which screen; each
// navigation item once, with what made it match.
FOUNDATION_EXPORT void PFBProbeAdvancedSearch(UIViewController* owner, UINavigationItem* item, BOOL searchScreen,
                                              NSString* (^match)(void));
