#import "Features/General/PFBHiddenNotificationsViewController.h"
#import "Common/PFBBundle.h"
#import "Support/TwitterChirpFont.h"
#import "Support/HookHelpers.h"
#import "Features/General/PFBHiddenNotifCell.h"

// MARK: - The screen

@interface PFBHiddenNotificationsViewController ()
@property (nonatomic, strong) UIView* pinnedBar;
@property (nonatomic, strong) UIVisualEffectView* barMaterial;
@property (nonatomic, strong) UILabel* pinnedCount;
@property (nonatomic, strong) UIButton* clearButton;
@property (nonatomic, strong) NSArray<NSDictionary*>* rows;
@end

@implementation PFBHiddenNotificationsViewController

- (instancetype)initCompact {
    self = [super initWithStyle:UITableViewStylePlain];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_TITLE"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    // The row stacks text (up to two lines) above the expiry, so rows self-size;
    // a fixed height would clip them.
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    // The card is opaque; only the pinned bar carries glass, like the
    // muted-words footer.
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self installPinnedBar];
    [self reload];
}

- (void)reload {
    self.rows = PFBHiddenNotifList();
    [self.tableView reloadData];
    // Reloading adds cells above the pinned bar, so its order is restored here.
    [self.tableView bringSubviewToFront:self.pinnedBar];
    [self refreshPinnedBar];
    [self updatePreferredSize];
}

- (void)updatePreferredSize {
    // Two passes: self-sizing rows report their real height only once the
    // first layout has measured them. One pass leaves the estimate in place.
    [self.tableView layoutIfNeeded];
    [self.tableView layoutIfNeeded];
    // The rows' height, the bubble's own top inset and the pinned bar below them. With
    // nothing hidden the bar is gone and the message row, which carries its own air,
    // sets the size alone.
    CGFloat systemTop = MAX(self.tableView.adjustedContentInset.top - self.tableView.contentInset.top, 0.0);
    CGFloat height = self.tableView.contentSize.height + systemTop;
    if (self.rows.count) {
        height = MAX(MIN(height + kPFBNotifBarHeight, 330), 90);
    }
    self.preferredContentSize = CGSizeMake(290, height);
}

// A CGColor does not follow the appearance by itself, so the border is set again.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.clearButton.layer.borderColor = [UIColor systemGray4Color].CGColor;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.tableView bringSubviewToFront:self.pinnedBar];
    [self updateBarMaterial];
    [self updatePreferredSize];
}

// The bar's material fades in as rows pass under it, the way system bars do.
- (void)updateBarMaterial {
    UIScrollView* list = self.tableView;
    CGFloat below = list.contentSize.height -
                    (list.contentOffset.y + CGRectGetHeight(list.bounds) -
                     list.adjustedContentInset.bottom);
    self.barMaterial.alpha = MIN(MAX(below / 8.0, 0.0), 1.0);
}

- (void)scrollViewDidScroll:(__unused UIScrollView*)scrollView {
    [self updateBarMaterial];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count ? (NSInteger)self.rows.count : 1;   // 1 = the example
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBHiddenNotifCell* cell =
        [tableView dequeueReusableCellWithIdentifier:@"pfbHiddenNotif"];
    if (!cell) {
        cell = [[PFBHiddenNotifCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:@"pfbHiddenNotif"];
    }
    // Recycling: every state a previous row could have left behind is reset.
    cell.contentView.alpha = 1.0;
    cell.snippet.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:14.5]);
    cell.snippet.textColor = [UIColor labelColor];
    cell.snippet.textAlignment = NSTextAlignmentNatural;
    [cell applyEmptyLayout:NO];

    if (!self.rows.count) {
        // Dimensions of the Hide thread screen: the row label at Chirp 16.5,
        // in full secondary color rather than reduced opacity, centered.
        cell.snippet.text =
            [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXAMPLE"];
        cell.snippet.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5]);
        cell.snippet.textColor = [UIColor secondaryLabelColor];
        cell.snippet.textAlignment = NSTextAlignmentCenter;
        cell.expiry.text = @"";
        cell.expiry.hidden = YES;
        [cell applyEmptyLayout:YES];
        return cell;
    }

    NSDictionary* row = self.rows[indexPath.row];
    NSString* text = row[@"t"];
    cell.snippet.text = text.length
        ? text
        : [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNTITLED"];
    cell.expiry.hidden = NO;
    // The days left, on the pill under the text.
    cell.expiry.text = [[PFBBundle sharedBundle] daysLeftText:(NSInteger)ceil(PFBNotifDaysLeft(row))];
    return cell;
}

