// PrimeFreeBird's resource bundle and localized strings.

#import "Common/PFBBundle.h"
#import "Debug/PFBDebugger.h"
#import "Debug/PFBProbe.h"

@interface PFBBundle ()
@property (nonatomic, strong) NSBundle* mainBundle;
@property (nonatomic, strong) NSBundle* englishBundle;
@end

@implementation PFBBundle
+ (instancetype)sharedBundle {
    static PFBBundle* sharedBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* bundlePath = nil;
        if ([fileManager
                fileExistsAtPath:
                    @"/Library/Application Support/PFB/PrimeFreeBird.bundle"]) {
            bundlePath = [NSURL
                fileURLWithPath:@"/Library/Application Support/PFB/PrimeFreeBird.bundle"];
        } else if ([fileManager fileExistsAtPath:@"/var/jb/Library/Application "
                                                 @"Support/PFB/PrimeFreeBird.bundle"]) {
            bundlePath = [NSURL
                fileURLWithPath:
                    @"/var/jb/Library/Application Support/PFB/PrimeFreeBird.bundle"];
        } else {
            // Sideloaded builds carry the bundle at the root of the app, under the
            // same name as the jailbreak paths above.
            bundlePath = [[NSBundle mainBundle] URLForResource:@"PrimeFreeBird"
                                                 withExtension:@"bundle"];
        }

        sharedBundle = [[self alloc] initWithBundlePath:bundlePath];
    });
    return sharedBundle;
}
- (instancetype)initWithBundlePath:(NSURL*)bundlePath {
    if (self = [super init]) {
        self.mainBundle = [NSBundle bundleWithPath:[bundlePath path]];
        NSString* english = [self.mainBundle pathForResource:@"en" ofType:@"lproj"];
        self.englishBundle = english ? [NSBundle bundleWithPath:english] : nil;
    }

    return self;
}

// A miss returns the value passed in, so a marker no string uses tells a miss apart.
static NSString* const kPFBMissingString = @"<PFB missing string>";

- (NSString*)localizedStringForKey:(NSString*)key {
    NSString* text = [self.mainBundle localizedStringForKey:key value:kPFBMissingString table:nil];
    if (!text || [text isEqualToString:kPFBMissingString]) {
        text = [self.englishBundle localizedStringForKey:key value:kPFBMissingString table:nil];
    }
    return text && ![text isEqualToString:kPFBMissingString] ? text : key;
}

// Fetches one of Twitter's own strings from the tables that hold the borrowed keys. A key
// none of them has falls back to the bundled copy, filed under TW_ so it never collides
// with a PrimeFreeBird key.
- (NSString*)localizedTwitterStringForKey:(NSString*)key {
    static NSArray<NSBundle*>* tables;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSBundle*>* found = [NSMutableArray array];
        for (NSString* name in @[
                 @"T1Strings_T1Strings.bundle", @"TwitterSharedStrings_TwitterSharedStrings.bundle",
                 @"ChatCore_ChatStrings.bundle", @"LiveActivities_LiveActivityStrings.bundle"
             ]) {
            NSBundle* table =
                [NSBundle bundleWithPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:name]];
            if (table) {
                [found addObject:table];
            }
        }
        tables = found.copy;
    });
    for (NSBundle* table in tables) {
        NSString* text = [table localizedStringForKey:key value:kPFBMissingString table:nil];
        if (text && ![text isEqualToString:kPFBMissingString]) {
            return text;
        }
    }
    NSString* prefixed = [@"TW_" stringByAppendingString:key];
    NSString* fallback = [self localizedStringForKey:prefixed];
    return fallback.length == 0 || [fallback isEqualToString:prefixed] ? key : fallback;
}
- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end

// MARK: - Probe

