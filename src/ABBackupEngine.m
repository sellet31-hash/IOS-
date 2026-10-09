#import "ABBackupEngine.h"
#import "ABAppLibrary.h"
#import "ABTarArchive.h"
#import <dirent.h>
#import <dlfcn.h>
#import <errno.h>
#import <grp.h>
#import <objc/message.h>
#import <pwd.h>
#import <signal.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

static const uint64_t ABSpaceMargin = 64ull * 1024ull * 1024ull;

@interface ABBackupEngine ()
@property (atomic) BOOL cancelled;
@property (atomic) BOOL busy;
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic) CFAbsoluteTime lastProgressTime;
@end

@implementation ABBackupEngine

+ (instancetype)sharedEngine {
    static ABBackupEngine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [ABBackupEngine new];
    });
    return engine;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateLock = [NSLock new];
        _workQueue = dispatch_queue_create("com.local.appbackup.engine", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)cancel {
    self.cancelled = YES;
}

- (BOOL)beginOperation:(NSError **)error {
    [self.stateLock lock];
    if (self.busy) {
        [self.stateLock unlock];
        if (error) {
            *error = ABMakeError(ABErrorBusy, @"已有一项备份或恢复在进行");
        }
        return NO;
    }
    self.busy = YES;
    self.cancelled = NO;
    self.lastProgressTime = 0;
    [self.stateLock unlock];
    return YES;
}

- (void)endOperation {
    [self.stateLock lock];
    self.busy = NO;
    self.cancelled = NO;
    [self.stateLock unlock];
}

- (void)report:(ABProgressBlock)progress
       message:(NSString *)message
          done:(uint64_t)done
         total:(uint64_t)total
         force:(BOOL)force {
    if (!progress) {
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!force && now - self.lastProgressTime < 0.1) {
        return;
    }
    self.lastProgressTime = now;
    double fraction = 0;
    if (total > 0) {
        fraction = (double)done / (double)total;
        if (fraction < 0) {
            fraction = 0;
        } else if (fraction > 1) {
            fraction = 1;
        }
    }
    NSString *text = [message copy] ?: @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(text, fraction, done, total);
    });
}

+ (NSURL *)backupDirectoryURL:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *documents = [manager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if (!documents) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"无法访问本应用的文档目录");
        }
        return nil;
    }
    NSURL *directory = [documents URLByAppendingPathComponent:@"Backups" isDirectory:YES];
    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    return directory;
}

+ (NSURL *)metadataURLForArchive:(NSURL *)archive {
    return [NSURL fileURLWithPath:[archive.path stringByAppendingString:@".meta"]];
}

+ (NSDictionary *)metadataForArchive:(NSURL *)archive {
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfURL:[self metadataURLForArchive:archive]];
    return [metadata isKindOfClass:[NSDictionary class]] ? metadata : @{};
}

+ (NSDate *)dateFromMetadata:(id)value {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
        return nil;
    }
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:value];
}

+ (BOOL)writeMetadataForArchive:(NSURL *)archive customName:(NSString *)customName lastUsedAt:(NSDate *)lastUsedAt error:(NSError **)error {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    if (customName.length > 0) {
        metadata[@"customName"] = customName;
    }
    if (lastUsedAt) {
        NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        NSString *stamp = [formatter stringFromDate:lastUsedAt];
        if (stamp.length > 0) {
            metadata[@"lastUsedAt"] = stamp;
        }
    }
    NSURL *metadataURL = [self metadataURLForArchive:archive];
    if (metadata.count == 0) {
        [[NSFileManager defaultManager] removeItemAtURL:metadataURL error:nil];
        return YES;
    }
    if (![metadata writeToURL:metadataURL error:error]) {
        return NO;
    }
    return YES;
}

+ (BOOL)renameBackupAtURL:(NSURL *)fileURL name:(NSString *)name error:(NSError **)error {
    if (!fileURL) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"找不到这份备份");
        }
        return NO;
    }
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (trimmed.length > 60) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"名称最多 60 个字");
        }
        return NO;
    }
    if ([trimmed rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:"]].location != NSNotFound) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"名称里不能包含 / \\ :");
        }
        return NO;
    }
    NSDictionary *metadata = [self metadataForArchive:fileURL];
    return [self writeMetadataForArchive:fileURL customName:trimmed lastUsedAt:[self dateFromMetadata:metadata[@"lastUsedAt"]] error:error];
}

+ (void)markBackupUsedAtURL:(NSURL *)fileURL {
    if (!fileURL) {
        return;
    }
    NSDictionary *metadata = [self metadataForArchive:fileURL];
    NSString *customName = [metadata[@"customName"] isKindOfClass:[NSString class]] ? metadata[@"customName"] : @"";
    [self writeMetadataForArchive:fileURL customName:customName lastUsedAt:[NSDate date] error:nil];
}

+ (void)deleteBackupAtURL:(NSURL *)fileURL {
    if (!fileURL) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:fileURL error:nil];
    [manager removeItemAtURL:[self metadataURLForArchive:fileURL] error:nil];
}

