// Measures Twitter's own Liquid Glass: its gate, the navigation and the tab bar it
// builds, and the top bars of the main screens. Lines go to MEASUREMENTS.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

@interface T1LiquidGlassGateInstaller : NSObject
+ (void)installGateForAccount:(id)account;
@end

@interface T1MainAppNavigationProviderFactory : NSObject
- (id)appNavigationProviderControllerForAccount:(id)account;
@end

static void PFBGlassMeasure(NSString* topic, NSString* line) {
    PFBCompatMeasure(topic, line, 16);
    PFBDebugLog(@"[glass] %@: %@", topic, line);
}

static NSString* PFBGlassClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"none";
}

// A BOOL answered by a class or an object with no argument; "?" when it cannot answer.
static NSString* PFBGlassAnswer(id target, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) {
        return @"?";
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(BOOL)) != 0) {
        return @"?";
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(target, selector) ? @"yes" : @"no";
}

static id PFBGlassObject(id target, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

// MARK: - The gate

%hook T1LiquidGlassGateInstaller

+ (void)installGateForAccount:(id)account {
    %orig;
    @try {
        Class appearance = NSClassFromString(@"_TtC11XAppearance10Appearance");
        id switches = PFBGlassObject(account, @"featureSwitches");
        NSString* redesign = @"?";
        if ([switches respondsToSelector:@selector(boolForKey:)]) {
            redesign = [switches boolForKey:@"ios_liquid_glass_redesign_enabled"] ? @"yes" : @"no";
        }
        NSBundle* main = [NSBundle mainBundle];
        NSString* line = [NSString
            stringWithFormat:@"account %@, switch %@, second value %@ (early exits %ld) -> enabled %@, "
                             @"forced by system %@, chrome %@; old design asked %@, SDK %@, iOS %@",
                             account ? @"yes" : @"no", redesign, PFBNativeGlassAsked() ? @"given" : @"Twitter's",
                             (long)PFBNativeGlassEarlyExits(), PFBGlassAnswer(appearance, @"isLiquidGlassEnabled"),
                             PFBGlassAnswer(appearance, @"isLiquidGlassForcedBySystem"),
                             PFBGlassAnswer(appearance, @"isLiquidGlassChromeActive"),
                             [main objectForInfoDictionaryKey:@"UIDesignRequiresCompatibility"] ?: @"?",
                             [main objectForInfoDictionaryKey:@"DTPlatformVersion"] ?: @"?",
                             [UIDevice currentDevice].systemVersion];
        PFBGlassMeasure(@"native glass gate", line);
    } @catch (id exception) {
        PFBGlassMeasure(@"native glass gate", [NSString stringWithFormat:@"exception: %@", exception]);
    }
}

%end

// MARK: - The navigation

%hook T1MainAppNavigationProviderFactory

- (id)appNavigationProviderControllerForAccount:(id)account {
    id controller = %orig;
    PFBGlassMeasure(@"native glass navigation", [NSString stringWithFormat:@"built %@", PFBGlassClassName(controller)]);
    return controller;
}

%end

// MARK: - The tab bar and the top bars

static void PFBGlassWalk(UIView* view, NSInteger depth, void (^visit)(UIView*)) {
    if (!view || depth > 14) {
        return;
    }
    visit(view);
    for (UIView* sub in view.subviews) {
        PFBGlassWalk(sub, depth + 1, visit);
    }
}

static BOOL PFBGlassIsTabBar(UIView* view) {
    NSString* name = NSStringFromClass([view class]);
    return [view isKindOfClass:[UITabBar class]] || [name hasSuffix:@"TabBarView"] ||
           [name isEqualToString:@"TFNCustomTabBar"];
}

// Every bar along the bottom: its class, frame, items and the titles drawn in it.
static void PFBGlassMeasureTabBars(UIWindow* window) {
    NSMutableArray<UIView*>* bars = [NSMutableArray array];
    __block BOOL oldHost = NO;
    PFBGlassWalk(window, 0, ^(UIView* view) {
      if ([NSStringFromClass([view class]) isEqualToString:@"T1TabBarHostView"]) {
          oldHost = YES;
      }
      if (PFBGlassIsTabBar(view) && !view.hidden && view.alpha > 0.01) {
          [bars addObject:view];
      }
    });
    CGFloat bottom = CGRectGetHeight(window.bounds) * 0.75;
    [bars filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIView* bar, __unused NSDictionary* bindings) {
            return CGRectGetMaxY([bar convertRect:bar.bounds toView:nil]) > bottom;
          }]];
    if (!bars.count) {
        PFBGlassMeasure(@"native glass tab bar",
                        [NSString stringWithFormat:@"no bar on screen, old host %@", oldHost ? @"yes" : @"no"]);
    }
    for (UIView* bar in bars) {
        __block NSInteger items = 0;
        NSMutableArray<NSString*>* titles = [NSMutableArray array];
        PFBGlassWalk(bar, 0, ^(UIView* view) {
          NSString* name = NSStringFromClass([view class]);
          if ([name hasSuffix:@"TabBarItemView"] || [name isEqualToString:@"T1TabView"] ||
              [name isEqualToString:@"UITabBarButton"] || [name hasSuffix:@"_UITabButton"]) {
              items++;
          }
          if ([view isKindOfClass:[UILabel class]] && ((UILabel*)view).text.length && !view.hidden &&
              view.alpha > 0.01 && titles.count < 6) {
              [titles addObject:((UILabel*)view).text];
          }
        });
        id delegate = [bar isKindOfClass:[UITabBar class]] ? ((UITabBar*)bar).delegate : nil;
        CGRect frame = [bar convertRect:bar.bounds toView:nil];
        PFBGlassMeasure(@"native glass tab bar",
                        [NSString stringWithFormat:@"%@ at %.0f,%.0f %.0fx%.0f, %ld items, titles [%@], delegate %@, old host %@",
                                                   PFBGlassClassName(bar), frame.origin.x, frame.origin.y,
                                                   frame.size.width, frame.size.height, (long)items,
                                                   [titles componentsJoinedByString:@", "], PFBGlassClassName(delegate),
                                                   oldHost ? @"yes" : @"no"]);
    }
}

