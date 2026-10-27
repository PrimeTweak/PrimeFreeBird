// The PrimeFreeBird entry in Twitter's settings, the tab bar there, custom fonts and the Cephei opt-in.

#import "Support/HookHelpers.h"
#import "Support/TwitterChirpFont.h"
#import "Common/PFBCompatibility.h"

// MARK: - PrimeFreeBird settings entry

static const void* SettingsEntryKey = &SettingsEntryKey;
static const void* SettingsRootKey = &SettingsRootKey;

static BOOL isSettingsClass(UIViewController* viewController) {
    return [viewController isKindOfClass:objc_getClass("T1GenericSettingsViewController")];
}

// The generic controller backs the root and every sub-page alike, so the root is
// the first settings-class controller in the navigation stack.
static BOOL settingsVCIsRoot(TFNItemsDataViewController* settingsVC) {
    for (UIViewController* viewController in settingsVC.navigationController.viewControllers) {
        if (viewController == settingsVC) {
            return YES;
        }

        if (isSettingsClass(viewController)) {
            return NO;
        }
    }

    return NO;
}

static BOOL sectionsContainPrimeFreeBirdEntry(NSArray* sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }

        for (id entry in (NSArray*)section) {
            if (objc_getAssociatedObject(entry, SettingsEntryKey)) {
                return YES;
            }
        }
    }

    return NO;
}

