// Unified notifications: Notifications stays on All, which already lists every notification,
// mentions included, and a search field takes the place of the All and Mentions row. Read once
// per launch, as Twitter builds the screen once.

#import "Support/HookHelpers.h"
#import "Support/Helpers.h"
#import "Support/TFNHeaders.h"
#import "Support/TwitterChirpFont.h"
#import <malloc/malloc.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Twitter's own search field, as its Settings screen draws it: 40 pt high in the 44 pt row,
// the glyph 17 pt in, the text 40 pt in, Chirp at 16.5 pt.
static const CGFloat kPFBSearchFieldHeight = 40.0;
static const CGFloat kPFBSearchSideInset = 20.0;
static const CGFloat kPFBSearchGlyphLeft = 17.0;
static const CGFloat kPFBSearchGlyphSize = 14.0;
static const CGFloat kPFBSearchTextLeft = 40.0;
static const CGFloat kPFBSearchFontSize = 16.5;
static const NSInteger kPFBSearchPanelTag = 90318;

static const char* kPFBSearchBarKey = "pfbSearchBar";
static const char* kPFBSearchListKey = "pfbSearchList";
static const char* kPFBSearchPanelKey = "pfbSearchPanel";
static const char* kPFBSearchRowKey = "pfbSearchRow";
static const char* kPFBSearchDroppedKey = "pfbSearchDropped";

static NSString* gPFBSearchQuery;
static NSMapTable* gPFBSearchCellWords;
static NSMapTable* gPFBSearchModelWords;
static BOOL gPFBSearchPanelPending;

static BOOL PFBUnifiedOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      on = [PFBSettings boolForKey:@"unified_notifications"];
    });
    return on;
}

// The segmented screen of Notifications: the one whose tabs T1NotificationsViewController gives.
static BOOL PFBUnifiedOwns(id segmentedController) {
    static Class notifications;
    notifications = notifications ?: NSClassFromString(@"T1NotificationsViewController");
    SEL dataSource = NSSelectorFromString(@"dataSource");
    if (!PFBUnifiedOn() || !notifications || ![segmentedController respondsToSelector:dataSource]) {
        return NO;
    }
    return [((id (*)(id, SEL))objc_msgSend)(segmentedController, dataSource) isKindOfClass:notifications];
}

// An ivar is read only when it is pointer-sized and points into the heap, so a Swift value stored
// inline is never taken for an object.
static id PFBUnifiedObjectIvar(id object, const char* name) {
    if (!object) {
        return nil;
    }
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar* list = class_copyIvarList(cls, &count);
        Ivar found = NULL;
        for (unsigned int i = 0; i < count; i++) {
            if (strcmp(ivar_getName(list[i]) ?: "", name) == 0) {
                found = list[i];
            }
        }
        if (!found) {
            free(list);
            continue;
        }
        ptrdiff_t offset = ivar_getOffset(found);
        ptrdiff_t next = (ptrdiff_t)class_getInstanceSize(cls);
        for (unsigned int i = 0; i < count; i++) {
            ptrdiff_t other = ivar_getOffset(list[i]);
            if (other > offset && other < next) {
                next = other;
            }
        }
        free(list);
        if (next - offset != (ptrdiff_t)sizeof(void*)) {
            return nil;
        }
        void* raw = *(void**)((uint8_t*)(__bridge void*)object + offset);
        if (!raw || ((uintptr_t)raw >> 63) || !malloc_zone_from_ptr(raw)) {
            return nil;
        }
        return (__bridge id)raw;
    }
    return nil;
}