+ (NSArray<ABBackupInfo *> *)allBackupsWithUnreadableCount:(NSUInteger *)unreadable error:(NSError **)error {
    NSURL *directory = [self backupDirectoryURL:error];
    if (!directory) {
        return nil;
    }
    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey] options:0 error:error];
    if (!files) {
        return nil;
    }
    NSMutableArray<ABBackupInfo *> *backups = [NSMutableArray array];
    NSUInteger failed = 0;
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    for (NSURL *file in files) {
        if (![file.pathExtension isEqualToString:@"abackup"]) {
            continue;
        }
        NSDictionary *manifest = nil;
        NSError *readError = nil;
        if (![ABTarArchive summarizeArchiveAtURL:file manifest:&manifest uncompressedBytes:NULL error:&readError]) {
            failed++;
            continue;
        }
        NSString *bundleID = [manifest[@"bundleIdentifier"] isKindOfClass:[NSString class]] ? manifest[@"bundleIdentifier"] : @"";
        if (bundleID.length == 0) {
            failed++;
            continue;
        }
        ABBackupInfo *info = [ABBackupInfo new];
        info.fileURL = file;
        info.bundleIdentifier = bundleID;
        info.displayName = [manifest[@"displayName"] isKindOfClass:[NSString class]] && [manifest[@"displayName"] length] > 0 ? manifest[@"displayName"] : bundleID;
        info.shortVersion = [manifest[@"shortVersion"] isKindOfClass:[NSString class]] ? manifest[@"shortVersion"] : @"";
        NSDictionary *metadata = [self metadataForArchive:file];
        info.customName = [metadata[@"customName"] isKindOfClass:[NSString class]] ? metadata[@"customName"] : @"";
        info.lastUsedAt = [self dateFromMetadata:metadata[@"lastUsedAt"]];
        NSString *created = [manifest[@"createdAt"] isKindOfClass:[NSString class]] ? manifest[@"createdAt"] : nil;
        info.createdAt = created ? [iso dateFromString:created] : nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:nil];
        info.fileSize = [attributes[NSFileSize] unsignedLongLongValue];
        if (!info.createdAt) {
            info.createdAt = attributes[NSFileModificationDate];
        }
        [backups addObject:info];
    }
    [backups sortUsingComparator:^NSComparisonResult(ABBackupInfo *lhs, ABBackupInfo *rhs) {
        return [rhs.createdAt ?: [NSDate distantPast] compare:lhs.createdAt ?: [NSDate distantPast]];
    }];
    if (unreadable) {
        *unreadable = failed;
    }
    return backups;
}

static NSString *ABChildPath(NSString *root, NSString *path) {
    if (root.length == 0 || path.length == 0) {
        return nil;
    }
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObject:root];
    if ([root hasPrefix:@"/private/"]) {
        [candidates addObject:[root substringFromIndex:8]];
    } else {
        [candidates addObject:[@"/private" stringByAppendingString:root]];
    }
    for (NSString *candidate in candidates) {
        if ([path isEqualToString:candidate]) {
            return @"";
        }
        NSString *prefix = [candidate hasSuffix:@"/"] ? candidate : [candidate stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) {
            return [path substringFromIndex:prefix.length];
        }
    }
    return nil;
}

static BOOL ABSkipped(NSString *relative, BOOL excludeCaches) {
    if (relative.length == 0 || [relative isEqualToString:ABMetadataFileName]) {
        return YES;
    }
    if ([relative isEqualToString:@"tmp"] || [relative hasPrefix:@"tmp/"]) {
        return YES;
    }
    if ([relative hasPrefix:@".ab-stash-"] || [relative hasPrefix:@".ab-old-"] || [relative containsString:@"/.ab-stash-"] || [relative containsString:@"/.ab-old-"]) {
        return YES;
    }
    if (!excludeCaches) {
        return NO;
    }
    return [relative isEqualToString:@"Library/Caches"] || [relative hasPrefix:@"Library/Caches/"] || [relative isEqualToString:@"Library/SplashBoard"] || [relative hasPrefix:@"Library/SplashBoard/"];
}

static NSString *ABReadLink(NSString *path, NSError **error) {
    NSMutableData *buffer = [NSMutableData dataWithLength:256];
    const char *filePath = path.fileSystemRepresentation;
    while (1) {
        ssize_t length = readlink(filePath, buffer.mutableBytes, buffer.length);
        if (length < 0) {
            if (error) {
                *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"无法读取符号链接 %@", path.lastPathComponent]);
            }
            return nil;
        }
        if ((NSUInteger)length < buffer.length) {
            NSString *target = [[NSString alloc] initWithBytes:buffer.bytes length:(NSUInteger)length encoding:NSUTF8StringEncoding];
            if (!target) {
                if (error) {
                    *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"符号链接不是文本：%@", path.lastPathComponent]);
                }
                return nil;
            }
            return target;
        }
        if (buffer.length >= 16384) {
            if (error) {
                *error = ABMakeError(ABErrorFailed, @"符号链接过长");
            }
            return nil;
        }
        buffer.length *= 2;
    }
}

static BOOL ABSafeGroupIdentifier(NSString *groupID) {
    if (groupID.length == 0 || groupID.length > 180 || [groupID containsString:@".."]) {
        return NO;
    }
    return [groupID rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:"]].location == NSNotFound;
}

static void ABTerminateApplication(NSString *bundleID) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
    });
    Class serviceClass = NSClassFromString(@"FBSSystemService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return;
    }
    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
    SEL selector = @selector(terminateApplication:forReason:andReport:withDescription:);
    if (![service respondsToSelector:selector]) {
        return;
    }
    typedef void (*ABTerminateFunction)(id, SEL, NSString *, int, BOOL, NSString *);
    ABTerminateFunction function = (ABTerminateFunction)objc_msgSend;
    function(service, selector, bundleID, 1, NO, @"AppBackup");
}

