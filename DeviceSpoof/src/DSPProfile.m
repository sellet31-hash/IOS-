#import "DSPProfile.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <stdio.h>
#import <string.h>
#import <uuid/uuid.h>

static NSString *const kDSPPrefsPathRootless = @"/var/jb/Library/Preferences/com.appbackup.devicespoof.plist";
static NSString *const kDSPPrefsFileName = @"com.appbackup.devicespoof.plist";
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

static const char kDSPIOSVersionUTF8[] = "26.0";
static const char kDSPSerialUTF8[] = "F3PF534FRQ7E";
static const char kDSPMLBUTF8[] = "F3PF534FRQ7EH7ABC";

static BOOL sDSPEnabled = YES;
static BOOL sSimulateFreshInstall = YES;
static NSUUID *sVendorUUID = nil;
static NSString *sInstallUUIDString = nil;
static NSString *sDeviceFingerprintHex = nil;
static char sRealMachine[32];
static char sSerial[13];
static char sMLB[20];
static char sProductUTF8[32] = "iPhone18,3";
static char sBoardUTF8[32] = "V57AP";
static NSString *sProductType = @"iPhone18,3";
static NSString *sMarketingName = @"iPhone 17";
static NSString *sRealMarketingName = nil;
static CGFloat sScreenWidth = 393;
static CGFloat sScreenHeight = 852;
static CGFloat sScreenScale = 3;

static BOOL DSPLooksLikeProductType(NSString *value) {
    return [value hasPrefix:@"iPhone"] && [value containsString:@","];
}

static void DSPApplySelectedModel(NSDictionary *plist) {
    NSString *product = plist[@"selectedProductType"];
    NSString *name = plist[@"selectedMarketingName"];
    NSString *board = plist[@"selectedHardwareModel"];
    if (!DSPLooksLikeProductType(product) || name.length == 0 || board.length == 0) {
        strlcpy(sProductUTF8, "iPhone18,3", sizeof(sProductUTF8));
        strlcpy(sBoardUTF8, "V57AP", sizeof(sBoardUTF8));
        sProductType = @"iPhone18,3";
        sMarketingName = @"iPhone 17";
        sScreenWidth = 393;
        sScreenHeight = 852;
        sScreenScale = 3;
        return;
    }
    strlcpy(sProductUTF8, product.UTF8String, sizeof(sProductUTF8));
    strlcpy(sBoardUTF8, board.UTF8String, sizeof(sBoardUTF8));
    sProductType = [product copy];
    sMarketingName = [name copy];
    double width = [plist[@"selectedScreenWidth"] doubleValue];
    double height = [plist[@"selectedScreenHeight"] doubleValue];
    double scale = [plist[@"selectedScreenScale"] doubleValue];
    sScreenWidth = width > 0 ? (CGFloat)width : 393;
    sScreenHeight = height > 0 ? (CGFloat)height : 852;
    sScreenScale = scale > 0 ? (CGFloat)scale : 3;
}

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

static NSString *DSPSandboxPrefsPath(void) {
    NSString *home = NSHomeDirectory();
    if (home.length == 0) {
        return nil;
    }
    return [home stringByAppendingPathComponent:[@"Library/Preferences" stringByAppendingPathComponent:kDSPPrefsFileName]];
}

static NSMutableDictionary *DSPLoadPlist(void) {
    NSDictionary *rootless = [NSDictionary dictionaryWithContentsOfFile:kDSPPrefsPathRootless];
    if (rootless.count > 0) {
        return [rootless mutableCopy];
    }
    NSString *sandbox = DSPSandboxPrefsPath();
    NSDictionary *local = sandbox.length ? [NSDictionary dictionaryWithContentsOfFile:sandbox] : nil;
    return local ? [local mutableCopy] : [NSMutableDictionary dictionary];
}

static void DSPSavePlist(NSDictionary *plist) {
    if (!plist) {
        return;
    }
    [plist writeToFile:kDSPPrefsPathRootless atomically:YES];
    NSString *sandbox = DSPSandboxPrefsPath();
    if (sandbox.length == 0) {
        return;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:[sandbox stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [plist writeToFile:sandbox atomically:YES];
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
    NSMutableDictionary *plist = DSPLoadPlist();

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
    DSPApplySelectedModel(plist);
    const char *serialSource = sInstallUUIDString.UTF8String;
    const char *alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    size_t sourceLength = serialSource ? strlen(serialSource) : 0;
    if (sourceLength == 0) {
        strlcpy(sSerial, "F3PF534FRQ7E", sizeof(sSerial));
    } else {
        for (int index = 0; index < 12; index++) {
            sSerial[index] = alphabet[((unsigned char)serialSource[index % sourceLength]) % 32];
        }
        sSerial[12] = '\0';
    }
    snprintf(sMLB, sizeof(sMLB), "%sH7ABC", sSerial);
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

+ (NSUUID *)spoofedAdvertisingIdentifier {
    if (!sVendorUUID) {
        return nil;
    }
    uuid_t bytes;
    [sVendorUUID getUUIDBytes:bytes];
    bytes[0] ^= 0x5A;
    bytes[15] ^= 0xA5;
    return [[NSUUID alloc] initWithUUIDBytes:bytes];
}

+ (NSString *)spoofedDeviceName {
    return @"iPhone";
}

+ (NSString *)shopeeDeviceFingerprintHex {
    return sDeviceFingerprintHex ?: @"";
}

+ (const char *)installSessionUUIDUTF8 {
    return sInstallUUIDString.UTF8String ?: "";
}

+ (const char *)productTypeUTF8 {
    return sProductUTF8;
}

+ (const char *)hardwareModelUTF8 {
    return sBoardUTF8;
}

+ (const char *)hwMachineUTF8 {
    return sProductUTF8;
}

+ (const char *)serialNumberUTF8 {
    return sSerial[0] ? sSerial : kDSPSerialUTF8;
}

+ (const char *)mlbSerialUTF8 {
    return sMLB[0] ? sMLB : kDSPMLBUTF8;
}

+ (NSString *)productType {
    return sProductType ?: @"iPhone18,3";
}

+ (NSString *)hardwareModel {
    return [NSString stringWithUTF8String:sBoardUTF8] ?: @"V57AP";
}

+ (NSString *)hwMachine {
    return sProductType ?: @"iPhone18,3";
}

+ (NSString *)marketingName {
    return sMarketingName ?: @"iPhone 17";
}

+ (NSString *)spoofedOSVersion {
    return @"26.0";
}

+ (const char *)osVersionUTF8 {
    return kDSPIOSVersionUTF8;
}

+ (CGRect)screenBounds {
    return CGRectMake(0, 0, sScreenWidth, sScreenHeight);
}

+ (CGFloat)screenScale {
    return sScreenScale;
}

+ (CGRect)nativeScreenBounds {
    return CGRectMake(0, 0, sScreenWidth * sScreenScale, sScreenHeight * sScreenScale);
}

@end
