// The Advanced Search form, styled after x.com/search-advanced: bordered fields
// with floating labels, example lines, filter toggles, language menu, date pickers.

#import "Features/Search/PFBAdvancedSearchViewController.h"
#import "Common/PFBBundle.h"
#import "Support/HookHelpers.h"
#import "Support/TwitterChirpFont.h"
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Features/Search/PFBAdvField.h"
#import "Features/Search/PFBAdvBoxCell.h"
#import "Features/Search/PFBAdvMenuCell.h"
#import "Features/Search/PFBAdvToggleCell.h"
#import "Features/Search/PFBAdvDateCell.h"

// MARK: - controller

@interface PFBAdvancedSearchViewController ()
@property (nonatomic, strong) NSArray<NSString*>* sectionKeys;
@property (nonatomic, strong) NSArray<NSArray<PFBAdvField*>*>* sections;
@property (nonatomic, strong) NSArray<NSString*>* languageCodes;
@end

// A glyph escapes the glass material's wash by being baked: opaque pixels handed
// over as AlwaysOriginal. A title has no such escape, since the label is drawn by
// the button, so the word is baked into a bitmap and passed as an image.
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

    // A system Done bar button gives one native Liquid Glass capsule, where a custom
    // view would be wrapped in a second one. With Liquid Glass on, NavBarIcons.x tints
    // Done items system blue; otherwise the button inherits the window tint.
    NSString* searchTitle = [bundle localizedStringForKey:@"ADVSEARCH_SEARCH"];
    UIFont* searchFont = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:15]);
    UIImage* bakedTitle = pfbBakedTitleImage(searchTitle, searchFont);
    if (bakedTitle) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithImage:bakedTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(pfbRunSearch)];
        // The word is a picture now, so VoiceOver is told what it says.
        self.navigationItem.rightBarButtonItem.accessibilityLabel = searchTitle;
    } else {
        // Only reachable if the bitmap could not be drawn at all; a bar button
        // with no image would simply be invisible, so the plain title stands in.
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:searchTitle
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(pfbRunSearch)];
        NSDictionary* chirpButton = @{
            NSFontAttributeName : searchFont,
            NSForegroundColorAttributeName : [UIColor whiteColor]
        };
        [self.navigationItem.rightBarButtonItem setTitleTextAttributes:chirpButton
                                                              forState:UIControlStateNormal];
        [self.navigationItem.rightBarButtonItem setTitleTextAttributes:chirpButton
                                                              forState:UIControlStateHighlighted];
    }

    if (self.presentingViewController) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                 target:self
                                 action:@selector(pfbCancel)];
        // Marked for the bar-glass pass: this one keeps the capsule iOS gives it.
        objc_setAssociatedObject(self.navigationItem.leftBarButtonItem,
                                 @selector(pfbKeepsBarGlass), @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSDictionary* chirpTitle = @{
        NSFontAttributeName : PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17])
    };
    self.navigationController.navigationBar.titleTextAttributes = chirpTitle;

    // Outline pill with pale gray border and text, the "Reset to default" style.
    UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 78.0)];
    UIButton* clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:[bundle localizedStringForKey:@"ADVSEARCH_CLEAR"]
           forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor secondaryLabelColor]
                forState:UIControlStateNormal];
    clear.titleLabel.font =
        PFBScaledFont([TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15.5]);
    clear.layer.borderWidth = 1.0;
    clear.layer.borderColor = [UIColor systemGray4Color].CGColor;
    clear.layer.cornerRadius = 22.0;
    [clear addTarget:self
                  action:@selector(pfbClearAll)
        forControlEvents:UIControlEventTouchUpInside];
    clear.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:clear];
    [NSLayoutConstraint activateConstraints:@[
        [clear.topAnchor constraintEqualToAnchor:footer.topAnchor constant:16.0],
        [clear.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor
                                            constant:16.0],
        [clear.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor
                                             constant:-16.0],
        [clear.heightAnchor constraintEqualToConstant:44.0],
    ]];
    self.tableView.tableFooterView = footer;

    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
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

- (UIMenu*)pfbLanguageMenu {
    NSString* current =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"pfb_advs_lang"]
            ?: @"";
    __weak typeof(self) weakSelf = self;
    NSMutableArray* actions = [NSMutableArray array];
    UIAction* any = [UIAction
        actionWithTitle:[[PFBBundle sharedBundle]
                            localizedStringForKey:@"ADVSEARCH_ANY_LANGUAGE"]
                  image:nil
             identifier:nil
                handler:^(UIAction* a) {
                    [[NSUserDefaults standardUserDefaults]
                        removeObjectForKey:@"pfb_advs_lang"];
                    [weakSelf.tableView reloadData];
                }];
    any.state = (current.length == 0) ? UIMenuElementStateOn
                                      : UIMenuElementStateOff;
    [actions addObject:any];
    for (NSString* code in self.languageCodes) {
        UIAction* a = [UIAction
            actionWithTitle:PFBAdvLangName(code)
                      image:nil
                 identifier:nil
                    handler:^(UIAction* act) {
                        [[NSUserDefaults standardUserDefaults]
                            setObject:code forKey:@"pfb_advs_lang"];
                        [weakSelf.tableView reloadData];
                    }];
        a.state = [current isEqualToString:code] ? UIMenuElementStateOn
                                                 : UIMenuElementStateOff;
        [actions addObject:a];
    }
    return [UIMenu menuWithChildren:actions];
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
    UIView* container = [[UIView alloc] init];
    UILabel* label = [[UILabel alloc] init];
    label.text = [[PFBBundle sharedBundle]
        localizedStringForKey:self.sectionKeys[(NSUInteger)section]];
    label.font = PFBScaledFont([TwitterChirpFont(TwitterFontStyleBold) fontWithSize:20]);
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor
            constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [label.trailingAnchor
            constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                           constant:-6.0],
    ]];
    return container;
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
            [cell configureWith:model
                           menu:[self pfbLanguageMenu]
                   currentTitle:[self pfbCurrentLanguageTitle]];
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

- (void)pfbClearAll {
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
            alertControllerWithTitle:[bundle localizedStringForKey:
                                                 @"ADVANCED_SEARCH_TITLE"]
                             message:[bundle localizedStringForKey:errorKey]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK_ACTION"]
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
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
        [presenter dismissViewControllerAnimated:YES completion:nil];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), launch);
}

@end
