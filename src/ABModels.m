#import "ABModels.h"

NSString *const ABErrorDomain = @"com.local.appbackup";
NSString *const ABBundleIdentifier = @"com.local.appbackup";
NSString *const ABToolVersion = @"1.0.0";
NSString *const ABMetadataFileName = @".com.apple.mobile_container_manager.metadata.plist";
NSString *const ABExcludeCachesKey = @"excludeCaches";
NSString *const ABIncludeGroupsKey = @"includeGroups";

NSError *ABMakeError(ABErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ABErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"未知错误"}];
}

NSString *ABFormatBytes(uint64_t bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

NSString *ABFormatDate(NSDate *date) {
    if (!date) {
        return @"";
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

@implementation ABBackupOptions

+ (void)initialize {
    if (self != [ABBackupOptions class]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        ABExcludeCachesKey: @YES,
        ABIncludeGroupsKey: @YES
    }];
}

+ (ABBackupOptions *)currentOptions {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    ABBackupOptions *options = [ABBackupOptions new];
    options.excludesCaches = [defaults boolForKey:ABExcludeCachesKey];
    options.includesAppGroups = [defaults boolForKey:ABIncludeGroupsKey];
    return options;
}

@end

@implementation ABAppInfo
@end

@implementation ABBackupInfo

- (NSString *)preferredTitle {
    if (self.customName.length > 0) {
        return self.customName;
    }
    if (self.displayName.length > 0) {
        return self.displayName;
    }
    return self.bundleIdentifier.length > 0 ? self.bundleIdentifier : @"备份";
}

- (NSString *)summaryText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *created = ABFormatDate(self.createdAt);
    if (created.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"备份于 %@", created]];
    }
    NSString *used = ABFormatDate(self.lastUsedAt);
    if (used.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"上次使用 %@", used]];
    } else {
        [parts addObject:@"尚未使用"];
    }
    if (self.shortVersion.length > 0) {
        [parts addObject:self.shortVersion];
    }
    if (self.fileSize > 0) {
        [parts addObject:ABFormatBytes(self.fileSize)];
    }
    return [parts componentsJoinedByString:@" · "];
}

@end

@implementation ABFileItem
@end
