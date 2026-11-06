#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <errno.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>
#import <mach-o/nlist.h>
#import "DSPProfile.h"
#import "DSPShopeeReport.h"

#ifndef VM_PROT_COPY
#define VM_PROT_COPY 0x10
#endif

static void DSPPrepareAnswers(void);

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, unsigned int, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static void *(*orig_dlsym)(void *, const char *);
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
static uint32_t gDSPReboundSlots = 0;
static uint32_t gDSPProtectFails = 0;
static uint32_t gDSPImagesSeen = 0;
static uint32_t gDSPChainSteps = 0;
static BOOL gDSPAnswersReady = NO;

static void DSPWriteLoadMarker(void) {
    NSDictionary *info = @{
        @"version" : @"1.2.23",
        @"bundle" : [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"process" : [[NSProcessInfo processInfo] processName] ?: @"",
        @"productType" : [DSPProfile productType],
        @"marketingName" : [DSPProfile marketingName],
        @"enabled" : @([DSPProfile isSpoofEnabled]),
        @"hookSysctl" : @(orig_sysctlbyname != NULL && gDSPReboundSlots > 0),
        @"hookUname" : @(orig_uname != NULL && gDSPReboundSlots > 0),
        @"hookGestalt" : @(orig_MGCopyAnswer != NULL && gDSPReboundSlots > 0),
        @"reboundSlots" : @(gDSPReboundSlots),
        @"protectFails" : @(gDSPProtectFails),
        @"imagesSeen" : @(gDSPImagesSeen),
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
    }
    return orig_dlsym ? orig_dlsym(handle, symbol) : dlsym(handle, symbol);
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
        gDSPReboundSlots++;
    } else {
        gDSPProtectFails++;
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

__attribute__((constructor(1))) static void DSPEarlyLoadNote(void) {
    FILE *file = fopen("/var/jb/tmp/devicespoof-loaded.txt", "w");
    if (!file) {
        return;
    }
    fprintf(file, "pid=%d prog=%s\n", getpid(), getprogname() ? getprogname() : "");
    fclose(file);
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
    if ([value isKindOfClass:[NSString class]]) {
        NSString *replaced = [DSPShopeeReport replaceHardwareTokensInString:(NSString *)value];
        if (replaced.length > 0 && ![replaced isEqualToString:(NSString *)value]) {
            return replaced;
        }
    }
    return value;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    if ([DSPProfile isSpoofEnabled] && [value isKindOfClass:[NSString class]]) {
        value = [DSPShopeeReport replaceHardwareTokensInString:(NSString *)value];
    }
    %orig;
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

static BOOL DSPImportNameMatches(const char *name, const char **canonical) {
    if (!name || !canonical) {
        return NO;
    }
    if (name[0] == '_') {
        name++;
    }
    if (strcmp(name, "sysctlbyname") == 0 || strcmp(name, "sysctl") == 0 || strcmp(name, "uname") == 0 ||
        strcmp(name, "dlsym") == 0 || strcmp(name, "MGCopyAnswer") == 0) {
        *canonical = name;
        return YES;
    }
    return NO;
}

static void *DSPRealSymbol(const char *canonical) {
    void *found = canonical ? dlsym(RTLD_DEFAULT, canonical) : NULL;
    if (found || !canonical || strcmp(canonical, "MGCopyAnswer") != 0) {
        return found;
    }
    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!gestalt) {
        gestalt = dlopen("/System/Library/Frameworks/MobileGestalt.framework/MobileGestalt", RTLD_LAZY);
    }
    return gestalt ? dlsym(gestalt, "MGCopyAnswer") : NULL;
}

static void DSPPatchNamedSymbol(const char *canonical, void **slot) {
    void *replacement = NULL;
    void **original = NULL;
    if (!canonical || !slot) {
        return;
    }
    if (strcmp(canonical, "sysctlbyname") == 0) {
        replacement = (void *)DSP_sysctlbyname;
        original = (void **)&orig_sysctlbyname;
    } else if (strcmp(canonical, "sysctl") == 0) {
        replacement = (void *)DSP_sysctl;
        original = (void **)&orig_sysctl;
    } else if (strcmp(canonical, "uname") == 0) {
        replacement = (void *)DSP_uname;
        original = (void **)&orig_uname;
    } else if (strcmp(canonical, "dlsym") == 0) {
        replacement = (void *)DSP_dlsym;
        original = (void **)&orig_dlsym;
    } else if (strcmp(canonical, "MGCopyAnswer") == 0) {
        replacement = (void *)DSP_MGCopyAnswer;
        original = (void **)&orig_MGCopyAnswer;
    }
    if (!replacement || !original || *slot == replacement) {
        return;
    }
    if (!*original) {
        *original = DSPRealSymbol(canonical);
    }
    if (!*original || *original == replacement) {
        return;
    }
    if (*slot != *original) {
        return;
    }
    DSPWriteSlot(slot, replacement);
}

static void DSPRebindNamedImports(const struct mach_header *header, intptr_t slide) {
    if (!header || header->magic != MH_MAGIC_64) {
        return;
    }
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    uintptr_t cursor = (uintptr_t)header64 + sizeof(*header64);
    for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize < cursor) {
            return;
        }
        if (command->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)command;
        } else if (command->cmd == LC_DYSYMTAB) {
            dysymtab = (const struct dysymtab_command *)command;
        }
        cursor += command->cmdsize;
    }
    if (!symtab || !dysymtab) {
        return;
    }
    uintptr_t linkeditBase = 0;
    cursor = (uintptr_t)header64 + sizeof(*header64);
    for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strcmp(segment->segname, "__LINKEDIT") == 0) {
                linkeditBase = (uintptr_t)(segment->vmaddr + slide - segment->fileoff);
                break;
            }
        }
        cursor += command->cmdsize;
    }
    if (!linkeditBase) {
        return;
    }
    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtab->symoff);
    const char *strings = (const char *)(linkeditBase + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(linkeditBase + dysymtab->indirectsymoff);
    cursor = (uintptr_t)header64 + sizeof(*header64);
    for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            const struct section_64 *section = (const struct section_64 *)(segment + 1);
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++, section++) {
                uint32_t type = section->flags & SECTION_TYPE;
                if (type != S_LAZY_SYMBOL_POINTERS && type != S_NON_LAZY_SYMBOL_POINTERS) {
                    continue;
                }
                uint32_t count = (uint32_t)(section->size / sizeof(void *));
                if (count == 0 || section->reserved1 > dysymtab->nindirectsyms || count > dysymtab->nindirectsyms - section->reserved1) {
                    continue;
                }
                void **slots = (void **)(section->addr + slide);
                for (uint32_t index = 0; index < count; index++) {
                    uint32_t symbolIndex = indirect[section->reserved1 + index];
                    if (symbolIndex == INDIRECT_SYMBOL_ABS || symbolIndex == INDIRECT_SYMBOL_LOCAL || symbolIndex == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
                        continue;
                    }
                    if (symbolIndex >= symtab->nsyms) {
                        continue;
                    }
                    uint32_t stringIndex = symbols[symbolIndex].n_un.n_strx;
                    if (stringIndex >= symtab->strsize) {
                        continue;
                    }
                    const char *canonical = NULL;
                    if (!DSPImportNameMatches(strings + stringIndex, &canonical)) {
                        continue;
                    }
                    DSPPatchNamedSymbol(canonical, &slots[index]);
                }
            }
        }
        cursor += command->cmdsize;
    }
}

