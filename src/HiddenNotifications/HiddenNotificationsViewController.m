#import "HiddenNotificationsViewController.h"
#import "../Core/BHTBundle.h"

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
@property (nonatomic, strong) UIButton* unhide;
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
    _expiry.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    _expiry.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
    _expiry.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
    _expiry.textAlignment = NSTextAlignmentCenter;
    _expiry.layer.cornerRadius = 10.0;
    _expiry.layer.cornerCurve = kCACornerCurveContinuous;
    _expiry.clipsToBounds = YES;
    _expiry.translatesAutoresizingMaskIntoConstraints = NO;
    [_expiry setContentCompressionResistancePriority:UILayoutPriorityRequired
                                             forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_expiry];

    _unhide = [UIButton buttonWithType:UIButtonTypeSystem];
    [_unhide setImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
             forState:UIControlStateNormal];
    _unhide.tintColor = [[UIColor labelColor] colorWithAlphaComponent:0.25];
    _unhide.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_unhide];

    // Everything sat on ONE horizontal line with 8 pt between the parts: the
    // text ran into the expiry pill, the pill ran into the ⊗, and a long
    // notification pushed both off the edge. Measured cotes from the UI plate:
    // the expiry moves UNDER the text, margins are 14 all round, and the
    // gutter to the ⊗ is 12 — so nothing can collide any more.
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.contentView.preservesSuperviewLayoutMargins = NO;

    [_snippet setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                              forAxis:UILayoutConstraintAxisHorizontal];
    [_unhide setContentCompressionResistancePriority:UILayoutPriorityRequired
                                             forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        // texte — deux lignes maximum, puis « … »
        [_snippet.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                               constant:14],
        [_snippet.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [_snippet.trailingAnchor constraintEqualToAnchor:_unhide.leadingAnchor constant:-12],

        // expiration — sous le texte, plus jamais en concurrence de largeur
        [_expiry.leadingAnchor constraintEqualToAnchor:_snippet.leadingAnchor],
        [_expiry.topAnchor constraintEqualToAnchor:_snippet.bottomAnchor constant:6],
        [_expiry.trailingAnchor constraintLessThanOrEqualToAnchor:_unhide.leadingAnchor
                                                         constant:-12],
        [_expiry.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                             constant:-12],
        [_expiry.heightAnchor constraintEqualToConstant:20],

        // ⊗ — calé en haut à droite, marge 14
        [_unhide.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                               constant:-14],
        [_unhide.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:13],
        [_unhide.widthAnchor constraintEqualToConstant:26],
        [_unhide.heightAnchor constraintEqualToConstant:26],
    ]];
    return self;
}

// The pill sizes itself around its text — a plain label needs the padding drawn.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize fit = [self.expiry sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20)];
    CGRect frame = self.expiry.frame;
    frame.size.width = fit.width + 18;
    frame.origin.x = CGRectGetMinX(self.unhide.frame) - 8 - frame.size.width;
    self.expiry.frame = frame;
}

@end

// MARK: - The screen

@interface HiddenNotificationsViewController ()
@property (nonatomic, assign) BOOL compact;
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
    self.tableView.backgroundColor =
        self.compact ? [UIColor clearColor] : [UIColor systemBackgroundColor];
    if (self.compact) {
        self.view.backgroundColor = [UIColor clearColor];
    }
    [self reload];
}

- (void)reload {
    self.rows = NFBHiddenNotifList();
    [self.tableView reloadData];
    [self updatePreferredSize];
}

- (void)updatePreferredSize {
    if (!self.compact) {
        return;
    }
    [self.tableView layoutIfNeeded];
    CGFloat height = MIN(self.tableView.contentSize.height + 6, 330);
    self.preferredContentSize = CGSizeMake(290, MAX(height, 96));
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
    cell.unhide.hidden = NO;

    if (!self.rows.count) {
        cell.snippet.text =
            [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXAMPLE"];
        cell.expiry.text = @"";
        cell.expiry.hidden = YES;
        cell.unhide.hidden = YES;
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
    NSString* format =
        [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_EXPIRES_IN"];
    cell.expiry.text = [NSString stringWithFormat:format, (long)days];
    cell.unhide.tag = indexPath.row;
    [cell.unhide removeTarget:self
                       action:@selector(unhideTapped:)
             forControlEvents:UIControlEventTouchUpInside];
    [cell.unhide addTarget:self
                    action:@selector(unhideTapped:)
          forControlEvents:UIControlEventTouchUpInside];
    return cell;
}

- (void)unhideTapped:(UIButton*)sender {
    if (sender.tag >= (NSInteger)self.rows.count) {
        return;
    }
    NSDictionary* row = self.rows[sender.tag];
    NFBUnhideNotif(row[@"id"]);
    nfbReapplyTimelineFilter();
    [self reload];
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

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    return self.rows.count ? 78 : 0.01;
}

- (UIView*)tableView:(UITableView*)tableView viewForFooterInSection:(NSInteger)section {
    if (!self.rows.count) {
        return nil;
    }
    UIView* footer = [[UIView alloc] init];

    UILabel* count = [[UILabel alloc] init];
    NSString* format =
        [[BHTBundle sharedBundle] localizedStringForKey:@"HIDDEN_NOTIFS_COUNT"];
    count.text = [NSString stringWithFormat:format, (long)self.rows.count];
    count.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    count.textColor = [UIColor secondaryLabelColor];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:count];

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
    [footer addSubview:clear];

    [NSLayoutConstraint activateConstraints:@[
        [count.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:14],
        [count.centerYAnchor constraintEqualToAnchor:clear.centerYAnchor],
        [clear.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-14],
        [clear.leadingAnchor constraintGreaterThanOrEqualToAnchor:count.trailingAnchor
                                                         constant:12],
        [clear.topAnchor constraintEqualToAnchor:footer.topAnchor constant:11],
        [clear.heightAnchor constraintEqualToConstant:34],
        [clear.widthAnchor constraintGreaterThanOrEqualToConstant:96],
    ]];
    return footer;
}

- (void)clearAllTapped {
    NFBUnhideAllNotifs();
    nfbReapplyTimelineFilter();
    [self reload];
}

@end
