//
//  Probe.x
//  PrimeFreeBird
//
//  A measuring instrument, not a feature. Nothing is drawn, nothing is changed:
//  it reads and writes to the log, once, so that one build answers every open
//  question about the row of actions under a Tweet.
//
//  Off unless Debug mode is on. Console.app on the Mac, subsystem filter
//  com.primefreebird.probe.
//
//  What it answers, in one run:
//    1. the class of the view model the row is configured with, and everything
//       it exposes — the question that six attempts have guessed at;
//    2. whether that model, or anything it holds, carries the four values this
//       feature needs, with their return types;
//    3. the class of the status handed to a button, which is the other way to
//       reach those values;
//    4. what the row owns: its own buttons, its subviews, their frames;
//    5. whether a foreign subview added to the row survives a layout pass —
//       the hypothesis that would explain a button that is built and never seen;
//    6. the numbers a native button answers with: visibility, inline action
//       type, count behaviour, image and rendering mode.
//

#import "HookHelpers.h"
#import <os/log.h>
#import <string.h>

static os_log_t NFBProbeLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      log = os_log_create("com.primefreebird.probe", "row");
    });
    return log;
}

static BOOL NFBProbeEnabled(void) {
    return [BHTSettings boolForKey:@"flex_twitter"];
}

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
        os_log(NFBProbeLog(), "%{public}@ : nil", label);
        return;
    }
    os_log(NFBProbeLog(), "%{public}@ : classe %{public}@", label,
           NSStringFromClass([object class]));
    os_log(NFBProbeLog(), "   replyCount ......... %{public}@",
           NFBProbeValue(object, @selector(replyCount)));
    os_log(NFBProbeLog(), "   conversationID ..... %{public}@",
           NFBProbeValue(object, @selector(conversationID)));
    os_log(NFBProbeLog(), "   inReplyToStatusID .. %{public}@",
           NFBProbeValue(object, @selector(inReplyToStatusID)));
    os_log(NFBProbeLog(), "   statusID ........... %{public}@",
           NFBProbeValue(object, @selector(statusID)));
    os_log(NFBProbeLog(), "   text ............... %{public}@",
           NFBProbeValue(object, @selector(text)));
    os_log(NFBProbeLog(), "   author ............. %{public}@",
           NFBProbeValue(object, @selector(author)));
}