static BOOL ABPathMatchesBundle(NSString *processPath, NSString *bundlePath) {
    if (processPath.length == 0 || bundlePath.length == 0 || ![bundlePath containsString:@".app"]) {
        return NO;
    }
    NSString *alternate = nil;
    if ([bundlePath hasPrefix:@"/private/"]) {
        alternate = [bundlePath substringFromIndex:8];
    } else {
        alternate = [@"/private" stringByAppendingString:bundlePath];
    }
    return [processPath hasPrefix:bundlePath] || [processPath hasPrefix:alternate];
}

static void ABKillProcessesForBundle(NSURL *bundleURL) {
    NSString *bundlePath = bundleURL.path;
    if (!ABPathMatchesBundle(bundlePath, bundlePath)) {
        return;
    }
    int name[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    size_t size = 0;
    if (sysctl(name, 3, NULL, &size, NULL, 0) != 0 || size == 0) {
        return;
    }
    struct kinfo_proc *processes = malloc(size);
    if (!processes) {
        return;
    }
    if (sysctl(name, 3, processes, &size, NULL, 0) != 0) {
        free(processes);
        return;
    }
    int count = (int)(size / sizeof(struct kinfo_proc));
    pid_t selfPid = getpid();
    NSMutableArray<NSNumber *> *pids = [NSMutableArray array];
    for (int index = 0; index < count; index++) {
        pid_t pid = processes[index].kp_proc.p_pid;
        if (pid <= 1 || pid == selfPid) {
            continue;
        }
        char path[4096];
        if (proc_pidpath(pid, path, sizeof(path)) <= 0) {
            continue;
        }
        NSString *processPath = [NSString stringWithUTF8String:path];
        if (ABPathMatchesBundle(processPath, bundlePath)) {
            [pids addObject:@(pid)];
        }
    }
    free(processes);
    for (NSNumber *pid in pids) {
        kill(pid.intValue, SIGTERM);
    }
    if (pids.count > 0) {
        [NSThread sleepForTimeInterval:0.4];
    }
    for (NSNumber *pid in pids) {
        kill(pid.intValue, SIGKILL);
    }
}

static void ABStopApplication(NSString *bundleID, NSURL *bundleURL) {
    ABTerminateApplication(bundleID);
    ABKillProcessesForBundle(bundleURL);
    [NSThread sleepForTimeInterval:0.4];
}

static void ABRepairOwnership(NSString *root) {
    if (root.length == 0) {
        return;
    }
    uid_t uid = 501;
    gid_t gid = 501;
    struct passwd *user = getpwnam("mobile");
    struct group *group = getgrnam("mobile");
    if (user) {
        uid = user->pw_uid;
    }
    if (group) {
        gid = group->gr_gid;
    }
    NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0) {
        NSString *path = pending.lastObject;
        [pending removeLastObject];
        const char *filePath = path.fileSystemRepresentation;
        struct stat info;
        if (lstat(filePath, &info) != 0) {
            continue;
        }
        lchown(filePath, uid, gid);
        if (S_ISLNK(info.st_mode)) {
            continue;
        }
        if (S_ISDIR(info.st_mode)) {
            if ((info.st_mode & 0700) != 0700) {
                chmod(filePath, 0755);
            }
            DIR *directory = opendir(filePath);
            if (!directory) {
                continue;
            }
            struct dirent *entry = NULL;
            while ((entry = readdir(directory)) != NULL) {
                if (entry->d_name[0] == '.' && (entry->d_name[1] == '\0' || (entry->d_name[1] == '.' && entry->d_name[2] == '\0'))) {
                    continue;
                }
                NSString *name = [NSString stringWithUTF8String:entry->d_name];
                if (name.length == 0) {
                    continue;
                }
                [pending addObject:[path stringByAppendingPathComponent:name]];
            }
            closedir(directory);
        } else if (S_ISREG(info.st_mode) && (info.st_mode & 0600) != 0600) {
            chmod(filePath, 0644);
        }
    }
}

static void ABRepairDataContainer(NSString *root) {
    if (root.length == 0) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *relative in @[@"Documents", @"Library", @"Library/Caches", @"Library/Preferences", @"tmp"]) {
        [manager createDirectoryAtPath:[root stringByAppendingPathComponent:relative] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    ABRepairOwnership(root);
}

static uint64_t ABFreeBytes(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:path error:nil];
    return [attributes[NSFileSystemFreeSize] unsignedLongLongValue];
}

- (BOOL)collectDirectory:(NSURL *)directory
              archiveRoot:(NSString *)archiveRoot
           excludeCaches:(BOOL)excludeCaches
                   items:(NSMutableArray<ABFileItem *> *)items
              totalBytes:(uint64_t *)totalBytes
               fileCount:(NSUInteger *)fileCount
              shouldStop:(BOOL (^)(void))shouldStop
                progress:(void (^)(NSString *relativePath))progress
                   error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:directory.path isDirectory:&isDirectory] || !isDirectory) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"数据目录不存在");
        }
        return NO;
    }
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:directory includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url, NSError *enumError) {
        return YES;
    }];
    if (!enumerator) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"无法遍历数据目录");
        }
        return NO;
    }
    for (NSURL *url in enumerator) {
        @autoreleasepool {
            if (shouldStop && shouldStop()) {
                if (error) {
                    *error = ABMakeError(ABErrorCancelled, @"已取消");
                }
                return NO;
            }
            NSString *relative = ABChildPath(directory.path, url.path);
            if (relative.length == 0) {
                continue;
            }
            if (ABSkipped(relative, excludeCaches)) {
                [enumerator skipDescendants];
                continue;
            }
            struct stat info;
            if (lstat(url.fileSystemRepresentation, &info) != 0) {
                if (error) {
                    NSString *message = (errno == EACCES || errno == EPERM) ? @"有文件无法读取。请解锁手机，并让屏幕保持打开后再试。" : [NSString stringWithFormat:@"无法读取 %@", relative];
                    *error = ABMakeError(ABErrorAccess, message);
                }
                return NO;
            }
            ABFileItem *item = [ABFileItem new];
            item.relativePath = relative;
            item.archivePath = [archiveRoot stringByAppendingPathComponent:relative];
            item.sourcePath = url.path;
            item.mode = (uint32_t)(info.st_mode & 0777);
            item.mtime = (int64_t)info.st_mtime;
            if (S_ISLNK(info.st_mode)) {
                NSString *target = ABReadLink(url.path, error);
                if (!target) {
                    return NO;
                }
                item.symlink = YES;
                item.linkTarget = target;
                [enumerator skipDescendants];
            } else if (S_ISDIR(info.st_mode)) {
                item.directory = YES;
            } else if (S_ISREG(info.st_mode)) {
                item.fileSize = (uint64_t)info.st_size;
                if (totalBytes) {
                    *totalBytes += item.fileSize;
                }
            } else {
                continue;
            }
            if (items) {
                [items addObject:item];
            }
            if (fileCount) {
                *fileCount += 1;
                if (progress && (*fileCount % 250) == 0) {
                    progress(relative);
                }
            }
        }
    }
    return YES;
}

