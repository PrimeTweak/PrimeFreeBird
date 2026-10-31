// Twitter's own tab editor, T1TabCustomizationViewController, under its Liquid Glass navigation.
// Its Save and restore read the gate's cached availability from Swift, so that cached flag is set;
// the saved selection, which Twitter clears at launch, is kept and handed back.

#import "Support/HookHelpers.h"
#import "Features/Appearance/CustomTabBar/PFBNativeTabSelectionStore.h"

// The messages sent below, declared for the compiler.
@protocol PFBNativeTabMessages <NSObject>
@optional
- (BOOL)isTabCustomizationEnabled;
- (id)appNavigation;
- (id)account;
- (id)accountID;
- (void)pfbRestoreNativeTabsAfterActivation:(NSNotification*)notification;
@end

// MainAppNavigationSettings.restoreTabIdentifiers(), exported by T1Twitter: a Swift method whose
// instance travels in the context register.
typedef void (*PFBRestoreTabIdentifiers)(void* settings __attribute__((swift_context))) __attribute__((swiftcall));

static __thread BOOL gPFBSavingNativeTabs;
static __thread BOOL gPFBRestoringNativeTabs;

static NSString* PFBTabAccountID(id object) {
    if (![object respondsToSelector:@selector(accountID)]) {
        return nil;
    }
    id accountID = ((id (*)(id, SEL))objc_msgSend)(object, @selector(accountID));
    return [accountID isKindOfClass:[NSString class]] ? accountID : nil;
}

// An object held in a stored property, read by ivar name; nil for a lazy property not made yet
// (Swift marks it with a small sentinel) or a slot outside the instance.
static id PFBTabObjectField(id object, const char* name) {
    Ivar field = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    if (!field) {
        return nil;
    }
    ptrdiff_t offset = ivar_getOffset(field);
    if (offset < (ptrdiff_t)sizeof(void*) || (size_t)offset + sizeof(id) > class_getInstanceSize(object_getClass(object))) {
        return nil;
    }
    uintptr_t reference = 0;
    memcpy(&reference, (const uint8_t*)(__bridge void*)object + offset, sizeof(reference));
    if (reference < 4096 || reference % sizeof(void*)) {
        return nil;
    }
    return object_getIvar(object, field);
}

// Opens the gate where Twitter's Swift code reads it: the one-byte availability cached in the
// legacy subscription config. No claim, reference or other stored value is changed.
static BOOL PFBEnableCachedTabCustomization(id config) {
    id helper = PFBTabObjectField(config, "migrationHelper");
    Class helperClass = NSClassFromString(@"_TtC14T1TwitterSwift33SubscriptionsInfraMigrationHelper");
    if (!helperClass || object_getClass(helper) != helperClass) {
        return NO;
    }
    id legacy = PFBTabObjectField(helper, "$__lazy_storage_$_legacyConfig");
    Class legacyClass = NSClassFromString(@"_TtC20TwitterSubscriptions31LegacySubscriptionFeatureConfig");
    if (!legacyClass || object_getClass(legacy) != legacyClass) {
        return NO;
    }
    Ivar enabled = class_getInstanceVariable(legacyClass, "isFeatureEnabled");
    Ivar claims = class_getInstanceVariable(legacyClass, "claims");
    if (!enabled || !claims) {
        return NO;
    }
    ptrdiff_t offset = ivar_getOffset(enabled);
    if (offset < (ptrdiff_t)(2 * sizeof(void*)) || (size_t)offset >= class_getInstanceSize(legacyClass) ||
        ivar_getOffset(claims) <= offset) {
        return NO;
    }
    uint8_t value = 1;
    memcpy((uint8_t*)(__bridge void*)legacy + offset, &value, sizeof(value));
    return YES;
}

// The editor's navigation settings once its gate answers open, or nil.
static id PFBPrepareNativeTabSave(id editor) {
    id model = PFBTabObjectField(editor, "viewModel");
    id settings = PFBTabObjectField(model, "navigationSettings");
    id config = PFBTabObjectField(settings, "$__lazy_storage_$_tabCustomizationConfig");
    if ([config respondsToSelector:@selector(isTabCustomizationEnabled)] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(config, @selector(isTabCustomizationEnabled))) {
        return settings;
    }
    PFBCompatMeasure(@"tab editor", @"gate could not be opened", 8);
    return nil;
}

