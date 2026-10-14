// The PrimeFreeBird entry in the app's settings, and the custom font picker.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

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

// Probe: notes each distinct settings page met, up to 6, by its scribe page and whether it is
// taken for the root, with the classes of its stack.
static void PFBProbeSettingsPage(TFNItemsDataViewController* settingsVC) {
    static NSUInteger noted;
    if (!PFBDebugIsRecording() || noted >= 6) {
        return;
    }
    id page = PFBProbeGetter(settingsVC, @"scribePage");
    NSString* name = [page isKindOfClass:[NSString class]] ? page : @"none";
    NSString* root = settingsVCIsRoot(settingsVC) ? @"yes" : @"no";
    NSString* key = [NSString stringWithFormat:@"03#F051 page %@ root=%@", name, root];
    if (!PFBProbeWants(key)) {
        return;
    }
    noted++;
    NSMutableArray<NSString*>* stack = [NSMutableArray array];
    for (UIViewController* viewController in settingsVC.navigationController.viewControllers) {
        if (stack.count < 8) {
            [stack addObject:NSStringFromClass([viewController class])];
        }
    }
    PFBProbeNote(key, @"03#F051 settings page %@: root=%@ stack [%@]", name, root, [stack componentsJoinedByString:@", "]);
}

// Probe: notes how Twitter shows its settings root, presented or pushed, once per way.
static void PFBProbeSettingsRootShown(TFNItemsDataViewController* settingsVC) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    UINavigationController* stack = settingsVC.navigationController;
    UIViewController* presenter = stack.presentingViewController;
    NSString* way = presenter ? [@"presented by " stringByAppendingString:NSStringFromClass([presenter class])]
                              : [@"not presented, in " stringByAppendingString:PFBProbeClassName(stack)];
    NSString* key = [@"02#F025 root " stringByAppendingString:way];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"02#F025 Twitter settings root: %@ (%lu screens in its stack)", way,
                     (unsigned long)stack.viewControllers.count);
    }
}

// Probe: 0.5 s after a settings root is tagged, notes its data view and, for rows 0 and 1, the cell
// class and whether it answers the two separator setters, with the cell hook's call count; nothing
// is noted while neither row is on screen, so a later appearance of the root reads them.
static void PFBProbeSettingsSeparators(TFNItemsDataViewController* settingsVC) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"03#F007 settings root")) {
        return;
    }
    __weak TFNItemsDataViewController* weakVC = settingsVC;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TFNItemsDataViewController* root = weakVC;
        if (!root || !PFBProbeWants(@"03#F007 settings root")) {
            return;
        }
        id view = PFBProbeGetter(root, @"tableViewIfLoaded");
        UITableView* table = [view isKindOfClass:[UITableView class]] ? view : nil;
        id other = table ? nil : PFBProbeGetter(root, @"collectionViewIfLoaded");
        UICollectionView* grid = [other isKindOfClass:[UICollectionView class]] ? other : nil;
        NSMutableArray<NSString*>* rows = [NSMutableArray array];
        NSUInteger found = 0;
        for (NSInteger row = 0; row < 2; row++) {
            NSIndexPath* path = [NSIndexPath indexPathForRow:row inSection:0];
            UIView* cell = nil;
            if (table.numberOfSections > 0 && row < [table numberOfRowsInSection:0]) {
                cell = [table cellForRowAtIndexPath:path];
            } else if (grid.numberOfSections > 0 && row < [grid numberOfItemsInSection:0]) {
                cell = [grid cellForItemAtIndexPath:path];
            }
            found += cell ? 1 : 0;
            [rows addObject:[NSString stringWithFormat:@"row%ld %@ sep %@/top %@", (long)row, PFBProbeClassName(cell),
                                                       [cell respondsToSelector:NSSelectorFromString(@"setSeparatorHidden:")]
                                                           ? @"yes" : @"no",
                                                       [cell respondsToSelector:NSSelectorFromString(@"setTopSeparatorHidden:")]
                                                           ? @"yes" : @"no"]];
        }
        if (!found) {
            return;
        }
        PFBProbeNote(@"03#F007 settings root", @"03#F007 settings root: data view %@; %@; separator hook reached %lu",
                     PFBProbeClassName(table ?: (id)grid ?: view), [rows componentsJoinedByString:@"; "],
                     (unsigned long)PFBProbeCountValue(@"03#F007 separator calls"));
    });
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

