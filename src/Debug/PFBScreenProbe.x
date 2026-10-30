// Screen by screen, once it has settled and at each capture: the bar Twitter keeps above Home
// for Spaces and live games, the blur iOS draws under the top bars, the notifications list as
// the hide code reads it, and the Suggested part of the Chat inbox. Menus: any Imagine entry.
// On Notifications, each frame of a pull or a refresh: the list, its rows and the empty panel.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBGameBarTopic = @"game bar";
static const NSUInteger kPFBGameBarLines = 16;
static NSString* const kPFBTopBlurTopic = @"top bar blur";
static const NSUInteger kPFBTopBlurLines = 25;
static NSString* const kPFBNotifRowTopic = @"notification rows";
static const NSUInteger kPFBNotifRowLines = 20;
static NSString* const kPFBSuggestedTopic = @"suggested chats";
static const NSUInteger kPFBSuggestedLines = 8;
static NSString* const kPFBImagineTopic = @"imagine entries";
static const NSUInteger kPFBImagineLines = 12;
// The top bars and the lists' top edges sit above this line.
static const CGFloat kPFBTopArea = 200.0;

static NSUInteger gPFBScreenGeneration;
static __weak id gPFBFleetAccessory;

static UIWindow* PFBProbeKeyWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return nil;
}

// The opacity a view shows with: zero when it or a parent is hidden, mid-animation values included.
CGFloat PFBShownOpacity(UIView* view) {
    CGFloat shown = 1.0;
    for (UIView* node = view; node; node = node.superview) {
        if (node.hidden) {
            return 0.0;
        }
        CALayer* presented = node.layer.presentationLayer;
        shown *= node.alpha * (presented ? presented.opacity : node.layer.opacity);
    }
    return shown;
}

// MARK: - Spaces and live game bar

@interface _TtC14T1TwitterSwift28FleetLineAccessoryController : NSObject
@end

static NSString* PFBGameBarOption(void) {
    return [PFBSettings boolForKey:@"hide_spaces"] ? @"Hide Spaces bar on" : @"Hide Spaces bar off";
}

static void PFBGameBarNote(NSString* line) {
    PFBCompatMeasure(kPFBGameBarTopic, [NSString stringWithFormat:@"%@ (%@)", line, PFBGameBarOption()],
                     kPFBGameBarLines);
}

// The bar's view as it shows: where it sits, how it is hidden, its items, and its parent's room.
static void PFBGameBarLook(NSString* moment) {
    id controller = gPFBFleetAccessory;
    Ivar ivar = controller ? class_getInstanceVariable(object_getClass(controller), "fleetLineView") : NULL;
    UIView* view = ivar ? object_getIvar(controller, ivar) : nil;
    if (!controller) {
        return;
    }
    if (![view isKindOfClass:[UIView class]]) {
        PFBGameBarNote([NSString stringWithFormat:@"%@: no bar view yet", moment]);
        return;
    }
    // Other screens are judged at a capture only; a settled screen counts when the bar is on it.
    if (!view.window && ![moment isEqualToString:@"at capture"]) {
        return;
    }
    __block NSInteger items = -1;
    PFBWalkAllSubviews(view, 3, ^(UIView* sub) {
      if (items < 0 && [sub isKindOfClass:[UICollectionView class]]) {
          UICollectionView* list = (UICollectionView*)sub;
          items = list.numberOfSections > 0 ? [list numberOfItemsInSection:0] : 0;
      }
    });
    CGRect frame = view.window ? [view convertRect:view.bounds toView:nil] : CGRectNull;
    UIView* parent = view.superview;
    PFBGameBarNote([NSString
        stringWithFormat:@"%@: %@ %@, frame %@, shown at %.2f, %ld items; in %@ %.0f pt high", moment,
                         PFBReadableClassName(view), view.window ? @"on screen" : @"off screen",
                         CGRectIsNull(frame) ? @"none"
                                             : [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", frame.origin.x,
                                                                          frame.origin.y, frame.size.width,
                                                                          frame.size.height],
                         PFBShownOpacity(view), (long)items, parent ? PFBReadableClassName(parent) : @"no parent",
                         CGRectGetHeight(parent.bounds)]);
}