#ifndef LC_DYLD_CHAINED_FIXUPS
#define LC_DYLD_CHAINED_FIXUPS 0x80000034u
#endif

static BOOL DSPReadAt(int fd, off_t offset, void *buffer, size_t length) {
    uint8_t *out = buffer;
    size_t done = 0;
    if (offset < 0) {
        return NO;
    }
    while (done < length) {
        ssize_t count = pread(fd, out + done, length - done, offset + (off_t)done);
        if (count <= 0) {
            return NO;
        }
        done += (size_t)count;
    }
    return YES;
}

static uint32_t DSPSwap32(uint32_t value) {
    return (value >> 24) | ((value >> 8) & 0xff00) | ((value << 8) & 0xff0000) | (value << 24);
}

static BOOL DSPChainedSymbol(const uint8_t *blob, uint32_t blobSize, uint32_t importsOffset, uint32_t symbolsOffset, uint32_t importsCount, uint32_t importsFormat, uint32_t ordinal, char *out, size_t outSize) {
    uint32_t nameOffset = 0;
    uint32_t entryOffset = 0;
    if (!blob || !out || outSize < 2 || ordinal >= importsCount) {
        return NO;
    }
    if (importsFormat == 1) {
        entryOffset = importsOffset + ordinal * 4;
        if (entryOffset + 4 > blobSize) {
            return NO;
        }
        uint32_t entry = 0;
        memcpy(&entry, blob + entryOffset, sizeof(entry));
        nameOffset = entry >> 9;
    } else if (importsFormat == 2) {
        entryOffset = importsOffset + ordinal * 8;
        if (entryOffset + 4 > blobSize) {
            return NO;
        }
        uint32_t entry = 0;
        memcpy(&entry, blob + entryOffset, sizeof(entry));
        nameOffset = entry >> 9;
    } else if (importsFormat == 3) {
        entryOffset = importsOffset + ordinal * 16;
        if (entryOffset + 8 > blobSize) {
            return NO;
        }
        uint64_t entry = 0;
        memcpy(&entry, blob + entryOffset, sizeof(entry));
        nameOffset = (uint32_t)(entry >> 32);
    } else {
        return NO;
    }
    if (symbolsOffset > blobSize || nameOffset > blobSize - symbolsOffset) {
        return NO;
    }
    const char *source = (const char *)blob + symbolsOffset + nameOffset;
    size_t limit = blobSize - (symbolsOffset + nameOffset);
    size_t length = 0;
    while (length < limit && source[length] != '\0') {
        length++;
    }
    if (length == 0 || length >= limit || length >= outSize) {
        return NO;
    }
    memcpy(out, source, length);
    out[length] = '\0';
    return YES;
}

