// The Advanced Search form in the new look: capsule fields, switches, dates and a language step.

#import "Features/Search/PFBAdvancedSearchViewController.h"
#import "Common/PFBBundle.h"
#import "Support/HookHelpers.h"
#import "Support/TwitterChirpFont.h"
#import <math.h>
#import "Features/Search/PFBAdvField.h"
#import "Features/Search/PFBAdvBoxCell.h"
#import "Features/Search/PFBAdvMenuCell.h"
#import "Features/Search/PFBAdvToggleCell.h"
#import "Features/Search/PFBAdvDateCell.h"
#import "Features/Search/PFBAdvLanguageViewController.h"
#import "Features/Search/PFBAdvancedSearchStyle.h"
#import "Support/PFBTwitterPopups.h"

// MARK: - section title

// A section's title in the palette's text color, set again when the appearance changes.
@interface PFBAdvSectionHead : UIView
@property (nonatomic, strong) UILabel* label;
@end

@implementation PFBAdvSectionHead

- (instancetype)initWithTitle:(NSString*)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _label = [[UILabel alloc] init];
        _label.text = title;
        _label.accessibilityTraits = UIAccessibilityTraitHeader;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kPFBAdvTextSide],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kPFBAdvTextSide],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0],
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    self.label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20]);
    self.label.textColor = PFBSettingsTextColor();
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end

// MARK: - controller

@interface PFBAdvancedSearchViewController ()
@property (nonatomic, strong) NSArray<NSString*>* sectionKeys;
@property (nonatomic, strong) NSArray<NSArray<PFBAdvField*>*>* sections;
@property (nonatomic, strong) NSArray<NSString*>* languageCodes;
@end

// A bar button tints a title with the glass material but leaves an original image as
// drawn, so the title is drawn into an image.
static UIImage* pfbBakedTitleImage(NSString* title, UIFont* font) {
    if (title.length == 0 || !font) {
        return nil;
    }
    NSDictionary* attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [UIColor whiteColor]
    };
    // A capsule built around an image comes out narrower than one built around a
    // title, so the difference is padded back into the bitmap transparently and the
    // button keeps its proportions.
    const CGFloat kSidePadding = 10.0;
    CGSize measured = [title sizeWithAttributes:attributes];
    CGSize size = CGSizeMake(ceilf((float)measured.width) + kSidePadding * 2.0,
                             ceilf((float)measured.height));
    if (size.width < 1.0 || size.height < 1.0) {
        return nil;
    }
    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* drawn = [renderer
        imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [title drawAtPoint:CGPointMake(kSidePadding, 0.0) withAttributes:attributes];
        }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@implementation PFBAdvancedSearchViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PFBThemeScreenEnter(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    PFBThemeScreenLeave(self);
}