%hook _TtC14T1TwitterSwift28FleetLineAccessoryController

- (BOOL)isHidden {
    BOOL hidden = %orig;
    gPFBFleetAccessory = self;
    static NSInteger last = -1;
    if (last != hidden) {
        last = hidden;
        PFBGameBarNote([NSString stringWithFormat:@"Twitter asked: hidden %@", hidden ? @"yes" : @"no"]);
    }
    return hidden;
}

- (UIView*)accessoryView {
    UIView* view = %orig;
    gPFBFleetAccessory = self;
    static NSInteger last = -1;
    if (last != (view != nil)) {
        last = view != nil;
        PFBGameBarNote([NSString stringWithFormat:@"Twitter asked: view %@", view ? PFBReadableClassName(view) : @"none"]);
    }
    return view;
}

- (void)attachToViewController:(UIViewController*)controller {
    %orig;
    gPFBFleetAccessory = self;
    PFBGameBarNote([NSString stringWithFormat:@"attached to %@", controller ? PFBReadableClassName(controller) : @"nothing"]);
}

%end

// MARK: - Top bar blur

// One line per screen, visual style and option: the iOS blur views at the top and how much
// of them shows, the lists whose top effect is on or off, and Twitter's own edges.
static void PFBTopBlurLook(NSString* screen) {
    UIWindow* window = PFBProbeKeyWindow();
    if (!window) {
        return;
    }
    NSString* style = [PFBSettings boolForKey:@"enable_liquid_glass"] ? @"Liquid Glass" : @"Standard";
    NSString* option = [PFBSettings boolForKey:@"hide_scroll_edge_blur"] ? @"on" : @"off";
    static NSMutableSet<NSString*>* seen;
    if (!seen) {
        seen = [NSMutableSet set];
    }
    NSString* key = [NSString stringWithFormat:@"%@|%@|%@", screen, style, option];
    if ([seen containsObject:key]) {
        return;
    }
    [seen addObject:key];
    __block NSUInteger blurs = 0, shown = 0, effectOn = 0, effectOff = 0, edges = 0;
    NSMutableArray<NSString*>* details = [NSMutableArray array];
    PFBWalkAllSubviews(window, 40, ^(UIView* view) {
      NSString* name = NSStringFromClass([view class]);
      CGRect frame = [view convertRect:view.bounds toView:nil];
      if ([name containsString:@"ScrollEdgeEffectView"] && ![name containsString:@"Backdrop"]) {
          if (CGRectGetMinY(frame) > kPFBTopArea || !CGRectIntersectsRect(frame, window.bounds)) {
              return;
          }
          blurs++;
          CGFloat opacity = PFBShownOpacity(view);
          if (opacity > 0.05 && CGRectGetHeight(frame) > 1.0) {
              shown++;
          }
          if (details.count < 4) {
              [details addObject:[NSString stringWithFormat:@"%.2f over %.0f pt", opacity, CGRectGetHeight(frame)]];
          }
      } else if ([name containsString:@"ScrollEdgeTreatment"]) {
          edges++;
      } else if ([view isKindOfClass:[UIScrollView class]] && CGRectGetMinY(frame) < kPFBTopArea &&
                 CGRectGetHeight(frame) > 200.0 && CGRectIntersectsRect(frame, window.bounds) &&
                 [view respondsToSelector:@selector(topEdgeEffect)]) {
          id effect = ((id (*)(id, SEL))objc_msgSend)(view, @selector(topEdgeEffect));
          if ([effect respondsToSelector:@selector(isHidden)]) {
              BOOL hidden = ((BOOL (*)(id, SEL))objc_msgSend)(effect, @selector(isHidden));
              if (hidden) {
                  effectOff++;
              } else {
                  effectOn++;
              }
          }
      }
    });
    PFBCompatMeasure(kPFBTopBlurTopic,
                     [NSString stringWithFormat:@"%@ · %@ · option %@: iOS blur seen %lu of %lu [%@] · lists with "
                                                @"the iOS top effect on %lu, off %lu · Twitter edges %lu",
                                                screen, style, option, (unsigned long)shown, (unsigned long)blurs,
                                                [details componentsJoinedByString:@"; "], (unsigned long)effectOn,
                                                (unsigned long)effectOff, (unsigned long)edges],
                     kPFBTopBlurLines);
}