// Probe: one language of Twitter's string bundles, the ones read above: every .strings table
// of the language's folder, then the bundle's .loctable entries for it. The .stringsdict
// plural forms go to plurals. The first table holding a key wins, as above.
static NSDictionary<NSString*, NSString*>* PFBProbeTwitterTable(NSArray<NSString*>* folders, NSMutableDictionary* plurals) {
    NSMutableDictionary<NSString*, NSString*>* table = [NSMutableDictionary dictionary];
    void (^merge)(NSMutableDictionary*, id) = ^(NSMutableDictionary* into, id from) {
      if (![from isKindOfClass:[NSDictionary class]]) {
          return;
      }
      for (id key in (NSDictionary*)from) {
          if ([key isKindOfClass:[NSString class]] && !into[key]) {
              into[key] = ((NSDictionary*)from)[key];
          }
      }
    };
    for (NSString* name in @[
             @"T1Strings_T1Strings.bundle", @"TwitterSharedStrings_TwitterSharedStrings.bundle",
             @"ChatCore_ChatStrings.bundle", @"LiveActivities_LiveActivityStrings.bundle"
         ]) {
        NSBundle* bundle = [NSBundle bundleWithPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:name]];
        // Each .loctable holds every language: read once per bundle, used per folder.
        NSMutableArray<NSDictionary*>* loctables = [NSMutableArray array];
        for (NSString* file in [bundle pathsForResourcesOfType:@"loctable" inDirectory:nil]) {
            NSDictionary* contents = [NSDictionary dictionaryWithContentsOfFile:file];
            if ([contents isKindOfClass:[NSDictionary class]]) {
                [loctables addObject:contents];
            }
        }
        for (NSString* folder in folders) {
            NSString* path = [bundle pathForResource:folder ofType:@"lproj"];
            NSArray<NSString*>* files = path ? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil] : @[];
            for (NSString* file in [files sortedArrayUsingSelector:@selector(compare:)]) {
                BOOL strings = [file.pathExtension isEqualToString:@"strings"];
                if (strings || [file.pathExtension isEqualToString:@"stringsdict"]) {
                    merge(strings ? table : plurals,
                          [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:file]]);
                }
            }
            for (NSDictionary* contents in loctables) {
                merge(table, contents[folder]);
            }
        }
    }
    return table;
}

// Probe: a value for a note, shortened, its no-break spaces named.
static NSString* PFBProbeShown(NSString* value) {
    NSString* text = value.length > 60 ? [value substringToIndex:60] : value;
    text = [text stringByReplacingOccurrencesOfString:@" " withString:@"<nbsp>"];
    return [text stringByReplacingOccurrencesOfString:@" " withString:@"<nnbsp>"];
}

// Probe: a value as quoted text for a note, or "absent".
static NSString* PFBProbeQuoted(id value) {
    return [value isKindOfClass:[NSString class]] ? [NSString stringWithFormat:@"“%@”", PFBProbeShown(value)]
                                                  : @"absent";
}

// Probe: the age test PFBNotifDateFromAgePiece (HiddenNotifications.x) applies, mirrored: a
// number and a one-letter unit, or else a short or a long date.
static BOOL PFBProbeAgeParses(NSString* sample) {
    static NSRegularExpression* relative;
    static NSDateFormatter* shortDate;
    static NSDateFormatter* longDate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      relative = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\s*([smhdwy])$"
                                                           options:NSRegularExpressionCaseInsensitive
                                                             error:nil];
      shortDate = [[NSDateFormatter alloc] init];
      [shortDate setLocalizedDateFormatFromTemplate:@"MMMd"];
      longDate = [[NSDateFormatter alloc] init];
      [longDate setLocalizedDateFormatFromTemplate:@"MMMdyyyy"];
    });
    NSString* tail = [sample stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSTextCheckingResult* match = [relative firstMatchInString:tail options:0 range:NSMakeRange(0, tail.length)];
    if (match.numberOfRanges == 3 && [[tail substringWithRange:[match rangeAtIndex:1]] doubleValue] > 0) {
        return YES;
    }
    return [longDate dateFromString:tail] != nil || [shortDate dateFromString:tail] != nil;
}

// Probe: a format's sample, its number written in as plain text, never through a format call.
static NSString* PFBProbeAgeSample(NSString* format, NSString* number) {
    static NSRegularExpression* specifier;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      specifier = [NSRegularExpression
          regularExpressionWithPattern:@"%(\\d+\\$)?[-+ 0#]*\\d*(\\.\\d+)?(hh|h|ll|l|q|z|t|j)?[diuoxX@]"
                               options:0
                                 error:nil];
    });
    NSTextCheckingResult* match = [specifier firstMatchInString:format options:0 range:NSMakeRange(0, format.length)];
    NSString* sample = match ? [format stringByReplacingCharactersInRange:match.range withString:number] : format;
    return [sample stringByReplacingOccurrencesOfString:@"%%" withString:@"%"];
}

