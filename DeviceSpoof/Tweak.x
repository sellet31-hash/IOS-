#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <string.h>
#import <unistd.h>
#import "DSPProfile.h"

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static CFStringRef kDSPProductTypeKey;
static CFStringRef kDSPHardwareModelKey;
static CFStringRef kDSPHWModelStrKey;
static CFStringRef kDSPProductTypeValue;
static CFStringRef kDSPHardwareModelValue;

static CFStringRef DSPAnswer(CFStringRef property) {
    if (!property || CFGetTypeID(property) != CFStringGetTypeID()) {
        return NULL;
    }
    if (kDSPProductTypeKey && CFEqual(property, kDSPProductTypeKey)) {
        return kDSPProductTypeValue;
    }
    if ((kDSPHardwareModelKey && CFEqual(property, kDSPHardwareModelKey)) ||
        (kDSPHWModelStrKey && CFEqual(property, kDSPHWModelStrKey))) {
        return kDSPHardwareModelValue;
    }
    return NULL;
}

static CFTypeRef DSP_MGCopyAnswer(CFStringRef property) {
    CFStringRef answer = DSPAnswer(property);
    if (answer) {
        return CFRetain(answer);
    }
    if (!orig_MGCopyAnswer) {
        return NULL;
    }
    return orig_MGCopyAnswer(property);
}

static BOOL DSPImageCanBePatched(const char *path) {
    if (!path || path[0] == '\0') {
        return NO;
    }
    if (strncmp(path, "/System/", 8) == 0 || strncmp(path, "/usr/", 5) == 0 || strncmp(path, "/private/preboot/", 17) == 0) {
        return NO;
    }
    if (strstr(path, "/var/jb/") || strstr(path, "DeviceSpoof") || strstr(path, "libsubstrate") || strstr(path, "ellekit") || strstr(path, "Substitute")) {
        return NO;
    }
    return YES;
}

static BOOL DSPSectionIsPointerTable(const struct section_64 *section) {
    uint32_t type = section->flags & SECTION_TYPE;
    if (type == S_NON_LAZY_SYMBOL_POINTERS || type == S_LAZY_SYMBOL_POINTERS) {
        return YES;
    }
    return strncmp(section->sectname, "__got", 16) == 0 || strncmp(section->sectname, "__la_symbol_ptr", 16) == 0;
}

static void DSPWriteSlot(void **slot, void *replacement) {
    vm_size_t page = (vm_size_t)getpagesize();
    vm_address_t pageStart = (vm_address_t)slot & ~(vm_address_t)(page - 1);
    kern_return_t result = vm_protect(mach_task_self(), pageStart, page, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (result != KERN_SUCCESS) {
        result = vm_protect(mach_task_self(), pageStart, page, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    }
    if (result == KERN_SUCCESS) {
        *slot = replacement;
    }
}

static void DSPRebindImage(const struct mach_header *header, intptr_t slide, void *target, void *replacement) {
    if (!header || header->magic != MH_MAGIC_64 || !target || target == replacement) {
        return;
    }
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    uintptr_t cursor = (uintptr_t)header64 + sizeof(*header64);
    for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize < cursor) {
            return;
        }
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strcmp(segment->segname, "__DATA") == 0 || strcmp(segment->segname, "__DATA_CONST") == 0) {
                const struct section_64 *section = (const struct section_64 *)(segment + 1);
                for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++, section++) {
                    if (!DSPSectionIsPointerTable(section) || section->size < sizeof(void *)) {
                        continue;
                    }
                    uintptr_t start = (uintptr_t)(section->addr + slide);
                    uintptr_t end = start + (uintptr_t)section->size;
                    start &= ~(uintptr_t)(sizeof(void *) - 1);
                    for (uintptr_t address = start; address + sizeof(void *) <= end; address += sizeof(void *)) {
                        void **slot = (void **)address;
                        if (*slot == target) {
                            DSPWriteSlot(slot, replacement);
                        }
                    }
                }
            }
        }
        cursor += command->cmdsize;
    }
}

static void DSPOnImage(const struct mach_header *header, intptr_t slide) {
    if (!orig_MGCopyAnswer) {
        return;
    }
    Dl_info info;
    if (dladdr(header, &info) == 0 || !DSPImageCanBePatched(info.dli_fname)) {
        return;
    }
    DSPRebindImage(header, slide, (void *)orig_MGCopyAnswer, (void *)DSP_MGCopyAnswer);
}

static void DSPPrepareAnswers(void) {
    kDSPProductTypeKey = CFStringCreateWithCString(NULL, "ProductType", kCFStringEncodingUTF8);
    kDSPHardwareModelKey = CFStringCreateWithCString(NULL, "HardwareModel", kCFStringEncodingUTF8);
    kDSPHWModelStrKey = CFStringCreateWithCString(NULL, "HWModelStr", kCFStringEncodingUTF8);
    kDSPProductTypeValue = CFStringCreateWithCString(NULL, [DSPProfile productTypeUTF8], kCFStringEncodingUTF8);
    kDSPHardwareModelValue = CFStringCreateWithCString(NULL, [DSPProfile hardwareModelUTF8], kCFStringEncodingUTF8);
}

static void DSPInstall(void) {
    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!gestalt) {
        gestalt = dlopen("/System/Library/Frameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
    }
    if (!gestalt) {
        return;
    }
    orig_MGCopyAnswer = (CFTypeRef (*)(CFStringRef))dlsym(gestalt, "MGCopyAnswer");
    if (!orig_MGCopyAnswer || !kDSPProductTypeValue || !kDSPHardwareModelValue) {
        orig_MGCopyAnswer = NULL;
        return;
    }
    _dyld_register_func_for_add_image(DSPOnImage);
}

%ctor {
    [DSPProfile reloadPreferences];
    if (![DSPProfile isSpoofEnabled]) {
        return;
    }
    DSPPrepareAnswers();
    DSPInstall();
}