static void DSPWalkFixupChain(int fd, off_t slice, off_t fileSize, const struct mach_header *header, const struct segment_command_64 *segment, uint64_t textVm, uint64_t position, uint16_t pointerFormat, const uint8_t *blob, uint32_t blobSize, uint32_t importsOffset, uint32_t symbolsOffset, uint32_t importsCount, uint32_t importsFormat) {
    uint32_t stride = (pointerFormat == 2 || pointerFormat == 6) ? 4 : 0;
    if (!fd || !header || !segment || textVm == 0 || stride == 0 || segment->vmaddr < textVm) {
        return;
    }
    for (uint32_t step = 0; step < 200000 && gDSPChainSteps < 25000; step++, gDSPChainSteps++) {
        if (position + sizeof(uint64_t) > segment->filesize || position + sizeof(uint64_t) > segment->vmsize) {
            return;
        }
        off_t fileOffset = slice + (off_t)segment->fileoff + (off_t)position;
        uint64_t raw = 0;
        if (fileOffset < slice || fileOffset + (off_t)sizeof(raw) > fileSize || !DSPReadAt(fd, fileOffset, &raw, sizeof(raw))) {
            return;
        }
        if ((raw >> 63) != 0) {
            char symbol[96];
            const char *canonical = NULL;
            if (DSPChainedSymbol(blob, blobSize, importsOffset, symbolsOffset, importsCount, importsFormat, (uint32_t)(raw & 0xffffffu), symbol, sizeof(symbol)) &&
                DSPImportNameMatches(symbol, &canonical)) {
                uintptr_t slotAddress = (uintptr_t)header + (uintptr_t)(segment->vmaddr - textVm) + (uintptr_t)position;
                if ((slotAddress & (sizeof(void *) - 1)) == 0) {
                    DSPPatchNamedSymbol(canonical, (void **)slotAddress);
                }
            }
        }
        uint32_t next = (uint32_t)((raw >> 51) & 0xfffu);
        if (next == 0) {
            return;
        }
        uint64_t delta = (uint64_t)next * stride;
        if (position + delta < position) {
            return;
        }
        position += delta;
    }
}