// The page takes Twitter's background and the close glyph its text color, which change with
// the appearance.
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
    self.navigationItem.leftBarButtonItem.tintColor = PFBSettingsTextColor();
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PFBBundle* bundle = [PFBBundle sharedBundle];
    self.title = [bundle localizedStringForKey:@"ADVANCED_SEARCH_TITLE"];

    self.languageCodes = @[
        @"en", @"fr", @"es", @"de", @"it", @"pt", @"ja", @"ko", @"ar", @"ru",
        @"zh", @"hi", @"id", @"tr", @"nl", @"pl", @"sv", @"uk", @"fa", @"he",
        @"th", @"vi",
    ];

    self.sectionKeys = @[
        @"ADVSEARCH_SECTION_WORDS",
        @"ADVSEARCH_SECTION_ACCOUNTS",
        @"ADVSEARCH_SECTION_FILTERS",
        @"ADVSEARCH_SECTION_ENGAGEMENT",
        @"ADVSEARCH_SECTION_DATES",
    ];
    self.sections = @[
        @[
            [PFBAdvField key:@"pfb_advs_all" label:@"ADVSEARCH_ALL_WORDS"
                      example:@"ADVSEARCH_EX_ALL" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_exact" label:@"ADVSEARCH_EXACT_PHRASE"
                      example:@"ADVSEARCH_EX_EXACT" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_any" label:@"ADVSEARCH_ANY_WORDS"
                      example:@"ADVSEARCH_EX_ANY" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_none" label:@"ADVSEARCH_NONE_WORDS"
                      example:@"ADVSEARCH_EX_NONE" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_tags" label:@"ADVSEARCH_HASHTAGS"
                      example:@"ADVSEARCH_EX_TAGS" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_lang" label:@"ADVSEARCH_LANGUAGE"
                      example:nil kind:PFBAdvFieldMenu],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_from" label:@"ADVSEARCH_FROM_ACCOUNTS"
                      example:@"ADVSEARCH_EX_FROM" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_to" label:@"ADVSEARCH_TO_ACCOUNTS"
                      example:@"ADVSEARCH_EX_TO" kind:PFBAdvFieldText],
            [PFBAdvField key:@"pfb_advs_mention" label:@"ADVSEARCH_MENTIONING"
                      example:@"ADVSEARCH_EX_MENTION" kind:PFBAdvFieldText],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_replies" label:@"ADVSEARCH_REPLIES"
                      example:@"ADVSEARCH_REPLIES_SUB" kind:PFBAdvFieldToggle],
            [PFBAdvField key:@"pfb_advs_links" label:@"ADVSEARCH_LINKS"
                      example:@"ADVSEARCH_LINKS_SUB" kind:PFBAdvFieldToggle],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_minreplies" label:@"ADVSEARCH_MIN_REPLIES"
                      example:@"ADVSEARCH_EX_MINREPLIES" kind:PFBAdvFieldNumber],
            [PFBAdvField key:@"pfb_advs_minfaves" label:@"ADVSEARCH_MIN_LIKES"
                      example:@"ADVSEARCH_EX_MINLIKES" kind:PFBAdvFieldNumber],
            [PFBAdvField key:@"pfb_advs_minrt" label:@"ADVSEARCH_MIN_REPOSTS"
                      example:@"ADVSEARCH_EX_MINREPOSTS" kind:PFBAdvFieldNumber],
        ],
        @[
            [PFBAdvField key:@"pfb_advs_since" label:@"ADVSEARCH_SINCE_DATE"
                      example:@"ADVSEARCH_EX_SINCE" kind:PFBAdvFieldDate],
            [PFBAdvField key:@"pfb_advs_until" label:@"ADVSEARCH_UNTIL_DATE"
                      example:@"ADVSEARCH_EX_UNTIL" kind:PFBAdvFieldDate],
        ],
    ];

    // With Liquid Glass, a system Done button gives one native capsule, which NavBarIcons.x
    // tints system blue under the white title; a custom view would get a second capsule.
    // Without it, the title is plain text in the label color.
    NSString* searchTitle = [bundle localizedStringForKey:@"ADVSEARCH_SEARCH"];
    UIFont* searchFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15]);
    UIImage* bakedTitle = [PFBSettings boolForKey:@"enable_liquid_glass"]
                              ? pfbBakedTitleImage(searchTitle, searchFont)
                              : nil;
    if (bakedTitle) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithImage:bakedTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(pfbRunSearch)];
        // The title is drawn as an image, so VoiceOver gets it as the label.
        self.navigationItem.rightBarButtonItem.accessibilityLabel = searchTitle;
    } else {
        UIBarButtonItem* search = [[UIBarButtonItem alloc] initWithTitle:searchTitle
                                                                   style:UIBarButtonItemStyleDone
                                                                  target:self
                                                                  action:@selector(pfbRunSearch)];
        NSDictionary* attributes =
            @{NSFontAttributeName : searchFont, NSForegroundColorAttributeName : [UIColor labelColor]};
        [search setTitleTextAttributes:attributes forState:UIControlStateNormal];
        [search setTitleTextAttributes:attributes forState:UIControlStateHighlighted];
        self.navigationItem.rightBarButtonItem = search;
    }

    // Twitter's close glyph, as its sheets have; marked for the bar-glass pass, it keeps the
    // capsule iOS gives it.
    if (self.presentingViewController) {
        UIBarButtonItem* close = [[UIBarButtonItem alloc]
            initWithImage:PFBTwitterGlyphFor(@"close_nomargin", [UIImage systemImageNamed:@"xmark"])
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:@selector(pfbCancel)];
        close.tintColor = PFBSettingsTextColor();
        close.accessibilityLabel = [bundle localizedTwitterStringForKey:@"CLOSE_ACTION_LABEL"];
        objc_setAssociatedObject(close, @selector(pfbKeepsBarGlass), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.navigationItem.leftBarButtonItem = close;
    }
    // The language step's back button shows its chevron alone.
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    NSDictionary* chirpTitle = @{
        NSFontAttributeName : PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17])
    };
    self.navigationController.navigationBar.titleTextAttributes = chirpTitle;

    // The outlined capsule of the new look's Reset to default.
    PFBShowcaseButton* clear = [PFBShowcaseButton buttonWithStyle:PFBShowcaseButtonStyleOutline];
    clear.label = [bundle localizedStringForKey:@"ADVSEARCH_CLEAR"];
    [clear addTarget:self
                  action:@selector(pfbClearAll)
        forControlEvents:UIControlEventTouchUpInside];
    CGFloat clearHeight = [clear sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].height;
    UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 20.0 + clearHeight + 24.0)];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:clear];
    [NSLayoutConstraint activateConstraints:@[
        [clear.topAnchor constraintEqualToAnchor:footer.topAnchor constant:20.0],
        [clear.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:kPFBAdvFieldSide],
        [clear.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-kPFBAdvFieldSide],
        [clear.heightAnchor constraintEqualToConstant:clearHeight],
    ]];
    self.tableView.tableFooterView = footer;

    self.tableView.backgroundColor = [PFBPalette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[PFBAdvBoxCell class]
           forCellReuseIdentifier:@"box"];
    [self.tableView registerClass:[PFBAdvMenuCell class]
           forCellReuseIdentifier:@"menu"];
    [self.tableView registerClass:[PFBAdvToggleCell class]
           forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:[PFBAdvDateCell class]
           forCellReuseIdentifier:@"date"];
    self.tableView.keyboardDismissMode =
        UIScrollViewKeyboardDismissModeInteractive;
}

