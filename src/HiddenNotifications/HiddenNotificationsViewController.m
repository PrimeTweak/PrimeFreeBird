#import "HiddenNotificationsViewController.h"
#import "../Core/BHTBundle.h"
#import "../Core/TwitterChirpFont.h"

// The registry lives in HiddenNotifications.x; these are its public reads.
extern NSArray<NSDictionary*>* NFBHiddenNotifList(void);
extern void NFBUnhideNotif(NSString* notifID);
extern void NFBUnhideAllNotifs(void);
extern double NFBNotifDaysLeft(NSDictionary* entry);
extern void nfbReapplyTimelineFilter(void);
extern UIColor* CurrentAccentColor(void);

// MARK: - The row
//
// Same construction as the muted-word row he signed off on: text on the left,
// a soft pill on the right, a ⊗ to remove. Colours are DERIVED FROM labelColor
// rather than taken from the semantic system fills — Twitter reinterprets
// those, and a badge came out unreadable once because of it.

@interface NFBHiddenNotifCell : UITableViewCell
@property (nonatomic, strong) UILabel* snippet;
@property (nonatomic, strong) UILabel* expiry;
@end

@implementation NFBHiddenNotifCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) {
        return nil;
    }
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _snippet = [[UILabel alloc] init];
    _snippet.font = [UIFont systemFontOfSize:14.5];
    _snippet.textColor = [UIColor labelColor];
    _snippet.numberOfLines = 2;
    _snippet.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_snippet];

    _expiry = [[UILabel alloc] init];
    // Cotes relevées sur sa cellule Muted words (kindLabel), à l'identique :
    // Chirp regular 12, texte à 60 %, fond à 7 %, rayon 5. Le gras est parti —
    // c'est lui qui rendait la pastille bavarde.
    _expiry.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:12];
    _expiry.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    _expiry.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
    _expiry.textAlignment = NSTextAlignmentCenter;
    _expiry.layer.cornerRadius = 5.0;
    _expiry.layer.cornerCurve = kCACornerCurveContinuous;
    _expiry.clipsToBounds = YES;
    _expiry.translatesAutoresizingMaskIntoConstraints = NO;
    [_expiry setContentCompressionResistancePriority:UILayoutPriorityRequired
                                             forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_expiry];

    // The ⊗ is gone — he asked for the left swipe to be the only way to
    // unhide, and it already existed. The text now runs to the 14 pt margin,
    // with the expiry stacked underneath it.
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.contentView.preservesSuperviewLayoutMargins = NO;

    [_snippet setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                              forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        // texte — deux lignes maximum, puis « … »
        [_snippet.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                               constant:14],
        [_snippet.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        // Le ⊗ est parti : le texte va jusqu'à la marge, comme il l'a demandé.
        [_snippet.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                               constant:-14],

        // expiration — sous le texte, plus jamais en concurrence de largeur
        [_expiry.leadingAnchor constraintEqualToAnchor:_snippet.leadingAnchor],
        [_expiry.topAnchor constraintEqualToAnchor:_snippet.bottomAnchor constant:6],
        [_expiry.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                         constant:-14],
        [_expiry.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                             constant:-12],
        [_expiry.heightAnchor constraintEqualToConstant:20],
    ]];
    return self;
}

// This used to place the pill by hand, measured from the ⊗ that no longer
// exists — with the button gone its frame is zero, and the pill would have been
// pushed off the left edge. Auto Layout now owns the position (leading edge,
// under the text) and the padding comes from the label's own intrinsic size.

@end

// MARK: - The screen

@interface HiddenNotificationsViewController ()
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, strong) UIView* pinnedBar;
@property (nonatomic, strong) UILabel* pinnedCount;
@property (nonatomic, strong) NSArray<NSDictionary*>* rows;
@end

@implementation HiddenNotificationsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (instancetype)initCompact {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _compact = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_TITLE"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    // The row now stacks text (up to two lines) above the expiry, so a fixed 52
    // would clip it. Self-sizing keeps every case correct.
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    // A popover paints its own material: forcing an opaque background here is
    // what once killed the glass on the muted-words popover.
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    if (self.compact) {
        // Was clear, which is why the navigation bar showed through as grey
        // blur inside the panel. His reference — the Muted words quick access —
        // is an opaque sheet, and so is this one now.
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    }
    [self installPinnedBar];
    [self reload];
}

- (void)reload {
    self.rows = NFBHiddenNotifList();
    [self.tableView reloadData];
    [self refreshPinnedBar];
    [self updatePreferredSize];
}

