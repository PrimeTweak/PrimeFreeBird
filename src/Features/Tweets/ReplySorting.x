// Sort replies: the order replies open in; Twitter's own sort control still changes it.

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import "Support/HookHelpers.h"
#import "Debug/PFBProbe.h"

// Twitter's reply orders, as its sorting state and a conversation's requests store them.
enum {
    PFBReplyOrderLikes = 0,
    PFBReplyOrderRecency = 1,
    PFBReplyOrderRelevance = 2,
};

// The order Sort replies asks for; NO while it is off.
static BOOL PFBPreferredReplyOrder(uint8_t* order) {
    switch ([PFBSettings integerForKey:@"reply_sorting"]) {
        case PFBReplySortRecent:
            *order = PFBReplyOrderRecency;
            return YES;
        case PFBReplySortLiked:
            *order = PFBReplyOrderLikes;
            return YES;
        case PFBReplySortRelevant:
            *order = PFBReplyOrderRelevance;
            return YES;
        default:
            return NO;
    }
}

static NSString* PFBReplyOrderName(uint8_t order) {
    switch (order) {
        case PFBReplyOrderLikes:
            return @"Likes";
        case PFBReplyOrderRecency:
            return @"Recency";
        default:
            return @"Relevance";
    }
}

// Above zero while the action of one of Twitter's menu items runs: an order picked there
// is the one kept.
static NSInteger PFBMenuActionDepth;

// Each page of replies is requested in the order held by the conversation's timeline
// transformer: its class, the screen's slot for it and its order field. NO when Twitter
// renamed one of them, so that a sorting state changes only if the requests can follow.
static BOOL PFBRequestOrderFields(Class* transformerClass, ptrdiff_t* slot, ptrdiff_t* field) {
    static Class cls;
    static ptrdiff_t slotOffset = -1;
    static ptrdiff_t fieldOffset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Ivar storage = class_getInstanceVariable(objc_getClass("T1ConversationContainerViewController"),
                                                 "$__lazy_storage_$_timelineTransformer");
        cls = objc_getClass("_TtC14T1TwitterSwift31ConversationTimelineTransformer");
        Ivar order = cls ? class_getInstanceVariable(cls, "rankingMode") : NULL;
        if (storage && order) {
            slotOffset = ivar_getOffset(storage);
            fieldOffset = ivar_getOffset(order);
        }
    });
    if (transformerClass) {
        *transformerClass = cls;
    }
    if (slot) {
        *slot = slotOffset;
    }
    if (field) {
        *field = fieldOffset;
    }
    return slotOffset >= 0;
}

// Measurement: each new sorting state, as a pick recognized in Twitter's menu or by the
// code that made it, as an image and an offset in it.
static void pfbProbeSortingState(NSString* path, void* caller) {
    if (PFBMenuActionDepth > 0) {
        PFB_PROBE(@"reply sort picks", 6, @"pick in Twitter's menu recognized (%@)", path);
        return;
    }
    Dl_info info;
    if (dladdr(caller, &info) && info.dli_fname) {
        PFB_PROBE(@"reply sort picks", 6, @"state made by %@ +0x%lx (%@)", [@(info.dli_fname) lastPathComponent],
                  (unsigned long)((uintptr_t)caller - (uintptr_t)info.dli_fbase), path);
    }
}

// The order a new sorting state starts with; NO keeps Twitter's, as for a pick in its menu.
static BOOL PFBOpeningReplyOrder(uint8_t* order) {
    return PFBMenuActionDepth == 0 && PFBRequestOrderFields(NULL, NULL, NULL) && PFBPreferredReplyOrder(order);
}

%hook TFNActionItem

+ (instancetype)actionItemWithTitle:(NSString*)title
                          imageName:(NSString*)imageName
                             action:(void (^)(void))action {
    if (!action) {
        return %orig;
    }
    void (^tracked)(void) = ^{
        PFBMenuActionDepth++;
        action();
        PFBMenuActionDepth--;
    };
    return %orig(title, imageName, tracked);
}

%end

%hook TFSReplySortingState

- (instancetype)init {
    self = %orig;
    pfbProbeSortingState(@"init", __builtin_return_address(0));
    uint8_t order;
    if (!self || !PFBOpeningReplyOrder(&order)) {
        return self;
    }
    switch (order) {
        case PFBReplyOrderRecency:
            [self sortByRecency];
            break;
        case PFBReplyOrderLikes:
            [self sortByLikes];
            break;
        default:
            [self sortByRelevance];
            break;
    }
    return self;
}

%end

// Twitter builds the transformer with the conversation screen, then looks up the
// navigation controller before any request: the order is set there, once per screen.
static const void* kPFBRequestOrderSetKey = &kPFBRequestOrderSetKey;