static void DSPRebindChainedFixups(const struct mach_header *header, const char *path) {
    int fd = -1;
    uint8_t *commands = NULL;
    uint8_t *blob = NULL;
    struct mach_header_64 mach;
    struct stat info;
    uint32_t magic = 0;
    off_t slice = 0;
    if (!header || header->magic != MH_MAGIC_64 || !path || path[0] != '/') {
        return;
    }
    fd = open(path, O_RDONLY);
    if (fd < 0 || fstat(fd, &info) != 0 || info.st_size < (off_t)sizeof(mach)) {
        if (fd >= 0) {
            close(fd);
        }
        return;
    }
    if (!DSPReadAt(fd, 0, &magic, sizeof(magic))) {
        close(fd);
        return;
    }
    if (magic == 0xBEBAFECAu || magic == 0xCAFEBABEu) {
        uint32_t archCount = 0;
        BOOL found = NO;
        BOOL swap = (magic == 0xBEBAFECAu);
        if (!DSPReadAt(fd, 4, &archCount, sizeof(archCount))) {
            close(fd);
            return;
        }
        if (swap) {
            archCount = DSPSwap32(archCount);
        }
        if (archCount == 0 || archCount > 8) {
            close(fd);
            return;
        }
        for (uint32_t arch = 0; arch < archCount; arch++) {
            uint32_t fields[5];
            if (!DSPReadAt(fd, 8 + (off_t)arch * 20, fields, sizeof(fields))) {
                close(fd);
                return;
            }
            if (swap) {
                for (int field = 0; field < 5; field++) {
                    fields[field] = DSPSwap32(fields[field]);
                }
            }
            if (fields[0] == 0x0100000Cu) {
                slice = (off_t)fields[2];
                found = YES;
                break;
            }
        }
        if (!found) {
            close(fd);
            return;
        }
    }
    if (!DSPReadAt(fd, slice, &mach, sizeof(mach)) || mach.magic != MH_MAGIC_64 || mach.sizeofcmds > 1024 * 1024) {
        close(fd);
        return;
    }
    commands = malloc(mach.sizeofcmds);
    if (!commands || !DSPReadAt(fd, slice + (off_t)sizeof(mach), commands, mach.sizeofcmds)) {
        free(commands);
        close(fd);
        return;
    }
    uint64_t textVm = 0;
    uint32_t fixupOffset = 0;
    uint32_t fixupSize = 0;
    uint32_t cursor = 0;
    for (uint32_t commandIndex = 0; commandIndex < mach.ncmds && cursor + sizeof(struct load_command) <= mach.sizeofcmds; commandIndex++) {
        struct load_command command;
        memcpy(&command, commands + cursor, sizeof(command));
        if (command.cmdsize < sizeof(command) || cursor + command.cmdsize > mach.sizeofcmds) {
            break;
        }
        if (command.cmd == LC_SEGMENT_64 && command.cmdsize >= sizeof(struct segment_command_64)) {
            struct segment_command_64 segment;
            memcpy(&segment, commands + cursor, sizeof(segment));
            if (textVm == 0 && strcmp(segment.segname, "__TEXT") == 0) {
                textVm = segment.vmaddr;
            }
        } else if (command.cmd == LC_DYLD_CHAINED_FIXUPS && command.cmdsize >= 16) {
            memcpy(&fixupOffset, commands + cursor + 8, sizeof(fixupOffset));
            memcpy(&fixupSize, commands + cursor + 12, sizeof(fixupSize));
        }
        cursor += command.cmdsize;
    }
    if (textVm == 0 || fixupSize < 28 || fixupSize > 8 * 1024 * 1024 || slice + (off_t)fixupOffset + (off_t)fixupSize > info.st_size) {
        free(commands);
        close(fd);
        return;
    }
    blob = malloc(fixupSize);
    if (!blob || !DSPReadAt(fd, slice + (off_t)fixupOffset, blob, fixupSize)) {
        free(blob);
        free(commands);
        close(fd);
        return;
    }
    uint32_t startsOffset = 0;
    uint32_t importsOffset = 0;
    uint32_t symbolsOffset = 0;
    uint32_t importsCount = 0;
    uint32_t importsFormat = 0;
    uint32_t symbolsFormat = 0;
    memcpy(&startsOffset, blob + 4, sizeof(startsOffset));
    memcpy(&importsOffset, blob + 8, sizeof(importsOffset));
    memcpy(&symbolsOffset, blob + 12, sizeof(symbolsOffset));
    memcpy(&importsCount, blob + 16, sizeof(importsCount));
    memcpy(&importsFormat, blob + 20, sizeof(importsFormat));
    memcpy(&symbolsFormat, blob + 24, sizeof(symbolsFormat));
    if (symbolsFormat != 0 || importsCount > 1000000 || startsOffset > fixupSize || importsOffset > fixupSize || symbolsOffset > fixupSize) {
        free(blob);
        free(commands);
        close(fd);
        return;
    }
    uint32_t segmentCount = 0;
    if (startsOffset + sizeof(segmentCount) > fixupSize) {
        free(blob);
        free(commands);
        close(fd);
        return;
    }
    memcpy(&segmentCount, blob + startsOffset, sizeof(segmentCount));
    if (segmentCount == 0 || segmentCount > 64 || startsOffset + sizeof(segmentCount) + segmentCount * sizeof(uint32_t) > fixupSize) {
        free(blob);
        free(commands);
        close(fd);
        return;
    }
    uint32_t slotsAtStart = gDSPReboundSlots;
    for (uint32_t segmentIndex = 0; segmentIndex < segmentCount && gDSPReboundSlots < slotsAtStart + 32; segmentIndex++) {
        uint32_t infoOffset = 0;
        memcpy(&infoOffset, blob + startsOffset + sizeof(uint32_t) + segmentIndex * sizeof(uint32_t), sizeof(infoOffset));
        if (infoOffset == 0) {
            continue;
        }
        uint32_t absolute = startsOffset + infoOffset;
        uint32_t infoSize = 0;
        uint16_t pageSize = 0;
        uint16_t pointerFormat = 0;
        uint64_t segmentOffset = 0;
        uint16_t pageCount = 0;
        if (absolute + 22 > fixupSize) {
            continue;
        }
        memcpy(&infoSize, blob + absolute, sizeof(infoSize));
        memcpy(&pageSize, blob + absolute + 4, sizeof(pageSize));
        memcpy(&pointerFormat, blob + absolute + 6, sizeof(pointerFormat));
        memcpy(&segmentOffset, blob + absolute + 8, sizeof(segmentOffset));
        memcpy(&pageCount, blob + absolute + 20, sizeof(pageCount));
        if (pageSize < sizeof(uint64_t) || infoSize < 22u + (uint32_t)pageCount * sizeof(uint16_t) || absolute + infoSize > fixupSize) {
            continue;
        }
        struct segment_command_64 segment;
        BOOL foundSegment = NO;
        uint32_t segmentCursor = 0;
        for (uint32_t commandIndex = 0; commandIndex < mach.ncmds && segmentCursor + sizeof(struct load_command) <= mach.sizeofcmds; commandIndex++) {
            struct load_command command;
            memcpy(&command, commands + segmentCursor, sizeof(command));
            if (command.cmdsize < sizeof(command) || segmentCursor + command.cmdsize > mach.sizeofcmds) {
                break;
            }
            if (command.cmd == LC_SEGMENT_64 && command.cmdsize >= sizeof(segment)) {
                struct segment_command_64 candidate;
                memcpy(&candidate, commands + segmentCursor, sizeof(candidate));
                if (candidate.vmaddr >= textVm && candidate.vmaddr - textVm == segmentOffset) {
                    segment = candidate;
                    foundSegment = YES;
                    break;
                }
            }
            segmentCursor += command.cmdsize;
        }
        if (!foundSegment) {
            continue;
        }
        uint32_t overflowCount = (infoSize - 22u - (uint32_t)pageCount * sizeof(uint16_t)) / sizeof(uint16_t);
        for (uint16_t page = 0; page < pageCount && gDSPReboundSlots < slotsAtStart + 32 && gDSPChainSteps < 25000; page++) {
            uint16_t start = 0;
            memcpy(&start, blob + absolute + 22 + (uint32_t)page * sizeof(uint16_t), sizeof(start));
            if (start == 0xFFFF || ((start & 0x8000) == 0 && start >= pageSize)) {
                continue;
            }
            if (start & 0x8000) {
                uint32_t overflowIndex = start & 0x7FFF;
                while (overflowIndex < overflowCount && gDSPReboundSlots < slotsAtStart + 32 && gDSPChainSteps < 25000) {
                    uint16_t entry = 0;
                    memcpy(&entry, blob + absolute + 22 + (uint32_t)pageCount * sizeof(uint16_t) + overflowIndex * sizeof(uint16_t), sizeof(entry));
                    overflowIndex++;
                    if ((entry & 0x7FFF) >= pageSize) {
                        break;
                    }
                    DSPWalkFixupChain(fd, slice, info.st_size, header, &segment, textVm, (uint64_t)page * pageSize + (entry & 0x7FFF), pointerFormat, blob, fixupSize, importsOffset, symbolsOffset, importsCount, importsFormat);
                    if (entry & 0x8000) {
                        break;
                    }
                }
            } else {
                DSPWalkFixupChain(fd, slice, info.st_size, header, &segment, textVm, (uint64_t)page * pageSize + start, pointerFormat, blob, fixupSize, importsOffset, symbolsOffset, importsCount, importsFormat);
            }
        }
    }
    free(blob);
    free(commands);
    close(fd);
}