- (BOOL)calculateSizeForApp:(ABAppInfo *)app options:(ABBackupOptions *)options bytes:(uint64_t *)bytes error:(NSError **)error {
    if ([app.bundleIdentifier isEqualToString:ABBundleIdentifier]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"不能统计本应用");
        }
        return NO;
    }
    ABContainerLocation *location = [[ABAppLibrary sharedLibrary] locationForBundleIdentifier:app.bundleIdentifier];
    NSURL *container = location.dataContainerURL ?: app.dataContainerURL;
    if (!container) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"没有数据目录");
        }
        return NO;
    }
    uint64_t total = 0;
    NSUInteger count = 0;
    if (![self collectDirectory:container archiveRoot:@"container" excludeCaches:options.excludesCaches items:nil totalBytes:&total fileCount:&count shouldStop:nil progress:nil error:error]) {
        return NO;
    }
    if (options.includesAppGroups) {
        for (NSString *groupID in location.groupContainers) {
            if (!ABSafeGroupIdentifier(groupID)) {
                continue;
            }
            NSURL *groupURL = location.groupContainers[groupID];
            if (![self collectDirectory:groupURL archiveRoot:[@"groups" stringByAppendingPathComponent:groupID] excludeCaches:options.excludesCaches items:nil totalBytes:&total fileCount:&count shouldStop:nil progress:nil error:error]) {
                return NO;
            }
        }
    }
    if (bytes) {
        *bytes = total;
    }
    return YES;
}

- (NSURL *)archiveURLForApp:(ABAppInfo *)app directory:(NSURL *)directory {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *base = [NSString stringWithFormat:@"%@_%@", app.bundleIdentifier, [formatter stringFromDate:[NSDate date]]];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *url = [directory URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"abackup"]];
    NSInteger suffix = 2;
    while ([manager fileExistsAtPath:url.path]) {
        NSString *name = [NSString stringWithFormat:@"%@-%ld", base, (long)suffix];
        url = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"abackup"]];
        suffix++;
    }
    return url;
}