static id PFBUnifiedSend(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static NSString* PFBUnifiedString(id value) {
    if ([value isKindOfClass:[NSAttributedString class]]) {
        return [(NSAttributedString*)value string];
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

// MARK: - the words of a row

static Class PFBSearchNotificationClass(void) {
    static Class cls;
    cls = cls ?: NSClassFromString(@"_TtC10TwitterURT32URTTimelineNotificationViewModel");
    return cls;
}

static Class PFBSearchTweetClass(void) {
    static Class cls;
    cls = cls ?: NSClassFromString(@"URTTimelineStatusItemViewModel");
    return cls;
}

// Whether a row is a notification or a Tweet, the rows a search keeps or drops; the others
// (load more, headers) always stay.
static BOOL PFBSearchRowIsSearchable(id model) {
    return (PFBSearchNotificationClass() && [model isKindOfClass:PFBSearchNotificationClass()]) ||
           (PFBSearchTweetClass() && [model isKindOfClass:PFBSearchTweetClass()]);
}

// A notification's line ("X liked your post") or a Tweet's text and author, with the words its
// cell showed once on screen, such as the Tweet a notification carries. Kept per row.
static NSString* PFBSearchWords(id model) {
    NSString* kept = model ? [gPFBSearchModelWords objectForKey:model] : nil;
    if (kept) {
        return kept;
    }
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    if (PFBSearchNotificationClass() && [model isKindOfClass:PFBSearchNotificationClass()]) {
        id richText = PFBUnifiedObjectIvar(PFBUnifiedObjectIvar(model, "notification"), "richText");
        NSString* line = PFBUnifiedString(PFBUnifiedSend(richText, @"text"));
        if (line.length) {
            [words addObject:line];
        }
    } else if (PFBSearchTweetClass() && [model isKindOfClass:PFBSearchTweetClass()]) {
        id status = PFBUnifiedObjectIvar(model, "status");
        for (NSString* name in @[ @"text", @"fromUserName", @"fromUserFullName" ]) {
            NSString* part = PFBUnifiedString(PFBUnifiedSend(status, name));
            if (part.length) {
                [words addObject:part];
            }
        }
    }
    NSString* shown = model ? [gPFBSearchCellWords objectForKey:model] : nil;
    if (shown.length) {
        [words addObject:shown];
    }
    if (!words.count && PFBSearchRowIsSearchable(model)) {
        PFBCompatMeasure(@"unified notifications", [NSString stringWithFormat:@"no words in a %@ row", NSStringFromClass([model class])], 3);
    }
    NSString* joined = [words componentsJoinedByString:@" "];
    if (model) {
        gPFBSearchModelWords = gPFBSearchModelWords ?: [NSMapTable weakToStrongObjectsMapTable];
        [gPFBSearchModelWords setObject:joined forKey:model];
    }
    return joined;
}

// A dropped row's cell is hidden, and shown again only by the search that hid it.
static void PFBSearchMarkCell(UITableViewCell* cell, BOOL keep) {
    if (!keep) {
        cell.hidden = YES;
        objc_setAssociatedObject(cell, kPFBSearchDroppedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(cell, kPFBSearchDroppedKey)) {
        cell.hidden = NO;
        objc_setAssociatedObject(cell, kPFBSearchDroppedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Every word typed must appear, whatever its case or accents.
static BOOL PFBSearchKeeps(id model) {
    if (!gPFBSearchQuery.length || !PFBSearchRowIsSearchable(model)) {
        return YES;
    }
    NSString* words = PFBSearchWords(model);
    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    for (NSString* term in [gPFBSearchQuery componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (term.length && [words rangeOfString:term options:options].location == NSNotFound) {
            return NO;
        }
    }
    return YES;
}

// MARK: - the lists searched

// A list of the Notifications screen, settled once its screen is known.
static BOOL PFBSearchOwnsList(id list) {
    if (!PFBUnifiedOn() || ![list isKindOfClass:[UIViewController class]]) {
        return NO;
    }
    NSNumber* known = objc_getAssociatedObject(list, kPFBSearchListKey);
    if (known) {
        return known.boolValue;
    }
    if (!((UIViewController*)list).parentViewController) {
        return NO;
    }
    BOOL owns = PFBNotifControllerOnNotificationsScreen(list);
    objc_setAssociatedObject(list, kPFBSearchListKey, @(owns), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return owns;
}

static id PFBSearchModelAt(id list, NSIndexPath* indexPath) {
    SEL itemSel = NSSelectorFromString(@"itemAtIndexPath:");
    if (![list respondsToSelector:itemSel]) {
        return nil;
    }
    id item = ((id (*)(id, SEL, id))objc_msgSend)(list, itemSel, indexPath);
    return PFBUnwrapDataViewItem(item) ?: item;
}

// "No results" while words are typed and none of the list's notifications holds them.
static void PFBSearchSyncPanel(UITableView* table) {
    id list = table.dataSource;
    NSInteger searchable = 0, kept = 0;
    if (gPFBSearchQuery.length) {
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                id model = PFBSearchModelAt(list, [NSIndexPath indexPathForRow:row inSection:section]);
                if (PFBSearchRowIsSearchable(model)) {
                    searchable++;
                    kept += PFBSearchKeeps(model) ? 1 : 0;
                }
            }
        }
    }
    UIView* panel = objc_getAssociatedObject(table, kPFBSearchPanelKey);
    if (searchable == 0 || kept > 0) {
        [panel removeFromSuperview];
        objc_setAssociatedObject(table, kPFBSearchPanelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSString* title = [bundle localizedStringForKey:@"NOTIF_SEARCH_EMPTY_TITLE"];
    NSString* body = [NSString stringWithFormat:[bundle localizedStringForKey:@"NOTIF_SEARCH_EMPTY_BODY"], gPFBSearchQuery];
    if (!panel) {
        panel = PFBNotifEmptyPanel(title, body);
        panel.tag = kPFBSearchPanelTag;
        objc_setAssociatedObject(table, kPFBSearchPanelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        PFBNotifSetEmptyPanelText(panel, title, body);
    }
    PFBNotifPlaceEmptyPanel(panel, table);
}

// The shown cells take the search at once; the others take it as the list lays them out.
static void PFBSearchApply(UITableView* table, BOOL toTop) {
    id list = table.dataSource;
    [table beginUpdates];
    [table endUpdates];
    for (NSIndexPath* indexPath in table.indexPathsForVisibleRows) {
        UITableViewCell* cell = [table cellForRowAtIndexPath:indexPath];
        if (cell) {
            PFBSearchMarkCell(cell, PFBSearchKeeps(PFBSearchModelAt(list, indexPath)));
        }
    }
    if (toTop) {
        [table setContentOffset:CGPointMake(table.contentOffset.x, -table.adjustedContentInset.top) animated:NO];
    }
    PFBSearchSyncPanel(table);
    if (gPFBSearchQuery.length) {
        PFBCOMPAT_ACTION(PFBCompat_unified_notifications, @"list searched");
    }
}

// The list shown under the field: the visible table of the Notifications pages.
static UITableView* PFBSearchShownList(UIView* root) {
    if ([root isKindOfClass:[UITableView class]] && root.window && !root.hidden &&
        PFBSearchOwnsList(((UITableView*)root).dataSource)) {
        return (UITableView*)root;
    }
    for (UIView* sub in root.subviews) {
        UITableView* found = PFBSearchShownList(sub);
        if (found) {
            return found;
        }
    }
    return nil;
}

// MARK: - the field

// Twitter's field colors, measured on its own field in light; the system's in dark.
static UIColor* PFBSearchColor(CGFloat lightWhite, UIColor* dark) {
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
      return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [dark resolvedColorWithTraitCollection:traits]
                                                                     : [UIColor colorWithWhite:lightWhite alpha:1.0];
    }];
}

@interface PFBNotifSearchBar : UIView <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITextField* field;
@property (nonatomic, strong) UIImageView* glyph;
@property (nonatomic, weak) UIViewController* screen;
@property (nonatomic, strong) UITapGestureRecognizer* outsideTap;
@end

@implementation PFBNotifSearchBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        NSString* placeholder = [[PFBBundle sharedBundle] localizedStringForKey:@"NOTIF_SEARCH_PLACEHOLDER"];
        UIFont* font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:kPFBSearchFontSize]);
        UIColor* gray = PFBSearchColor(169.0 / 255.0, [UIColor placeholderTextColor]);
        _field = [[UITextField alloc] init];
        _field.backgroundColor = PFBSearchColor(242.0 / 255.0, [UIColor tertiarySystemFillColor]);
        _field.layer.cornerRadius = kPFBSearchFieldHeight / 2.0;
        _field.font = font;
        _field.textColor = [UIColor labelColor];
        _field.tintColor = PFBBrandAccentColor();
        _field.attributedPlaceholder = [[NSAttributedString alloc]
            initWithString:placeholder
                attributes:@{NSFontAttributeName : font, NSForegroundColorAttributeName : gray}];
        _field.accessibilityLabel = placeholder;
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _field.returnKeyType = UIReturnKeySearch;
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.delegate = self;
        _glyph = [[UIImageView alloc] init];
        _glyph.contentMode = UIViewContentModeCenter;
        UIView* lead = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPFBSearchTextLeft, kPFBSearchFieldHeight)];
        _glyph.frame = CGRectMake(kPFBSearchGlyphLeft, 0, kPFBSearchGlyphSize, kPFBSearchFieldHeight);
        [lead addSubview:_glyph];
        _field.leftView = lead;
        _field.leftViewMode = UITextFieldViewModeAlways;
        [_field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_field];
        [self applyGlyph];
    }
    return self;
}

// Twitter's search glyph bakes its color in, so it is drawn again with each appearance.
- (void)applyGlyph {
    UIColor* gray = [PFBSearchColor(169.0 / 255.0, [UIColor placeholderTextColor]) resolvedColorWithTraitCollection:self.traitCollection];
    if ([UIImage respondsToSelector:@selector(tfn_vectorImageNamed:fitsSize:fillColor:)]) {
        self.glyph.image = [UIImage tfn_vectorImageNamed:@"search_stroke"
                                                fitsSize:CGSizeMake(kPFBSearchGlyphSize, kPFBSearchGlyphSize)
                                               fillColor:gray];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyGlyph];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    self.field.frame = CGRectMake(kPFBSearchSideInset, (CGRectGetHeight(bounds) - kPFBSearchFieldHeight) / 2.0,
                                  MAX(0, CGRectGetWidth(bounds) - kPFBSearchSideInset * 2.0), kPFBSearchFieldHeight);
}

- (void)textChanged {
    NSString* text = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL wasEmpty = gPFBSearchQuery.length == 0;
    gPFBSearchQuery = text.length ? text : nil;
    UITableView* table = PFBSearchShownList(self.screen.viewIfLoaded);
    if (table) {
        PFBSearchApply(table, wasEmpty != (gPFBSearchQuery.length == 0));
    }
}

// While the keyboard is up, a drag on the list or a tap anywhere but the field puts it away; the
// tap still reaches what it lands on, a notification or a button.
- (void)textFieldDidBeginEditing:(UITextField*)textField {
    PFBSearchShownList(self.screen.viewIfLoaded).keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    if (!self.outsideTap) {
        self.outsideTap = [[UITapGestureRecognizer alloc] initWithTarget:textField action:@selector(resignFirstResponder)];
        self.outsideTap.cancelsTouchesInView = NO;
        self.outsideTap.delegate = self;
    }
    [textField.window addGestureRecognizer:self.outsideTap];
}

- (void)textFieldDidEndEditing:(UITextField*)textField {
    [self.outsideTap.view removeGestureRecognizer:self.outsideTap];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldReceiveTouch:(UITouch*)touch {
    return ![touch.view isDescendantOfView:self.field];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer {
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [textField resignFirstResponder];
    return NO;
}

@end

// MARK: - the row

static Class PFBUnifiedTabBarClass(void) {
    static Class cls;
    cls = cls ?: NSClassFromString(@"_TtC10TFNUISwift25LegacySegmentedTabBarView");
    return cls;
}

static UIView* PFBUnifiedFindKind(UIView* root, Class cls, NSUInteger depth) {
    if (!cls || !root) {
        return nil;
    }
    if ([root isKindOfClass:cls]) {
        return root;
    }
    if (depth == 0) {
        return nil;
    }
    for (UIView* sub in root.subviews) {
        UIView* found = PFBUnifiedFindKind(sub, cls, depth - 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

// The row on screen over the room Twitter keeps for it under the bar: the tab bar drawn there.
static void PFBUnifiedCollectRows(UIView* root, CGRect zone, UIView** best, CGFloat* overlap) {
    if (root.hidden || root.alpha < 0.01) {
        return;
    }
    if ([root isKindOfClass:PFBUnifiedTabBarClass()]) {
        CGRect frame = [root convertRect:root.bounds toView:nil];
        CGRect shared = CGRectIntersection(frame, zone);
        CGFloat area = CGRectIsNull(shared) ? 0 : CGRectGetWidth(shared) * CGRectGetHeight(shared);
        if (area > *overlap) {
            *overlap = area;
            *best = root;
        }
        return;
    }
    for (UIView* sub in root.subviews) {
        PFBUnifiedCollectRows(sub, zone, best, overlap);
    }
}

// The row found for a screen, held weakly.
@interface PFBUnifiedRowRef : NSObject
@property (nonatomic, weak) UIView* row;
@end

@implementation PFBUnifiedRowRef
@end

// The row's own pieces give way to the field, which fills the row.
static void PFBUnifiedCoverRow(UIView* row, PFBNotifSearchBar* bar) {
    for (UIView* sub in row.subviews) {
        if (sub != bar) {
            sub.hidden = YES;
        }
    }
    bar.frame = row.bounds;
    [row bringSubviewToFront:bar];
}

// Sends the segmented screen to its first page and keeps the pager there.
static void PFBUnifiedHoldPager(id segmented) {
    UIViewController* pages = PFBUnifiedSend(segmented, @"pagingViewController");
    UICollectionView* pager = (UICollectionView*)PFBUnifiedFindKind(pages.viewIfLoaded, [UICollectionView class], 3);
    if (pager.scrollEnabled) {
        pager.scrollEnabled = NO;
        PFBCOMPAT_ACTION(PFBCompat_unified_notifications, @"swipe to Mentions off");
    }
}

static void PFBUnifiedInstall(UIViewController* screen) {
    UIView* zone = PFBUnifiedFindKind(screen.view, NSClassFromString(@"_TtC11XNavigation18AccessoryStackView"), 2);
    CGRect room = zone ? [zone convertRect:zone.bounds toView:nil] : CGRectNull;
    if (!screen.view.window || CGRectGetHeight(room) < 20.0) {
        return;
    }
    PFBUnifiedRowRef* ref = objc_getAssociatedObject(screen, kPFBSearchRowKey);
    UIView* row = ref.row.window ? ref.row : nil;
    if (!row) {
        CGFloat overlap = 0;
        PFBUnifiedCollectRows(screen.view.window, room, &row, &overlap);
    }
    if (!row) {
        PFBCompatMeasure(@"unified notifications",
                         [NSString stringWithFormat:@"field not placed: no row over the %.0f pt room under the bar", CGRectGetHeight(room)], 2);
        return;
    }
    if (ref.row != row) {
        ref = [[PFBUnifiedRowRef alloc] init];
        ref.row = row;
        objc_setAssociatedObject(screen, kPFBSearchRowKey, ref, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    PFBNotifSearchBar* bar = objc_getAssociatedObject(row, kPFBSearchBarKey);
    if (!bar) {
        bar = [[PFBNotifSearchBar alloc] initWithFrame:row.bounds];
        bar.screen = screen;
        if (gPFBSearchQuery.length) {
            bar.field.text = gPFBSearchQuery;
        }
        [row addSubview:bar];
        objc_setAssociatedObject(row, kPFBSearchBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PFBCOMPAT_ACTION(PFBCompat_unified_notifications, @"search field in place of the tabs");
    }
    PFBUnifiedCoverRow(row, bar);
    PFBUnifiedHoldPager(PFBUnifiedObjectIvar(screen, "$__lazy_storage_$_segmentedController"));
}

%hook T1NotificationsViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (PFBUnifiedOn()) {
        PFBUnifiedInstall((UIViewController*)self);
    }
}

%end

// The row keeps the field over its own pieces, which Twitter lays out again on each pass.
%hook _TtC10TFNUISwift25LegacySegmentedTabBarView

- (void)layoutSubviews {
    %orig;
    PFBNotifSearchBar* bar = objc_getAssociatedObject(self, kPFBSearchBarKey);
    if (bar) {
        PFBUnifiedCoverRow((UIView*)self, bar);
    }
}

%end

// The screen opens on All, whatever tab it was set to open on.
%hook _TtC10TFNUISwift29LegacySegmentedViewController

- (void)viewDidLoad {
    Ivar initial = PFBUnifiedOwns(self) ? class_getInstanceVariable(object_getClass(self), "initialSelectedIndex") : NULL;
    if (initial) {
        NSInteger* stored = (NSInteger*)((uint8_t*)(__bridge void*)self + ivar_getOffset(initial));
        if (*stored > 0) {
            *stored = 0;
            PFBCOMPAT_ACTION(PFBCompat_unified_notifications, @"opening tab kept on All");
        }
    }
    %orig;
}

%end

// Rows the search drops take no room and draw nothing; the words of each shown notification
// cell are kept for the next search.
%hook TFNItemsDataViewController

- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (gPFBSearchQuery.length && PFBSearchOwnsList((UIViewController*)self) &&
        !PFBSearchKeeps(PFBSearchModelAt(self, indexPath))) {
        return 0.0;
    }
    return %orig;
}

- (CGFloat)tableView:(UITableView*)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (gPFBSearchQuery.length && PFBSearchOwnsList((UIViewController*)self) &&
        !PFBSearchKeeps(PFBSearchModelAt(self, indexPath))) {
        return 0.0;
    }
    return %orig;
}

- (void)tableView:(UITableView*)tableView willDisplayCell:(UITableViewCell*)cell forRowAtIndexPath:(NSIndexPath*)indexPath {
    %orig;
    if (!PFBSearchOwnsList((UIViewController*)self)) {
        return;
    }
    static Class notificationCell;
    notificationCell = notificationCell ?: NSClassFromString(@"T1URTTimelineNotificationCell");
    id model = PFBSearchModelAt(self, indexPath);
    id viewModel = notificationCell && [cell isKindOfClass:notificationCell] ? PFBUnifiedObjectIvar(cell, "viewModel") : nil;
    if (viewModel && model) {
        NSMutableArray<NSString*>* shown = [NSMutableArray array];
        for (NSString* name in @[ @"titleTextModel", @"attributedSubTextModel" ]) {
            NSString* text = PFBUnifiedString(PFBUnifiedSend(PFBUnifiedObjectIvar(viewModel, name.UTF8String), @"attributedString"));
            if (text.length) {
                [shown addObject:text];
            }
        }
        gPFBSearchCellWords = gPFBSearchCellWords ?: [NSMapTable weakToStrongObjectsMapTable];
        [gPFBSearchCellWords setObject:[shown componentsJoinedByString:@" "] forKey:model];
        [gPFBSearchModelWords removeObjectForKey:model];
    }
    PFBSearchMarkCell(cell, PFBSearchKeeps(model));
    // Rows loaded while searching can end a "No results": checked once per pass of the list.
    if (gPFBSearchQuery.length && !gPFBSearchPanelPending) {
        gPFBSearchPanelPending = YES;
        __weak UITableView* weakTable = tableView;
        dispatch_async(dispatch_get_main_queue(), ^{
          gPFBSearchPanelPending = NO;
          if (weakTable) {
              PFBSearchSyncPanel(weakTable);
          }
        });
    }
}

%end