static void PFBSetRequestOrder(id screen) {
    Class transformerClass;
    ptrdiff_t transformerOffset;
    ptrdiff_t orderOffset;
    if (!PFBRequestOrderFields(&transformerClass, &transformerOffset, &orderOffset)) {
        return;
    }
    void* transformer = *(void**)((uintptr_t)(__bridge void*)screen + (uintptr_t)transformerOffset);
    if (!transformer || objc_getAssociatedObject(screen, kPFBRequestOrderSetKey)) {
        return;
    }
    objc_setAssociatedObject(screen, kPFBRequestOrderSetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (object_getClass((__bridge id)transformer) != transformerClass) {
        return;
    }
    PFBCompatReach(PFBCompatPath_reply_order_request);
    uint8_t order;
    if (!PFBPreferredReplyOrder(&order)) {
        PFBCOMPAT_OBSERVE(PFBCompat_reply_sorting, @"replies requested in Twitter's order");
        return;
    }
    *((uint8_t*)transformer + orderOffset) = order;
    PFBCOMPAT_ACTION(PFBCompat_reply_sorting, @"replies requested by %@", PFBReplyOrderName(order));
}

%hook T1ConversationContainerViewController

- (UINavigationController*)navigationController {
    PFBSetRequestOrder(self);
    return %orig;
}

%end

// A conversation creates its state with Swift's ReplySortingState.init(rankingMode:),
// reached from T1Twitter through a symbol pointer.
typedef void* (*PFBReplySortingInit)(uint8_t order, void* __attribute__((swift_context)) state)
    __attribute__((swiftcall));
static PFBReplySortingInit gReplySortingInit;

__attribute__((swiftcall)) static void* PFBReplySortingInitHook(uint8_t order,
                                                               void* __attribute__((swift_context)) state) {
    PFBCompatReach(PFBCompatPath_reply_order_set);
    pfbProbeSortingState(@"Swift init", __builtin_return_address(0));
    uint8_t preferred;
    return gReplySortingInit(PFBOpeningReplyOrder(&preferred) ? preferred : order, state);
}

// Points every symbol pointer of the image that holds target at replacement. The bound
// address is matched: with chained fixups, the indirect symbol table does not name them.
static NSUInteger PFBRebindPointers(const struct mach_header_64* header, intptr_t slide, void* target,
                                    void* replacement) {
    NSUInteger rebound = 0;
    const struct load_command* cmd = (const struct load_command*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* segment = (const struct segment_command_64*)cmd;
            const struct section_64* sections = (const struct section_64*)(segment + 1);
            // A segment made read-only after binding is written through a private copy
            // of its page, then made read-only again.
            vm_prot_t restored = (segment->flags & SG_READ_ONLY) ? VM_PROT_READ : VM_PROT_READ | VM_PROT_WRITE;
            for (uint32_t j = 0; j < segment->nsects; j++) {
                uint32_t type = sections[j].flags & SECTION_TYPE;
                if (type != S_NON_LAZY_SYMBOL_POINTERS) {
                    continue;
                }
                void** slots = (void**)((uintptr_t)slide + sections[j].addr);
                for (uint64_t k = 0; k < sections[j].size / sizeof(void*); k++) {
                    if (slots[k] != target) {
                        continue;
                    }
                    vm_address_t page = (vm_address_t)&slots[k] & ~(vm_address_t)vm_page_mask;
                    if (vm_protect(mach_task_self(), page, vm_page_size, false,
                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
                        continue;
                    }
                    slots[k] = replacement;
                    vm_protect(mach_task_self(), page, vm_page_size, false, restored);
                    rebound++;
                }
            }
        }
        cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
    }
    return rebound;
}

static void PFBRebindReplySortingInit(const struct mach_header* header, intptr_t slide) {
    Dl_info info;
    if (header->magic != MH_MAGIC_64 || !dladdr(header, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, "/T1Twitter.framework/T1Twitter")) {
        return;
    }
    NSUInteger rebound = PFBRebindPointers((const struct mach_header_64*)header, slide, (void*)gReplySortingInit,
                                           (void*)PFBReplySortingInitHook);
    dispatch_async(dispatch_get_main_queue(), ^{
        PFBCompatMeasure(@"reply order",
                         rebound ? @"opening order hooked in T1Twitter" : @"opening order: no call found in T1Twitter",
                         2);
    });
}

%ctor {
    %init;
    gReplySortingInit = (PFBReplySortingInit)dlsym(
        RTLD_DEFAULT,
        "$s14TFSTwitterCore17ReplySortingStateC11rankingModeAC14GraphQLScalars015TimelineRankingG5InputO_tcfc");
    if (!gReplySortingInit) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PFBCompatMeasure(@"reply order", @"opening order: Twitter's init not found", 2);
        });
        return;
    }
    _dyld_register_func_for_add_image(PFBRebindReplySortingInit);
}
