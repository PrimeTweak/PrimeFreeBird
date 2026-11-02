// The rows of a settings page in Twitter's new look: one per group, opening the group in a sheet,
// and one per row that opens a screen, opening it from the page itself.

#import "Settings/Native/PFBNativeSettingsPageRows.h"
#import "Common/PFBBundle.h"
#import "Common/PFBSettings.h"
#import "Settings/Native/PFBNativeSettingsRowCell.h"
#import "Settings/Native/PFBNativeSettingsSheetController.h"
#import "Settings/PFBModernSettingsPageViewController.h"

static BOOL PFBRowIsGroup(NSDictionary* entry) {
    return [entry[@"type"] isEqualToString:@"header"];
}

@interface PFBNativeSettingsPageRows ()
@property (nonatomic, weak) PFBModernSettingsPageViewController* page;
@property (nonatomic, copy) NSArray<NSDictionary*>* rows;
@end

@implementation PFBNativeSettingsPageRows

- (instancetype)initWithPage:(PFBModernSettingsPageViewController*)page {
    if ((self = [super init])) {
        _page = page;
        _rows = @[];
    }
    return self;
}

- (void)showInTable:(UITableView*)table {
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = [PFBNativeSettingsRowStyle shared].rowHeight;
    [table registerClass:[PFBNativeSettingsRowCell class] forCellReuseIdentifier:@"NativeRow"];
}

// The page's own rules decide what shows. A group keeps its row while some of its rows stay in
// its sheet.
- (NSArray<NSDictionary*>*)currentRows {
    PFBModernSettingsPageViewController* page = self.page;
    NSArray<NSDictionary*>* entries = [PFBSettings settingsForPage:[page pageKey]];
    [page updateVisibleToggles];
    NSMutableArray<NSDictionary*>* rows = [NSMutableArray array];
    for (NSDictionary* entry in page.visibleToggles) {
        BOOL shown = PFBRowIsGroup(entry) ? [self group:entry keepsRowsOf:entries] : [entry[@"opensPage"] boolValue];
        if (shown) {
            [rows addObject:entry];
        }
    }
    return rows;
}

- (BOOL)group:(NSDictionary*)header keepsRowsOf:(NSArray<NSDictionary*>*)entries {
    NSUInteger start = [entries indexOfObjectIdenticalTo:header];
    if (start == NSNotFound) {
        return NO;
    }
    for (NSUInteger row = start + 1; row < entries.count && !PFBRowIsGroup(entries[row]); row++) {
        if (![entries[row][@"opensPage"] boolValue]) {
            return YES;
        }
    }
    return NO;
}

// Counted from the page's first header, as the sheet's page counts its group.
- (NSInteger)groupOf:(NSDictionary*)header in:(NSArray<NSDictionary*>*)entries {
    NSInteger group = -1;
    for (NSDictionary* entry in entries) {
        if (PFBRowIsGroup(entry)) {
            group++;
        }
        if (entry == header) {
            return group;
        }
    }
    return NSNotFound;
}

- (NSString*)titleOf:(NSDictionary*)entry {
    NSString* key = entry[@"titleKey"] ?: [NSString stringWithFormat:@"%@_TITLE", [entry[@"key"] uppercaseString]];
    return [[PFBBundle sharedBundle] localizedStringForKey:key];
}

// The stored choice a row names, or its default until one is made, as the classic row's subtitle.
- (NSString*)valueOf:(NSDictionary*)entry {
    NSString* key = entry[@"prefKeyForSubtitle"];
    if (!key) {
        return nil;
    }
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([stored isKindOfClass:[NSString class]]) {
        return stored;
    }
    NSString* fallback = entry[@"subtitleDefaultKey"];
    return fallback ? [[PFBBundle sharedBundle] localizedStringForKey:fallback] : entry[@"subtitleDefault"];
}