static TFNSettingsNavigationItem* makePrimeFreeBirdSettingsItem(
    TFNItemsDataViewController* settingsVC) {
    // Adapts automatically: darker gray in light mode, light gray in dark mode,
    // matching the system's other settings icons.
    UIColor* iconColor = [UIColor secondaryLabelColor];

    // imageNamed: cannot see loose PDFs in a bundle (only compiled asset catalogs), so the
    // PDF is opened by path, its page rendered at icon size and tinted gray like the native
    // settings icons.
    UIImage* twitterIcon = nil;
    NSURL* birdURL = [[PFBBundle sharedBundle] pathForFile:@"bird_stroke.pdf"];
    if (birdURL) {
        CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)birdURL);
        if (pdf) {
            CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
            if (page) {
                CGSize canvasSize = CGSizeMake(20, 20);
                CGFloat birdSize = 17;
                CGFloat inset = (canvasSize.width - birdSize) / 2.0;
                UIGraphicsImageRendererFormat* fmt = [UIGraphicsImageRendererFormat preferredFormat];
                fmt.opaque = NO;
                UIGraphicsImageRenderer* renderer =
                    [[UIGraphicsImageRenderer alloc] initWithSize:canvasSize format:fmt];
                UIImage* rendered = [renderer imageWithActions:^(UIGraphicsImageRendererContext* ctx) {
                    CGContextRef c = ctx.CGContext;
                    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
                    CGFloat scale = MIN(birdSize / box.size.width,
                                        birdSize / box.size.height);
                    CGContextTranslateCTM(c, inset, canvasSize.height - inset);
                    CGContextScaleCTM(c, 1, -1);
                    CGContextScaleCTM(c, scale, scale);
                    CGContextDrawPDFPage(c, page);
                }];
                twitterIcon = [[rendered imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                                  imageWithTintColor:iconColor];
            }
            CGPDFDocumentRelease(pdf);
        }
    }

    TFNTwitterAccount* account = [(T1GenericSettingsViewController*)settingsVC account];
    TFNSettingsNavigationItem* settingsEntry = [[objc_getClass("TFNSettingsNavigationItem") alloc]
            initWithTitle:@PFB_PRODUCT_NAME
                   detail:[[PFBBundle sharedBundle] localizedStringForKey:@"PFB_SETTINGS_DETAIL"]
                 iconName:nil
        controllerFactory:^UIViewController* {
            return [PFBManager PFBSettingsWithAccount:account];
        }];

    if (twitterIcon) {
        [settingsEntry setValue:twitterIcon forKey:@"icon"];
    }

    objc_setAssociatedObject(settingsEntry, SettingsEntryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return settingsEntry;
}

static NSArray* sectionsByInsertingEntry(TFNItemsDataViewController* settingsVC,
                                         NSArray* sections) {
    NSMutableArray* newSections = [sections mutableCopy] ?: [NSMutableArray array];
    TFNSettingsNavigationItem* entry = makePrimeFreeBirdSettingsItem(settingsVC);
    // The apparent separator under this row is the grouped table's section seam,
    // created by injecting the row as its own section, not a hairline view. Joining
    // Twitter's first section removes it structurally.
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
    PFBProbeSettingsRootShown(settingsVC);
    PFBProbeSettingsSeparators(settingsVC);

    if (sectionsContainPrimeFreeBirdEntry(settingsVC.sections)) {
        return;
    }

    settingsVC.sections = sectionsByInsertingEntry(settingsVC, settingsVC.sections);
    PFBCOMPAT_ACTION(PFBCompat_settings_entry, @"entry in Twitter settings");
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

    PFBCOMPAT_ACTION(PFBCompat_settings_entry, @"entry in Twitter settings");
    return sectionsByInsertingEntry(settingsVC, sections);
}

