#import "ABDeviceStore.h"

static NSString *const ABDevicePrefsPath = @"/var/jb/Library/Preferences/com.appbackup.devicespoof.plist";

@implementation ABDeviceStore

+ (NSMutableDictionary *)loadPrefs {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ABDevicePrefsPath];
    return prefs ? [prefs mutableCopy] : [NSMutableDictionary dictionary];
}

+ (BOOL)savePrefs:(NSDictionary *)prefs error:(NSError **)error {
    NSString *directory = [ABDevicePrefsPath stringByDeletingLastPathComponent];
    NSFileManager *files = [NSFileManager defaultManager];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    if (![prefs writeToURL:[NSURL fileURLWithPath:ABDevicePrefsPath] error:error]) {
        return NO;
    }
    return YES;
}

+ (BOOL)isEnabled {
    id value = [self loadPrefs][@"enabled"];
    return ![value isKindOfClass:[NSNumber class]] || [(NSNumber *)value boolValue];
}

+ (void)setEnabled:(BOOL)enabled {
    NSMutableDictionary *prefs = [self loadPrefs];
    prefs[@"enabled"] = @(enabled);
    [self savePrefs:prefs error:nil];
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
