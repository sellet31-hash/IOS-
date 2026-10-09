#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const ABErrorDomain;
FOUNDATION_EXPORT NSString *const ABBundleIdentifier;
FOUNDATION_EXPORT NSString *const ABToolVersion;
FOUNDATION_EXPORT NSString *const ABMetadataFileName;
FOUNDATION_EXPORT NSString *const ABExcludeCachesKey;
FOUNDATION_EXPORT NSString *const ABIncludeGroupsKey;

typedef NS_ENUM(NSInteger, ABErrorCode) {
    ABErrorCancelled = 1,
    ABErrorBusy = 2,
    ABErrorAccess = 3,
    ABErrorSpace = 4,
    ABErrorFormat = 5,
    ABErrorNotInstalled = 6,
    ABErrorFailed = 7
};

NSError *ABMakeError(ABErrorCode code, NSString *message);
NSString *ABFormatBytes(uint64_t bytes);
NSString *ABFormatDate(NSDate *date);

@interface ABBackupOptions : NSObject
@property (nonatomic) BOOL excludesCaches;
@property (nonatomic) BOOL includesAppGroups;
+ (ABBackupOptions *)currentOptions;
@end

@interface ABAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *shortVersion;
@property (nonatomic, copy) NSString *bundleVersion;
@property (nonatomic, copy) NSURL *dataContainerURL;
@property (nonatomic, copy) NSURL *bundleURL;
@property (nonatomic) BOOL sizeKnown;
@property (nonatomic) BOOL sizeFailed;
@property (nonatomic) BOOL measuredExcludesCaches;
@property (nonatomic) BOOL measuredIncludesGroups;
@property (nonatomic) uint64_t dataBytes;
@end

@interface ABBackupInfo : NSObject
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *customName;
@property (nonatomic, copy) NSString *shortVersion;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *lastUsedAt;
@property (nonatomic) uint64_t fileSize;
- (NSString *)preferredTitle;
- (NSString *)summaryText;
@end

@interface ABFileItem : NSObject
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, copy) NSString *archivePath;
@property (nonatomic, copy) NSString *sourcePath;
@property (nonatomic, copy) NSString *linkTarget;
@property (nonatomic) BOOL directory;
@property (nonatomic) BOOL symlink;
@property (nonatomic) uint64_t fileSize;
@property (nonatomic) uint32_t mode;
@property (nonatomic) int64_t mtime;
@end
