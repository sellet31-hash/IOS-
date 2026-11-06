#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <errno.h>
#import <string.h>
#import <sys/syscall.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>
#import "DSPProfile.h"
#import "DSPShopeeReport.h"

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

typedef struct {
    void *target;
    void *replacement;
} DSPBind;

static void DSPPrepareAnswers(void);
static void DSPInstallInlineHooks(void);

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, unsigned int, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static void *(*orig_dlsym)(void *, const char *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static int (*orig_syscall)(int, long, long, long, long, long, long);
static void *gDSPTargetMGCopyAnswer;
static void *gDSPTargetSysctlbyname;
static void *gDSPTargetSysctl;
static void *gDSPTargetUname;
static void *gDSPTargetDlsym;
static void *gDSPTargetSecItem;
static void *gDSPTargetSyscall;
static __thread int gDSPSysctlbynameDepth;
static __thread int gDSPSysctlDepth;
static __thread int gDSPUnameDepth;
static __thread int gDSPStringHookDepth;

static CFStringRef kDSPProductTypeKey;
static CFStringRef kDSPHardwareModelKey;
static CFStringRef kDSPHWModelStrKey;
static CFStringRef kDSPSerialNumberKey;
static CFStringRef kDSPMLBSerialNumberKey;
static CFStringRef kDSPProductTypeValue;
static CFStringRef kDSPHardwareModelValue;
static CFStringRef kDSPSerialNumberValue;
static CFStringRef kDSPMLBSerialNumberValue;
static CFStringRef kDSPInstallSessionValue;
static CFStringRef kDSPInstallUUIDKey;
static CFStringRef kDSPInstallationUUIDKey;
static CFStringRef kDSPSystemSessionUUIDKey;
static CFStringRef kDSPBootSessionUUIDKey;
static CFStringRef kDSPProductVersionKey;
static CFStringRef kDSPHumanReadableProductVersionKey;
static CFStringRef kDSPProductVersionValue;
static CFStringRef kDSPMarketingNameKey;
static CFStringRef kDSPMarketingNameValue;
static const char *kDSPMachineUTF8;
static const char *kDSPModelUTF8;
static const char *kDSPIOSVersionUTF8;
static unsigned int gDSPBindCount = 0;
static DSPBind gDSPBinds[8];
static BOOL gDSPAnswersReady = NO;

static void DSPWriteLoadMarker(void) {
    NSDictionary *info = @{
        @"version" : @"1.2.12",
        @"bundle" : [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"productType" : [DSPProfile productType],
        @"marketingName" : [DSPProfile marketingName],
        @"enabled" : @([DSPProfile isSpoofEnabled]),
        @"hookSysctl" : @(orig_sysctlbyname != NULL),
        @"hookUname" : @(orig_uname != NULL),
        @"hookGestalt" : @(orig_MGCopyAnswer != NULL),
        @"loadedAt" : @((NSInteger)[[NSDate date] timeIntervalSince1970]),
        @"markerHint" : @"Filza: Shopee container Library/Caches, or /var/jb/tmp/",
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:info
                                                            format:NSPropertyListXMLFormat_v1_0
                                                           options:0
                                                             error:nil];
    if (!data) {
        return;
    }
    NSString *fileName = @"com.appbackup.devicespoof.lastload.plist";
    NSString *sandboxCaches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (sandboxCaches.length) {
        [data writeToFile:[sandboxCaches stringByAppendingPathComponent:fileName] atomically:YES];
    }
    [data writeToFile:[@"/var/jb/tmp" stringByAppendingPathComponent:fileName] atomically:YES];
}

static void DSPEnsureReady(void) {
    if (gDSPAnswersReady) {
        return;
    }
    [DSPProfile reloadPreferences];
    if ([DSPProfile isSpoofEnabled]) {
        DSPPrepareAnswers();
    }
    gDSPAnswersReady = YES;
}

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
    if (kDSPMLBSerialNumberKey && CFEqual(property, kDSPMLBSerialNumberKey)) {
        return kDSPMLBSerialNumberValue;
    }
    if (kDSPInstallSessionValue) {
        if ((kDSPInstallUUIDKey && CFEqual(property, kDSPInstallUUIDKey)) ||
            (kDSPInstallationUUIDKey && CFEqual(property, kDSPInstallationUUIDKey)) ||
            (kDSPSystemSessionUUIDKey && CFEqual(property, kDSPSystemSessionUUIDKey)) ||
            (kDSPBootSessionUUIDKey && CFEqual(property, kDSPBootSessionUUIDKey))) {
            return kDSPInstallSessionValue;
        }
    }
    if (kDSPProductVersionValue) {
        if ((kDSPProductVersionKey && CFEqual(property, kDSPProductVersionKey)) ||
            (kDSPHumanReadableProductVersionKey && CFEqual(property, kDSPHumanReadableProductVersionKey))) {
            return kDSPProductVersionValue;
        }
    }
    if (kDSPMarketingNameKey && kDSPMarketingNameValue && CFEqual(property, kDSPMarketingNameKey)) {
        return kDSPMarketingNameValue;
    }
    return NULL;
}

static BOOL DSPAttrContainsNeedle(CFDictionaryRef query, CFStringRef attrKey) {
    CFTypeRef value = CFDictionaryGetValue(query, attrKey);
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
        return NO;
    }
    NSString *lower = [(__bridge NSString *)value lowercaseString];
    NSArray<NSString *> *needles = @[
        @"device", @"fingerprint", @"install", @"visitor", @"distinct", @"shopee",
        @"machine", @"hardware", @"devid", @"uuid", @"client", @"track"
    ];
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL DSPQueryIsPersistedDeviceSecret(CFDictionaryRef query) {
    if (!query || ![DSPProfile simulateFreshInstall]) {
        return NO;
    }
    CFTypeRef klass = CFDictionaryGetValue(query, kSecClass);
    if (klass == kSecClassCertificate || klass == kSecClassIdentity) {
        return NO;
    }
    return DSPAttrContainsNeedle(query, kSecAttrAccount) ||
           DSPAttrContainsNeedle(query, kSecAttrService) ||
           DSPAttrContainsNeedle(query, kSecAttrLabel) ||
           DSPAttrContainsNeedle(query, kSecAttrGeneric);
}

static OSStatus DSP_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (DSPQueryIsPersistedDeviceSecret(query)) {
        if (result) {
            *result = NULL;
        }
        return errSecItemNotFound;
    }
    return orig_SecItemCopyMatching ? orig_SecItemCopyMatching(query, result) : errSecParam;
}

