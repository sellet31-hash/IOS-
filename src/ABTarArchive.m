#import "ABTarArchive.h"
#import "abtar.h"

@interface ABTarBox : NSObject
@property (nonatomic, copy) BOOL (^shouldStop)(void);
@property (nonatomic, copy) void (^onBytes)(int64_t written);
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic) uint64_t lastWritten;
@end

@implementation ABTarBox
@end

static int ABTarShouldStop(void *context) {
    ABTarBox *box = (__bridge ABTarBox *)context;
    return box.shouldStop && box.shouldStop();
}

static void ABTarBytes(void *context, int64_t written) {
    ABTarBox *box = (__bridge ABTarBox *)context;
    if (box.onBytes) {
        box.onBytes(written);
    }
}

static BOOL ABTarFailed(abtar_status status, NSString *path, NSError **error) {
    if (status == ABTAR_OK || status == ABTAR_EOF) {
        return NO;
    }
    if (error) {
        if (status == ABTAR_ERR_CANCELLED) {
            *error = ABMakeError(ABErrorCancelled, @"已取消");
        } else if (status == ABTAR_ERR_PATH) {
            *error = ABMakeError(ABErrorFormat, path.length ? [NSString stringWithFormat:@"路径不安全：%@", path] : @"归档里有不安全的路径");
        } else if (status == ABTAR_ERR_FORMAT) {
            *error = ABMakeError(ABErrorFormat, @"无法读取这份备份");
        } else if (status == ABTAR_ERR_NOMEM) {
            *error = ABMakeError(ABErrorFailed, @"内存不足");
        } else {
            *error = ABMakeError(ABErrorFailed, path.length ? [NSString stringWithFormat:@"无法处理 %@", path] : @"读写备份失败");
        }
    }
    return YES;
}

@implementation ABTarArchive

+ (BOOL)writeManifestAtPath:(NSString *)manifestPath
                      items:(NSArray<ABFileItem *> *)items
                      toURL:(NSURL *)destinationURL
                 onProgress:(void (^)(NSString *path, uint64_t bytesWritten))onProgress
                 shouldStop:(BOOL (^)(void))shouldStop
                      error:(NSError **)error {
    ABTarBox *box = [ABTarBox new];
    box.shouldStop = shouldStop;
    __block uint64_t written = 0;
    box.onBytes = ^(int64_t count) {
        written = (uint64_t)MAX(count, 0);
        if (onProgress) {
            onProgress(box.currentPath ?: @"", written);
        }
    };
    abtar_writer *writer = NULL;
    abtar_status status = abtar_writer_create(destinationURL.fileSystemRepresentation, &writer);
    if (ABTarFailed(status, destinationURL.lastPathComponent, error)) {
        return NO;
    }
    abtar_writer_set_cancel(writer, ABTarShouldStop, (__bridge void *)box);
    abtar_writer_set_progress(writer, ABTarBytes, (__bridge void *)box);
    box.currentPath = @"manifest.plist";
    status = abtar_writer_add_file(writer, "manifest.plist", manifestPath.fileSystemRepresentation, 0644, (int64_t)[NSDate date].timeIntervalSince1970);
    if (ABTarFailed(status, @"manifest.plist", error)) {
        abtar_writer_cancel(writer);
        return NO;
    }
    for (ABFileItem *item in items) {
        if (shouldStop && shouldStop()) {
            abtar_writer_cancel(writer);
            if (error) {
                *error = ABMakeError(ABErrorCancelled, @"已取消");
            }
            return NO;
        }
        const char *archivePath = item.archivePath.fileSystemRepresentation;
        box.currentPath = item.relativePath.length ? item.relativePath : item.archivePath;
        if (onProgress) {
            onProgress(box.currentPath, written);
        }
        if (item.directory) {
            status = abtar_writer_add_dir(writer, archivePath, item.mode, item.mtime);
        } else if (item.symlink) {
            const char *target = item.linkTarget.UTF8String;
            if (!target) {
                abtar_writer_cancel(writer);
                if (error) {
                    *error = ABMakeError(ABErrorFailed, [NSString stringWithFormat:@"符号链接无法编码：%@", item.relativePath]);
                }
                return NO;
            }
            status = abtar_writer_add_symlink(writer, archivePath, target, item.mtime);
        } else {
            status = abtar_writer_add_file(writer, archivePath, item.sourcePath.fileSystemRepresentation, item.mode, item.mtime);
        }
        if (ABTarFailed(status, item.relativePath, error)) {
            abtar_writer_cancel(writer);
            return NO;
        }
    }
    status = abtar_writer_finish(writer);
    return !ABTarFailed(status, destinationURL.lastPathComponent, error);
}