%hook T1GenericSettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    PFBThemeScreenEnter(self);
    insertPrimeFreeBirdSettingsIfRoot(self);
    PFBProbeSettingsPage(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    PFBThemeScreenLeave(self);
}
%end

// Probe: counts the separator code's calls, up to 50, and notes once per cell class
// whether the cell it acts on answers the two setters.
static BOOL gPFBProbeSeparatorDone;
static void PFBProbeSeparatorSetters(UITableViewCell* cell) {
    if (gPFBProbeSeparatorDone || !PFBDebugIsRecording()) {
        return;
    }
    gPFBProbeSeparatorDone = PFBProbeCount(@"03#F007 separator calls") >= 50;
    NSString* key = [@"03#F016 separator " stringByAppendingString:NSStringFromClass([cell class])];
    if (PFBProbeWants(key)) {
        PFBProbeNote(key, @"03#F016 settings separator: %@ setSeparatorHidden:%d setTopSeparatorHidden:%d",
                     NSStringFromClass([cell class]), [cell respondsToSelector:NSSelectorFromString(@"setSeparatorHidden:")],
                     [cell respondsToSelector:NSSelectorFromString(@"setTopSeparatorHidden:")]);
    }
}

// Every sections rebuild runs through this transform right before setSections:,
// so hooking it on the base class covers the settings root and its sub-pages.
%hook TFNItemsDataViewController
- (NSArray*)updatedSections:(NSArray*)sections forStyle:(NSInteger)style {
    NSArray* updatedSections = %orig;
    return sectionsWithPrimeFreeBirdEntry(self, updatedSections);
}

// The injected row sits in Twitter's own settings table, so the separator under it
// is drawn by Twitter's cell. TFNTextCell carries setSeparatorHidden: and
// setTopSeparatorHidden:, used directly and reapplied on every vend.
static void PFBHideRowSeparator(UITableViewCell* cell) {
    PFBProbeSeparatorSetters(cell);
    SEL hide = @selector(setSeparatorHidden:);
    if ([cell respondsToSelector:hide]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(cell, hide, YES);
    }
    SEL hideTop = @selector(setTopSeparatorHidden:);
    if ([cell respondsToSelector:hideTop]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(cell, hideTop, YES);
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell* cell = %orig;
    if (![objc_getAssociatedObject(self, SettingsRootKey) boolValue] || !cell ||
        !sectionsContainPrimeFreeBirdEntry(
            ((TFNItemsDataViewController*)self).sections)) {
        return cell;
    }
    // The PrimeFreeBird row is section 0, row 0, and the first native row is row 1; the
    // separator is hidden on both sides of the seam so no hairline shows under it.
    if (indexPath.section == 0 && (indexPath.row == 0 || indexPath.row == 1)) {
        PFBHideRowSeparator(cell);
    }
    return cell;
}

%end

// MARK: - Change font

%hook UIFontPickerViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig(arg1);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[[PFBBundle sharedBundle]
                          localizedStringForKey:@"CUSTOM_FONTS_NAVIGATION_BUTTON_TITLE"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(customFontsHandler)];
}
%new
- (void)customFontsHandler {
    if ([[NSFileManager defaultManager]
            fileExistsAtPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]) {
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

        NSDictionary* plistDictionary = [NSPropertyListSerialization
            propertyListWithData:
                [NSData dataWithContentsOfURL:
                            [NSURL fileURLWithPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]]
                         options:NSPropertyListImmutable
                          format:NULL
                           error:nil];
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
    } else {
        UIAlertController* errAlert = [UIAlertController
            alertControllerWithTitle:@PFB_PRODUCT_NAME
                             message:[[PFBBundle sharedBundle]
                                         localizedStringForKey:@"CUSTOM_FONTS_TUT_ALERT_MESSAGE"]
                      preferredStyle:UIAlertControllerStyleAlert];

        [errAlert
            addAction:
                [UIAlertAction
                    actionWithTitle:[[PFBBundle sharedBundle]
                                        localizedStringForKey:@"INSTALL_IFONT_BUTTON_TITLE"]
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction* _Nonnull action) {
                                [[UIApplication sharedApplication]
                                              openURL:[NSURL
                                                          URLWithString:
                                                              @"https://apps.apple.com/sa/app/"
                                                              @"ifont-find-install-any-font/id1173222289"]
                                              options:@{}
                                    completionHandler:nil];
                            }]];
        [errAlert addAction:[UIAlertAction
                                actionWithTitle:[[PFBBundle sharedBundle]
                                                    localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
        [self presentViewController:errAlert animated:true completion:nil];
    }
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
        // With no font chosen at all, the option stands off, as the report counts it.
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

// Probe: notes how many installed families load by their family name, the form the regular
// font is stored in, and how many through a family descriptor; run by the path tour.
void PFBProbeFontLoading(void) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"SF-2 fonts")) {
        return;
    }
    NSArray<NSString*>* families = [UIFont familyNames];
    NSUInteger byName = 0;
    NSUInteger byDescriptor = 0;
    NSMutableArray<NSString*>* failing = [NSMutableArray array];
    for (NSString* family in families) {
        if ([UIFont fontWithName:family size:17]) {
            byName++;
        } else if (failing.count < 5) {
            [failing addObject:family];
        }
        UIFontDescriptor* descriptor =
            [UIFontDescriptor fontDescriptorWithFontAttributes:@{UIFontDescriptorFamilyAttribute: family}];
        if ([[UIFont fontWithDescriptor:descriptor size:17].familyName isEqualToString:family]) {
            byDescriptor++;
        }
    }
    PFBProbeNote(@"SF-2 fonts",
                 @"SF-2 fonts: %lu of %lu families load by family name, %lu of %lu by family descriptor; failing by name: %@",
                 (unsigned long)byName, (unsigned long)families.count, (unsigned long)byDescriptor,
                 (unsigned long)families.count, failing.count ? [failing componentsJoinedByString:@", "] : @"none");
}