// Everything a class exposes: its own methods, its ivars, and where the four
// values might be hiding one level down.
static void NFBProbeClassSurface(id object, NSString* label) {
    if (!object) {
        return;
    }
    Class cls = object_getClass(object);
    os_log(NFBProbeLog(), "%{public}@ : surface de %{public}@", label,
           NSStringFromClass(cls));

    unsigned int methodCount = 0;
    Method* methods = class_copyMethodList(cls, &methodCount);
    NSMutableArray* names = [NSMutableArray array];
    for (unsigned int i = 0; i < methodCount; i++) {
        [names addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    os_log(NFBProbeLog(), "   %lu méthodes : %{public}@", (unsigned long)names.count,
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
            os_log(NFBProbeLog(), "   ivar %{public}s : %{public}s", ivarName, type);
            continue;
        }
        id value = object_getIvar(object, ivars[i]);
        BOOL carries = [value respondsToSelector:@selector(replyCount)] ||
                       [value respondsToSelector:@selector(conversationID)] ||
                       [value respondsToSelector:@selector(statusID)];
        os_log(NFBProbeLog(), "   ivar %{public}s : %{public}@%{public}s", ivarName,
               value ? NSStringFromClass([value class]) : @"nil",
               carries ? "   <<< PORTE LES VALEURS" : "");
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
    if (!NFBProbeEnabled() || seen >= 2) {
        return classes;
    }
    seen++;
    os_log(NFBProbeLog(), "=== LISTE DE CLASSES (%ld) ===", (long)seen);
    NSMutableArray* names = [NSMutableArray array];
    for (id entry in classes) {
        [names addObject:NSStringFromClass((Class)entry) ?: @"?"];
    }
    os_log(NFBProbeLog(), "   classes rendues : %{public}@",
           [names componentsJoinedByString:@", "]);
    os_log(NFBProbeLog(), "   options = %lu · displayType = %lu",
           (unsigned long)options, (unsigned long)displayType);
    NFBProbeStatusValues(viewModel, @"viewModel reçu");
    NFBProbeClassSurface(viewModel, @"viewModel reçu");
    return classes;
}

// MARK: - What the row owns, and whether a foreign view survives

- (void)layoutSubviews {
    %orig;
    static NSInteger seen = 0;
    if (!NFBProbeEnabled() || seen >= 3) {
        return;
    }
    UIView* row = (UIView*)self;
    if (CGRectGetWidth(row.bounds) < 1.0) {
        return;
    }
    seen++;
    os_log(NFBProbeLog(), "=== RANGÉE (%ld) === cadre %{public}@", (long)seen,
           NSStringFromCGRect(row.frame));

    // The model, read the way the feature reads it.
    id model = nil;
    @try {
        model = [row valueForKey:@"viewModel"];
    } @catch (NSException* exception) {
        os_log(NFBProbeLog(), "   valueForKey viewModel : exception %{public}@",
               exception.name);
    }
    NFBProbeStatusValues(model, @"viewModel de la rangée");

    // What the row keeps as its own buttons.
    @try {
        id owned = [row valueForKey:@"inlineActionButtons"];
        os_log(NFBProbeLog(), "   inlineActionButtons : %{public}@",
               [owned description] ?: @"nil");
    } @catch (NSException* exception) {
        os_log(NFBProbeLog(), "   inlineActionButtons : exception %{public}@",
               exception.name);
    }

    // Its subviews, with their frames — this is where a button of ours would
    // have to live, and at what size.
    os_log(NFBProbeLog(), "   %lu sous-vues :", (unsigned long)row.subviews.count);
    for (UIView* subview in row.subviews) {
        os_log(NFBProbeLog(), "      %{public}@ %{public}@ caché=%d alpha=%.2f",
               NSStringFromClass([subview class]),
               NSStringFromCGRect(subview.frame), subview.hidden,
               subview.alpha);
    }
    os_log(NFBProbeLog(), "   clipsToBounds = %d", row.clipsToBounds);

    // Does a foreign subview survive? One is planted on the first pass and
    // looked for on the next: this settles whether the row discards what it
    // does not own, which would explain a button built and never seen.
    static const NSInteger kMarkerTag = 90777;
    UIView* marker = [row viewWithTag:kMarkerTag];
    if (marker) {
        os_log(NFBProbeLog(),
               "   TÉMOIN : toujours présent · cadre %{public}@ caché=%d",
               NSStringFromCGRect(marker.frame), marker.hidden);
    } else {
        marker = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 4.0, 4.0)];
        marker.tag = kMarkerTag;
        marker.backgroundColor = [UIColor clearColor];
        [row addSubview:marker];
        os_log(NFBProbeLog(), "   TÉMOIN : planté, à relire au passage suivant");
    }

    // One native button, in full: the numbers our own would have to answer.
    for (UIView* subview in row.subviews) {
        if (![subview isKindOfClass:%c(TTAStatusInlineActionButton)]) {
            continue;
        }
        os_log(NFBProbeLog(), "   BOUTON NATIF %{public}@ · cadre %{public}@",
               NSStringFromClass([subview class]), NSStringFromCGRect(subview.frame));
        os_log(NFBProbeLog(), "      visibility ......... %{public}@",
               NFBProbeValue(subview, @selector(visibility)));
        os_log(NFBProbeLog(), "      inlineActionType ... %{public}@",
               NFBProbeValue(subview, @selector(inlineActionType)));
        os_log(NFBProbeLog(), "      shouldShowCount .... %{public}@",
               NFBProbeValue(subview, @selector(shouldShowCount)));
        os_log(NFBProbeLog(), "      count .............. %{public}@",
               NFBProbeValue(subview, @selector(count)));
        os_log(NFBProbeLog(), "      actionSheetTitle ... %{public}@",
               NFBProbeValue(subview, @selector(actionSheetTitle)));
        UIImageView* imageView = nil;
        @try {
            imageView = [subview valueForKey:@"imageView"];
        } @catch (__unused NSException* exception) {
        }
        if (imageView) {
            UIImage* image = imageView.image;
            os_log(NFBProbeLog(),
                   "      imageView %{public}@ · image %.0fx%.0f · mode=%ld · "
                   "tint %{public}@",
                   NSStringFromCGRect(imageView.frame), image.size.width,
                   image.size.height, (long)image.renderingMode,
                   [imageView.tintColor description] ?: @"nil");
        }
        break;
    }
}

%end

// MARK: - The status, handed straight to a button

%hook TTAStatusInlineActionButton

- (void)statusDidUpdate:(id)status
                options:(NSUInteger)options
     displayTextOptions:(id)displayTextOptions
               animated:(BOOL)animated
        featureSwitches:(id)featureSwitches {
    %orig;
    static NSInteger seen = 0;
    if (!NFBProbeEnabled() || seen >= 2) {
        return;
    }
    seen++;
    os_log(NFBProbeLog(), "=== STATUT REMIS À UN BOUTON (%ld) === %{public}@",
           (long)seen, NSStringFromClass([self class]));
    NFBProbeStatusValues(status, @"statut reçu");
    NFBProbeClassSurface(status, @"statut reçu");
}

%end