// MARK: - Notification rows

// The first dismiss button in the row's top right, where Twitter puts its own.
static UIButton* PFBNotifTopRightButton(UITableViewCell* cell) {
    Class dismiss = NSClassFromString(@"TFNDismissButton");
    __block UIButton* found = nil;
    PFBWalkAllSubviews(cell, 10, ^(UIView* view) {
      if (found || !dismiss || ![view isKindOfClass:dismiss]) {
          return;
      }
      CGRect frame = [view convertRect:view.bounds toView:cell];
      if (CGRectGetMidX(frame) > CGRectGetMidX(cell.bounds) && CGRectGetMinY(frame) < 60.0) {
          found = (UIButton*)view;
      }
    });
    return found;
}

static NSString* PFBNotifGlyphText(UIButton* button) {
    if (!button) {
        return @"no button";
    }
    UIImage* image = [button imageForState:UIControlStateNormal];
    NSString* what = PFBNotifIsCrossImage(image) ? @"the hide cross"
                     : image ? [NSString stringWithFormat:@"Twitter's glyph %.0fx%.0f", image.size.width, image.size.height]
                             : @"no image";
    return [NSString stringWithFormat:@"%@%@%@", what, button.hidden || button.alpha < 0.05 ? @", hidden" : @"",
                                      button.accessibilityLabel.length
                                          ? [NSString stringWithFormat:@", labeled \"%@\"", button.accessibilityLabel]
                                          : @""];
}

static void PFBNotifRowsLook(UIViewController* screen) {
    UIWindow* window = screen.viewIfLoaded.window;
    if (!window) {
        return;
    }
    NSString* option = [PFBSettings boolForKey:@"hide_notifications"] ? @"on" : @"off";
    PFBWalkAllSubviews(screen.view, 20, ^(UIView* view) {
      if (![view isKindOfClass:[UITableView class]]) {
          return;
      }
      UITableView* table = (UITableView*)view;
      if (!CGRectIntersectsRect([table convertRect:table.bounds toView:nil], window.bounds)) {
          return;
      }
      for (NSIndexPath* indexPath in table.indexPathsForVisibleRows) {
          UITableViewCell* cell = [table cellForRowAtIndexPath:indexPath];
          if (!cell || CGRectGetHeight(cell.bounds) < 30.0) {
              continue;
          }
          PFBCompatMeasure(kPFBNotifRowTopic,
                           [NSString stringWithFormat:@"%@ · %@ · top right: %@ (option %@)",
                                                      PFBReadableClassName(cell), PFBNotifRowFacts(table, indexPath),
                                                      PFBNotifGlyphText(PFBNotifTopRightButton(cell)), option],
                           kPFBNotifRowLines);
      }
    });
}

// MARK: - Suggested chats