static BOOL DSPPathIsShopeeImage(const char *path) {
    if (!path || strstr(path, "DeviceSpoof") || strstr(path, "libellekit") || strstr(path, "libsubstrate")) {
        return NO;
    }
    return strstr(path, "Shopee") != NULL || strstr(path, "shopee") != NULL;
}

static void DSPRebindShopeeImports(void) {
    uint32_t count = _dyld_image_count();
    uint32_t patchedImages = 0;
    gDSPChainSteps = 0;
    for (uint32_t index = 0; index < count && patchedImages < 24 && gDSPChainSteps < 25000; index++) {
        const char *name = _dyld_get_image_name(index);
        if ((index != 0 && !DSPPathIsShopeeImage(name)) || (name && (strncmp(name, "/System/", 8) == 0 || strncmp(name, "/usr/lib/", 9) == 0))) {
            continue;
        }
        const struct mach_header *header = _dyld_get_image_header(index);
        if (!header) {
            continue;
        }
        gDSPImagesSeen++;
        patchedImages++;
        DSPRebindNamedImports(header, _dyld_get_image_vmaddr_slide(index));
        DSPRebindChainedFixups(header, name);
    }
}

%ctor {
    static BOOL installed = NO;
    if (installed) {
        return;
    }
    DSPWriteLoadMarker();
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
    BOOL isShopee = [bundleIdentifier rangeOfString:@"shopee" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [processName rangeOfString:@"shopee" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (!isShopee) {
        installed = YES;
        return;
    }
    [DSPProfile reloadPreferences];
    DSPEnsureReady();
    if ([DSPProfile isSpoofEnabled]) {
        char realMachine[32] = {0};
        size_t realMachineLength = sizeof(realMachine);
        if (sysctlbyname("hw.machine", realMachine, &realMachineLength, NULL, 0) == 0 && realMachine[0]) {
            [DSPProfile captureRealMachine:realMachine];
        }
        DSPRebindShopeeImports();
    }
    DSPWriteLoadMarker();
    installed = YES;
}