// MARK: language helpers

static NSString* PFBAdvLangName(NSString* code) {
    NSString* name =
        [[NSLocale currentLocale] localizedStringForLanguageCode:code];
    if (name.length) {
        return [[[name substringToIndex:1] localizedUppercaseString]
            stringByAppendingString:[name substringFromIndex:1]];
    }
    return code;
}

- (NSString*)pfbCurrentLanguageTitle {
    NSString* code =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"];
    if (code.length == 0) {
        return [[PFBBundle sharedBundle]
            localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"];
    }
    return PFBAdvLangName(code);
}

// The language step: Any language first, then the languages in the form's order.
- (void)pfbOpenLanguages {
    NSMutableArray<NSString*>* titles =
        [NSMutableArray arrayWithObject:[[PFBBundle sharedBundle] localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"]];
    NSMutableArray<NSString*>* codes = [NSMutableArray arrayWithObject:@""];
    for (NSString* code in self.languageCodes) {
        [titles addObject:PFBAdvLangName(code)];
        [codes addObject:code];
    }
    NSString* current = [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"] ?: @"";
    __weak typeof(self) weakSelf = self;
    PFBAdvLanguageViewController* step =
        [[PFBAdvLanguageViewController alloc] initWithTitles:titles
                                                       codes:codes
                                                      chosen:current
                                                        pick:^(NSString* code) {
                                                            NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
                                                            if (code.length) {
                                                                [defaults setObject:code forKey:@"pfb_advs_lang"];
                                                            } else {
                                                                [defaults removeObjectForKey:@"pfb_advs_lang"];
                                                            }
                                                            [weakSelf.tableView reloadData];
                                                        }];
    [self.navigationController pushViewController:step animated:YES];
}

// Filters default ON (the web form's default): absent key means included.
static BOOL PFBAdvFilterOn(NSString* key) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    return ([d objectForKey:key] == nil) ? YES : [d boolForKey:key];
}

// MARK: table

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView*)tableView
    numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (UIView*)tableView:(UITableView*)tableView
    viewForHeaderInSection:(NSInteger)section {
    return [[PFBAdvSectionHead alloc]
        initWithTitle:[[PFBBundle sharedBundle] localizedStringForKey:self.sectionKeys[(NSUInteger)section]]];
}

- (CGFloat)tableView:(UITableView*)tableView
    heightForHeaderInSection:(NSInteger)section {
    return 46.0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    PFBAdvField* model =
        self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    switch (model.kind) {
        case PFBAdvFieldMenu: {
            PFBAdvMenuCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"menu"
                                                forIndexPath:indexPath];
            __weak typeof(self) weakSelf = self;
            [cell configureWith:model
                   currentTitle:[self pfbCurrentLanguageTitle]
                           open:^{
                               [weakSelf pfbOpenLanguages];
                           }];
            return cell;
        }
        case PFBAdvFieldToggle: {
            PFBAdvToggleCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"toggle"
                                                forIndexPath:indexPath];
            [cell configureWith:model on:PFBAdvFilterOn(model.storeKey)];
            return cell;
        }
        case PFBAdvFieldDate: {
            PFBAdvDateCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"date"
                                                forIndexPath:indexPath];
            [cell configureWith:model];
            return cell;
        }
        default: {
            PFBAdvBoxCell* cell =
                [tableView dequeueReusableCellWithIdentifier:@"box"
                                                forIndexPath:indexPath];
            [cell configureWith:model];
            return cell;
        }
    }
}