static CFTypeRef DSP_MGCopyAnswer(CFStringRef property) {
    CFStringRef answer = DSPAnswer(property);
    if (answer) {
        return CFRetain(answer);
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
}

static const char *DSPSpoofForSysctlName(const char *name) {
    if (!name) {
        return NULL;
    }
    if ((strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.product") == 0) && kDSPMachineUTF8) {
        return kDSPMachineUTF8;
    }
    if (strcmp(name, "hw.model") == 0 && kDSPModelUTF8) {
        return kDSPModelUTF8;
    }
    if (strcmp(name, "kern.osproductversion") == 0 && kDSPIOSVersionUTF8) {
        return kDSPIOSVersionUTF8;
    }
    return NULL;
}

static int DSPWriteSpoofedCString(void *oldp, size_t *oldlenp, const char *value) {
    size_t need = strlen(value) + 1;
    if (!oldp) {
        if (oldlenp) {
            *oldlenp = need;
        }
        return 0;
    }
    if (!oldlenp) {
        errno = EINVAL;
        return -1;
    }
    if (*oldlenp < need) {
        *oldlenp = need;
        errno = ENOMEM;
        return -1;
    }
    memcpy(oldp, value, need);
    *oldlenp = need;
    return 0;
}

static int DSP_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const char *spoof = DSPSpoofForSysctlName(name);
    if (spoof) {
        return DSPWriteSpoofedCString(oldp, oldlenp, spoof);
    }
    if (!orig_sysctlbyname) {
        errno = ENOSYS;
        return -1;
    }
    if (gDSPSysctlbynameDepth > 0) {
        errno = EAGAIN;
        return -1;
    }
    gDSPSysctlbynameDepth++;
    int result = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    gDSPSysctlbynameDepth--;
    return result;
}

static int DSP_sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && namelen >= 2 && name[0] == CTL_HW) {
        const char *spoof = NULL;
        if (name[1] == HW_MACHINE && kDSPMachineUTF8) {
            spoof = kDSPMachineUTF8;
        } else if (name[1] == HW_MODEL && kDSPModelUTF8) {
            spoof = kDSPModelUTF8;
        }
        if (spoof) {
            return DSPWriteSpoofedCString(oldp, oldlenp, spoof);
        }
    }
    if (!orig_sysctl) {
        errno = ENOSYS;
        return -1;
    }
    if (gDSPSysctlDepth > 0) {
        errno = EAGAIN;
        return -1;
    }
    gDSPSysctlDepth++;
    int result = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    gDSPSysctlDepth--;
    return result;
}