// Hands Twitter the kept selection: its own restore decodes it and publishes it to the glass bar,
// even when launch cleared Twitter's copy. An account with nothing kept is left to Twitter.
static void PFBRestoreNativeTabSelection(id controller) {
    if (![controller respondsToSelector:@selector(appNavigation)]) {
        return;
    }
    id navigation = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(appNavigation));
    if (![navigation respondsToSelector:@selector(account)]) {
        return;
    }
    id account = ((id (*)(id, SEL))objc_msgSend)(navigation, @selector(account));
    if (![[PFBNativeTabSelectionStore sharedStore] hasSelectionForAccountID:PFBTabAccountID(account)]) {
        return;
    }
    static PFBRestoreTabIdentifiers restore;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      restore = (PFBRestoreTabIdentifiers)dlsym(RTLD_DEFAULT,
                                                "$s14T1TwitterSwift25MainAppNavigationSettingsC21restoreTabIdentifiersyyF");
      if (!restore) {
          PFBCompatMeasure(@"tab editor", @"Twitter's restore function not found", 8);
      }
    });
    Class editorClass = NSClassFromString(@"T1TabCustomizationViewController");
    id editor = restore ? [PFBCustomTabBarUtility editorForAccount:account] : nil;
    if (!editorClass || ![editor isKindOfClass:editorClass]) {
        return;
    }
    id settings = PFBPrepareNativeTabSave(editor);
    if (!settings) {
        return;
    }
    BOOL restoring = gPFBRestoringNativeTabs;
    gPFBRestoringNativeTabs = YES;
    @try {
        restore((__bridge void*)settings);
    } @finally {
        gPFBRestoringNativeTabs = restoring;
    }
}

%hook T1TabCustomizationConfig

// When Twitter's answer is closed, the cached flag is set and the gate asked again;
// an open answer then counts as Twitter's tab editor gate opened.
- (BOOL)isTabCustomizationEnabled {
    BOOL open = %orig;
    if (open || !PFBEnableCachedTabCustomization(self)) {
        return open;
    }
    open = %orig;
    if (open) {
        PFBCompatReach(PFBCompatPath_native_tab_editor);
        PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"Twitter's tab editor gate opened");
    }
    return open;
}

%end

%hook TFSAccountUserDefaults

- (void)setObject:(id)value forKey:(id)key {
    %orig;
    if (gPFBSavingNativeTabs && [PFBNativeTabSelectionStore isNativeTabSettingsKey:key]) {
        NSData* data = [value isKindOfClass:[NSData class]] ? value : nil;
        [[PFBNativeTabSelectionStore sharedStore] saveData:data forAccountID:PFBTabAccountID(self) settingsKey:key];
        PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"selection from Twitter's tab editor kept");
    }
}

- (id)objectForKey:(id)key {
    if ([PFBNativeTabSelectionStore isNativeTabSettingsKey:key] &&
        (gPFBRestoringNativeTabs || [PFBCustomTabBarUtility usesNativeEditor])) {
        NSData* saved = [[PFBNativeTabSelectionStore sharedStore] dataForAccountID:PFBTabAccountID(self) settingsKey:key];
        if (saved) {
            return saved;
        }
    }
    return %orig;
}

%end

%hook _TtC14T1TwitterSwift34XTabbedAppNavigationViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pfbRestoreNativeTabsAfterActivation:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

%new
- (void)pfbRestoreNativeTabsAfterActivation:(NSNotification*)notification {
    id controller = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      PFBRestoreNativeTabSelection(controller);
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    id controller = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      PFBRestoreNativeTabSelection(controller);
    });
}

%end

%hook T1TabCustomizationViewController

- (void)viewDidLoad {
    %orig;
    PFBPrepareNativeTabSave(self);
}

- (void)didPressSaveButton {
    PFBPrepareNativeTabSave(self);
    BOOL saving = gPFBSavingNativeTabs;
    gPFBSavingNativeTabs = [PFBCustomTabBarUtility usesNativeEditor];
    @try {
        %orig;
    } @finally {
        gPFBSavingNativeTabs = saving;
    }
}

%end