- (NSURL *)performBackupForApp:(ABAppInfo *)app options:(ABBackupOptions *)options progress:(ABProgressBlock)progress error:(NSError **)error {
    if ([app.bundleIdentifier isEqualToString:ABBundleIdentifier]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"不能备份「应用备份」自己");
        }
        return nil;
    }
    BOOL (^stopped)(void) = ^{
        return self.cancelled;
    };
    [self report:progress message:@"正在定位数据目录" done:0 total:0 force:YES];
    ABContainerLocation *location = [[ABAppLibrary sharedLibrary] locationForBundleIdentifier:app.bundleIdentifier];
    NSURL *container = location.dataContainerURL ?: app.dataContainerURL;
    if (!container) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"这个应用还没有数据目录，请先打开一次");
        }
        return nil;
    }
    [self report:progress message:@"正在退出应用" done:0 total:0 force:YES];
    ABStopApplication(app.bundleIdentifier, location.bundleURL ?: app.bundleURL);
    NSMutableArray<ABFileItem *> *items = [NSMutableArray array];
    NSMutableArray<NSString *> *groupIDs = [NSMutableArray array];
    uint64_t total = 0;
    NSUInteger count = 0;
    BOOL collected = [self collectDirectory:container archiveRoot:@"container" excludeCaches:options.excludesCaches items:items totalBytes:&total fileCount:&count shouldStop:stopped progress:^(NSString *relativePath) {
        [self report:progress message:[NSString stringWithFormat:@"正在统计 %@", relativePath] done:0 total:0 force:NO];
    } error:error];
    if (!collected) {
        return nil;
    }
    if (options.includesAppGroups) {
        for (NSString *groupID in location.groupContainers) {
            if (stopped()) {
                if (error) {
                    *error = ABMakeError(ABErrorCancelled, @"已取消");
                }
                return nil;
            }
            if (!ABSafeGroupIdentifier(groupID)) {
                continue;
            }
            NSURL *groupURL = location.groupContainers[groupID];
            NSUInteger before = items.count;
            if (![self collectDirectory:groupURL archiveRoot:[@"groups" stringByAppendingPathComponent:groupID] excludeCaches:options.excludesCaches items:items totalBytes:&total fileCount:&count shouldStop:stopped progress:^(NSString *relativePath) {
                [self report:progress message:[NSString stringWithFormat:@"正在统计 %@", relativePath] done:0 total:0 force:NO];
            } error:error]) {
                return nil;
            }
            if (items.count > before) {
                [groupIDs addObject:groupID];
            }
        }
    }
    NSError *directoryError = nil;
    NSURL *directory = [ABBackupEngine backupDirectoryURL:&directoryError];
    if (!directory) {
        if (error) {
            *error = directoryError;
        }
        return nil;
    }
    uint64_t overhead = (uint64_t)(items.count + 8) * 1024ull;
    if (total > UINT64_MAX - overhead - ABSpaceMargin || ABFreeBytes(directory.path) < total + overhead + ABSpaceMargin) {
        if (error) {
            *error = ABMakeError(ABErrorSpace, [NSString stringWithFormat:@"可用空间不足，这份备份大约需要 %@", ABFormatBytes(total + overhead)]);
        }
        return nil;
    }
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    NSDictionary *manifest = @{
        @"formatVersion": @1,
        @"bundleIdentifier": app.bundleIdentifier ?: @"",
        @"displayName": location.displayName.length ? location.displayName : (app.displayName ?: @""),
        @"shortVersion": location.shortVersion.length ? location.shortVersion : (app.shortVersion ?: @""),
        @"bundleVersion": location.bundleVersion.length ? location.bundleVersion : (app.bundleVersion ?: @""),
        @"createdAt": [iso stringFromDate:[NSDate date]] ?: @"",
        @"excludesCaches": @(options.excludesCaches),
        @"includesAppGroups": @(options.includesAppGroups),
        @"groups": groupIDs,
        @"tool": @"AppBackup",
        @"toolVersion": ABToolVersion
    };
    NSString *manifestPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", [NSUUID UUID].UUIDString]];
    NSURL *destination = [self archiveURLForApp:app directory:directory];
    if (![manifest writeToFile:manifestPath atomically:YES]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"无法写入备份清单");
        }
        return nil;
    }
    [self report:progress message:@"正在打包" done:0 total:MAX(total, 1) force:YES];
    NSError *writeError = nil;
    BOOL wrote = [ABTarArchive writeManifestAtPath:manifestPath items:items toURL:destination onProgress:^(NSString *path, uint64_t bytesWritten) {
        [self report:progress message:path.length ? path : @"正在打包" done:bytesWritten total:MAX(total, 1) force:NO];
    } shouldStop:stopped error:&writeError];
    [[NSFileManager defaultManager] removeItemAtPath:manifestPath error:nil];
    if (!wrote) {
        [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
        if (error) {
            *error = writeError ?: ABMakeError(ABErrorFailed, @"打包失败");
        }
        return nil;
    }
    [self report:progress message:@"备份完成" done:total total:MAX(total, 1) force:YES];
    return destination;
}

- (BOOL)replaceChildrenOfDirectory:(NSURL *)live
                     withDirectory:(NSURL *)extracted
                             error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSURL *> *liveChildren = [manager contentsOfDirectoryAtURL:live includingPropertiesForKeys:nil options:0 error:error];
    if (!liveChildren) {
        return NO;
    }
    NSArray<NSURL *> *newChildren = [manager contentsOfDirectoryAtURL:extracted includingPropertiesForKeys:nil options:0 error:error];
    if (!newChildren) {
        return NO;
    }
    NSURL *stash = [live URLByAppendingPathComponent:[NSString stringWithFormat:@".ab-stash-%@", [NSUUID UUID].UUIDString] isDirectory:YES];
    if (![manager createDirectoryAtURL:stash withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSMutableArray<NSString *> *stashed = [NSMutableArray array];
    NSMutableArray<NSString *> *moved = [NSMutableArray array];
    NSError *localError = nil;
    BOOL ok = YES;
    for (NSURL *child in liveChildren) {
        NSString *name = child.lastPathComponent;
        if ([name isEqualToString:ABMetadataFileName]) {
            continue;
        }
        if (![manager moveItemAtURL:child toURL:[stash URLByAppendingPathComponent:name] error:&localError]) {
            ok = NO;
            break;
        }
        [stashed addObject:name];
    }
    if (ok) {
        for (NSURL *child in newChildren) {
            NSString *name = child.lastPathComponent;
            if ([name isEqualToString:ABMetadataFileName] || [name hasPrefix:@".ab-"]) {
                continue;
            }
            NSURL *target = [live URLByAppendingPathComponent:name];
            if ([manager moveItemAtURL:child toURL:target error:&localError]) {
                [moved addObject:name];
                continue;
            }
            NSError *copyError = nil;
            if ([manager copyItemAtURL:child toURL:target error:&copyError]) {
                [moved addObject:name];
                continue;
            }
            localError = copyError;
            ok = NO;
            break;
        }
    }
    if (!ok) {
        for (NSString *name in moved) {
            [manager removeItemAtURL:[live URLByAppendingPathComponent:name] error:nil];
        }
        for (NSString *name in stashed) {
            [manager moveItemAtURL:[stash URLByAppendingPathComponent:name] toURL:[live URLByAppendingPathComponent:name] error:nil];
        }
        [manager removeItemAtURL:stash error:nil];
        if (error) {
            *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"写回失败：%@。如果数据不完整，请查看数据目录里的 .ab-stash- 文件夹。", localError.localizedDescription ?: @"未知原因"]);
        }
        return NO;
    }
    [manager removeItemAtURL:stash error:nil];
    return YES;
}

