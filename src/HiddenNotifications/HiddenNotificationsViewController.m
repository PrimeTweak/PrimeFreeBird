#import "HiddenNotificationsViewController.h"
#import "../Core/BHTBundle.h"
#import "../Core/TwitterChirpFont.h"
#import "../Hooks/HookHelpers.h"

// The registry lives in HiddenNotifications.x; these are its public reads.
extern NSArray<NSDictionary*>* NFBHiddenNotifList(void);
extern void NFBUnhideNotif(NSString* notifID);
extern void NFBUnhideAllNotifs(void);
extern double NFBNotifDaysLeft(NSDictionary* entry);
extern void nfbReapplyTimelineFilter(void);
extern UIColor* CurrentAccentColor(void);

// MARK: - The row

// Same construction as the muted-word row: text on the left, a soft pill on the
// right. Colours are derived from labelColor rather than the semantic system fills,
// which Twitter reinterprets.

// A label that carries its own horizontal padding, declared through its intrinsic
// size so Auto Layout keeps placing it. Measuring the padding by hand ties it to a
// neighbour that may not be there.
@interface NFBNotifPaddedLabel : UILabel
@end

@implementation NFBNotifPaddedLabel

static const CGFloat kNFBNotifPillPadding = 8.0;   // gauche et droite seulement

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width += kNFBNotifPillPadding * 2.0;
    return size;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fit = [super sizeThatFits:size];
    fit.width += kNFBNotifPillPadding * 2.0;
    return fit;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(
        rect, UIEdgeInsetsMake(0, kNFBNotifPillPadding, 0, kNFBNotifPillPadding))];
}

@end

@interface NFBHiddenNotifCell : UITableViewCell
@property (nonatomic, strong) UILabel* snippet;
@property (nonatomic, strong) UILabel* expiry;
@property (nonatomic, strong) NSLayoutConstraint* snippetTop;
@property (nonatomic, strong) NSLayoutConstraint* expiryBottom;
@property (nonatomic, strong) NSLayoutConstraint* snippetBottom;
- (void)applyEmptyLayout:(BOOL)empty;
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

    _expiry = [[NFBNotifPaddedLabel alloc] init];
    // Dimensions taken from the Muted words kindLabel: Chirp regular 12, text
    // at 60 %, background at 7 %, radius 5. Bold is deliberately not used, as
    // it made the pill too loud.
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

    // The remove glyph is gone: the left swipe is the only way to unhide, and
    // it already existed. The text now runs to the 14 pt margin, with the
    // expiry stacked underneath it.
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.contentView.preservesSuperviewLayoutMargins = NO;

    [_snippet setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                              forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        // Text: two lines at most, then an ellipsis.
        [_snippet.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                               constant:14],
        (_snippetTop = [_snippet.topAnchor
            constraintEqualToAnchor:self.contentView.topAnchor constant:12]),
        // With no remove glyph, the text runs to the margin.
        [_snippet.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                               constant:-14],

        // The expiry sits under the text and never competes with it for width.
        [_expiry.leadingAnchor constraintEqualToAnchor:_snippet.leadingAnchor],
        [_expiry.topAnchor constraintEqualToAnchor:_snippet.bottomAnchor constant:6],
        [_expiry.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                         constant:-14],
        (_expiryBottom = [_expiry.bottomAnchor
            constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12]),
        [_expiry.heightAnchor constraintEqualToConstant:20],
    ]];
    return self;
}

// Empty state: the text stands alone, centred, with air above and below, using
// the dimensions of the Hide thread screen. With rows, everything returns to
// the normal two-line layout.
- (void)applyEmptyLayout:(BOOL)empty {
    if (!self.snippetBottom) {
        self.snippetBottom =
            [self.snippet.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                     constant:-28];
    }
    self.snippetTop.constant = empty ? 26 : 12;
    self.expiryBottom.active = !empty;
    self.snippetBottom.active = empty;
    self.snippet.numberOfLines = empty ? 0 : 2;
}