// Chat's own wording in the app's language, with the brand "X" left out so a renamed one matches.
static NSString* PFBChatText(NSString* key) {
    static NSBundle* bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSString* path = [NSBundle.mainBundle pathForResource:@"ChatCore_ChatStrings" ofType:@"bundle"];
      bundle = path ? [NSBundle bundleWithPath:path] : nil;
    });
    NSString* text = [bundle localizedStringForKey:key value:nil table:nil];
    if (!text.length || [text isEqualToString:key]) {
        return nil;
    }
    NSRegularExpression* brand = [NSRegularExpression regularExpressionWithPattern:@"\\bX\\b" options:0 error:nil];
    text = [brand stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// The inbox's Suggested header and Find friends row, as the texts on screen show them. A screen
// named for chats is noted either way; any other only when one of them is on it.
static void PFBSuggestedChatsLook(UIViewController* controller) {
    UIView* root = controller.viewIfLoaded;
    NSString* header = PFBChatText(@"CHAT_COLD_INBOX_SUGGESTED_TITLE");
    NSString* friends = PFBChatText(@"CHAT_COLD_INBOX_FIND_FRIENDS_TITLE");
    if (!root.window || (!header && !friends)) {
        return;
    }
    __block NSUInteger texts = 0;
    __block BOOL headerShown = NO, friendsShown = NO;
    PFBWalkAllSubviews(root, 40, ^(UIView* view) {
      if (PFBShownOpacity(view) < 0.05) {
          return;
      }
      NSString* text = [view isKindOfClass:[UILabel class]] ? ((UILabel*)view).text : nil;
      for (NSString* candidate in @[ text ?: @"", view.accessibilityLabel ?: @"" ]) {
          if (!candidate.length) {
              continue;
          }
          texts++;
          headerShown = headerShown || (header && [candidate isEqualToString:header]);
          friendsShown = friendsShown || (friends && [candidate hasPrefix:friends]);
      }
    });
    NSString* screen = PFBReadableClassName(controller);
    BOOL chatScreen = [screen rangeOfString:@"Inbox|Chat|DM|Message" options:NSRegularExpressionSearch].location != NSNotFound;
    if (!chatScreen && !headerShown && !friendsShown) {
        return;
    }
    PFBCompatMeasure(kPFBSuggestedTopic,
                     [NSString stringWithFormat:@"%@: Suggested header %@, Find friends row %@, %lu texts read (option %@)",
                                                screen, headerShown ? @"shown" : @"absent",
                                                friendsShown ? @"shown" : @"absent", (unsigned long)texts,
                                                [PFBSettings boolForKey:@"hide_suggested_chats"] ? @"on" : @"off"],
                     kPFBSuggestedLines);
}

// MARK: - Notifications refresh, frame by frame

static NSString* const kPFBRefreshTopic = @"notification refresh";
static const NSUInteger kPFBRefreshLines = 80;

// While the list is pulled or refreshing, and 3 s after, each change of what shows: the list's
// offset and inset, the visible rows, the sweeps, and the panel's place, opacity and count.
// A jump of the panel or the list within one frame is noted as such.
@interface PFBRefreshSampler : NSObject
@property (nonatomic, weak) UIViewController* screen;
@property (nonatomic, weak) UITableView* list;
@property (nonatomic, strong) CADisplayLink* link;
@property (nonatomic) CFTimeInterval activeSince;
@property (nonatomic) CFTimeInterval lastActive;
@property (nonatomic, copy) NSString* lastState;
@property (nonatomic) CGFloat lastPanelY;
@property (nonatomic) CGFloat lastOffset;
@end

static PFBRefreshSampler* gPFBRefreshSampler;

@implementation PFBRefreshSampler

// The notifications list: the one holding the panel, or the widest list on screen.
- (UITableView*)findList {
    UITableView* list = self.list;
    if (list.window) {
        return list;
    }
    __block UITableView* found = nil;
    PFBWalkAllSubviews(self.screen.viewIfLoaded, 20, ^(UIView* view) {
      if (![view isKindOfClass:[UITableView class]] || !view.window) {
          return;
      }
      if (PFBNotifEmptyPanel((UITableView*)view, NULL) ||
          (!found && CGRectGetWidth(view.bounds) >= CGRectGetWidth(view.window.bounds) - 1.0 &&
           CGRectIntersectsRect([view convertRect:view.bounds toView:nil], view.window.bounds))) {
          found = (UITableView*)view;
      }
    });
    self.list = found;
    return found;
}

- (void)tick:(CADisplayLink*)link {
    UIViewController* screen = self.screen;
    if (!screen.viewIfLoaded.window) {
        [link invalidate];
        gPFBRefreshSampler = nil;
        return;
    }
    UITableView* list = [self findList];
    if (!list) {
        return;
    }
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat inset = list.adjustedContentInset.top;
    BOOL refreshing = list.refreshControl.isRefreshing;
    BOOL pulled = list.contentOffset.y < -inset - 2.0;
    if (refreshing || pulled) {
        if (self.activeSince == 0) {
            self.activeSince = now;
            self.lastState = nil;
        }
        self.lastActive = now;
    } else if (self.activeSince == 0 || now - self.lastActive > 3.0) {
        self.activeSince = 0;
        return;
    }
    NSUInteger panels = 0;
    UIView* panel = PFBNotifEmptyPanel(list, &panels);
    CGFloat panelY = panel.window ? [panel convertRect:panel.bounds toView:nil].origin.y : -1.0;
    NSUInteger rows = 0;
    for (UITableViewCell* cell in list.visibleCells) {
        rows += CGRectGetHeight(cell.bounds) > 1.0 && PFBShownOpacity(cell) > 0.05;
    }
    NSString* panelText = !panel ? @"none"
                          : !panel.window ? @"off the window"
                                          : [NSString stringWithFormat:@"y %.0f shown %.1f", panelY, PFBShownOpacity(panel)];
    NSString* state = [NSString stringWithFormat:@"refreshing %@, panel %@, panels %lu, visible rows %lu, sweeps %lu",
                                                 refreshing ? @"yes" : @"no", panelText, (unsigned long)panels,
                                                 (unsigned long)rows, (unsigned long)PFBNotifSweepCount()];
    CGFloat panelJump = panel.window && self.lastPanelY >= 0 ? panelY - self.lastPanelY : 0.0;
    CGFloat listJump = list.contentOffset.y - self.lastOffset;
    BOOL jump = self.lastState && (fabs(panelJump) > 8.0 || fabs(listJump) > 20.0);
    if (jump || ![state isEqualToString:self.lastState]) {
        PFBCompatMeasure(kPFBRefreshTopic,
                         [NSString stringWithFormat:@"+%.2f s: list offset %.0f, inset %.0f, %@%@", now - self.activeSince,
                                                    list.contentOffset.y, inset, state,
                                                    jump ? [NSString stringWithFormat:@" · jump in one frame: panel %+.0f pt, list %+.0f pt",
                                                                                      panelJump, listJump]
                                                         : @""],
                         kPFBRefreshLines);
        self.lastState = state;
    }
    self.lastPanelY = panelY;
    self.lastOffset = list.contentOffset.y;
}

@end

static void PFBRefreshWatch(UIViewController* screen) {
    if (gPFBRefreshSampler.screen == screen) {
        return;
    }
    [gPFBRefreshSampler.link invalidate];
    PFBRefreshSampler* sampler = [[PFBRefreshSampler alloc] init];
    sampler.screen = screen;
    sampler.lastPanelY = -1.0;
    sampler.link = [CADisplayLink displayLinkWithTarget:sampler selector:@selector(tick:)];
    [sampler.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    gPFBRefreshSampler = sampler;
}

// MARK: - When to look

static void PFBScreenLook(UIViewController* controller, NSString* moment) {
    @try {
        PFBGameBarLook(moment);
        PFBTopBlurLook(PFBReadableClassName(controller));
        Class notifications = NSClassFromString(@"T1NotificationsViewController");
        if (notifications && [controller isKindOfClass:notifications]) {
            PFBNotifRowsLook(controller);
            PFBRefreshWatch(controller);
        }
        PFBSuggestedChatsLook(controller);
    } @catch (__unused id exception) {
    }
}

static __weak UIViewController* gPFBScreenInFront;

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController* controller = (UIViewController*)self;
    BOOL notifications = [NSStringFromClass([controller class]) isEqualToString:@"T1NotificationsViewController"];
    if (!notifications && controller.navigationController.topViewController != controller) {
        return;
    }
    gPFBScreenInFront = controller;
    NSUInteger generation = ++gPFBScreenGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (generation == gPFBScreenGeneration) {
          PFBScreenLook(controller, @"settled screen");
      }
    });
}