// Swipe on this list unhides — the mirror of the gesture that hid it.
- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    return self.rows.count > 0;
}

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (!self.rows.count) {
        return nil;
    }
    NSString* title = [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNHIDE"];
    __weak typeof(self) weakSelf = self;
    NSDictionary* row = self.rows[indexPath.row];
    UIContextualAction* unhide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* view,
                                    void (^completion)(BOOL)) {
            PFBUnhideNotif(row[@"id"]);
            completion(YES);
            [weakSelf reload];
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[unhide]];
}

// MARK: - the pinned bar (count + clear all)

// A subview of the table constrained to its frameLayoutGuide, the same construction
// as Quick access: it stays put, and no gesture on the rows can reach it. A table
// footer would scroll with the list.

static const CGFloat kPFBNotifBarHeight = 57.0;

- (void)installPinnedBar {
    if (self.pinnedBar) {
        return;
    }
    UIView* bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor clearColor];

    UIView* hairline = [[UIView alloc] init];
    hairline.backgroundColor = [UIColor separatorColor];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:hairline];

    UILabel* count = [[UILabel alloc] init];
    count.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:13]);
    count.textColor = [UIColor secondaryLabelColor];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:count];

    UIButton* clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:[[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ALL"]
           forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    clear.titleLabel.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleSemibold) fontWithSize:13.5]);
    clear.layer.borderWidth = 1.0;
    clear.layer.borderColor = [UIColor systemGray4Color].CGColor;
    self.clearButton = clear;
    clear.layer.cornerRadius = 17.0;
    clear.layer.cornerCurve = kCACornerCurveContinuous;
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [clear addTarget:self
                  action:@selector(clearAllTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:clear];

    [self.tableView addSubview:bar];
    UILayoutGuide* frame = self.tableView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:kPFBNotifBarHeight],
        [bar.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor],

        [hairline.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [hairline.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],

        [count.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [count.centerYAnchor constraintEqualToAnchor:clear.centerYAnchor],
        [clear.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-14],
        [clear.leadingAnchor constraintGreaterThanOrEqualToAnchor:count.trailingAnchor
                                                         constant:12],
        [clear.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [clear.heightAnchor constraintEqualToConstant:34],
        [clear.widthAnchor constraintGreaterThanOrEqualToConstant:96],
    ]];

    self.barMaterial = PFBMaterialBehind(bar);
    self.pinnedBar = bar;
    self.pinnedCount = count;
}

- (void)refreshPinnedBar {
    if (!self.pinnedBar) {
        return;
    }
    self.pinnedBar.hidden = !self.rows.count;
    // The rows stop above the bar; with no rows there is no bar to clear.
    CGFloat bottom = self.rows.count ? kPFBNotifBarHeight : 0.0;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    self.tableView.verticalScrollIndicatorInsets = self.tableView.contentInset;
    if (!self.rows.count) {
        return;
    }
    NSString* format =
        [[PFBBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_COUNT"];
    self.pinnedCount.text = [NSString stringWithFormat:format, (long)self.rows.count];
}

// Every hidden notification comes back at once, so the question comes first.
- (void)clearAllTapped {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    NSInteger count = (NSInteger)self.rows.count;
    NSString* message = count == 1
        ? [bundle localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ONE_MESSAGE"]
        : [NSString stringWithFormat:[bundle localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ALL_MESSAGE"], (long)count];
    UIAlertController* confirm =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ALL_TITLE"]
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"CANCEL_ACTION"]
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    __weak typeof(self) weakSelf = self;
    UIAlertAction* unhide =
        [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ALL"]
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction* action) {
                                   PFBUnhideAllNotifs();
                                   // Nothing is left to manage: the bubble closes while the
                                   // list refreshes behind it.
                                   [weakSelf dismissViewControllerAnimated:YES completion:nil];
                               }];
    [confirm addAction:unhide];
    confirm.preferredAction = unhide;
    [self presentViewController:confirm animated:YES completion:nil];
}

@end
