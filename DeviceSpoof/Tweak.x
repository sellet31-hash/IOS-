#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <string.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>
#import "DSPProfile.h"

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, unsigned int, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static void *(*orig_dlsym)(void *, const char *);

static CFStringRef kDSPProductTypeKey;
static CFStringRef kDSPHardwareModelKey;
static CFStringRef kDSPHWModelStrKey;
static CFStringRef kDSPSerialNumberKey;
static CFStringRef kDSPProductTypeValue;
static CFStringRef kDSPHardwareModelValue;
static CFStringRef kDSPSerialNumberValue;
static const char *kDSPMachineUTF8;
static const char *kDSPModelUTF8;

typedef struct {
    void *target;
    void *replacement;
} DSPBind;

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
    if (kDSPSerialNumberKey && CFEqual(property, kDSPSerialNumberKey)) {
        return kDSPSerialNumberValue;
    }
    return NULL;
}

static CFTypeRef DSP_MGCopyAnswer(CFStringRef property) {
    CFStringRef answer = DSPAnswer(property);
    if (answer) {
        return CFRetain(answer);
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
}

static void DSPReplaceCString(void *buffer, size_t *length, const char *value) {
    if (!buffer || !length || !value) {
        return;
    }
    size_t need = strlen(value) + 1;
    if (*length >= need) {
        memcpy(buffer, value, need);
        *length = need;
    }
}

static int DSP_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int result = orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
    if (result != 0 || !name || !oldp || !oldlenp) {
        return result;
    }
    if (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) {
        DSPReplaceCString(oldp, oldlenp, kDSPMachineUTF8);
    } else if (strcmp(name, "hw.model") == 0) {
        DSPReplaceCString(oldp, oldlenp, kDSPModelUTF8);
    }
    return result;
}

static int DSP_sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int result = orig_sysctl ? orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen) : -1;
    if (result != 0 || !name || namelen < 2 || !oldp || !oldlenp || name[0] != CTL_HW) {
        return result;
    }
    if (name[1] == HW_MACHINE) {
        DSPReplaceCString(oldp, oldlenp, kDSPMachineUTF8);
    } else if (name[1] == HW_MODEL) {
        DSPReplaceCString(oldp, oldlenp, kDSPModelUTF8);
    }
    return result;
}

static int DSP_uname(struct utsname *buffer) {
    int result = orig_uname ? orig_uname(buffer) : -1;
    if (result == 0 && buffer && kDSPMachineUTF8) {
        strlcpy(buffer->machine, kDSPMachineUTF8, sizeof(buffer->machine));
    }
    return result;
}

static void *DSP_dlsym(void *handle, const char *symbol) {
    if (symbol) {
        if (strcmp(symbol, "MGCopyAnswer") == 0 && orig_MGCopyAnswer) {
            return (void *)DSP_MGCopyAnswer;
        }
        if (strcmp(symbol, "sysctlbyname") == 0 && orig_sysctlbyname) {
            return (void *)DSP_sysctlbyname;
        }
        if (strcmp(symbol, "sysctl") == 0 && orig_sysctl) {
            return (void *)DSP_sysctl;
        }
        if (strcmp(symbol, "uname") == 0 && orig_uname) {
            return (void *)DSP_uname;
        }
    }
    return orig_dlsym ? orig_dlsym(handle, symbol) : NULL;
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

static BOOL DSPSectionCanHoldPointers(const struct section_64 *section) {
    uint32_t type = section->flags & SECTION_TYPE;
    if (type == S_ZEROFILL || type == S_GB_ZEROFILL || type == S_THREAD_LOCAL_ZEROFILL) {
        return NO;
    }
    return section->size >= sizeof(void *);
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

static void DSPRebindImage(const struct mach_header *header, intptr_t slide, const DSPBind *binds, unsigned int bindCount) {
    if (!header || header->magic != MH_MAGIC_64 || !binds || bindCount == 0) {
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
                    if (!DSPSectionCanHoldPointers(section)) {
                        continue;
                    }
                    uintptr_t start = (uintptr_t)(section->addr + slide);
                    uintptr_t end = start + (uintptr_t)section->size;
                    start &= ~(uintptr_t)(sizeof(void *) - 1);
                    for (uintptr_t address = start; address + sizeof(void *) <= end; address += sizeof(void *)) {
                        void **slot = (void **)address;
                        void *value = *slot;
                        for (unsigned int bindIndex = 0; bindIndex < bindCount; bindIndex++) {
                            if (value == binds[bindIndex].target && binds[bindIndex].target != binds[bindIndex].replacement) {
                                DSPWriteSlot(slot, binds[bindIndex].replacement);
                                break;
                            }
                        }
                    }
                }
            }
        }
        cursor += command->cmdsize;
    }
}