%end

// MARK: - Imagine entries

static NSUInteger gPFBMenusRead;
static NSUInteger gPFBImagineMenus;

// Every entry title of a menu, submenus included.
static void PFBMenuTitles(NSArray* children, NSMutableArray<NSString*>* titles, NSInteger depth) {
    for (id child in children) {
        if ([child isKindOfClass:[UIMenuElement class]] && ((UIMenuElement*)child).title.length) {
            [titles addObject:((UIMenuElement*)child).title];
        } else if (![child isKindOfClass:[UIMenuElement class]] && [child respondsToSelector:@selector(title)]) {
            id title = [child valueForKey:@"title"];
            if ([title isKindOfClass:[NSString class]] && ((NSString*)title).length) {
                [titles addObject:title];
            }
        }
        if (depth < 3 && [child isKindOfClass:[UIMenu class]]) {
            PFBMenuTitles(((UIMenu*)child).children, titles, depth + 1);
        }
    }
}

// Notes each entry naming Imagine, with the screen in front and the menu's first entries.
static void PFBImagineLook(NSArray* children, NSString* kind) {
    if (![children isKindOfClass:[NSArray class]] || !children.count) {
        return;
    }
    gPFBMenusRead++;
    NSMutableArray<NSString*>* titles = [NSMutableArray array];
    PFBMenuTitles(children, titles, 0);
    BOOL found = NO;
    for (NSString* title in titles) {
        if ([title rangeOfString:@"imagine" options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        found = YES;
        UIViewController* screen = gPFBScreenInFront;
        NSArray* beside = [titles subarrayWithRange:NSMakeRange(0, MIN(titles.count, (NSUInteger)4))];
        PFBCompatMeasure(kPFBImagineTopic,
                         [NSString stringWithFormat:@"\"%@\" in a %@ on %@, beside [%@] (Hide Grok creation %@)", title, kind,
                                                    screen ? PFBReadableClassName(screen) : @"?",
                                                    [beside componentsJoinedByString:@", "],
                                                    [PFBSettings boolForKey:@"hide_grok_create"] ? @"on" : @"off"],
                         kPFBImagineLines);
    }
    if (found) {
        gPFBImagineMenus++;
    }
}

%hook UIMenu

+ (UIMenu*)menuWithTitle:(NSString*)title children:(NSArray*)children {
    @try {
        PFBImagineLook(children, @"menu");
    } @catch (__unused id exception) {
    }
    return %orig;
}

+ (UIMenu*)menuWithTitle:(NSString*)title
                   image:(UIImage*)image
              identifier:(UIMenuIdentifier)identifier
                 options:(UIMenuOptions)options
                children:(NSArray*)children {
    @try {
        PFBImagineLook(children, @"menu");
    } @catch (__unused id exception) {
    }
    return %orig;
}

%end

%hook TFNMenuSheetViewController

- (id)initWithActionItems:(NSArray*)items {
    @try {
        PFBImagineLook(items, @"sheet");
    } @catch (__unused id exception) {
    }
    return %orig;
}

%end

%ctor {
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:PFBDebuggerWillCaptureNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(__unused NSNotification* note) {
                                                    UIViewController* controller = gPFBScreenInFront;
                                                    if (controller) {
                                                        PFBScreenLook(controller, @"at capture");
                                                    }
                                                    PFBCompatMeasure(kPFBImagineTopic,
                                                                     [NSString stringWithFormat:@"at capture: %lu menus read since launch, %lu with Imagine",
                                                                                                (unsigned long)gPFBMenusRead,
                                                                                                (unsigned long)gPFBImagineMenus],
                                                                     kPFBImagineLines);
                                                  }];
}