static int DSP_syscall(int number, long arg1, long arg2, long arg3, long arg4, long arg5, long arg6) {
    int result = orig_syscall ? orig_syscall(number, arg1, arg2, arg3, arg4, arg5, arg6) : -1;
#ifndef SYS_sysctl
#define SYS_sysctl 202
#endif
    if (number != SYS_sysctl || result != 0 || arg1 == 0 || arg3 == 0 || arg4 == 0) {
        return result;
    }
    int *name = (int *)(uintptr_t)arg1;
    unsigned int namelen = (unsigned int)arg2;
    void *oldp = (void *)(uintptr_t)arg3;
    size_t *oldlenp = (size_t *)(uintptr_t)arg4;
    if (!name || namelen < 2 || name[0] != CTL_HW) {
        return result;
    }
    const char *spoof = NULL;
    if (name[1] == HW_MACHINE && kDSPMachineUTF8) {
        spoof = kDSPMachineUTF8;
    } else if (name[1] == HW_MODEL && kDSPModelUTF8) {
        spoof = kDSPModelUTF8;
    }
    if (!spoof) {
        return result;
    }
    size_t need = strlen(spoof) + 1;
    if (*oldlenp < need) {
        return result;
    }
    memcpy(oldp, spoof, need);
    *oldlenp = need;
    return result;
}

static int DSP_uname(struct utsname *buffer) {
    if (!orig_uname) {
        errno = ENOSYS;
        return -1;
    }
    if (gDSPUnameDepth > 0) {
        errno = EAGAIN;
        return -1;
    }
    gDSPUnameDepth++;
    int result = orig_uname(buffer);
    gDSPUnameDepth--;
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
        if (strcmp(symbol, "SecItemCopyMatching") == 0 && orig_SecItemCopyMatching) {
            return (void *)DSP_SecItemCopyMatching;
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

static void DSPRebuildBindTable(void) {
    gDSPBindCount = 0;
    if (gDSPTargetMGCopyAnswer && orig_MGCopyAnswer) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetMGCopyAnswer, (void *)DSP_MGCopyAnswer};
    }
    if (gDSPTargetSysctlbyname && orig_sysctlbyname) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetSysctlbyname, (void *)DSP_sysctlbyname};
    }
    if (gDSPTargetSysctl && orig_sysctl) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetSysctl, (void *)DSP_sysctl};
    }
    if (gDSPTargetUname && orig_uname) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetUname, (void *)DSP_uname};
    }
    if (gDSPTargetDlsym && orig_dlsym) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetDlsym, (void *)DSP_dlsym};
    }
    if (gDSPTargetSecItem && orig_SecItemCopyMatching) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetSecItem, (void *)DSP_SecItemCopyMatching};
    }
    if (gDSPTargetSyscall && orig_syscall) {
        gDSPBinds[gDSPBindCount++] = (DSPBind){gDSPTargetSyscall, (void *)DSP_syscall};
    }
}