// MARK: actions

- (void)pfbCancel {
    [self.presentingViewController dismissViewControllerAnimated:YES
                                                      completion:nil];
}

// Every field and filter of the form is emptied, so the question comes first.
- (void)pfbClearAll {
    PFBBundle* bundle = [PFBBundle sharedBundle];
    UIAlertController* confirm =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"ADVSEARCH_CLEAR"]
                                            message:[bundle localizedStringForKey:@"ADVSEARCH_CLEAR_CONFIRM_MESSAGE"]
                                     preferredStyle:UIAlertControllerStyleAlert];
    PFBAlertAddAction(confirm, [bundle localizedStringForKey:@"CANCEL_ACTION"], UIAlertActionStyleCancel, YES, nil);
    __weak typeof(self) weakSelf = self;
    PFBAlertAddAction(confirm, [bundle localizedStringForKey:@"ADVSEARCH_CLEAR_ACTION"], UIAlertActionStyleDestructive,
                      YES, ^{
                          [weakSelf pfbEmptyForm];
                      });
    PFBAlertPresent(confirm, self, YES, nil);
}

- (void)pfbEmptyForm {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    for (NSArray<PFBAdvField*>* section in self.sections) {
        for (PFBAdvField* f in section) {
            [d removeObjectForKey:f.storeKey];
        }
    }
    [self.tableView reloadData];
}

// MARK: query building