// nil when Twitter's row class no longer answers the initializer.
static TFNSettingsNavigationItem* makePrimeFreeBirdSettingsItem(
    TFNItemsDataViewController* settingsVC) {
    Class itemClass = objc_getClass("TFNSettingsNavigationItem");
    if (![itemClass instancesRespondToSelector:@selector(initWithTitle:detail:iconName:controllerFactory:)]) {
        return nil;
    }
    // Adapts automatically: darker gray in light mode, light gray in dark mode,
    // matching the system's other settings icons.
    UIColor* iconColor = [UIColor secondaryLabelColor];

    // The outlined bird, 17 pt on a 20 pt icon.
    UIImage* twitterIcon =
        [[PFBBundlePDFImage(@"bird_stroke.pdf", CGSizeMake(20, 20), 17.0 / 20.0)
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:iconColor];

    TFNTwitterAccount* account = [settingsVC respondsToSelector:@selector(account)]
                                     ? [(T1GenericSettingsViewController*)settingsVC account]
                                     : nil;
    TFNSettingsNavigationItem* settingsEntry = [[itemClass alloc]
            initWithTitle:@PFB_PRODUCT_NAME
                   detail:[[PFBBundle sharedBundle] localizedStringForKey:@"PFB_SETTINGS_DETAIL"]
                 iconName:nil
        controllerFactory:^UIViewController* {
            return [PFBManager PFBSettingsWithAccount:account];
        }];

    // The icon has no setter: key-value coding writes its _icon ivar, looked up first so a
    // renamed one only loses the icon.
    if (twitterIcon && class_getInstanceVariable(object_getClass(settingsEntry), "_icon")) {
        [settingsEntry setValue:twitterIcon forKey:@"icon"];
    }

    objc_setAssociatedObject(settingsEntry, SettingsEntryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return settingsEntry;
}

// nil when no entry could be made.
static NSArray* sectionsByInsertingEntry(TFNItemsDataViewController* settingsVC,
                                         NSArray* sections) {
    TFNSettingsNavigationItem* entry = makePrimeFreeBirdSettingsItem(settingsVC);
    if (!entry) {
        return nil;
    }
    NSMutableArray* newSections = [sections mutableCopy] ?: [NSMutableArray array];
    // The row joins Twitter's first section: a section of its own would draw the
    // grouped table's seam under it.
    if (newSections.count > 0 && [newSections[0] isKindOfClass:[NSArray class]]) {
        NSMutableArray* firstSection = [(NSArray*)newSections[0] mutableCopy];
        [firstSection insertObject:entry atIndex:0];
        newSections[0] = firstSection;
    } else {
        [newSections insertObject:@[ entry ] atIndex:0];
    }
    return newSections;
}

// Async fetches rebuild the sections and discard one-shot inserts, and root-ness is
// unknowable during the first build. The root is tagged in viewWillAppear, inserted
// once, and the rebuild transform below re-adds the entry on later snapshots.
static void insertPrimeFreeBirdSettingsIfRoot(TFNItemsDataViewController* settingsVC) {
    if (!settingsVCIsRoot(settingsVC)) {
        return;
    }

    objc_setAssociatedObject(settingsVC, SettingsRootKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (sectionsContainPrimeFreeBirdEntry(settingsVC.sections)) {
        return;
    }

    NSArray* withEntry = sectionsByInsertingEntry(settingsVC, settingsVC.sections);
    if (withEntry) {
        settingsVC.sections = withEntry;
        PFBCOMPAT_ACTION(PFBCompat_settings_entry, @"entry in Twitter settings");
    }
}

static NSArray* sectionsWithPrimeFreeBirdEntry(TFNItemsDataViewController* settingsVC,
                                             NSArray* sections) {
    if (!isSettingsClass(settingsVC)) {
        return sections;
    }

    if (![objc_getAssociatedObject(settingsVC, SettingsRootKey) boolValue]) {
        return sections;
    }

    if (sectionsContainPrimeFreeBirdEntry(sections)) {
        return sections;
    }

    NSArray* withEntry = sectionsByInsertingEntry(settingsVC, sections);
    if (!withEntry) {
        return sections;
    }
    PFBCOMPAT_ACTION(PFBCompat_settings_entry, @"entry in Twitter settings");
    return withEntry;
}

// MARK: - Tab bar in the settings

// Twitter keeps its tab bar on screen in the settings. It is hidden with
// Twitter's own call, which selecting a tab undoes.
static void setSettingsTabBarHidden(UIViewController* settingsVC, BOOL hidden) {
    T1TabBarViewController* tabBar = [settingsVC respondsToSelector:@selector(tfn_tabBarIntegration)]
                                         ? [settingsVC tfn_tabBarIntegration]
                                         : nil;
    if (![tabBar respondsToSelector:@selector(setTabBarHidden:withDuration:)]) {
        return;
    }
    PFBCompatReach(PFBCompatPath_settings_tab_bar);
    [tabBar setTabBarHidden:hidden withDuration:0.0];
    if (hidden) {
        PFBCOMPAT_ACTION(PFBCompat_custom_tab_bar, @"tab bar hidden in Twitter settings");
    }
}

// Leaving the settings, not covered by a screen pushed over them: no settings page
// stays in the stack.
static BOOL settingsVCLeavesSettings(UIViewController* settingsVC) {
    UINavigationController* stack = settingsVC.navigationController;
    if (!settingsVC.isMovingFromParentViewController && !settingsVC.isBeingDismissed &&
        !stack.isBeingDismissed) {
        return NO;
    }
    for (UIViewController* viewController in stack.viewControllers) {
        if (viewController != settingsVC && isSettingsClass(viewController)) {
            return NO;
        }
    }
    return YES;
}

%hook T1GenericSettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    PFBThemeScreenEnter(self);
    insertPrimeFreeBirdSettingsIfRoot(self);
    setSettingsTabBarHidden(self, YES);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (settingsVCLeavesSettings(self)) {
        setSettingsTabBarHidden(self, NO);
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    PFBThemeScreenLeave(self);
}
%end

// Every sections rebuild runs through this transform right before setSections:,
// so hooking it on the base class covers the settings root and its sub-pages.
%hook TFNItemsDataViewController
- (NSArray*)updatedSections:(NSArray*)sections forStyle:(NSInteger)style {
    NSArray* updatedSections = %orig;
    return sectionsWithPrimeFreeBirdEntry(self, updatedSections);
}

%end

// MARK: - Change font

// The fonts installed with iFont, listed in a file outside the app. A sideloaded app
// cannot read it, and the font picker then gets no Custom fonts button.
static NSString* const kPFBAddedFontsPath = @"/var/mobile/Library/Fonts/AddedFontCache.plist";

%hook UIFontPickerViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig(arg1);
    if (![[NSFileManager defaultManager] isReadableFileAtPath:kPFBAddedFontsPath]) {
        return;
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[[PFBBundle sharedBundle]
                          localizedStringForKey:@"CUSTOM_FONTS_NAVIGATION_BUTTON_TITLE"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(customFontsHandler)];
}
%new
- (void)customFontsHandler {
    NSData* data = [NSData dataWithContentsOfFile:kPFBAddedFontsPath];
    NSDictionary* plistDictionary =
        data ? [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:nil]
             : nil;
    if (![plistDictionary isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSAttributedString* AttString = [[NSAttributedString alloc]
        initWithString:[[PFBBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_MENU_TITLE"]
            attributes:@{
                NSFontAttributeName: [PFBManager menuTitleFont],
                NSForegroundColorAttributeName: UIColor.labelColor
            }];
    TFNActiveTextItem* title =
        [[%c(TFNActiveTextItem) alloc] initWithTextModel:[[%c(TFNAttributedTextModel) alloc]
                                                                 initWithAttributedString:AttString]
                                                activeRanges:nil];

    NSMutableArray* actions = [[NSMutableArray alloc] init];
    [actions addObject:title];

    [plistDictionary enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, id _Nonnull obj,
                                                         BOOL* _Nonnull stop) {
        @try {
            NSString* fontName = ((NSArray*)[obj valueForKey:@"psNames"]).firstObject;
            if (![fontName isKindOfClass:[NSString class]] || fontName.length == 0) {
                return;
            }
            TFNActionItem* fontAction = [%c(TFNActionItem)
                actionItemWithTitle:fontName
                             action:^{
                                 if (self.configuration.includeFaces) {
                                     [self setSelectedFontDescriptor:[UIFontDescriptor
                                                                         fontDescriptorWithFontAttributes:@{
                                                                             UIFontDescriptorNameAttribute:
                                                                                 fontName
                                                                         }]];
                                 } else {
                                     [self setSelectedFontDescriptor:[UIFontDescriptor
                                                                         fontDescriptorWithFontAttributes:@{
                                                                             UIFontDescriptorFamilyAttribute:
                                                                                 fontName
                                                                         }]];
                                 }
                                 [self.delegate fontPickerViewControllerDidPickFont:self];
                             }];
            [actions addObject:fontAction];
        } @catch (NSException* exception) {
        }
    }];

    TFNMenuSheetViewController* alert = [[%c(TFNMenuSheetViewController) alloc]
        initWithActionItems:[NSArray arrayWithArray:actions]];
    [alert tfnPresentedCustomPresentFromViewController:self animated:YES completion:nil];
}
%end

// Swaps an app font for the chosen custom one at the same size, keeping bold
// where the original was bold. Returns the original when the feature is off, no
// font is set, or the chosen one will not load.
static UIFont* PFBCustomFont(UIFont* original, BOOL bold) {
    if (!original) {
        return original;
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"custom_fonts"]) {
        PFBCOMPAT_OBSERVE(PFBCompat_custom_fonts, @"font request seen");
        return original;
    }
    NSString* customName = [[NSUserDefaults standardUserDefaults]
        stringForKey:bold ? @"pfb_font_2" : @"pfb_font_1"];
    if (customName.length == 0) {
        // With no font chosen at all, the option has nothing to apply: the sheet counts it as off.
        if (![[NSUserDefaults standardUserDefaults] stringForKey:bold ? @"pfb_font_1" : @"pfb_font_2"].length) {
            PFBCOMPAT_OBSERVE(PFBCompat_custom_fonts, @"font request seen");
        }
        return original;
    }
    UIFont* custom = [UIFont fontWithName:customName size:original.pointSize];
    if (custom) {
        PFBCOMPAT_ACTION(PFBCompat_custom_fonts, @"%@", customName);
    }
    return custom ?: original;
}

// Named-font construction (tweet body and most text styles) funnels through here.
%hook UIFont
+ (UIFont*)tfn_fontWithName:(NSString*)name size:(CGFloat)size {
    UIFont* original = %orig;
    BOOL bold = [name containsString:@"Bold"] || [name containsString:@"Heavy"];
    return PFBCustomFont(original, bold);
}
%end

// The interface's own text (names, buttons, titles) and the tabular counters are
// built by XFontCatalog, which never calls tfn_fontWithName, so they are covered
// here too. Boldness is read from the font the app would have used.
%hook XFontCatalog
+ (UIFont*)customFontOfSize:(CGFloat)size weight:(NSInteger)weight
      scalesWithDynamicType:(BOOL)scales {
    UIFont* original = %orig;
    PFBCompatReach(PFBCompatPath_interface_text);
    BOOL bold = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    return PFBCustomFont(original, bold);
}
+ (UIFont*)contentFontWithOffset:(CGFloat)offset weight:(NSInteger)weight {
    UIFont* original = %orig;
    PFBCompatReach(PFBCompatPath_interface_text);
    BOOL bold = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    return PFBCustomFont(original, bold);
}
// Counters and timers ask for digits of equal width so they hold still as they change;
// the custom font keeps them where it has such digits.
+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(CGFloat)weight {
    UIFont* original = %orig;
    PFBCompatReach(PFBCompatPath_counter_digits);
    BOOL bold = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    UIFont* custom = PFBCustomFont(original, bold);
    return custom == original ? original : PFBTabularDigitsFont(custom);
}
%end

// Cephei blocks HBPreferences access from app processes unless this opt-in
// returns YES.
%hook HBForceCepheiPrefs
+ (BOOL)forceCepheiPrefsWhichIReallyNeedToAccessAndIKnowWhatImDoingISwear {
    return YES;
}
%end