- (BOOL)performRestoreAtURL:(NSURL *)archiveURL
         bundleIdentifier:(NSString *)bundleIdentifier
                 warnings:(NSMutableArray<NSString *> *)warnings
                 progress:(ABProgressBlock)progress
                    error:(NSError **)error {
    BOOL (^stopped)(void) = ^{
        return self.cancelled;
    };
    [self report:progress message:@"正在检查备份" done:0 total:0 force:YES];
    NSDictionary *manifest = nil;
    uint64_t uncompressed = 0;
    if (![ABTarArchive summarizeArchiveAtURL:archiveURL manifest:&manifest uncompressedBytes:&uncompressed error:error]) {
        return NO;
    }
    NSNumber *format = manifest[@"formatVersion"];
    if (![format isKindOfClass:[NSNumber class]] || format.integerValue != 1) {
        if (error) {
            *error = ABMakeError(ABErrorFormat, @"这份备份的版本无法识别");
        }
        return NO;
    }
    NSString *archivedID = [manifest[@"bundleIdentifier"] isKindOfClass:[NSString class]] ? manifest[@"bundleIdentifier"] : @"";
    if (![archivedID isEqualToString:bundleIdentifier]) {
        if (error) {
            *error = ABMakeError(ABErrorFormat, @"这份备份不属于这个应用");
        }
        return NO;
    }
    if (![[ABAppLibrary sharedLibrary] canReadOtherApps]) {
        if (error) {
            *error = ABMakeError(ABErrorAccess, @"无法写入其他应用的数据。请用 TrollStore 安装本应用。");
        }
        return NO;
    }
    ABContainerLocation *location = [[ABAppLibrary sharedLibrary] locationForBundleIdentifier:bundleIdentifier];
    if (!location.dataContainerURL) {
        if (error) {
            *error = ABMakeError(ABErrorNotInstalled, @"请先安装这个应用，打开一次，再恢复数据");
        }
        return NO;
    }
    if (uncompressed > UINT64_MAX - ABSpaceMargin || ABFreeBytes(NSTemporaryDirectory()) < uncompressed + ABSpaceMargin) {
        if (error) {
            *error = ABMakeError(ABErrorSpace, [NSString stringWithFormat:@"可用空间不足，恢复大约还需要 %@", ABFormatBytes(uncompressed)]);
        }
        return NO;
    }
    NSURL *temp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ab-restore-%@", [NSUUID UUID].UUIDString]] isDirectory:YES];
    [self report:progress message:@"正在解压" done:0 total:MAX(uncompressed, 1) force:YES];
    BOOL extracted = [ABTarArchive extractArchiveAtURL:archiveURL toURL:temp onProgress:^(NSString *path, uint64_t bytesWritten) {
        [self report:progress message:path.length ? path : @"正在解压" done:bytesWritten total:MAX(uncompressed, 1) force:NO];
    } shouldStop:stopped error:error];
    if (!extracted) {
        [[NSFileManager defaultManager] removeItemAtURL:temp error:nil];
        return NO;
    }
    if (stopped()) {
        [[NSFileManager defaultManager] removeItemAtURL:temp error:nil];
        if (error) {
            *error = ABMakeError(ABErrorCancelled, @"已取消");
        }
        return NO;
    }
    [self report:progress message:@"正在退出应用" done:uncompressed total:MAX(uncompressed, 1) force:YES];
    ABStopApplication(bundleIdentifier, location.bundleURL);
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *extractedContainer = [temp URLByAppendingPathComponent:@"container" isDirectory:YES];
    BOOL isDirectory = NO;
    BOOL restoredContainer = NO;
    if ([manager fileExistsAtPath:extractedContainer.path isDirectory:&isDirectory] && isDirectory) {
        [self report:progress message:@"正在写回数据" done:uncompressed total:MAX(uncompressed, 1) force:YES];
        if (![self replaceChildrenOfDirectory:location.dataContainerURL withDirectory:extractedContainer error:error]) {
            [manager removeItemAtURL:temp error:nil];
            return NO;
        }
        restoredContainer = YES;
    }
    NSURL *groupsRoot = [temp URLByAppendingPathComponent:@"groups" isDirectory:YES];
    if ([manager fileExistsAtPath:groupsRoot.path isDirectory:&isDirectory] && isDirectory) {
        NSArray<NSURL *> *groupDirs = [manager contentsOfDirectoryAtURL:groupsRoot includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *groupDir in groupDirs) {
            NSString *groupID = groupDir.lastPathComponent;
            NSURL *liveGroup = location.groupContainers[groupID];
            if (!liveGroup) {
                [warnings addObject:[NSString stringWithFormat:@"找不到 App Group：%@。主数据仍会恢复。", groupID]];
                continue;
            }
            NSError *groupError = nil;
            if (![self replaceChildrenOfDirectory:liveGroup withDirectory:groupDir error:&groupError]) {
                [warnings addObject:[NSString stringWithFormat:@"App Group %@ 没有完整写回：%@", groupID, groupError.localizedDescription ?: @"未知原因"]];
                continue;
            }
            [self report:progress message:@"正在修正权限" done:uncompressed total:MAX(uncompressed, 1) force:YES];
            ABRepairOwnership(liveGroup.path);
        }
    }
    if (restoredContainer) {
        [self report:progress message:@"正在修正权限" done:uncompressed total:MAX(uncompressed, 1) force:YES];
        ABRepairDataContainer(location.dataContainerURL.path);
    }
    [manager removeItemAtURL:temp error:nil];
    [self report:progress message:@"恢复完成" done:uncompressed total:MAX(uncompressed, 1) force:YES];
    return YES;
}

