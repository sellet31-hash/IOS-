#import <Foundation/Foundation.h>
#import "ABModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^ABProgressBlock)(NSString *message, double fraction, uint64_t bytesDone, uint64_t bytesTotal);
typedef void (^ABBackupCompletion)(NSURL *_Nullable archiveURL, NSError *_Nullable error);
typedef void (^ABRestoreCompletion)(NSArray<NSString *> *_Nullable warnings, NSError *_Nullable error);

@interface ABBackupEngine : NSObject
@property (atomic, readonly) BOOL busy;
+ (instancetype)sharedEngine;
- (void)cancel;
+ (nullable NSURL *)backupDirectoryURL:(NSError *_Nullable *_Nullable)error;
+ (NSArray<ABBackupInfo *> *)allBackupsWithUnreadableCount:(NSUInteger *_Nullable)unreadable
                                                     error:(NSError *_Nullable *_Nullable)error;
+ (BOOL)renameBackupAtURL:(NSURL *)fileURL name:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
+ (void)markBackupUsedAtURL:(NSURL *)fileURL;
+ (void)deleteBackupAtURL:(NSURL *)fileURL;
- (BOOL)calculateSizeForApp:(ABAppInfo *)app
                    options:(ABBackupOptions *)options
                      bytes:(uint64_t *)bytes
                      error:(NSError *_Nullable *_Nullable)error;
- (void)backupApp:(ABAppInfo *)app
          options:(ABBackupOptions *)options
         progress:(nullable ABProgressBlock)progress
       completion:(ABBackupCompletion)completion;
- (void)cleanApp:(ABAppInfo *)app
        progress:(nullable ABProgressBlock)progress
      completion:(void (^)(NSError *_Nullable error))completion;
- (void)restoreBackupAtURL:(NSURL *)archiveURL
        bundleIdentifier:(NSString *)bundleIdentifier
                progress:(nullable ABProgressBlock)progress
              completion:(ABRestoreCompletion)completion;
@end

NS_ASSUME_NONNULL_END
