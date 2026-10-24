// Sort replies: the order a conversation's replies open in. Twitter's own sort control
// still changes it for that conversation.

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import "Support/HookHelpers.h"

// Twitter's reply orders, as -[TFSReplySortingState sortByLikes], sortByRecency and
// sortByRelevance store them.
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

// The order a sorting state Twitter creates starts with: Sort replies' own, unless the
// state comes from a pick in Twitter's menu.
static uint8_t PFBOpeningReplyOrder(uint8_t order) {
    if (PFBMenuActionDepth > 0) {
        return order;
    }
    PFBCompatReach(PFBCompatPath_reply_order_set);
    uint8_t preferred;
    if (!PFBPreferredReplyOrder(&preferred)) {
        PFBCOMPAT_OBSERVE(PFBCompat_reply_sorting, @"replies opened in Twitter's order");
        return order;
    }
    PFBCOMPAT_ACTION(PFBCompat_reply_sorting, @"replies opened by %@", PFBReplyOrderName(preferred));
    return preferred;
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

// Created with Twitter's default order, Relevance, before its menu or its conversation
// sets another.
%hook TFSReplySortingState

- (instancetype)init {
    self = %orig;
    if (!self) {
        return self;
    }
    switch (PFBOpeningReplyOrder(PFBReplyOrderRelevance)) {
        case PFBReplyOrderRecency:
            [self sortByRecency];
            break;
        case PFBReplyOrderLikes:
            [self sortByLikes];
            break;
        default:
            break;
    }
    return self;
}

%end

// A conversation creates its state with Swift's ReplySortingState.init(rankingMode:),
// reached from T1Twitter through a symbol pointer.
typedef void* (*PFBReplySortingInit)(uint8_t order, void* __attribute__((swift_context)) state)
    __attribute__((swiftcall));
static PFBReplySortingInit gReplySortingInit;

__attribute__((swiftcall)) static void* PFBReplySortingInitHook(uint8_t order,
                                                               void* __attribute__((swift_context)) state) {
    return gReplySortingInit(PFBOpeningReplyOrder(order), state);
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
                if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) {
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