// Probe: notes whether the custom fonts list the font picker's button reads is visible to the
// app, and how many entries reading it the way the button's menu does gives; run by the path tour.
void PFBProbeCustomFontsFile(void) {
    if (!PFBDebugIsRecording() || !PFBProbeWants(@"10F#F-03 custom fonts list")) {
        return;
    }
    NSString* path = @"/var/mobile/Library/Fonts/AddedFontCache.plist";
    NSFileManager* files = [NSFileManager defaultManager];
    NSData* data = [NSData dataWithContentsOfFile:path];
    id list = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil]
                   : nil;
    NSString* contents = [list isKindOfClass:[NSDictionary class]]
                             ? [NSString stringWithFormat:@"%lu entries", (unsigned long)((NSDictionary*)list).count]
                             : (data ? @"not a dictionary" : @"no");
    PFBProbeNote(@"10F#F-03 custom fonts list", @"10F#F-03 custom fonts list: exists %@, readable %@, read %@",
                 [files fileExistsAtPath:path] ? @"yes" : @"no", [files isReadableFileAtPath:path] ? @"yes" : @"no", contents);
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
    BOOL bold = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    return PFBCustomFont(original, bold);
}
+ (UIFont*)contentFontWithOffset:(CGFloat)offset weight:(NSInteger)weight {
    UIFont* original = %orig;
    BOOL bold = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    return PFBCustomFont(original, bold);
}
+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(CGFloat)weight {
    UIFont* original = %orig;
    BOOL bold = (original.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
    return PFBCustomFont(original, bold);
}
%end

// Cephei blocks HBPreferences access from app processes unless this opt-in
// returns YES.
%hook HBForceCepheiPrefs
+ (BOOL)forceCepheiPrefsWhichIReallyNeedToAccessAndIKnowWhatImDoingISwear {
    return YES;
}
%end