// Probe: the forms of one age unit in a language: its singular and plural formats, or their
// one and other plural forms when a format is a .stringsdict placeholder, each with whether
// the age test reads its sample.
static NSString* PFBProbeAgeForms(NSString* unit, NSDictionary* table, NSDictionary* plurals) {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    for (NSString* key in @[
             [NSString stringWithFormat:@"TIME_SHORT_%@_FORMAT", unit], [NSString stringWithFormat:@"TIME_SHORT_%@S_FORMAT", unit]
         ]) {
        BOOL many = [key hasSuffix:@"S_FORMAT"];
        NSMutableArray<NSArray<NSString*>*>* forms = [NSMutableArray array];
        id raw = table[key];
        id rule = plurals[key];
        if ([raw isKindOfClass:[NSString class]] && ![raw containsString:@"%#@"]) {
            [forms addObject:@[ raw, many ? @"3" : @"1" ]];
        } else if ([rule isKindOfClass:[NSDictionary class]]) {
            for (id variable in [(NSDictionary*)rule allValues]) {
                if (![variable isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                for (NSString* count in @[ @"one", @"other" ]) {
                    id form = ((NSDictionary*)variable)[count];
                    if ([form isKindOfClass:[NSString class]]) {
                        [forms addObject:@[ form, [count isEqualToString:@"one"] ? @"1" : @"3" ]];
                    }
                }
            }
        }
        for (NSArray<NSString*>* form in forms) {
            if ([seen containsObject:form[0]]) {
                continue;
            }
            [seen addObject:form[0]];
            [parts addObject:[NSString stringWithFormat:@"'%@' %@", PFBProbeShown(form[0]),
                                                        PFBProbeAgeParses(PFBProbeAgeSample(form[0], form[1])) ? @"ok" : @"no"]];
        }
    }
    return parts.count ? [parts componentsJoinedByString:@", "] : @"absent";
}

// Probe: Twitter's own English and French text for a few keys, and its short age formats in
// both languages with whether the notifications' age test reads them; run by the path tour.
void PFBProbeTwitterStrings(void) {
    if (!PFBDebugIsRecording()) {
        return;
    }
    NSArray<NSString*>* keys = @[
        @"GROK_BOT_UPSELL_SIDEBAR_TITLE", @"SUPER_FOLLOW_BUTTON_LABEL", @"LARGE_SUPER_FOLLOW_BUTTON_TEXT",
        @"SUBSCRIBE_ACTION_LABEL", @"WHO_TO_FOLLOW_LABEL", @"EXPANDED_BIO_SHOW_MORE_LABEL",
        @"PROFILE_EXPANDED_BIO_BUTTON_LABEL", @"BOOKMARKS_LABEL", @"BOOKMARK_BUTTON"
    ];
    NSArray<NSString*>* languages = @[ @"en", @"fr" ];
    BOOL wanted = PFBProbeWants(@"08#F036 ages en") || PFBProbeWants(@"08#F036 ages fr");
    for (NSString* key in keys) {
        wanted = wanted || PFBProbeWants([@"13#T4.a-4 " stringByAppendingString:key]);
    }
    if (!wanted) {
        return;
    }
    NSMutableDictionary* englishPlurals = [NSMutableDictionary dictionary];
    NSMutableDictionary* frenchPlurals = [NSMutableDictionary dictionary];
    NSDictionary* english = PFBProbeTwitterTable(@[ @"en", @"Base" ], englishPlurals);
    NSDictionary* french = PFBProbeTwitterTable(@[ @"fr" ], frenchPlurals);
    NSSet<NSString*>* subscribe =
        [NSSet setWithArray:@[ @"SUPER_FOLLOW_BUTTON_LABEL", @"LARGE_SUPER_FOLLOW_BUTTON_TEXT", @"SUBSCRIBE_ACTION_LABEL" ]];
    for (NSString* key in keys) {
        NSString* note = [@"13#T4.a-4 " stringByAppendingString:key];
        if (PFBProbeWants(note)) {
            PFBProbeNote(note, @"13#T4.a-4%@ Twitter text %@: en %@ · fr %@",
                         [subscribe containsObject:key] ? @" 13#T4.e-10" : @"", key, PFBProbeQuoted(english[key]),
                         PFBProbeQuoted(french[key]));
        }
    }
    NSArray<NSArray<NSString*>*>* units =
        @[ @[ @"s", @"SECOND" ], @[ @"m", @"MINUTE" ], @[ @"h", @"HOUR" ], @[ @"d", @"DAY" ], @[ @"w", @"WEEK" ],
           @[ @"mo", @"MONTH" ], @[ @"y", @"YEAR" ] ];
    for (NSString* language in languages) {
        NSString* note = [@"08#F036 ages " stringByAppendingString:language];
        if (!PFBProbeWants(note)) {
            continue;
        }
        BOOL inFrench = [language isEqualToString:@"fr"];
        NSMutableArray<NSString*>* parts = [NSMutableArray array];
        for (NSArray<NSString*>* unit in units) {
            [parts addObject:[NSString stringWithFormat:@"%@ %@", unit[0],
                                                        PFBProbeAgeForms(unit[1], inFrench ? french : english,
                                                                         inFrench ? frenchPlurals : englishPlurals)]];
        }
        PFBProbeNote(note, @"08#F036 ages %@: %@", language, [parts componentsJoinedByString:@" · "]);
    }
}
