#import "ABDeviceStore.h"
#import "ABAppLibrary.h"

static NSString *const ABDevicePrefsName = @"com.appbackup.devicespoof.plist";
static NSString *const ABShopeeBundleIdentifier = @"com.beeasy.shopee.tw";

@implementation ABDeviceStore

+ (NSArray<NSString *> *)candidatePaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    ABAppLibrary *library = [ABAppLibrary sharedLibrary];
    [library reload];
    NSURL *container = [library locationForBundleIdentifier:ABShopeeBundleIdentifier].dataContainerURL;
    if (container.path.length) {
        [paths addObject:[container.path stringByAppendingPathComponent:[@"Library/Preferences" stringByAppendingPathComponent:ABDevicePrefsName]]];
    }
    [paths addObjectsFromArray:@[
        [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:ABDevicePrefsName],
        [@"/private/var/mobile/Library/Preferences" stringByAppendingPathComponent:ABDevicePrefsName],
        [@"/var/jb/var/mobile/Library/Preferences" stringByAppendingPathComponent:ABDevicePrefsName],
        [@"/var/jb/Library/Preferences" stringByAppendingPathComponent:ABDevicePrefsName],
    ]];
    return paths;
}

+ (NSMutableDictionary *)loadPrefs {
    NSMutableDictionary *fallback = nil;
    for (NSString *path in [self candidatePaths]) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (prefs.count == 0) {
            continue;
        }
        NSString *selected = prefs[@"selectedProductType"];
        if ([selected isKindOfClass:[NSString class]] && selected.length > 0) {
            return [prefs mutableCopy];
        }
        if (!fallback) {
            fallback = [prefs mutableCopy];
        }
    }
    return fallback ?: [NSMutableDictionary dictionary];
}

+ (BOOL)writePrefs:(NSDictionary *)prefs toPath:(NSString *)path error:(NSError **)error {
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSFileManager *files = [NSFileManager defaultManager];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    return [prefs writeToURL:[NSURL fileURLWithPath:path] error:error];
}

+ (BOOL)savePrefs:(NSDictionary *)prefs error:(NSError **)error {
    NSError *lastError = nil;
    BOOL saved = NO;
    for (NSString *path in [self candidatePaths]) {
        NSError *writeError = nil;
        if ([self writePrefs:prefs toPath:path error:&writeError]) {
            saved = YES;
        } else {
            lastError = writeError;
        }
    }
    if (!saved && error) {
        *error = lastError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:@{NSLocalizedDescriptionKey : @"没有可写的配置目录。请用 TrollStore 安装应用备份。"}];
    }
    return saved;
}

+ (BOOL)isEnabled {
    id value = [self loadPrefs][@"enabled"];
    return ![value isKindOfClass:[NSNumber class]] || [(NSNumber *)value boolValue];
}

+ (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    NSMutableDictionary *prefs = [self loadPrefs];
    prefs[@"enabled"] = @(enabled);
    return [self savePrefs:prefs error:error];
}

+ (ABDeviceModel *)selectedModel {
    NSString *identifier = [self loadPrefs][@"selectedProductType"];
    if (identifier.length == 0) {
        return [ABDeviceCatalog defaultModel];
    }
    return [ABDeviceCatalog modelForIdentifier:identifier];
}

+ (BOOL)selectModel:(ABDeviceModel *)model error:(NSError **)error {
    if (!model) {
        return NO;
    }
    NSMutableDictionary *prefs = [self loadPrefs];
    prefs[@"selectedProductType"] = model.identifier;
    prefs[@"selectedMarketingName"] = model.name;
    prefs[@"selectedHardwareModel"] = model.board;
    prefs[@"selectedScreenWidth"] = @(model.width);
    prefs[@"selectedScreenHeight"] = @(model.height);
    prefs[@"selectedScreenScale"] = @(model.scale);
    if (!prefs[@"enabled"]) {
        prefs[@"enabled"] = @YES;
    }
    return [self savePrefs:prefs error:error];
}

+ (BOOL)requestFreshIdentity:(NSError **)error {
    NSMutableDictionary *prefs = [self loadPrefs];
    prefs[@"regenerateFreshInstall"] = @YES;
    prefs[@"simulateFreshInstall"] = @YES;
    return [self savePrefs:prefs error:error];
}

@end