static BOOL ABKeyLooksLikeIdentity(NSString *key) {
    NSString *lower = key.lowercaseString;
    NSArray<NSString *> *needles = @[
        @"device", @"uuid", @"guid", @"fingerprint", @"installid", @"install_id", @"idfv", @"idfa",
        @"advert", @"visitor", @"clientid", @"client_id", @"machine", @"hardware", @"serial",
        @"distinct", @"appsflyer", @"firebase", @"adjust", @"umeng", @"analytics", @"devid",
        @"deviceid", @"machineid", @"uniqueid", @"unique_id", @"androidid", @"imei", @"oaid"
    ];
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL ABKeyLooksLikeCredential(NSString *key) {
    NSString *lower = key.lowercaseString;
    NSArray<NSString *> *skip = @[
        @"token", @"auth", @"password", @"passwd", @"login", @"credential", @"secret", @"oauth",
        @"refresh", @"access", @"cookie", @"jwt", @"passwd", @"sessionkey", @"privatekey", @"apikey"
    ];
    for (NSString *needle in skip) {
        if ([lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL ABStringLooksLikeIdentifier(NSString *value) {
    if (value.length < 8 || value.length > 128) {
        return NO;
    }
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"];
    NSCharacterSet *invalid = [hex invertedSet];
    if ([value rangeOfCharacterFromSet:invalid].location == NSNotFound) {
        return YES;
    }
    if (value.length == 36 && [value characterAtIndex:8] == '-' && [value characterAtIndex:13] == '-') {
        return YES;
    }
    return NO;
}

static NSString *ABRandomIdentifierString(void) {
    return [[NSUUID UUID] UUIDString];
}

static id ABScrubPlistObject(id object) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)object count]];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            NSString *name = [key isKindOfClass:[NSString class]] ? key : [key description];
            if (ABKeyLooksLikeIdentity(name) && !ABKeyLooksLikeCredential(name)) {
                if ([value isKindOfClass:[NSString class]] && ABStringLooksLikeIdentifier(value)) {
                    result[key] = ABRandomIdentifierString();
                    return;
                }
                if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                    result[key] = ABScrubPlistObject(value);
                    return;
                }
                if ([value isKindOfClass:[NSString class]]) {
                    result[key] = ABRandomIdentifierString();
                    return;
                }
            }
            result[key] = ABScrubPlistObject(value);
        }];
        return result;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)object count]];
        for (id value in (NSArray *)object) {
            [result addObject:ABScrubPlistObject(value)];
        }
        return result;
    }
    return object;
}

static BOOL ABScrubPreferencesInDirectory(NSString *directory) {
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        return YES;
    }
    NSArray<NSURL *> *files = [manager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:directory] includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *file in files) {
        if (![[file.pathExtension lowercaseString] isEqualToString:@"plist"]) {
            continue;
        }
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfURL:file];
        if (!plist) {
            continue;
        }
        id scrubbed = ABScrubPlistObject(plist);
        if (![scrubbed writeToURL:file atomically:YES]) {
            return NO;
        }
    }
    return YES;
}

static BOOL ABFolderLooksLikeTracker(NSString *name) {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *needles = @[
        @"google", @"firebase", @"appsflyer", @"adjust", @"facebook", @"umeng", @"sensors",
        @"analytics", @"crashlytics", @"talkingdata", @"bugly", @"tencent", @"bytedance", @"tiktok",
        @"shopee_track", @"tracking"
    ];
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL ABRemoveTrackerSupportInDirectory(NSString *root) {
    NSString *support = [root stringByAppendingPathComponent:@"Library/Application Support"];
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:support isDirectory:&isDirectory] || !isDirectory) {
        return YES;
    }
    NSArray<NSURL *> *children = [manager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:support] includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *child in children) {
        if (ABFolderLooksLikeTracker(child.lastPathComponent)) {
            [manager removeItemAtURL:child error:nil];
        }
    }
    return YES;
}

static void ABCollectCleanTargetsForRoot(NSString *root, NSMutableArray<NSString *> *removeOnly, NSMutableArray<NSString *> *recreateEmpty) {
    if (root.length == 0) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *relative in @[
        @"tmp", @"Library/Caches", @"Library/SplashBoard", @"Library/WebKit", @"Library/Cookies",
        @"Library/HTTPStorages", @"Library/Saved Application State", @"Library/com.apple.WebKit.WebContent"
    ]) {
        NSString *path = [root stringByAppendingPathComponent:relative];
        if (![manager fileExistsAtPath:path]) {
            continue;
        }
        if ([relative isEqualToString:@"tmp"] || [relative hasPrefix:@"Library/Caches"] || [relative isEqualToString:@"Library/SplashBoard"]) {
            [recreateEmpty addObject:path];
        } else {
            [removeOnly addObject:path];
        }
    }
}

- (BOOL)removeDirectoryFully:(NSString *)path error:(NSError **)error {
    if (path.length == 0) {
        return YES;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path]) {
        return YES;
    }
    NSError *removeError = nil;
    if (![manager removeItemAtPath:path error:&removeError]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"无法删除 %@：%@", path.lastPathComponent, removeError.localizedDescription ?: @"未知原因"]);
        }
        return NO;
    }
    return YES;
}

- (BOOL)removeCacheDirectory:(NSString *)path error:(NSError **)error {
    if (path.length == 0) {
        return YES;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:path isDirectory:&isDirectory]) {
        return YES;
    }
    NSError *removeError = nil;
    if (![manager removeItemAtPath:path error:&removeError]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"无法删除 %@：%@", path.lastPathComponent, removeError.localizedDescription ?: @"未知原因"]);
        }
        return NO;
    }
    if (![manager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&removeError]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"无法重建 %@：%@", path.lastPathComponent, removeError.localizedDescription ?: @"未知原因"]);
        }
        return NO;
    }
    ABRepairOwnership(path);
    return YES;
}

