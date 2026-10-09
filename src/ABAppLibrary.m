#import "ABAppLibrary.h"
#import <dlfcn.h>
#import <objc/message.h>

@implementation ABContainerLocation
@end

@interface ABAppLibrary ()
@property (nonatomic) BOOL accessDenied;
@property (nonatomic, copy) NSArray<ABAppInfo *> *apps;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, copy) NSDictionary<NSString *, NSURL *> *dataIndex;
@property (nonatomic, copy) NSDictionary<NSString *, NSURL *> *bundleIndex;
@property (nonatomic, copy) NSDictionary<NSString *, NSURL *> *groupIndex;
@end

@implementation ABAppLibrary

+ (instancetype)sharedLibrary {
    static ABAppLibrary *library;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        library = [ABAppLibrary new];
    });
    return library;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [NSLock new];
        _apps = @[];
    }
    return self;
}

- (void)reload {
    [self.lock lock];
    self.dataIndex = nil;
    self.bundleIndex = nil;
    self.groupIndex = nil;
    [self.lock unlock];
    NSArray<ABAppInfo *> *apps = [self collectApps];
    BOOL denied = ![self canReadOtherApps];
    [self.lock lock];
    self.apps = apps;
    self.accessDenied = denied;
    [self.lock unlock];
}

- (NSArray<ABAppInfo *> *)installedApps {
    [self.lock lock];
    NSArray<ABAppInfo *> *apps = self.apps ?: @[];
    [self.lock unlock];
    return apps;
}

- (ABAppInfo *)appForBundleIdentifier:(NSString *)bundleIdentifier {
    for (ABAppInfo *app in [self installedApps]) {
        if ([app.bundleIdentifier isEqualToString:bundleIdentifier]) {
            return app;
        }
    }
    return nil;
}

- (BOOL)canReadOtherApps {
    return [[NSFileManager defaultManager] isReadableFileAtPath:@"/var/mobile/Containers/Data/Application"];
}

- (void)loadLaunchServices {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!NSClassFromString(@"LSApplicationWorkspace")) {
            dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW);
        }
        if (!NSClassFromString(@"LSApplicationWorkspace")) {
            dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
        }
    });
}