- (void)updatePreferredSize {
    if (!self.compact) {
        return;
    }
    // Two passes: self-sizing rows report their real height only once the
    // first layout has measured them. One pass leaves the estimate in place.
    [self.tableView layoutIfNeeded];
    [self.tableView layoutIfNeeded];
    // contentSize already includes the footer; no padding is added on top of
    // it, otherwise the sheet grows a strip of white at the bottom.
    // The pinned bar sits on top of the table, so its height is added rather
    // than being part of contentSize.
    CGFloat height = MIN(self.tableView.contentSize.height + kNFBNotifBarHeight, 330);
    self.preferredContentSize = CGSizeMake(290, MAX(height, 90));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePreferredSize];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count ? (NSInteger)self.rows.count : 1;   // 1 = the example
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NFBHiddenNotifCell* cell =
        [tableView dequeueReusableCellWithIdentifier:@"nfbHiddenNotif"];
    if (!cell) {
        cell = [[NFBHiddenNotifCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:@"nfbHiddenNotif"];
    }
    // Recycling: every state a previous row could have left behind is reset.
    cell.contentView.alpha = 1.0;

    if (!self.rows.count) {
        cell.snippet.text =
            [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXAMPLE"];
        cell.expiry.text = @"";
        cell.expiry.hidden = YES;
        cell.contentView.alpha = 0.38;
        return cell;
    }

    NSDictionary* row = self.rows[indexPath.row];
    NSString* text = row[@"t"];
    cell.snippet.text = text.length
        ? text
        : [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNTITLED"];
    cell.expiry.hidden = NO;
    NSInteger days = (NSInteger)ceil(NFBNotifDaysLeft(row));
    // He asked to see WHEN it expires, not only how long is left — kept on the
    // same pill so nothing is added to the layout: « 30d left · Sep 17 ».
    // He asked for the date to go: the countdown alone, and quieter.
    NSString* format =
        [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXPIRES_IN"];
    cell.expiry.text = [NSString stringWithFormat:format, (long)days];
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
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNHIDE"];
    __weak typeof(self) weakSelf = self;
    NSDictionary* row = self.rows[indexPath.row];
    UIContextualAction* unhide = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(__unused UIContextualAction* action,
                                    __unused UIView* view,
                                    void (^completion)(BOOL)) {
            NFBUnhideNotif(row[@"id"]);
            nfbReapplyTimelineFilter();
            completion(YES);
            [weakSelf reload];
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[unhide]];
}

// MARK: footer — the count and "clear all"

// MARK: - the pinned bar (count + clear all)
//
// It used to be a table footer, so it scrolled with the list and the swipe
// could grab it. His reference — the Quick access — pins its bar as a SUBVIEW
// of the table, constrained to the table's frameLayoutGuide: it stays put, and
// no gesture on the rows can ever reach it. Same construction here.

static const CGFloat kNFBNotifBarHeight = 57.0;

- (void)installPinnedBar {
    if (self.pinnedBar || !self.compact) {
        return;
    }
    UIView* bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor systemBackgroundColor];

    UIView* hairline = [[UIView alloc] init];
    hairline.backgroundColor = [UIColor separatorColor];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:hairline];

    UILabel* count = [[UILabel alloc] init];
    count.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    count.textColor = [UIColor secondaryLabelColor];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:count];

    UIButton* clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_CLEAR_ALL"]
           forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    clear.layer.borderWidth = 1.0;
    clear.layer.borderColor = [UIColor systemGray4Color].CGColor;
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
        [bar.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:kNFBNotifBarHeight],

        [hairline.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [hairline.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],

        [count.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [count.centerYAnchor constraintEqualToAnchor:clear.centerYAnchor],
        [clear.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-14],
        [clear.leadingAnchor constraintGreaterThanOrEqualToAnchor:count.trailingAnchor
                                                         constant:12],
        [clear.topAnchor constraintEqualToAnchor:bar.topAnchor constant:11],
        [clear.heightAnchor constraintEqualToConstant:34],
        [clear.widthAnchor constraintGreaterThanOrEqualToConstant:96],
    ]];

    self.pinnedBar = bar;
    self.pinnedCount = count;
    // The rows must not end up underneath it.
    self.tableView.contentInset =
        UIEdgeInsetsMake(0, 0, kNFBNotifBarHeight, 0);
    self.tableView.verticalScrollIndicatorInsets = self.tableView.contentInset;
}

- (void)refreshPinnedBar {
    self.pinnedBar.hidden = !self.rows.count;
    if (!self.rows.count) {
        return;
    }
    NSString* format =
        [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_COUNT"];
    self.pinnedCount.text = [NSString stringWithFormat:format, (long)self.rows.count];
}

- (void)clearAllTapped {
    NFBUnhideAllNotifs();
    nfbReapplyTimelineFilter();
    [self reload];
}

@end
