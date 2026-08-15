//
//  Probe.x
//  PrimeFreeBird
//
//  A measuring instrument, not a feature. Nothing is drawn, nothing is changed:
//  it reads and writes to the log, once, so that one build answers every open
//  question about the row of actions under a Tweet.
//
//  Console.app on the Mac, with the phone selected: search NFBPROBE as plain
//  text. No subsystem filter, no setting to turn on — a probe that has to be
//  configured before it speaks is a probe that stays silent.
//
//  What it answers, in one run:
//    1. the class of the view model the row is configured with, and everything
//       it exposes — the question that six attempts have guessed at;
//    2. whether that model, or anything it holds, carries the four values this
//       feature needs, with their return types;
//    3. (removed) the status handed to a button: hooking that method meant
//       declaring its parameter types, and one of them is an integer where an
//       object was assumed — ARC retained the number as an address and the app
//       came down. A method is not hooked here unless its signature is known.
//    4. what the row owns: its own buttons, its subviews, their frames;
//    5. whether a foreign subview added to the row survives a layout pass —
//       the hypothesis that would explain a button that is built and never seen;
//    6. the numbers a native button answers with: visibility, inline action
//       type, count behaviour, image and rendering mode.
//

#import "HookHelpers.h"
#import <string.h>



// NSLog rather than os_log: it reaches Console without a subsystem filter, and
// the prefix below can be searched as plain text. A probe that cannot be found
// in the log is worth nothing.
#define NFBLog(fmt, ...) NSLog(@"NFBPROBE " fmt, ##__VA_ARGS__)

// MARK: - Reading a value without trusting its type
//
// The rule this file was built on: never message a selector without checking
// what it returns. A count read as an object hands a number to the runtime as
// an address, which is how this crashed before.

