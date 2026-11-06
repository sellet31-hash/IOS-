#import "DSPProfile.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <string.h>

static NSString *const kDSPPrefsPathRootless = @"/var/jb/Library/Preferences/com.appbackup.devicespoof.plist";
static NSString *const kDSPKeyEnabled = @"enabled";
static NSString *const kDSPKeyVendorUUID = @"vendorUUID";
static NSString *const kDSPKeyStoredVendorUUID = @"storedVendorUUID";
static NSString *const kDSPKeyInstallUUID = @"installUUID";
static NSString *const kDSPKeyStoredInstallUUID = @"storedInstallUUID";
static NSString *const kDSPKeyRegenerateVendorId = @"regenerateVendorId";
static NSString *const kDSPKeyRegenerateFreshInstall = @"regenerateFreshInstall";
static NSString *const kDSPKeySimulateFreshInstall = @"simulateFreshInstall";
static NSString *const kDSPKeyDeviceFingerprint = @"deviceFingerprint";
static NSString *const kDSPKeyStoredDeviceFingerprint = @"storedDeviceFingerprint";
static NSString *const kDSPKeyModelEpoch = @"modelEpoch";
static const NSInteger kDSPModelEpoch = 1;

static const char kDSPProductTypeUTF8[] = "iPhone18,3";
static const char kDSPHardwareModelUTF8[] = "V57AP";
static const char kDSPIOSVersionUTF8[] = "26.0";
static const char kDSPSerialUTF8[] = "F3PF534FRQ7E";
static const char kDSPMLBUTF8[] = "F3PF534FRQ7EH7ABC";

static BOOL sDSPEnabled = YES;
static BOOL sSimulateFreshInstall = YES;
static NSUUID *sVendorUUID = nil;
static NSString *sInstallUUIDString = nil;
static NSString *sDeviceFingerprintHex = nil;
static char sRealMachine[32];
static NSString *sRealMarketingName = nil;

static NSString *DSPMarketingNameForMachine(NSString *machine) {
    if (machine.length == 0) {
        return nil;
    }
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"iPhone12,1" : @"iPhone 11",
            @"iPhone12,3" : @"iPhone 11 Pro",
            @"iPhone12,5" : @"iPhone 11 Pro Max",
            @"iPhone13,1" : @"iPhone 12 mini",
            @"iPhone13,2" : @"iPhone 12",
            @"iPhone13,3" : @"iPhone 12 Pro",
            @"iPhone13,4" : @"iPhone 12 Pro Max",
            @"iPhone14,4" : @"iPhone 13 mini",
            @"iPhone14,5" : @"iPhone 13",
            @"iPhone14,2" : @"iPhone 13 Pro",
            @"iPhone14,3" : @"iPhone 13 Pro Max",
            @"iPhone14,7" : @"iPhone 14",
            @"iPhone14,8" : @"iPhone 14 Plus",
            @"iPhone15,2" : @"iPhone 14 Pro",
            @"iPhone15,3" : @"iPhone 14 Pro Max",
            @"iPhone15,4" : @"iPhone 15",
            @"iPhone15,5" : @"iPhone 15 Plus",
            @"iPhone16,1" : @"iPhone 15 Pro",
            @"iPhone16,2" : @"iPhone 15 Pro Max",
            @"iPhone17,1" : @"iPhone 16 Pro",
            @"iPhone17,2" : @"iPhone 16 Pro Max",
            @"iPhone17,3" : @"iPhone 16",
            @"iPhone17,4" : @"iPhone 16 Plus",
            @"iPhone17,5" : @"iPhone 16e",
        };
    });
    return names[machine];
}

static NSUUID *DSPParseUUID(NSString *value) {
    if (value.length == 0) {
        return nil;
    }
    return [[NSUUID alloc] initWithUUIDString:value];
}

static void DSPSavePlist(NSDictionary *plist) {
    if (!plist) {
        return;
    }
    [plist writeToFile:kDSPPrefsPathRootless atomically:YES];
}

static NSString *DSPFreshUUIDString(void) {
    return [[NSUUID UUID] UUIDString];
}

static NSString *DSPFreshDeviceFingerprintHex(void) {
    uint8_t bytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) == errSecSuccess) {
        NSMutableString *hex = [NSMutableString stringWithCapacity:32];
        for (NSUInteger i = 0; i < sizeof(bytes); i++) {
            [hex appendFormat:@"%02X", bytes[i]];
        }
        return hex;
    }
    NSString *raw = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return raw.uppercaseString;
}

@implementation DSPProfile