- (BOOL)performCleanForApp:(ABAppInfo *)app progress:(ABProgressBlock)progress error:(NSError **)error {
    if ([app.bundleIdentifier isEqualToString:ABBundleIdentifier]) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"不能清理「应用备份」自己");
        }
        return NO;
    }
    if (![[ABAppLibrary sharedLibrary] canReadOtherApps]) {
        if (error) {
            *error = ABMakeError(ABErrorAccess, @"无法清理其他应用。请用 TrollStore 安装本应用。");
        }
        return NO;
    }
    ABContainerLocation *location = [[ABAppLibrary sharedLibrary] locationForBundleIdentifier:app.bundleIdentifier];
    NSURL *container = location.dataContainerURL ?: app.dataContainerURL;
    if (!container) {
        if (error) {
            *error = ABMakeError(ABErrorFailed, @"这个应用还没有数据目录，请先打开一次");
        }
        return NO;
    }
    [self report:progress message:@"正在退出应用" done:0 total:1 force:YES];
    ABStopApplication(app.bundleIdentifier, location.bundleURL ?: app.bundleURL);
    NSMutableArray<NSString *> *removeOnly = [NSMutableArray array];
    NSMutableArray<NSString *> *recreateEmpty = [NSMutableArray array];
    NSMutableArray<NSString *> *roots = [NSMutableArray arrayWithObject:container.path];
    for (NSURL *groupURL in location.groupContainers.allValues) {
        [roots addObject:groupURL.path];
    }
    for (NSString *root in roots) {
        ABCollectCleanTargetsForRoot(root, removeOnly, recreateEmpty);
    }
    NSUInteger total = removeOnly.count + recreateEmpty.count + roots.count + 1;
    NSUInteger index = 0;
    for (NSString *path in removeOnly) {
        if (self.cancelled) {
            if (error) {
                *error = ABMakeError(ABErrorCancelled, @"已取消");
            }
            return NO;
        }
        index++;
        [self report:progress message:[NSString stringWithFormat:@"正在删除 %@", path.lastPathComponent] done:index total:MAX(total, 1) force:YES];
        if (![self removeDirectoryFully:path error:error]) {
            return NO;
        }
    }
    for (NSString *path in recreateEmpty) {
        if (self.cancelled) {
            if (error) {
                *error = ABMakeError(ABErrorCancelled, @"已取消");
            }
            return NO;
        }
        index++;
        [self report:progress message:[NSString stringWithFormat:@"正在清理 %@", path.lastPathComponent] done:index total:MAX(total, 1) force:YES];
        if (![self removeCacheDirectory:path error:error]) {
            return NO;
        }
    }
    for (NSString *root in roots) {
        if (self.cancelled) {
            if (error) {
                *error = ABMakeError(ABErrorCancelled, @"已取消");
            }
            return NO;
        }
        index++;
        [self report:progress message:@"正在重置本地标识" done:index total:MAX(total, 1) force:YES];
        if (!ABScrubPreferencesInDirectory([root stringByAppendingPathComponent:@"Library/Preferences"])) {
            if (error) {
                *error = ABMakeError(ABErrorFailed, @"无法改写偏好设置里的设备标识");
            }
            return NO;
        }
        ABRemoveTrackerSupportInDirectory(root);
    }
    index++;
    [self report:progress message:@"正在修正权限" done:index total:MAX(total, 1) force:YES];
    ABRepairDataContainer(container.path);
    for (NSString *root in roots) {
        if (![root isEqualToString:container.path]) {
            ABRepairOwnership(root);
        }
    }
    [self report:progress message:@"清理完成" done:total total:MAX(total, 1) force:YES];
    return YES;
}

- (void)cleanApp:(ABAppInfo *)app progress:(ABProgressBlock)progress completion:(void (^)(NSError *error))completion {
    NSError *startError = nil;
    if (![self beginOperation:&startError]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(startError);
        });
        return;
    }
    dispatch_async(self.workQueue, ^{
        NSError *workError = nil;
        [self performCleanForApp:app progress:progress error:&workError];
        [self endOperation];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(workError);
        });
    });
}

- (void)backupApp:(ABAppInfo *)app options:(ABBackupOptions *)options progress:(ABProgressBlock)progress completion:(ABBackupCompletion)completion {
    NSError *startError = nil;
    if (![self beginOperation:&startError]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, startError);
        });
        return;
    }
    dispatch_async(self.workQueue, ^{
        NSError *workError = nil;
        NSURL *url = [self performBackupForApp:app options:options progress:progress error:&workError];
        [self endOperation];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(url, workError);
        });
    });
}

- (void)restoreBackupAtURL:(NSURL *)archiveURL bundleIdentifier:(NSString *)bundleIdentifier progress:(ABProgressBlock)progress completion:(ABRestoreCompletion)completion {
    NSError *startError = nil;
    if (![self beginOperation:&startError]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, startError);
        });
        return;
    }
    dispatch_async(self.workQueue, ^{
        NSMutableArray<NSString *> *warnings = [NSMutableArray array];
        NSError *workError = nil;
        BOOL ok = [self performRestoreAtURL:archiveURL bundleIdentifier:bundleIdentifier warnings:warnings progress:progress error:&workError];
        [self endOperation];
        NSArray *finishedWarnings = [warnings copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(ok ? finishedWarnings : nil, workError);
        });
    });
}

@end