static void DSPRebindOneImage(const struct mach_header *header, intptr_t slide, const char *name) {
    if (!header || gDSPBindCount == 0) {
        return;
    }
    if (name && !DSPImageCanBePatched(name)) {
        return;
    }
    DSPRebindImage(header, slide, gDSPBinds, gDSPBindCount);
}

static void DSPDyldImageAdded(const struct mach_header *header, intptr_t slide) {
    if (![DSPProfile isSpoofEnabled]) {
        return;
    }
    const char *name = NULL;
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        if (_dyld_get_image_header(index) == header) {
            name = _dyld_get_image_name(index);
            break;
        }
    }
    DSPRebindOneImage(header, slide, name);
}

static void DSPRebindLoadedImages(void) {
    DSPRebuildBindTable();
    if (gDSPBindCount == 0) {
        return;
    }
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        DSPRebindOneImage(_dyld_get_image_header(index), _dyld_get_image_vmaddr_slide(index), _dyld_get_image_name(index));
    }
}

static void DSPPrepareAnswers(void) {
    kDSPMachineUTF8 = [DSPProfile hwMachineUTF8];
    kDSPModelUTF8 = [DSPProfile hardwareModelUTF8];
    kDSPIOSVersionUTF8 = [DSPProfile osVersionUTF8];
    kDSPProductTypeKey = CFStringCreateWithCString(NULL, "ProductType", kCFStringEncodingUTF8);
    kDSPHardwareModelKey = CFStringCreateWithCString(NULL, "HardwareModel", kCFStringEncodingUTF8);
    kDSPHWModelStrKey = CFStringCreateWithCString(NULL, "HWModelStr", kCFStringEncodingUTF8);
    kDSPSerialNumberKey = CFStringCreateWithCString(NULL, "SerialNumber", kCFStringEncodingUTF8);
    kDSPMLBSerialNumberKey = CFStringCreateWithCString(NULL, "MLBSerialNumber", kCFStringEncodingUTF8);
    kDSPProductTypeValue = CFStringCreateWithCString(NULL, kDSPMachineUTF8, kCFStringEncodingUTF8);
    kDSPHardwareModelValue = CFStringCreateWithCString(NULL, kDSPModelUTF8, kCFStringEncodingUTF8);
    kDSPSerialNumberValue = CFStringCreateWithCString(NULL, [DSPProfile serialNumberUTF8], kCFStringEncodingUTF8);
    kDSPMLBSerialNumberValue = CFStringCreateWithCString(NULL, [DSPProfile mlbSerialUTF8], kCFStringEncodingUTF8);
    kDSPInstallUUIDKey = CFStringCreateWithCString(NULL, "InstallUUID", kCFStringEncodingUTF8);
    kDSPInstallationUUIDKey = CFStringCreateWithCString(NULL, "InstallationUUID", kCFStringEncodingUTF8);
    kDSPSystemSessionUUIDKey = CFStringCreateWithCString(NULL, "SystemSessionUUID", kCFStringEncodingUTF8);
    kDSPBootSessionUUIDKey = CFStringCreateWithCString(NULL, "BootSessionUUID", kCFStringEncodingUTF8);
    kDSPInstallSessionValue = CFStringCreateWithCString(NULL, [DSPProfile installSessionUUIDUTF8], kCFStringEncodingUTF8);
    kDSPProductVersionKey = CFStringCreateWithCString(NULL, "ProductVersion", kCFStringEncodingUTF8);
    kDSPHumanReadableProductVersionKey = CFStringCreateWithCString(NULL, "HumanReadableProductVersionString", kCFStringEncodingUTF8);
    kDSPProductVersionValue = CFStringCreateWithCString(NULL, [DSPProfile osVersionUTF8], kCFStringEncodingUTF8);
    kDSPMarketingNameKey = CFStringCreateWithCString(NULL, "MarketingName", kCFStringEncodingUTF8);
    kDSPMarketingNameValue = CFStringCreateWithCString(NULL, [DSPProfile marketingName].UTF8String, kCFStringEncodingUTF8);
}

