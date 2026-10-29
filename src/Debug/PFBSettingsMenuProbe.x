// Reads how Twitter's new settings menu builds its rows when it shows, as the tour opens it: its
// list, rows, header and bar buttons go to MEASUREMENTS, so a PrimeFreeBird row can find its place.

#import "Support/HookHelpers.h"
#import "Common/PFBCompatibility.h"
#import "Debug/PFBDebugger.h"

static NSString* const kPFBMenuProbeTopic = @"new settings";

// "_TtC9XSettings26SettingsListViewController" reads "XSettings.SettingsListViewController".
static NSString* PFBMenuProbeName(id object) {
    NSString* name = object ? NSStringFromClass([object class]) : @"none";
    if (![name hasPrefix:@"_TtC"] || [name hasPrefix:@"_TtCC"]) {
        return name;
    }
    const char* cursor = name.UTF8String + 4;
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    while (*cursor >= '0' && *cursor <= '9') {
        char* end = NULL;
        long length = strtol(cursor, &end, 10);
        if (length <= 0 || (long)strlen(end) < length) {
            return name;
        }
        [parts addObject:[[NSString alloc] initWithBytes:end length:(NSUInteger)length encoding:NSUTF8StringEncoding] ?: @"?"];
        cursor = end + length;
    }
    return parts.count == 2 && *cursor == '\0' ? [parts componentsJoinedByString:@"."] : name;
}

static NSString* PFBMenuProbeRect(CGRect rect) {
    return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", rect.origin.x, rect.origin.y, rect.size.width,
                                      rect.size.height];
}

// The first table or collection view under a view, breadth first.
static UIScrollView* PFBMenuProbeList(UIView* root) {
    NSMutableArray<UIView*>* queue = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
    for (NSUInteger i = 0; i < queue.count && i < 600; i++) {
        UIView* view = queue[i];
        if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) {
            return (UIScrollView*)view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

// The classes on the way from the screen's view down to its list.
static NSString* PFBMenuProbePath(UIView* root, UIView* list) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (UIView* node = list.superview; node && node != root && names.count < 8; node = node.superview) {
        [names insertObject:PFBMenuProbeName(node) atIndex:0];
    }
    return names.count ? [names componentsJoinedByString:@" > "] : @"directly in the screen";
}

// A row's parts: its labels with text, size and color, its images with size and tint, and its
// other bare views.
static NSString* PFBMenuProbeCellText(UIView* cell) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    PFBWalkAllSubviews(cell, 8, ^(UIView* view) {
      if (parts.count >= 12 || view == cell || view.hidden) {
          return;
      }
      CGRect frame = [view convertRect:view.bounds toView:cell];
      if ([view isKindOfClass:[UILabel class]]) {
          UILabel* label = (UILabel*)view;
          [parts addObject:[NSString stringWithFormat:@"label \"%@\" %@ %.1f pt %@", label.text ?: @"", PFBMenuProbeRect(frame),
                                                      label.font.pointSize, PFBColorText(label.textColor)]];
      } else if ([view isKindOfClass:[UIImageView class]] && ((UIImageView*)view).image) {
          [parts addObject:[NSString stringWithFormat:@"image %@ tint %@", PFBMenuProbeRect(frame),
                                                      PFBColorText(view.tintColor)]];
      } else if (!view.subviews.count) {
          [parts addObject:[NSString stringWithFormat:@"%@ %@", PFBMenuProbeName(view), PFBMenuProbeRect(frame)]];
      }
    });
    return parts.count ? [parts componentsJoinedByString:@", "] : @"empty";
}

static NSString* PFBMenuProbeItemsText(NSArray<UIBarButtonItem*>* items) {
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (UIBarButtonItem* item in items) {
        [names addObject:item.customView ? PFBMenuProbeName(item.customView)
                                         : (item.title.length ? item.title : (item.image ? @"image" : @"?"))];
    }
    return [NSString stringWithFormat:@"[%@]", [names componentsJoinedByString:@", "]];
}

