//
//  DiagProbe.x
//  PrimeFreeBird
//
//  TEMPORARY, READ-ONLY probe. It changes no behaviour: every hook returns
//  %orig untouched and nothing is added to, removed from or reordered in any
//  view. Delete this file once both questions below are answered.
//
//  Question A -- which value separates the "For you" tab from "Following"?
//
//    Timeline.x guards the reading marker with NFBReadingLooksLikeForYou,
//    which walks the responder chain for a class name containing "ForYou".
//    A full sweep of the binaries finds 14 such classes out of 19666, all of
//    them GraphQL model types; none can appear in a responder chain. The
//    guard therefore never returns YES and the marker is allowed on "For
//    you", which is what shows up after a refresh.
//
//    THFHomeTimelineItemsViewController exposes -scribePage, -scribeSection
//    and -timeline. One line per tab names the replacement discriminator.
//
//  Question B -- how does the native empty state sit on the Mentions tab?
//
//    The custom empty state is currently pinned to the controller view and
//    stays centred. The native one is to be imitated, so what matters is the
//    class it uses, the view it is attached to, and whether that view sits
//    inside the scroll view -- which is what makes it move with the list.
//

#import "HookHelpers.h"
#import "Debug/NFBDebugger.h"

// Declaration shim used as a cast target for selectors that are not declared
// in src/Headers. Never instantiated, never messaged as a class, so no class
// symbol is referenced.
@interface NFBProbeTimelineShim : NSObject
- (NSString*)scribePage;
- (NSString*)scribeSection;
- (id)timeline;
@end

// Deduplication: a layout pass fires many times per second, and only distinct
// readings carry information.
static NSMutableSet* NFBProbeSeen(void) {
    static NSMutableSet* seen = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        seen = [[NSMutableSet alloc] init];
    });
    return seen;
}

static BOOL NFBProbeFirstTime(NSString* key) {
    if (key.length == 0) {
        return NO;
    }
    NSMutableSet* seen = NFBProbeSeen();
    @synchronized (seen) {
        if ([seen containsObject:key]) {
            return NO;
        }
        if (seen.count > 200) {
            [seen removeAllObjects];
        }
        [seen addObject:key];
    }
    return YES;
}

static NSString* NFBProbeShort(id value) {
    if (!value) {
        return @"nil";
    }
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    NSString* text = [NSString stringWithFormat:@"%@<%@>",
                      NSStringFromClass([value class]), [value description]];
    if (text.length > 90) {
        text = [[text substringToIndex:90] stringByAppendingString:@"..."];
    }
    return text;
}

// MARK: - Question A: For you versus Following

static void NFBProbeReportTimeline(UIViewController* controller, NSString* moment) {
    NSString* page = nil;
    NSString* section = nil;
    id timeline = nil;
    NFBProbeTimelineShim* shim = (NFBProbeTimelineShim*)controller;
    if ([controller respondsToSelector:@selector(scribePage)]) {
        page = NFBProbeShort([shim scribePage]);
    }
    if ([controller respondsToSelector:@selector(scribeSection)]) {
        section = NFBProbeShort([shim scribeSection]);
    }
    if ([controller respondsToSelector:@selector(timeline)]) {
        timeline = [shim timeline];
    }
    NSString* line = [NSString stringWithFormat:
        @"[tab] page=%@ section=%@ timeline=%@",
        page ?: @"(none)", section ?: @"(none)", NFBProbeShort(timeline)];
    if (NFBProbeFirstTime(line)) {
        NFBDebugLog(@"%@ (%@)", line, moment);
    }

    // The responder chain is logged once per distinct shape so a class-name
    // based discriminator can be ruled in or out on evidence.
    NSMutableArray* chain = [NSMutableArray array];
    UIResponder* responder = controller;
    while ((responder = responder.nextResponder) && chain.count < 10) {
        [chain addObject:NSStringFromClass([responder class])];
        if ([responder isKindOfClass:[UIWindow class]]) {
            break;
        }
    }
    NSString* chainLine = [NSString stringWithFormat:@"[tab] chain=%@",
                           [chain componentsJoinedByString:@" > "]];
    if (NFBProbeFirstTime(chainLine)) {
        NFBDebugLog(@"%@", chainLine);
    }
}