%hook UIDevice

- (NSUUID *)identifierForVendor {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        NSUUID *vendor = [DSPProfile spoofedVendorIdentifier];
        if (vendor) {
            return vendor;
        }
    }
    return %orig;
}

- (NSString *)systemVersion {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile spoofedOSVersion];
    }
    return %orig;
}

- (NSString *)model {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile marketingName];
    }
    return %orig;
}

- (NSString *)localizedModel {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile marketingName];
    }
    return %orig;
}

- (NSString *)machineModel {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile productType];
    }
    return %orig;
}

- (NSString *)machineModelName {
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile marketingName];
    }
    return %orig;
}

%end

%hook UIScreen

- (CGRect)bounds {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile screenBounds];
    }
    return %orig;
}

- (CGRect)nativeBounds {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile nativeScreenBounds];
    }
    return %orig;
}

- (CGFloat)scale {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile screenScale];
    }
    return %orig;
}

- (CGFloat)nativeScale {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile screenScale];
    }
    return %orig;
}

%end

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    if ([DSPProfile isSpoofEnabled]) {
        NSOperatingSystemVersion version = {0};
        version.majorVersion = 26;
        version.minorVersion = 0;
        version.patchVersion = 0;
        return version;
    }
    return %orig;
}

- (NSString *)operatingSystemVersionString {
    if ([DSPProfile isSpoofEnabled]) {
        return [DSPProfile spoofedOSVersion];
    }
    return %orig;
}

%end

%hook NSUserDefaults