static NSArray<NSString*>* PFBAdvTokens(NSString* raw) {
    NSMutableArray* out = [NSMutableArray array];
    NSCharacterSet* seps =
        [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    for (NSString* t in [raw componentsSeparatedByCharactersInSet:seps]) {
        NSString* trimmed = [t stringByTrimmingCharactersInSet:
                                   [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length) { [out addObject:trimmed]; }
    }
    return out;
}

static NSString* PFBAdvOrGroup(NSArray<NSString*>* tokens) {
    if (tokens.count == 1) { return tokens[0]; }
    return [NSString stringWithFormat:@"(%@)",
                                      [tokens componentsJoinedByString:@" OR "]];
}

static NSString* PFBAdvValue(NSString* key) {
    NSString* v = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return [v stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceCharacterSet]] ?: @"";
}

- (NSString*)pfbBuildQueryOrError:(NSString**)errorKey {
    NSMutableArray* parts = [NSMutableArray array];

    NSString* all = PFBAdvValue(@"pfb_advs_all");
    if (all.length) { [parts addObject:all]; }

    NSString* exact = PFBAdvValue(@"pfb_advs_exact");
    if (exact.length) {
        [parts addObject:[NSString stringWithFormat:@"\"%@\"", exact]];
    }

    NSArray* any = PFBAdvTokens(PFBAdvValue(@"pfb_advs_any"));
    if (any.count) { [parts addObject:PFBAdvOrGroup(any)]; }

    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_none"))) {
        [parts addObject:[NSString stringWithFormat:@"-%@", t]];
    }

    NSMutableArray* tags = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_tags"))) {
        [tags addObject:[t hasPrefix:@"#"]
                            ? t
                            : [NSString stringWithFormat:@"#%@", t]];
    }
    if (tags.count) { [parts addObject:PFBAdvOrGroup(tags)]; }

    NSString* lang =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"];
    if (lang.length) {
        [parts addObject:[NSString stringWithFormat:@"lang:%@", lang]];
    }

    NSMutableArray* from = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_from"))) {
        NSString* u = [t hasPrefix:@"@"] ? [t substringFromIndex:1] : t;
        [from addObject:[NSString stringWithFormat:@"from:%@", u]];
    }
    if (from.count) { [parts addObject:PFBAdvOrGroup(from)]; }

    NSMutableArray* to = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_to"))) {
        NSString* u = [t hasPrefix:@"@"] ? [t substringFromIndex:1] : t;
        [to addObject:[NSString stringWithFormat:@"to:%@", u]];
    }
    if (to.count) { [parts addObject:PFBAdvOrGroup(to)]; }

    NSMutableArray* mention = [NSMutableArray array];
    for (NSString* t in PFBAdvTokens(PFBAdvValue(@"pfb_advs_mention"))) {
        NSString* u = [t hasPrefix:@"@"] ? t
                                         : [NSString stringWithFormat:@"@%@", t];
        [mention addObject:u];
    }
    if (mention.count) { [parts addObject:PFBAdvOrGroup(mention)]; }

    if (!PFBAdvFilterOn(@"pfb_advs_replies")) {
        [parts addObject:@"-filter:replies"];
    }
    if (!PFBAdvFilterOn(@"pfb_advs_links")) {
        [parts addObject:@"-filter:links"];
    }

    struct {
        __unsafe_unretained NSString* key;
        __unsafe_unretained NSString* op;
    } mins[] = {
        { @"pfb_advs_minreplies", @"min_replies" },
        { @"pfb_advs_minfaves", @"min_faves" },
        { @"pfb_advs_minrt", @"min_retweets" },
    };
    for (size_t i = 0; i < sizeof(mins) / sizeof(mins[0]); i++) {
        NSString* v = PFBAdvValue(mins[i].key);
        if (v.length && v.integerValue > 0) {
            [parts addObject:[NSString stringWithFormat:@"%@:%ld", mins[i].op,
                                                        (long)v.integerValue]];
        }
    }

    NSString* since = PFBAdvValue(@"pfb_advs_since");
    if (since.length) {
        [parts addObject:[NSString stringWithFormat:@"since:%@", since]];
    }
    NSString* until = PFBAdvValue(@"pfb_advs_until");
    if (until.length) {
        [parts addObject:[NSString stringWithFormat:@"until:%@", until]];
    }

    if (!parts.count) {
        *errorKey = @"ADVSEARCH_EMPTY";
        return nil;
    }
    return [parts componentsJoinedByString:@" "];
}

// MARK: launch

- (void)pfbRunSearch {
    [self.view endEditing:YES];
    NSString* errorKey = nil;
    NSString* query = [self pfbBuildQueryOrError:&errorKey];
    if (!query) {
        PFBBundle* bundle = [PFBBundle sharedBundle];
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:[bundle localizedStringForKey:@"ADVSEARCH_EMPTY_TITLE"]
                             message:[bundle localizedStringForKey:errorKey]
                      preferredStyle:UIAlertControllerStyleAlert];
        PFBAlertAddAction(alert, [bundle localizedStringForKey:@"OK_ACTION"], UIAlertActionStyleDefault, YES, nil);
        PFBAlertPresent(alert, self, YES, nil);
        return;
    }

    NSString* encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:
                                   [NSCharacterSet URLQueryAllowedCharacterSet]];
    encoded = [[encoded stringByReplacingOccurrencesOfString:@"&"
                                                  withString:@"%26"]
        stringByReplacingOccurrencesOfString:@"+"
                                  withString:@"%2B"];
    NSURL* deepLink = [NSURL
        URLWithString:[NSString
                          stringWithFormat:@"twitter://search?query=%@", encoded]];

    // The form closes first, then the deep link goes straight to the app delegate's
    // own URL router. Never through iOS: a sideloaded bundle may not have the
    // twitter:// scheme registered, and the web fallback lands on a login wall.
    void (^launch)(void) = ^{
        id delegate = [UIApplication sharedApplication].delegate;
        if (deepLink && [delegate respondsToSelector:@selector(openURL:options:)]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(delegate,
                                                      @selector(openURL:options:),
                                                      deepLink, @{});
        }
    };
    UIViewController* presenter = self.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:YES completion:launch];
    } else {
        launch();
    }
}

@end
