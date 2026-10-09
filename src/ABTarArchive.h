#import <Foundation/Foundation.h>
#import "ABModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface ABTarArchive : NSObject
+ (BOOL)writeManifestAtPath:(NSString *)manifestPath
                      items:(NSArray<ABFileItem *> *)items
                      toURL:(NSURL *)destinationURL
                 onProgress:(void (^_Nullable)(NSString *path, uint64_t bytesWritten))onProgress
                 shouldStop:(BOOL (^_Nullable)(void))shouldStop
                      error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)summarizeArchiveAtURL:(NSURL *)archiveURL
                      manifest:(NSDictionary *_Nullable *_Nullable)manifest
            uncompressedBytes:(uint64_t *)uncompressedBytes
                        error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)extractArchiveAtURL:(NSURL *)archiveURL
                      toURL:(NSURL *)destinationURL
                 onProgress:(void (^_Nullable)(NSString *path, uint64_t bytesWritten))onProgress
                 shouldStop:(BOOL (^_Nullable)(void))shouldStop
                      error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