%hook THFHomeTimelineItemsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        NFBProbeReportTimeline(self, @"appear");
    } @catch (id exception) {
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView*)scrollView {
    %orig;
    @try {
        NFBProbeReportTimeline(self, @"settle");
    } @catch (id exception) {
    }
}

%end

// MARK: - Question B: the notifications empty state

// First scroll view in the mounted hierarchy. Reading subviews forces no
// layout and builds nothing.
static UIScrollView* NFBProbeFindList(UIView* root) {
    if (!root) {
        return nil;
    }
    NSMutableArray* stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView* view = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([view isKindOfClass:[UIScrollView class]]) {
            return (UIScrollView*)view;
        }
        for (UIView* child in view.subviews) {
            [stack addObject:child];
        }
    }
    return nil;
}

static BOOL NFBProbeInsideScrollView(UIView* view) {
    UIView* parent = view.superview;
    while (parent) {
        if ([parent isKindOfClass:[UIScrollView class]]) {
            return YES;
        }
        parent = parent.superview;
    }
    return NO;
}

// Walks the mounted hierarchy. Nothing is instantiated and no layout is
// forced: only subviews and frames are read.
static void NFBProbeScanEmptyState(UIView* root, NSString* screen) {
    if (!root) {
        return;
    }
    NSMutableArray* stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView* view = stack.lastObject;
        [stack removeLastObject];
        NSString* name = NSStringFromClass([view class]);
        if ([name containsString:@"EmptyState"] || [name containsString:@"Placeholder"]) {
            NSString* line = [NSString stringWithFormat:
                @"[empty] %@ on %@ | parent=%@ | scrolls=%@ | frame=%.0fx%.0f@%.0f",
                name, screen,
                view.superview ? NSStringFromClass([view.superview class]) : @"nil",
                NFBProbeInsideScrollView(view) ? @"YES" : @"NO",
                view.bounds.size.width, view.bounds.size.height, view.frame.origin.y];
            if (NFBProbeFirstTime(line)) {
                NFBDebugLog(@"%@", line);
            }
        }
        for (UIView* child in view.subviews) {
            [stack addObject:child];
        }
    }
}

%hook TFNItemsDataViewController

- (void)viewDidLayoutSubviews {
    %orig;
    @try {
        NSString* screen = NSStringFromClass([self class]);
        if (![screen containsString:@"Notification"] &&
            ![screen containsString:@"Mention"]) {
            return;
        }
        // A layout pass fires many times per second. Only a near-empty list is
        // of interest here, and at most once per second.
        if (self.sections.count > 1) {
            return;
        }
        static NSTimeInterval last = 0;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - last < 1.0) {
            return;
        }
        last = now;
        // The -tableView accessor is a lazy getter that builds the view; calling
        // it speculatively has crashed this tweak before. The mounted
        // hierarchy is searched instead.
        UIScrollView* list = NFBProbeFindList(self.view);
        NSString* geometry = [NSString stringWithFormat:
            @"[empty] %@ | sections=%lu | content=%.0f | inset=%.0f",
            screen, (unsigned long)self.sections.count,
            list ? list.contentSize.height : -1.0,
            list ? list.adjustedContentInset.top : -1.0];
        if (NFBProbeFirstTime(geometry)) {
            NFBDebugLog(@"%@", geometry);
        }
        NFBProbeScanEmptyState(self.view, screen);
    } @catch (id exception) {
    }
}

%end

%ctor {
    NFBDebugLog(@"[probe] tab discriminator and empty state probe armed");
}