- (NSString *)stringForKey:(NSString *)defaultName {
    if ([DSPProfile isSpoofEnabled] && defaultName.length > 0) {
        if ([DSPShopeeReport isDeviceFingerprintKey:defaultName]) {
            return [DSPShopeeReport deviceFingerprintHex];
        }
        if ([DSPShopeeReport isDeviceModelKey:defaultName]) {
            return [DSPShopeeReport productTypeForReports];
        }
        if ([DSPShopeeReport isOSVersionKey:defaultName]) {
            return [DSPShopeeReport osVersionForReports];
        }
        if ([DSPShopeeReport isMarketingNameKey:defaultName]) {
            return [DSPShopeeReport marketingNameForReports];
        }
    }
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    id value = %orig;
    if (![DSPProfile isSpoofEnabled] || defaultName.length == 0) {
        return value;
    }
    if ([DSPShopeeReport isDeviceFingerprintKey:defaultName]) {
        return [DSPShopeeReport deviceFingerprintHex];
    }
    if ([DSPShopeeReport isDeviceModelKey:defaultName] && [value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        if ([stringValue containsString:@"iPhone"] || [stringValue containsString:@"iPad"]) {
            return [DSPShopeeReport productTypeForReports];
        }
    }
    if ([DSPShopeeReport isOSVersionKey:defaultName]) {
        return [DSPShopeeReport osVersionForReports];
    }
    if ([DSPShopeeReport isMarketingNameKey:defaultName]) {
        return [DSPShopeeReport marketingNameForReports];
    }
    return value;
}

%end

%hook NSJSONSerialization

+ (NSData *)dataWithJSONObject:(id)obj options:(NSUInteger)opt error:(NSError **)error {
    if ([DSPProfile isSpoofEnabled] && obj) {
        id rewritten = [DSPShopeeReport rewritePayloadIfNeeded:obj];
        return %orig(rewritten, opt, error);
    }
    return %orig(obj, opt, error);
}

%end

%hook NSMutableURLRequest

- (void)setHTTPBody:(NSData *)HTTPBody {
    if ([DSPProfile isSpoofEnabled] && HTTPBody.length > 0) {
        NSData *replaced = [DSPShopeeReport replaceHardwareTokensInData:HTTPBody];
        %orig(replaced ?: HTTPBody);
        return;
    }
    %orig;
}

%end

%hook NSString

+ (instancetype)stringWithUTF8String:(const char *)bytes {
    const char *realMachine = [DSPProfile realMachineUTF8];
    if (gDSPStringHookDepth > 0 || ![DSPProfile isSpoofEnabled] || !bytes || !realMachine || !strstr(bytes, realMachine)) {
        return %orig;
    }
    gDSPStringHookDepth++;
    NSString *value = %orig;
    NSString *replaced = value ? [DSPShopeeReport replaceHardwareTokensInString:value] : value;
    gDSPStringHookDepth--;
    return replaced ?: value;
}

+ (instancetype)stringWithCString:(const char *)bytes encoding:(NSStringEncoding)encoding {
    const char *realMachine = [DSPProfile realMachineUTF8];
    if (gDSPStringHookDepth > 0 || ![DSPProfile isSpoofEnabled] || !bytes || !realMachine || !strstr(bytes, realMachine)) {
        return %orig;
    }
    gDSPStringHookDepth++;
    NSString *value = %orig;
    NSString *replaced = value ? [DSPShopeeReport replaceHardwareTokensInString:value] : value;
    gDSPStringHookDepth--;
    return replaced ?: value;
}

%end

static BOOL DSPHookLinked(void *symbol, void *replacement, void **original) {
    if (!symbol || !replacement || !original) {
        return NO;
    }
    *original = NULL;
    MSHookFunction(symbol, replacement, original);
    return *original != NULL && *original != symbol && *original != replacement;
}

static void DSPInstallInlineHooks(void) {
    char realMachine[32] = {0};
    size_t realMachineLength = sizeof(realMachine);
    if (sysctlbyname("hw.machine", realMachine, &realMachineLength, NULL, 0) == 0) {
        [DSPProfile captureRealMachine:realMachine];
    }

    gDSPTargetSysctlbyname = (void *)sysctlbyname;
    gDSPTargetSysctl = (void *)sysctl;
    gDSPTargetUname = (void *)uname;
    gDSPTargetDlsym = (void *)dlsym;
    gDSPTargetSecItem = (void *)SecItemCopyMatching;
    gDSPTargetSyscall = dlsym(RTLD_DEFAULT, "syscall");
    orig_dlsym = (void *(*)(void *, const char *))dlsym;

    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!gestalt) {
        gestalt = dlopen("/System/Library/Frameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
    }
    if (gestalt) {
        gDSPTargetMGCopyAnswer = dlsym(gestalt, "MGCopyAnswer");
    }
    if (!gDSPTargetMGCopyAnswer) {
        gDSPTargetMGCopyAnswer = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
    }

    DSPHookLinked(gDSPTargetSysctlbyname, (void *)DSP_sysctlbyname, (void **)&orig_sysctlbyname);
    DSPHookLinked(gDSPTargetSysctl, (void *)DSP_sysctl, (void **)&orig_sysctl);
    DSPHookLinked(gDSPTargetUname, (void *)DSP_uname, (void **)&orig_uname);
    DSPHookLinked(gDSPTargetSecItem, (void *)DSP_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
    DSPHookLinked(gDSPTargetMGCopyAnswer, (void *)DSP_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
    DSPHookLinked(gDSPTargetSyscall, (void *)DSP_syscall, (void **)&orig_syscall);
}

%ctor {
    static BOOL installed = NO;
    if (installed) {
        return;
    }
    [DSPProfile reloadPreferences];
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        DSPInstallInlineHooks();
        DSPRebindLoadedImages();
        _dyld_register_func_for_add_image(DSPDyldImageAdded);
    }
    DSPWriteLoadMarker();
    installed = YES;
}