// NO when the menu is no longer on screen, so its next appearance is read instead.
static BOOL PFBMenuProbeRead(UIViewController* menu) {
    UIView* root = menu.viewIfLoaded;
    if (!root.window) {
        return NO;
    }
    NSMutableArray<NSString*>* stack = [NSMutableArray array];
    for (UIViewController* screen in menu.navigationController.viewControllers) {
        [stack addObject:PFBMenuProbeName(screen)];
    }
    UINavigationItem* item = menu.navigationItem;
    NSMutableArray<NSString*>* lines = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"screen %@ in [%@]%@ · title view %@ · left %@ · right %@", PFBMenuProbeName(menu),
                                   [stack componentsJoinedByString:@", "], menu.presentingViewController ? @", presented" : @"",
                                   PFBMenuProbeName(item.titleView), PFBMenuProbeItemsText(item.leftBarButtonItems),
                                   PFBMenuProbeItemsText(item.rightBarButtonItems)]];
    UIScrollView* list = PFBMenuProbeList(root);
    if (!list) {
        [lines addObject:@"no table or collection view under the screen"];
    } else {
        BOOL table = [list isKindOfClass:[UITableView class]];
        id source = table ? (id)((UITableView*)list).dataSource : (id)((UICollectionView*)list).dataSource;
        id delegate = table ? (id)((UITableView*)list).delegate : (id)((UICollectionView*)list).delegate;
        NSInteger sections = table ? [(UITableView*)list numberOfSections] : [(UICollectionView*)list numberOfSections];
        NSMutableArray<NSString*>* counts = [NSMutableArray array];
        for (NSInteger section = 0; section < MIN(sections, 8); section++) {
            NSInteger rows = table ? [(UITableView*)list numberOfRowsInSection:section]
                                   : [(UICollectionView*)list numberOfItemsInSection:section];
            [counts addObject:[NSString stringWithFormat:@"%ld", (long)rows]];
        }
        SEL select = table ? @selector(tableView:didSelectRowAtIndexPath:) : @selector(collectionView:didSelectItemAtIndexPath:);
        UIView* header = table ? ((UITableView*)list).tableHeaderView : nil;
        [lines addObject:[NSString stringWithFormat:@"list %@ %@ under %@ · data source %@ · delegate %@, selects %@ · "
                                                    @"sections %ld, rows [%@] · inset top %.0f bottom %.0f · header %@",
                                                    PFBMenuProbeName(list), PFBMenuProbeRect([list convertRect:list.bounds toView:nil]),
                                                    PFBMenuProbePath(root, list), PFBMenuProbeName(source),
                                                    PFBMenuProbeName(delegate),
                                                    [delegate respondsToSelector:select] ? @"yes" : @"no", (long)sections,
                                                    [counts componentsJoinedByString:@" "], list.adjustedContentInset.top,
                                                    list.adjustedContentInset.bottom,
                                                    header ? [NSString stringWithFormat:@"%@ %@", PFBMenuProbeName(header),
                                                                                        PFBMenuProbeRect(header.frame)]
                                                           : @"none"]];
        NSArray<UIView*>* cells = table ? (NSArray<UIView*>*)((UITableView*)list).visibleCells
                                        : (NSArray<UIView*>*)((UICollectionView*)list).visibleCells;
        cells = [cells sortedArrayUsingComparator:^NSComparisonResult(UIView* a, UIView* b) {
          return CGRectGetMinY(a.frame) < CGRectGetMinY(b.frame) ? NSOrderedAscending : NSOrderedDescending;
        }];
        for (UIView* cell in [cells subarrayWithRange:NSMakeRange(0, MIN(cells.count, (NSUInteger)4))]) {
            NSIndexPath* path = table ? [(UITableView*)list indexPathForCell:(UITableViewCell*)cell]
                                      : [(UICollectionView*)list indexPathForCell:(UICollectionViewCell*)cell];
            [lines addObject:[NSString stringWithFormat:@"row %ld.%ld %@ %@ · %@", (long)path.section, (long)path.item,
                                                        PFBMenuProbeName(cell), PFBMenuProbeRect(cell.frame),
                                                        PFBMenuProbeCellText(cell)]];
        }
    }
    for (NSString* line in lines) {
        PFBCompatMeasure(kPFBMenuProbeTopic, line, 12);
    }
    return YES;
}

static BOOL gPFBMenuProbeRead;

BOOL PFBSettingsMenuProbeRead(void) {
    return gPFBMenuProbeRead;
}

%hook _TtC9XSettings26SettingsListViewController

// Read once per launch, after the rows are laid out.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gPFBMenuProbeRead) {
        return;
    }
    __weak UIViewController* menu = (UIViewController*)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (gPFBMenuProbeRead) {
          return;
      }
      @try {
          gPFBMenuProbeRead = PFBMenuProbeRead(menu);
      } @catch (id exception) {
          gPFBMenuProbeRead = YES;
          PFBCompatMeasure(kPFBMenuProbeTopic, [NSString stringWithFormat:@"stopped (%@)", exception], 12);
      }
    });
}

%end