// The app navigation object, its tabs as panels and the one in front.
static void PFBGlassMeasurePanels(UIViewController* root) {
    NSMutableArray<UIViewController*>* queue = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
    id navigation = nil;
    for (NSUInteger i = 0; i < queue.count && i < 256 && !navigation; i++) {
        navigation = PFBGlassObject(queue[i], @"appNavigation");
        [queue addObjectsFromArray:queue[i].childViewControllers];
    }
    id panels = PFBGlassObject(navigation, @"visiblePanelIDs");
    NSString* current = @"?";
    SEL currentPanel = NSSelectorFromString(@"currentPanelID");
    if ([navigation respondsToSelector:currentPanel] &&
        [navigation methodSignatureForSelector:currentPanel].methodReturnType[0] == 'q') {
        current = [NSString stringWithFormat:@"%lld", ((long long (*)(id, SEL))objc_msgSend)(navigation, currentPanel)];
    }
    NSString* list = [panels isKindOfClass:[NSArray class]]
                         ? [[panels valueForKey:@"description"] componentsJoinedByString:@" "]
                         : PFBGlassClassName(panels);
    PFBGlassMeasure(@"native glass panels", [NSString stringWithFormat:@"%@: panels [%@], current %@",
                                                                       PFBGlassClassName(navigation), list, current]);
}

// The screens whose top bar goes to the report, by a part of their class name.
static NSString* PFBGlassScreen(UIViewController* controller) {
    NSString* name = NSStringFromClass([controller class]);
    for (NSString* screen in @[
             @"HomeTimelineContainerViewController", @"GuideContainerViewController", @"T1NotificationsViewController",
             @"XChatViewController", @"T1ConversationContainerViewController", @"T1ProfileViewController",
             @"T1GenericSettingsViewController", @"PFBModernSettingsPageViewController"
         ]) {
        if ([name containsString:screen]) {
            return screen;
        }
    }
    return nil;
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString* screen = PFBGlassScreen(self);
    if (!screen) {
        return;
    }
    @try {
        UINavigationController* navigation = self.navigationController;
        UINavigationBar* bar = navigation.navigationBar;
        PFBGlassMeasure(@"native glass top bars",
                        [NSString stringWithFormat:@"%@: navigation %@, bar %@ %.0f pt%@", screen,
                                                   PFBGlassClassName(navigation), PFBGlassClassName(bar),
                                                   bar.frame.size.height, bar.hidden || navigation.navigationBarHidden
                                                                              ? @", hidden"
                                                                              : @""]);
        static NSInteger tabBarLooks;
        if ([screen isEqualToString:@"HomeTimelineContainerViewController"] && tabBarLooks++ < 3) {
            UIWindow* window = self.view.window;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
              @try {
                  PFBGlassMeasureTabBars(window);
                  PFBGlassMeasurePanels(window.rootViewController);
              } @catch (id exception) {
                  PFBGlassMeasure(@"native glass tab bar", [NSString stringWithFormat:@"exception: %@", exception]);
              }
            });
        }
    } @catch (id exception) {
        PFBGlassMeasure(@"native glass top bars", [NSString stringWithFormat:@"exception: %@", exception]);
    }
}

%end