+ (void)reloadPreferences {
    NSMutableDictionary *plist = [[NSDictionary dictionaryWithContentsOfFile:kDSPPrefsPathRootless] mutableCopy];
    if (!plist) {
        plist = [NSMutableDictionary dictionary];
    }

    id enabled = plist[kDSPKeyEnabled];
    if ([enabled isKindOfClass:[NSNumber class]]) {
        sDSPEnabled = [(NSNumber *)enabled boolValue];
    } else {
        sDSPEnabled = YES;
    }

    id simulate = plist[kDSPKeySimulateFreshInstall];
    if ([simulate isKindOfClass:[NSNumber class]]) {
        sSimulateFreshInstall = [(NSNumber *)simulate boolValue];
    } else {
        sSimulateFreshInstall = YES;
    }

    BOOL dirty = NO;
    BOOL regen = [plist[kDSPKeyRegenerateFreshInstall] boolValue] || [plist[kDSPKeyRegenerateVendorId] boolValue];
    if ([plist[kDSPKeyModelEpoch] integerValue] < kDSPModelEpoch) {
        regen = YES;
        plist[kDSPKeyModelEpoch] = @(kDSPModelEpoch);
    }
    if (regen) {
        [plist removeObjectForKey:kDSPKeyRegenerateFreshInstall];
        [plist removeObjectForKey:kDSPKeyRegenerateVendorId];
        plist[kDSPKeyStoredVendorUUID] = DSPFreshUUIDString();
        plist[kDSPKeyStoredInstallUUID] = DSPFreshUUIDString();
        plist[kDSPKeyStoredDeviceFingerprint] = DSPFreshDeviceFingerprintHex();
        dirty = YES;
    }

    NSString *manualFingerprint = plist[kDSPKeyDeviceFingerprint];
    if (manualFingerprint.length > 0) {
        sDeviceFingerprintHex = [manualFingerprint uppercaseString];
    } else {
        NSString *storedFingerprint = plist[kDSPKeyStoredDeviceFingerprint];
        if (storedFingerprint.length > 0) {
            sDeviceFingerprintHex = [storedFingerprint uppercaseString];
        } else {
            NSString *fresh = DSPFreshDeviceFingerprintHex();
            plist[kDSPKeyStoredDeviceFingerprint] = fresh;
            sDeviceFingerprintHex = fresh;
            dirty = YES;
        }
    }

    NSString *manualInstall = plist[kDSPKeyInstallUUID];
    if (manualInstall.length > 0) {
        sInstallUUIDString = [manualInstall copy];
    } else {
        NSString *storedInstall = plist[kDSPKeyStoredInstallUUID];
        if (storedInstall.length > 0) {
            sInstallUUIDString = [storedInstall copy];
        } else {
            NSString *fresh = DSPFreshUUIDString();
            plist[kDSPKeyStoredInstallUUID] = fresh;
            sInstallUUIDString = fresh;
            dirty = YES;
        }
    }

    NSUUID *manualVendor = DSPParseUUID(plist[kDSPKeyVendorUUID]);
    if (manualVendor) {
        sVendorUUID = manualVendor;
    } else {
        NSString *storedVendor = plist[kDSPKeyStoredVendorUUID];
        if (storedVendor.length > 0) {
            sVendorUUID = DSPParseUUID(storedVendor);
        } else {
            NSString *fresh = DSPFreshUUIDString();
            plist[kDSPKeyStoredVendorUUID] = fresh;
            sVendorUUID = DSPParseUUID(fresh);
            dirty = YES;
        }
    }

    if (dirty) {
        DSPSavePlist(plist);
    }
}

+ (void)captureRealMachine:(const char *)machine {
    if (!machine || machine[0] == '\0' || sRealMachine[0] != '\0') {
        return;
    }
    strlcpy(sRealMachine, machine, sizeof(sRealMachine));
    NSString *machineString = [[NSString alloc] initWithBytes:sRealMachine
                                                        length:strlen(sRealMachine)
                                                      encoding:NSUTF8StringEncoding];
    sRealMarketingName = DSPMarketingNameForMachine(machineString);
}

+ (const char *)realMachineUTF8 {
    return sRealMachine[0] ? sRealMachine : NULL;
}

+ (NSString *)realMarketingName {
    return sRealMarketingName;
}

+ (BOOL)isSpoofEnabled {
    return sDSPEnabled;
}

+ (BOOL)simulateFreshInstall {
    return sSimulateFreshInstall;
}

+ (NSUUID *)spoofedVendorIdentifier {
    return sVendorUUID;
}

+ (NSString *)shopeeDeviceFingerprintHex {
    return sDeviceFingerprintHex ?: @"";
}

+ (const char *)installSessionUUIDUTF8 {
    return sInstallUUIDString.UTF8String ?: "";
}

+ (const char *)productTypeUTF8 {
    return kDSPProductTypeUTF8;
}

+ (const char *)hardwareModelUTF8 {
    return kDSPHardwareModelUTF8;
}

+ (const char *)hwMachineUTF8 {
    return kDSPProductTypeUTF8;
}

+ (const char *)serialNumberUTF8 {
    return kDSPSerialUTF8;
}

+ (const char *)mlbSerialUTF8 {
    return kDSPMLBUTF8;
}

+ (NSString *)productType {
    return @"iPhone18,3";
}

+ (NSString *)hardwareModel {
    return @"V57AP";
}

+ (NSString *)hwMachine {
    return @"iPhone18,3";
}

+ (NSString *)marketingName {
    return @"iPhone 17";
}

+ (NSString *)spoofedOSVersion {
    return @"26.0";
}

+ (const char *)osVersionUTF8 {
    return kDSPIOSVersionUTF8;
}

+ (CGRect)screenBounds {
    return CGRectMake(0, 0, 393, 852);
}

+ (CGFloat)screenScale {
    return 3.0;
}

+ (CGRect)nativeScreenBounds {
    return CGRectMake(0, 0, 1179, 2556);
}

@end