- (void)configure:(PFBNativeSettingsRowCell*)cell with:(NSDictionary*)entry {
    BOOL group = PFBRowIsGroup(entry);
    [cell configureWithTitle:[self titleOf:entry]
                    iconName:entry[@"icon"]
                       value:group ? nil : [self valueOf:entry]
                   accessory:group ? PFBNativeSettingsRowAccessoryMore : PFBNativeSettingsRowAccessoryChevron];
}

// Read again whenever the table asks, so a reload from anywhere shows the rows as they now stand.
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    self.rows = [self currentRows];
    return (NSInteger)self.rows.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBNativeSettingsRowCell* cell = [tableView dequeueReusableCellWithIdentifier:@"NativeRow"
                                                                     forIndexPath:indexPath];
    [self configure:cell with:self.rows[(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* entry = self.rows[(NSUInteger)indexPath.row];
    if (PFBRowIsGroup(entry)) {
        [self openGroup:entry];
    } else {
        [self open:entry at:indexPath];
    }
}

- (void)openGroup:(NSDictionary*)header {
    PFBModernSettingsPageViewController* page = self.page;
    NSInteger group = [self groupOf:header in:[PFBSettings settingsForPage:[page pageKey]]];
    if (!page || group == NSNotFound) {
        return;
    }
    PFBModernSettingsPageViewController* rows = [[[page class] alloc] initWithAccount:page.account
                                                                               pageKey:[page pageKey]
                                                                                 group:group];
    __weak typeof(self) weakSelf = self;
    [PFBNativeSettingsSheetController presentRows:rows
                                           titled:[self titleOf:header]
                                             from:page
                                           closed:^{
                                               [weakSelf showChanges];
                                           }];
}

// The action runs on the page, which is on the settings stack, as its classic row runs it.
- (void)open:(NSDictionary*)entry at:(NSIndexPath*)indexPath {
    PFBModernSettingsPageViewController* page = self.page;
    SEL action = entry[@"action"] ? NSSelectorFromString(entry[@"action"]) : NULL;
    if (!action || ![page respondsToSelector:action]) {
        return;
    }
    NSMutableDictionary* payload = [entry mutableCopy];
    payload[@"indexPath"] = indexPath;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [page performSelector:action withObject:payload];
#pragma clang diagnostic pop
}

// Once a sheet has gone, the rows its switches showed or hid come or go, and the others show
// their values as they now stand.
- (void)showChanges {
    UITableView* table = self.page.tableView;
    // A reload still waiting is done first, so the rows before the change are those on screen.
    [table layoutIfNeeded];
    NSArray<NSDictionary*>* before = self.rows;
    NSArray<NSDictionary*>* after = [self currentRows];
    NSMutableArray<NSIndexPath*>* gone = [NSMutableArray array];
    NSMutableArray<NSIndexPath*>* come = [NSMutableArray array];
    [before enumerateObjectsUsingBlock:^(NSDictionary* entry, NSUInteger row, __unused BOOL* stop) {
        if ([after indexOfObjectIdenticalTo:entry] == NSNotFound) {
            [gone addObject:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
        }
    }];
    [after enumerateObjectsUsingBlock:^(NSDictionary* entry, NSUInteger row, __unused BOOL* stop) {
        if ([before indexOfObjectIdenticalTo:entry] == NSNotFound) {
            [come addObject:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
        }
    }];
    self.rows = after;
    if (gone.count || come.count) {
        [table performBatchUpdates:^{
            [table deleteRowsAtIndexPaths:gone withRowAnimation:UITableViewRowAnimationFade];
            [table insertRowsAtIndexPaths:come withRowAnimation:UITableViewRowAnimationFade];
        }
                        completion:nil];
    }
    for (NSIndexPath* path in table.indexPathsForVisibleRows) {
        UITableViewCell* cell = [table cellForRowAtIndexPath:path];
        if ([cell isKindOfClass:[PFBNativeSettingsRowCell class]] && (NSUInteger)path.row < self.rows.count) {
            [self configure:(PFBNativeSettingsRowCell*)cell with:self.rows[(NSUInteger)path.row]];
        }
    }
}

@end