// Auto Layout owns the pill's position, at the leading edge under the text, and the
// padding comes from the label's own intrinsic size.

@end

// MARK: - The screen

@interface HiddenNotificationsViewController ()
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, strong) UIView* pinnedBar;
@property (nonatomic, strong) UIVisualEffectView* barMaterial;
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
    // The row stacks text (up to two lines) above the expiry, so rows self-size;
    // a fixed height would clip them.
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    // The card is opaque; only the pinned bar carries glass, like the
    // muted-words footer.
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    if (self.compact) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    }
    [self installPinnedBar];
    [self reload];
}

- (void)reload {
    self.rows = NFBHiddenNotifList();
    [self.tableView reloadData];
    // Reloading adds cells above the pinned bar, so its order is restored here.
    [self.tableView bringSubviewToFront:self.pinnedBar];
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
    // The pinned bar sits over the table, so its height and the arrow's reserve are
    // added to the rows'. With nothing hidden the bar is gone and the message row,
    // which carries its own air, sets the size alone.
    CGFloat height = self.tableView.contentSize.height;
    if (self.rows.count) {
        height = MAX(MIN(height + kNFBNotifBarHeight, 330), 90) + NFBPopoverArrowReserve;
    }
    self.preferredContentSize = CGSizeMake(290, height);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.tableView bringSubviewToFront:self.pinnedBar];
    [self updateBarMaterial];
    [self updatePreferredSize];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.compact) {
        NFBPopoverLogOverflow(self.view);
    }
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
    NFBHiddenNotifCell* cell =
        [tableView dequeueReusableCellWithIdentifier:@"nfbHiddenNotif"];
    if (!cell) {
        cell = [[NFBHiddenNotifCell alloc] initWithStyle:UITableViewCellStyleDefault
                                         reuseIdentifier:@"nfbHiddenNotif"];
    }
    // Recycling: every state a previous row could have left behind is reset.
    cell.contentView.alpha = 1.0;
    cell.snippet.font = [UIFont systemFontOfSize:14.5];
    cell.snippet.textColor = [UIColor labelColor];
    cell.snippet.textAlignment = NSTextAlignmentNatural;
    [cell applyEmptyLayout:NO];

    if (!self.rows.count) {
        // Dimensions of the Hide thread screen: the row label at Chirp 16.5,
        // in full secondary colour rather than reduced opacity, which made the
        // text ghostly, and centred with air around it.
        cell.snippet.text =
            [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXAMPLE"];
        cell.snippet.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:16.5];
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
        : [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_UNTITLED"];
    cell.expiry.hidden = NO;
    NSInteger days = (NSInteger)ceil(NFBNotifDaysLeft(row));
    // The countdown alone, on the existing pill, so nothing is added to the
    // layout.
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

// A subview of the table constrained to its frameLayoutGuide, the same construction
// as Quick access: it stays put, and no gesture on the rows can reach it. A table
// footer would scroll with the list.

static const CGFloat kNFBNotifBarHeight = 57.0;

- (void)installPinnedBar {
    if (self.pinnedBar || !self.compact) {
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
        [bar.heightAnchor constraintEqualToConstant:kNFBNotifBarHeight],
        [bar.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor
                                         constant:-NFBPopoverArrowReserve],

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

    self.barMaterial = NFBMaterialBehind(bar);
    self.pinnedBar = bar;
    self.pinnedCount = count;
}

- (void)refreshPinnedBar {
    if (!self.pinnedBar) {
        return;
    }
    self.pinnedBar.hidden = !self.rows.count;
    // The rows stop above the bar; with no rows there is no bar to clear.
    CGFloat bottom = self.rows.count ? kNFBNotifBarHeight + NFBPopoverArrowReserve : 0.0;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
    self.tableView.verticalScrollIndicatorInsets = self.tableView.contentInset;
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