static NSString* NFBProbeReturnType(id target, SEL selector) {
    if (![target respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature* signature = [target methodSignatureForSelector:selector];
    const char* type = signature.methodReturnType;
    return type ? [NSString stringWithUTF8String:type] : nil;
}

static NSString* NFBProbeValue(id target, SEL selector) {
    NSString* type = NFBProbeReturnType(target, selector);
    if (!type.length) {
        return @"(ne répond pas)";
    }
    const char* t = type.UTF8String;
    @try {
        switch (t[0]) {
            case '@': {
                id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
                return [NSString stringWithFormat:@"@ %@ = %@",
                                                  NSStringFromClass([value class]),
                                                  [value description] ?: @"nil"];
            }
            case 'q':
            case 'Q':
                return [NSString
                    stringWithFormat:@"%s = %lld", t,
                                     ((long long (*)(id, SEL))objc_msgSend)(target, selector)];
            case 'l':
            case 'L':
                return [NSString stringWithFormat:@"%s = %ld", t,
                                                  ((long (*)(id, SEL))objc_msgSend)(target, selector)];
            case 'i':
            case 'I':
                return [NSString stringWithFormat:@"%s = %d", t,
                                                  ((int (*)(id, SEL))objc_msgSend)(target, selector)];
            case 's':
            case 'S':
                return [NSString stringWithFormat:@"%s = %d", t,
                                                  (int)((short (*)(id, SEL))objc_msgSend)(target, selector)];
            case 'c':
            case 'C':
            case 'B':
                return [NSString stringWithFormat:@"%s = %d", t,
                                                  (int)((char (*)(id, SEL))objc_msgSend)(target, selector)];
            default:
                return [NSString stringWithFormat:@"%s (type non lu)", t];
        }
    } @catch (NSException* exception) {
        return [NSString stringWithFormat:@"%s (exception: %@)", t, exception.name];
    }
}

// The four values this feature needs, asked of one object.
static void NFBProbeStatusValues(id object, NSString* label) {
    if (!object) {
        NFBLog("%@ : nil", label);
        return;
    }
    NFBLog("%@ : classe %@", label,
           NSStringFromClass([object class]));
    NFBLog("   replyCount ......... %@",
           NFBProbeValue(object, @selector(replyCount)));
    NFBLog("   conversationID ..... %@",
           NFBProbeValue(object, @selector(conversationID)));
    NFBLog("   inReplyToStatusID .. %@",
           NFBProbeValue(object, @selector(inReplyToStatusID)));
    NFBLog("   statusID ........... %@",
           NFBProbeValue(object, @selector(statusID)));
    NFBLog("   text ............... %@",
           NFBProbeValue(object, @selector(text)));
    NFBLog("   author ............. %@",
           NFBProbeValue(object, @selector(author)));
}

// Everything a class exposes: its own methods, its ivars, and where the four
// values might be hiding one level down.
static void NFBProbeClassSurface(id object, NSString* label) {
    if (!object) {
        return;
    }
    Class cls = object_getClass(object);
    NFBLog("%@ : surface de %@", label,
           NSStringFromClass(cls));

    unsigned int methodCount = 0;
    Method* methods = class_copyMethodList(cls, &methodCount);
    NSMutableArray* names = [NSMutableArray array];
    for (unsigned int i = 0; i < methodCount; i++) {
        [names addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    NFBLog("   %lu méthodes : %@", (unsigned long)names.count,
           [names componentsJoinedByString:@", "]);

    unsigned int ivarCount = 0;
    Ivar* ivars = class_copyIvarList(cls, &ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        const char* ivarName = ivar_getName(ivars[i]);
        const char* type = ivar_getTypeEncoding(ivars[i]);
        if (!ivarName || !type) {
            continue;
        }
        if (type[0] != '@') {
            NFBLog("   ivar %s : %s", ivarName, type);
            continue;
        }
        // Read inside a guard: an ivar declared as an object can hold something
        // the runtime cannot retain, and touching it is how the previous build
        // brought the app down.
        @try {
            id value = object_getIvar(object, ivars[i]);
            BOOL carries = [value respondsToSelector:@selector(replyCount)] ||
                           [value respondsToSelector:@selector(conversationID)] ||
                           [value respondsToSelector:@selector(statusID)];
            NFBLog("   ivar %s : %@%s", ivarName,
                   value ? NSStringFromClass([value class]) : @"nil",
                   carries ? "   <<< PORTE LES VALEURS" : "");
        } @catch (__unused NSException* exception) {
            NFBLog("   ivar %s : illisible", ivarName);
        }
    }
    free(ivars);
}

// MARK: - The list the row is built from

%hook TTAStatusInlineActionsView

+ (NSArray*)_t1_inlineActionViewClassesForViewModel:(id)viewModel
                                            options:(NSUInteger)options
                                        displayType:(NSUInteger)displayType
                                            account:(id)account {
    NSArray* classes = %orig;
    static NSInteger seen = 0;
    if (seen >= 2) {
        return classes;
    }
    seen++;
    NFBLog("=== LISTE DE CLASSES (%ld) ===", (long)seen);
    NSMutableArray* names = [NSMutableArray array];
    for (id entry in classes) {
        [names addObject:NSStringFromClass((Class)entry) ?: @"?"];
    }
    NFBLog("   classes rendues : %@",
           [names componentsJoinedByString:@", "]);
    NFBLog("   options = %lu · displayType = %lu",
           (unsigned long)options, (unsigned long)displayType);
    NFBProbeStatusValues(viewModel, @"viewModel reçu");
    NFBProbeClassSurface(viewModel, @"viewModel reçu");
    return classes;
}

// MARK: - What the row owns, and whether a foreign view survives

- (void)layoutSubviews {
    %orig;
    static NSInteger seen = 0;
    if (seen >= 3) {
        return;
    }
    UIView* row = (UIView*)self;
    if (CGRectGetWidth(row.bounds) < 1.0) {
        return;
    }
    seen++;
    NFBLog("=== RANGÉE (%ld) === cadre %@", (long)seen,
           NSStringFromCGRect(row.frame));

    // The model, read the way the feature reads it.
    id model = nil;
    @try {
        model = [row valueForKey:@"viewModel"];
    } @catch (NSException* exception) {
        NFBLog("   valueForKey viewModel : exception %@",
               exception.name);
    }
    NFBProbeStatusValues(model, @"viewModel de la rangée");

    // What the row keeps as its own buttons.
    @try {
        id owned = [row valueForKey:@"inlineActionButtons"];
        NFBLog("   inlineActionButtons : %@",
               [owned description] ?: @"nil");
    } @catch (NSException* exception) {
        NFBLog("   inlineActionButtons : exception %@",
               exception.name);
    }

    // Its subviews, with their frames — this is where a button of ours would
    // have to live, and at what size.
    NFBLog("   %lu sous-vues :", (unsigned long)row.subviews.count);
    for (UIView* subview in row.subviews) {
        NFBLog("      %@ %@ caché=%d alpha=%.2f",
               NSStringFromClass([subview class]),
               NSStringFromCGRect(subview.frame), subview.hidden,
               subview.alpha);
    }
    NFBLog("   clipsToBounds = %d", row.clipsToBounds);

    // Does a foreign subview survive? One is planted on the first pass and
    // looked for on the next: this settles whether the row discards what it
    // does not own, which would explain a button built and never seen.
    static const NSInteger kMarkerTag = 90777;
    UIView* marker = [row viewWithTag:kMarkerTag];
    if (marker) {
        NFBLog("   TÉMOIN : toujours présent · cadre %@ caché=%d",
               NSStringFromCGRect(marker.frame), marker.hidden);
    } else {
        marker = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 4.0, 4.0)];
        marker.tag = kMarkerTag;
        marker.backgroundColor = [UIColor clearColor];
        [row addSubview:marker];
        NFBLog("   TÉMOIN : planté, à relire au passage suivant");
    }

    // One native button, in full: the numbers our own would have to answer.
    for (UIView* subview in row.subviews) {
        if (![subview isKindOfClass:%c(TTAStatusInlineActionButton)]) {
            continue;
        }
        NFBLog("   BOUTON NATIF %@ · cadre %@",
               NSStringFromClass([subview class]), NSStringFromCGRect(subview.frame));
        NFBLog("      visibility ......... %@",
               NFBProbeValue(subview, @selector(visibility)));
        NFBLog("      inlineActionType ... %@",
               NFBProbeValue(subview, @selector(inlineActionType)));
        NFBLog("      shouldShowCount .... %@",
               NFBProbeValue(subview, @selector(shouldShowCount)));
        NFBLog("      count .............. %@",
               NFBProbeValue(subview, @selector(count)));
        NFBLog("      actionSheetTitle ... %@",
               NFBProbeValue(subview, @selector(actionSheetTitle)));
        UIImageView* imageView = nil;
        @try {
            imageView = [subview valueForKey:@"imageView"];
        } @catch (__unused NSException* exception) {
        }
        if (imageView) {
            UIImage* image = imageView.image;
            NFBLog("      imageView %@ · image %.0fx%.0f · mode=%ld · "
                   "tint %@",
                   NSStringFromCGRect(imageView.frame), image.size.width,
                   image.size.height, (long)image.renderingMode,
                   [imageView.tintColor description] ?: @"nil");
        }
        break;
    }
}

%end

// Printed as soon as the tweak loads: if this line is missing from the log,
// the file is not in the build and nothing else below can be expected.
%ctor {
    NFBLog(@"chargée — ouvrez le fil, deux ou trois Tweets suffisent");
}
