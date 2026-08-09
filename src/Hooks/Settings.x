//
//  Settings.x
//  PrimeFreeBird
//

#import "HookHelpers.h"

extern NSInteger NFBColorThemeScreenVisible;

// MARK: - PrimeFreeBird settings entry

static const void* SettingsEntryKey = &SettingsEntryKey;
static const void* SettingsRootKey = &SettingsRootKey;

static BOOL isSettingsClass(UIViewController* viewController) {
    return [viewController isKindOfClass:objc_getClass("T1GenericSettingsViewController")] ||
           [viewController isKindOfClass:objc_getClass("T1SettingsViewController")];
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

static TFNSettingsNavigationItem* makePrimeFreeBirdSettingsItem(
    TFNItemsDataViewController* settingsVC) {
    // Adapts automatically: darker grey in light mode, light grey in dark mode,
    // matching the system's other settings icons.
    UIColor* iconColor = [UIColor secondaryLabelColor];

    // imageNamed: can't see loose PDFs in a bundle (only compiled asset
    // catalogs), so we open the PDF by path and render its page at icon size,
    // then tint it grey like the native settings icons.
    UIImage* twitterIcon = nil;
    NSURL* birdURL = [[BHTBundle sharedBundle] pathForFile:@"bird_stroke.pdf"];
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
    TFNSettingsNavigationItem* bhtwitter = [[objc_getClass("TFNSettingsNavigationItem") alloc]
            initWithTitle:@NFB_PRODUCT_NAME
                   detail:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"]
                 iconName:nil
        controllerFactory:^UIViewController* {
            return [BHTManager BHTSettingsWithAccount:account];
        }];

    if (twitterIcon) {
        [bhtwitter setValue:twitterIcon forKey:@"icon"];
    }

    objc_setAssociatedObject(bhtwitter, SettingsEntryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return bhtwitter;
}

static NSArray* sectionsByInsertingEntry(TFNItemsDataViewController* settingsVC,
                                         NSArray* sections) {
    NSMutableArray* newSections = [sections mutableCopy] ?: [NSMutableArray array];
    TFNSettingsNavigationItem* entry = makePrimeFreeBirdSettingsItem(settingsVC);
    // The apparent "separator" under this row is the grouped table's SECTION
    // SEAM, created by injecting the row as its own section at index 0 — not a
    // hairline view. Joining Twitter's first section removes the seam
    // structurally:
    // the row's bottom edge becomes an ordinary intra-section boundary, drawn
    // (or not drawn) exactly like the native rows below it.
    if (newSections.count > 0 && [newSections[0] isKindOfClass:[NSArray class]]) {
        NSMutableArray* firstSection = [(NSArray*)newSections[0] mutableCopy];
        [firstSection insertObject:entry atIndex:0];
        newSections[0] = firstSection;
    } else {
        [newSections insertObject:@[ entry ] atIndex:0];
    }
    return newSections;
}

// Async settings fetches rebuild the sections and discard one-shot inserts, and
// root-ness is unknowable during the first build (not yet on the nav stack). So
// tag the root in viewWillAppear, insert once to repair the first build, and let
// the rebuild transform below re-add the entry on every later snapshot.
static void insertPrimeFreeBirdSettingsIfRoot(TFNItemsDataViewController* settingsVC) {
    if (!settingsVCIsRoot(settingsVC)) {
        return;
    }

    objc_setAssociatedObject(settingsVC, SettingsRootKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (sectionsContainPrimeFreeBirdEntry(settingsVC.sections)) {
        return;
    }

    settingsVC.sections = sectionsByInsertingEntry(settingsVC, settingsVC.sections);
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

    return sectionsByInsertingEntry(settingsVC, sections);
}

%hook T1GenericSettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NFBColorThemeScreenVisible++;
    insertPrimeFreeBirdSettingsIfRoot(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (NFBColorThemeScreenVisible > 0) {
        NFBColorThemeScreenVisible--;
    }
}
%end

%hook T1SettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NFBColorThemeScreenVisible++;
    insertPrimeFreeBirdSettingsIfRoot(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (NFBColorThemeScreenVisible > 0) {
        NFBColorThemeScreenVisible--;
    }
}
%end

// Every sections rebuild runs through this transform right before setSections:,
// so hooking it on the base class covers both settings roots.
%hook TFNItemsDataViewController
- (NSArray*)updatedSections:(NSArray*)sections forStyle:(NSInteger)style {
    NSArray* updatedSections = %orig;
    return sectionsWithPrimeFreeBirdEntry(self, updatedSections);
}

// Kill the non-native hairline under our injected row without touching its
// style: push the native separator inset offscreen, and hide any TFN-drawn
// hairline inside this ONE cell on the next runloop (dividers are laid out
// after the cell is returned). The class-name log makes any second round
// surgical instead of guesswork.
// The PrimeFreeBird row is injected into TWITTER's settings table
// (TFNItemsDataViewController), so the separator under it is drawn by Twitter's
// own cell — not by anything in our code, which is why every ModernSettings
// change and every subview/layer sweep missed it. The IPA shows TFNTextCell
// carries the real setters setSeparatorHidden: and setTopSeparatorHidden:.
// Hide our row's bottom separator, and the next row's top separator, using
// those setters directly (KVC on the property threw — this is the class's own
// API). Reapplied on every vend so cell reuse cannot bring it back.
static void NFBHideRowSeparator(UITableViewCell* cell) {
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
    // Our row is section 0, row 0; the row directly beneath the visible
    // boundary is section 1, row 0. Hide the separator on both sides of the
    // seam so no hairline shows under PrimeFreeBird.
    if (indexPath.section == 0 && (indexPath.row == 0 || indexPath.row == 1)) {
        // Row 0 is ours; row 1 is the first native row now sharing our
        // section. Hiding both sides of the seam keeps the edge clean even if
        // this table draws intra-section separators.
        NFBHideRowSeparator(cell);
    }
    return cell;
}

%end

// MARK: - Change font

%hook UIFontPickerViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig(arg1);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[[BHTBundle sharedBundle]
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
            initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [BHTManager menuTitleFont],
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
            alertControllerWithTitle:@NFB_PRODUCT_NAME
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"CUSTOM_FONTS_TUT_ALERT_MESSAGE"]
                      preferredStyle:UIAlertControllerStyleAlert];

        [errAlert
            addAction:
                [UIAlertAction
                    actionWithTitle:[[BHTBundle sharedBundle]
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
                                actionWithTitle:[[BHTBundle sharedBundle]
                                                    localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
        [self presentViewController:errAlert animated:true completion:nil];
    }
}
%end

// All font construction funnels through +[UIFont tfn_fontWithName:size:],
// so remapping here covers every text style in one place.
%hook UIFont
+ (UIFont*)tfn_fontWithName:(NSString*)name size:(CGFloat)size {
    UIFont* origFont = %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"custom_fonts"]) {
        return origFont;
    }
    BOOL isBold = [name containsString:@"Bold"] || [name containsString:@"Heavy"];
    NSString* customName = [[NSUserDefaults standardUserDefaults]
        objectForKey:isBold ? @"bhtwitter_font_2" : @"bhtwitter_font_1"];
    if (!customName) {
        return origFont;
    }
    return [UIFont fontWithName:customName size:size] ?: origFont;
}
%end

// Cephei blocks HBPreferences access from app processes unless this opt-in
// returns YES.
%hook HBForceCepheiPrefs
+ (BOOL)forceCepheiPrefsWhichIReallyNeedToAccessAndIKnowWhatImDoingISwear {
    return YES;
}
%end