+ (BOOL)summarizeArchiveAtURL:(NSURL *)archiveURL
                      manifest:(NSDictionary **)manifest
            uncompressedBytes:(uint64_t *)uncompressedBytes
                        error:(NSError **)error {
    abtar_reader *reader = NULL;
    abtar_status status = abtar_reader_open(archiveURL.fileSystemRepresentation, &reader);
    if (ABTarFailed(status, archiveURL.lastPathComponent, error)) {
        return NO;
    }
    BOOL foundManifest = NO;
    uint64_t total = 0;
    abtar_entry entry;
    while ((status = abtar_reader_next(reader, &entry)) == ABTAR_OK) {
        if (entry.typeflag == '0') {
            if (entry.size > 0) {
                total += (uint64_t)entry.size;
            }
        }
        if (!foundManifest && entry.path && strcmp(entry.path, "manifest.plist") == 0) {
            void *bytes = NULL;
            int64_t size = 0;
            status = abtar_reader_slurp_current(reader, &bytes, &size, 2 * 1024 * 1024);
            if (ABTarFailed(status, @"manifest.plist", error)) {
                free(bytes);
                abtar_reader_close(reader);
                return NO;
            }
            NSData *data = [NSData dataWithBytesNoCopy:bytes length:(NSUInteger)size freeWhenDone:YES];
            NSError *plistError = nil;
            id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&plistError];
            if (![plist isKindOfClass:[NSDictionary class]]) {
                abtar_reader_close(reader);
                if (error) {
                    *error = ABMakeError(ABErrorFormat, @"备份清单损坏");
                }
                return NO;
            }
            if (manifest) {
                *manifest = plist;
            }
            foundManifest = YES;
        }
    }
    abtar_reader_close(reader);
    if (ABTarFailed(status, archiveURL.lastPathComponent, error)) {
        return NO;
    }
    if (!foundManifest) {
        if (error) {
            *error = ABMakeError(ABErrorFormat, @"这不是应用备份文件");
        }
        return NO;
    }
    if (uncompressedBytes) {
        *uncompressedBytes = total;
    }
    return YES;
}

+ (BOOL)extractArchiveAtURL:(NSURL *)archiveURL
                      toURL:(NSURL *)destinationURL
                 onProgress:(void (^)(NSString *path, uint64_t bytesWritten))onProgress
                 shouldStop:(BOOL (^)(void))shouldStop
                      error:(NSError **)error {
    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:destinationURL withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        if (error) {
            *error = directoryError;
        }
        return NO;
    }
    ABTarBox *box = [ABTarBox new];
    box.shouldStop = shouldStop;
    box.onBytes = ^(int64_t count) {
        box.lastWritten = (uint64_t)MAX(count, 0);
        if (onProgress) {
            onProgress(box.currentPath ?: @"", box.lastWritten);
        }
    };
    abtar_reader *reader = NULL;
    abtar_status status = abtar_reader_open(archiveURL.fileSystemRepresentation, &reader);
    if (ABTarFailed(status, archiveURL.lastPathComponent, error)) {
        return NO;
    }
    abtar_reader_set_progress(reader, ABTarBytes, (__bridge void *)box);
    abtar_entry entry;
    while ((status = abtar_reader_next(reader, &entry)) == ABTAR_OK) {
        if (shouldStop && shouldStop()) {
            abtar_reader_close(reader);
            if (error) {
                *error = ABMakeError(ABErrorCancelled, @"已取消");
            }
            return NO;
        }
        NSString *path = entry.path ? [NSString stringWithUTF8String:entry.path] : @"";
        box.currentPath = path;
        if (onProgress) {
            onProgress(path, box.lastWritten);
        }
        status = abtar_reader_extract_current(reader, destinationURL.fileSystemRepresentation);
        if (ABTarFailed(status, path, error)) {
            abtar_reader_close(reader);
            return NO;
        }
    }
    abtar_reader_close(reader);
    return !ABTarFailed(status, archiveURL.lastPathComponent, error);
}

@end