- (id)value:(id)object key:(NSString *)key {
    if (!object || key.length == 0) {
        return nil;
    }
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

- (NSString *)stringValue:(id)value {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSURL *)URLValue:(id)value {
    if ([value isKindOfClass:[NSURL class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return [NSURL fileURLWithPath:value];
    }
    return nil;
}

- (void)ensureFilesystemIndex {
    [self.lock lock];
    BOOL ready = self.dataIndex != nil && self.bundleIndex != nil;
    [self.lock unlock];
    if (ready) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableDictionary<NSString *, NSURL *> *data = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSURL *> *bundles = [NSMutableDictionary dictionary];
    NSURL *dataRoot = [NSURL fileURLWithPath:@"/var/mobile/Containers/Data/Application" isDirectory:YES];
    NSURL *bundleRoot = [NSURL fileURLWithPath:@"/var/containers/Bundle/Application" isDirectory:YES];
    for (NSURL *directory in [manager contentsOfDirectoryAtURL:dataRoot includingPropertiesForKeys:nil options:0 error:nil]) {
        NSURL *metadataURL = [directory URLByAppendingPathComponent:ABMetadataFileName];
        NSString *identifier = [self stringValue:[NSDictionary dictionaryWithContentsOfURL:metadataURL][@"MCMMetadataIdentifier"]];
        if (identifier.length > 0) {
            data[identifier] = directory;
        }
    }
    for (NSURL *uuidDirectory in [manager contentsOfDirectoryAtURL:bundleRoot includingPropertiesForKeys:nil options:0 error:nil]) {
        for (NSURL *child in [manager contentsOfDirectoryAtURL:uuidDirectory includingPropertiesForKeys:nil options:0 error:nil]) {
            if (![child.pathExtension isEqualToString:@"app"]) {
                continue;
            }
            NSString *identifier = [self stringValue:[NSDictionary dictionaryWithContentsOfURL:[child URLByAppendingPathComponent:@"Info.plist"]][@"CFBundleIdentifier"]];
            if (identifier.length > 0) {
                bundles[identifier] = child;
            }
        }
    }
    [self.lock lock];
    if (!self.dataIndex) {
        self.dataIndex = data;
    }
    if (!self.bundleIndex) {
        self.bundleIndex = bundles;
    }
    [self.lock unlock];
}

- (NSDictionary<NSString *, NSURL *> *)groupContainerIndex {
    [self.lock lock];
    NSDictionary *cached = self.groupIndex;
    [self.lock unlock];
    if (cached) {
        return cached;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *root = [NSURL fileURLWithPath:@"/var/mobile/Containers/Shared/AppGroup" isDirectory:YES];
    NSMutableDictionary<NSString *, NSURL *> *map = [NSMutableDictionary dictionary];
    for (NSURL *directory in [manager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil]) {
        NSURL *metadataURL = [directory URLByAppendingPathComponent:ABMetadataFileName];
        NSString *identifier = [self stringValue:[NSDictionary dictionaryWithContentsOfURL:metadataURL][@"MCMMetadataIdentifier"]];
        if (identifier.length > 0) {
            map[identifier] = directory;
        }
    }
    [self.lock lock];
    if (!self.groupIndex) {
        self.groupIndex = map;
    }
    NSDictionary *result = self.groupIndex;
    [self.lock unlock];
    return result ?: @{};
}

- (NSArray<NSString *> *)groupIdentifiersInData:(NSData *)data {
    const unsigned char *bytes = data.bytes;
    NSUInteger length = data.length;
    NSMutableOrderedSet<NSString *> *found = [NSMutableOrderedSet orderedSet];
    for (NSUInteger index = 0; index + 6 < length; index++) {
        if (bytes[index] == 'g' && bytes[index + 1] == 'r' && bytes[index + 2] == 'o' && bytes[index + 3] == 'u' && bytes[index + 4] == 'p' && bytes[index + 5] == '.') {
            NSUInteger end = index + 6;
            while (end < length) {
                unsigned char character = bytes[end];
                BOOL allowed = (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character == '.' || character == '-' || character == '_';
                if (!allowed) {
                    break;
                }
                end++;
            }
            if (end > index + 6) {
                NSString *identifier = [[NSString alloc] initWithBytes:bytes + index length:end - index encoding:NSUTF8StringEncoding];
                if (identifier) {
                    [found addObject:identifier];
                }
            }
            index = end;
        }
    }
    return found.array;
}

- (NSArray<NSString *> *)groupIdentifiersInExecutable:(NSURL *)executableURL {
    NSError *error = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:executableURL error:&error];
    if (!handle) {
        return @[];
    }
    NSData *data = nil;
    @try {
        unsigned long long size = handle.seekToEndOfFile;
        unsigned long long window = 4ull * 1024ull * 1024ull;
        unsigned long long offset = size > window ? size - window : 0;
        [handle seekToFileOffset:offset];
        data = [handle readDataOfLength:(NSUInteger)MIN(window, size)];
    } @catch (NSException *exception) {
        data = nil;
    }
    [handle closeFile];
    if (data.length == 0) {
        return @[];
    }
    NSData *key = [@"com.apple.security.application-groups" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [data rangeOfData:key options:0 range:NSMakeRange(0, data.length)];
    if (range.location == NSNotFound) {
        return @[];
    }
    NSUInteger start = range.location + range.length;
    NSUInteger slice = MIN((NSUInteger)8192, data.length - start);
    return [self groupIdentifiersInData:[data subdataWithRange:NSMakeRange(start, slice)]];
}

- (NSURL *)executableForBundleURL:(NSURL *)bundleURL {
    if (!bundleURL) {
        return nil;
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
    NSString *name = [self stringValue:info[@"CFBundleExecutable"]];
    if (name.length == 0) {
        name = bundleURL.lastPathComponent.stringByDeletingPathExtension;
    }
    return [bundleURL URLByAppendingPathComponent:name];
}

- (NSDictionary<NSString *, NSURL *> *)groupsForProxy:(id)proxy bundleURL:(NSURL *)bundleURL {
    NSMutableDictionary<NSString *, NSURL *> *resolved = [NSMutableDictionary dictionary];
    NSDictionary *raw = [self value:proxy key:@"groupContainerURLs"];
    if ([raw isKindOfClass:[NSDictionary class]]) {
        [raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSURL *url = [self URLValue:obj];
            NSString *identifier = [self stringValue:key];
            if (identifier.length > 0 && url) {
                resolved[identifier] = url;
            }
        }];
    }
    if (resolved.count > 0) {
        return resolved;
    }
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    NSDictionary *entitlements = [self value:proxy key:@"entitlements"];
    id groups = [entitlements isKindOfClass:[NSDictionary class]] ? entitlements[@"com.apple.security.application-groups"] : nil;
    if ([groups isKindOfClass:[NSArray class]]) {
        for (id identifier in groups) {
            if ([identifier isKindOfClass:[NSString class]]) {
                [identifiers addObject:identifier];
            }
        }
    }
    if (identifiers.count == 0) {
        [identifiers addObjectsFromArray:[self groupIdentifiersInExecutable:[self executableForBundleURL:bundleURL]]];
    }
    NSDictionary<NSString *, NSURL *> *index = [self groupContainerIndex];
    for (NSString *identifier in identifiers) {
        NSURL *url = index[identifier];
        if (url) {
            resolved[identifier] = url;
        }
    }
    return resolved;
}

- (id)proxyForBundleIdentifier:(NSString *)bundleIdentifier {
    [self loadLaunchServices];
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL selector = @selector(applicationProxyForIdentifier:);
    if (!proxyClass || ![proxyClass respondsToSelector:selector]) {
        return nil;
    }
    id proxy = ((id (*)(id, SEL, NSString *))objc_msgSend)(proxyClass, selector, bundleIdentifier);
    NSString *found = [self stringValue:[self value:proxy key:@"applicationIdentifier"]];
    if (![found isEqualToString:bundleIdentifier]) {
        return nil;
    }
    return proxy;
}

- (ABAppInfo *)appInfoFromProxy:(id)proxy {
    NSString *identifier = [self stringValue:[self value:proxy key:@"applicationIdentifier"]];
    if (identifier.length == 0 || [identifier isEqualToString:ABBundleIdentifier]) {
        return nil;
    }
    NSString *type = [self stringValue:[self value:proxy key:@"applicationType"]];
    NSURL *bundleURL = [self URLValue:[self value:proxy key:@"bundleURL"]];
    BOOL userApp = type.length == 0 || [type caseInsensitiveCompare:@"User"] == NSOrderedSame;
    NSString *bundlePath = bundleURL.path.lowercaseString ?: @"";
    BOOL userLocation = [bundlePath containsString:@"/var/containers/bundle/application/"];
    if (!userApp && !userLocation) {
        return nil;
    }
    ABAppInfo *app = [ABAppInfo new];
    app.bundleIdentifier = identifier;
    app.displayName = [self stringValue:[self value:proxy key:@"localizedName"]];
    if (app.displayName.length == 0) {
        app.displayName = identifier;
    }
    app.shortVersion = [self stringValue:[self value:proxy key:@"shortVersionString"]] ?: @"";
    app.bundleVersion = [self stringValue:[self value:proxy key:@"bundleVersion"]] ?: @"";
    app.bundleURL = bundleURL;
    app.dataContainerURL = [self URLValue:[self value:proxy key:@"dataContainerURL"]];
    if (!app.dataContainerURL || !app.bundleURL) {
        [self ensureFilesystemIndex];
        [self.lock lock];
        NSDictionary<NSString *, NSURL *> *dataIndex = self.dataIndex;
        NSDictionary<NSString *, NSURL *> *bundleIndex = self.bundleIndex;
        [self.lock unlock];
        if (!app.dataContainerURL) {
            app.dataContainerURL = dataIndex[identifier];
        }
        if (!app.bundleURL) {
            app.bundleURL = bundleIndex[identifier];
        }
    }
    return app;
}

- (NSArray<ABAppInfo *> *)appsFromLaunchServices {
    [self loadLaunchServices];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        return @[];
    }
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, @selector(defaultWorkspace));
    if (![workspace respondsToSelector:@selector(allInstalledApplications)]) {
        return @[];
    }
    NSArray *proxies = nil;
    @try {
        proxies = ((NSArray * (*)(id, SEL))objc_msgSend)(workspace, @selector(allInstalledApplications));
    } @catch (NSException *exception) {
        return @[];
    }
    NSMutableDictionary<NSString *, ABAppInfo *> *unique = [NSMutableDictionary dictionary];
    for (id proxy in proxies) {
        ABAppInfo *app = [self appInfoFromProxy:proxy];
        if (app) {
            unique[app.bundleIdentifier] = app;
        }
    }
    return unique.allValues;
}

- (NSArray<ABAppInfo *> *)appsFromFilesystem {
    [self ensureFilesystemIndex];
    [self.lock lock];
    NSDictionary<NSString *, NSURL *> *bundleIndex = self.bundleIndex;
    NSDictionary<NSString *, NSURL *> *dataIndex = self.dataIndex;
    [self.lock unlock];
    NSMutableArray<ABAppInfo *> *apps = [NSMutableArray array];
    [bundleIndex enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSURL *bundleURL, BOOL *stop) {
        if ([identifier isEqualToString:ABBundleIdentifier]) {
            return;
        }
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
        ABAppInfo *app = [ABAppInfo new];
        app.bundleIdentifier = identifier;
        app.displayName = [self stringValue:info[@"CFBundleDisplayName"]];
        if (app.displayName.length == 0) {
            app.displayName = [self stringValue:info[@"CFBundleName"]];
        }
        if (app.displayName.length == 0) {
            app.displayName = identifier;
        }
        app.shortVersion = [self stringValue:info[@"CFBundleShortVersionString"]] ?: @"";
        app.bundleVersion = [self stringValue:info[@"CFBundleVersion"]] ?: @"";
        app.bundleURL = bundleURL;
        app.dataContainerURL = dataIndex[identifier];
        [apps addObject:app];
    }];
    return apps;
}

- (NSArray<ABAppInfo *> *)collectApps {
    NSMutableArray<ABAppInfo *> *apps = [[self appsFromLaunchServices] mutableCopy];
    if (apps.count == 0 && [self canReadOtherApps]) {
        [apps addObjectsFromArray:[self appsFromFilesystem]];
    }
    [apps sortUsingComparator:^NSComparisonResult(ABAppInfo *lhs, ABAppInfo *rhs) {
        return [lhs.displayName localizedStandardCompare:rhs.displayName];
    }];
    return apps;
}

- (ABContainerLocation *)locationForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return nil;
    }
    id proxy = [self proxyForBundleIdentifier:bundleIdentifier];
    ABContainerLocation *location = [ABContainerLocation new];
    location.bundleURL = [self URLValue:[self value:proxy key:@"bundleURL"]];
    location.dataContainerURL = [self URLValue:[self value:proxy key:@"dataContainerURL"]];
    location.displayName = [self stringValue:[self value:proxy key:@"localizedName"]];
    location.shortVersion = [self stringValue:[self value:proxy key:@"shortVersionString"]];
    location.bundleVersion = [self stringValue:[self value:proxy key:@"bundleVersion"]];
    if (!location.dataContainerURL || !location.bundleURL) {
        [self ensureFilesystemIndex];
        [self.lock lock];
        NSDictionary<NSString *, NSURL *> *dataIndex = self.dataIndex;
        NSDictionary<NSString *, NSURL *> *bundleIndex = self.bundleIndex;
        [self.lock unlock];
        if (!location.dataContainerURL) {
            location.dataContainerURL = dataIndex[bundleIdentifier];
        }
        if (!location.bundleURL) {
            location.bundleURL = bundleIndex[bundleIdentifier];
        }
    }
    if (!location.dataContainerURL && !location.bundleURL && !proxy) {
        return nil;
    }
    location.groupContainers = [self groupsForProxy:proxy bundleURL:location.bundleURL] ?: @{};
    return location;
}

@end
