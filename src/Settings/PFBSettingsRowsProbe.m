// Journal lines on how far the rows of a settings list move; see PFBSettingsRowsProbe.h.

#import "Settings/PFBSettingsRowsProbe.h"
#import "Debug/PFBDebugger.h"
#import <math.h>

// The row's top as drawn right now, animations included, under the top of the list's visible
// area; NAN when the row has no cell. The sheet's own moves are noted apart, with its height.
static CGFloat PFBShownTop(UITableView* table, NSIndexPath* path) {
    UITableViewCell* cell = path ? [table cellForRowAtIndexPath:path] : nil;
    if (!cell) {
        return NAN;
    }
    CALayer* row = cell.layer.presentationLayer;
    CALayer* list = table.layer.presentationLayer;
    if (!row || !list) {
        row = cell.layer;
        list = table.layer;
    }
    return [row convertRect:row.bounds toLayer:list].origin.y - list.bounds.origin.y;
}

void PFBSettingsWatchRows(UITableView* table, NSString* reason) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    NSIndexPath* path = table.indexPathsForVisibleRows.firstObject;
    CGFloat start = PFBShownTop(table, path);
    if (isnan(start)) {
        return;
    }
    CGFloat offset = table.contentOffset.y;
    CGFloat content = table.contentSize.height;
    NSTimeInterval animation = UIView.inheritedAnimationDuration;
    __block CGFloat widest = 0;
    __weak UITableView* weakTable = table;
    // Read on the next frames, while an animation may run, then once any has ended.
    NSArray<NSNumber*>* delays = @[ @0, @0.017, @0.034, @0.05, @0.1, @0.2, @0.35, @0.6 ];
    [delays enumerateObjectsUsingBlock:^(NSNumber* delay, NSUInteger index, __unused BOOL* stop) {
        BOOL last = index + 1 == delays.count;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           UITableView* list = weakTable;
                           CGFloat top = PFBShownTop(list, path);
                           if (!isnan(top) && fabs(top - start) > fabs(widest)) {
                               widest = top - start;
                           }
                           if (!last) {
                               return;
                           }
                           NSString* end = isnan(top) ? @"off screen"
                                                      : [NSString stringWithFormat:@"%+.1f pt", top - start];
                           PFBDebugLog(@"[rows] %@: first row moved %+.1f pt at most, ends %@; offset %.1f -> %.1f, "
                                       @"content %.1f -> %.1f, inside an animation of %.2f s",
                                       reason, widest, end, offset, list.contentOffset.y, content,
                                       list.contentSize.height, animation);
                       });
    }];
}

void PFBSettingsNoteSheetHeight(CGFloat from, CGFloat to, BOOL opening) {
    PFBDebugLog(@"[rows] sheet height %.1f -> %.1f pt%@", from, to, opening ? @", while it opens" : @", animated");
}