static void DSPRebindLoadedImages(void) {
    DSPBind binds[5];
    unsigned int count = 0;
    if (orig_MGCopyAnswer) {
        binds[count++] = (DSPBind){(void *)orig_MGCopyAnswer, (void *)DSP_MGCopyAnswer};
    }
    if (orig_sysctlbyname) {
        binds[count++] = (DSPBind){(void *)orig_sysctlbyname, (void *)DSP_sysctlbyname};
    }
    if (orig_sysctl) {
        binds[count++] = (DSPBind){(void *)orig_sysctl, (void *)DSP_sysctl};
    }
    if (orig_uname) {
        binds[count++] = (DSPBind){(void *)orig_uname, (void *)DSP_uname};
    }
    if (orig_dlsym) {
        binds[count++] = (DSPBind){(void *)orig_dlsym, (void *)DSP_dlsym};
    }
    if (count == 0) {
        return;
    }
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        const char *name = _dyld_get_image_name(index);
        if (!DSPImageCanBePatched(name)) {
            continue;
        }
        DSPRebindImage(_dyld_get_image_header(index), _dyld_get_image_vmaddr_slide(index), binds, count);
    }
}

static void DSPPrepareAnswers(void) {
    kDSPMachineUTF8 = [DSPProfile hwMachineUTF8];
    kDSPModelUTF8 = [DSPProfile hardwareModelUTF8];
    kDSPProductTypeKey = CFStringCreateWithCString(NULL, "ProductType", kCFStringEncodingUTF8);
    kDSPHardwareModelKey = CFStringCreateWithCString(NULL, "HardwareModel", kCFStringEncodingUTF8);
    kDSPHWModelStrKey = CFStringCreateWithCString(NULL, "HWModelStr", kCFStringEncodingUTF8);
    kDSPSerialNumberKey = CFStringCreateWithCString(NULL, "SerialNumber", kCFStringEncodingUTF8);
    kDSPProductTypeValue = CFStringCreateWithCString(NULL, kDSPMachineUTF8, kCFStringEncodingUTF8);
    kDSPHardwareModelValue = CFStringCreateWithCString(NULL, kDSPModelUTF8, kCFStringEncodingUTF8);
    kDSPSerialNumberValue = CFStringCreateWithCString(NULL, [DSPProfile serialNumberUTF8], kCFStringEncodingUTF8);
}

static void DSPResolveOriginals(void) {
    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!gestalt) {
        gestalt = dlopen("/System/Library/Frameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
    }
    if (gestalt) {
        orig_MGCopyAnswer = (CFTypeRef (*)(CFStringRef))dlsym(gestalt, "MGCopyAnswer");
    }
    orig_sysctlbyname = (int (*)(const char *, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctlbyname");
    orig_sysctl = (int (*)(int *, unsigned int, void *, size_t *, void *, size_t))dlsym(RTLD_DEFAULT, "sysctl");
    orig_uname = (int (*)(struct utsname *))dlsym(RTLD_DEFAULT, "uname");
    orig_dlsym = (void *(*)(void *, const char *))dlsym(RTLD_DEFAULT, "dlsym");
}

%ctor {
    static BOOL installed = NO;
    if (installed) {
        return;
    }
    [DSPProfile reloadPreferences];
    if (![DSPProfile isSpoofEnabled]) {
        installed = YES;
        return;
    }
    DSPPrepareAnswers();
    DSPResolveOriginals();
    DSPRebindLoadedImages();
    installed = YES;
}
