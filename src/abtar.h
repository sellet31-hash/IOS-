#ifndef ABTAR_H
#define ABTAR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum abtar_status {
    ABTAR_OK = 0,
    ABTAR_EOF = 1,
    ABTAR_ERR_IO = 2,
    ABTAR_ERR_FORMAT = 3,
    ABTAR_ERR_PATH = 4,
    ABTAR_ERR_UNSUPPORTED = 5,
    ABTAR_ERR_NOMEM = 6,
    ABTAR_ERR_CANCELLED = 7
} abtar_status;

typedef void (*abtar_progress_fn)(void *ctx, int64_t payload_bytes_written);
typedef int (*abtar_cancel_fn)(void *ctx);

typedef struct abtar_writer abtar_writer;
typedef struct abtar_reader abtar_reader;

typedef struct abtar_entry {
    const char *path;
    const char *link_target;
    int64_t size;
    int64_t mtime;
    uint32_t mode;
    char typeflag;
} abtar_entry;

abtar_status abtar_writer_create(const char *path, abtar_writer **out_writer);
void abtar_writer_set_progress(abtar_writer *writer, abtar_progress_fn fn, void *ctx);
void abtar_writer_set_cancel(abtar_writer *writer, abtar_cancel_fn fn, void *ctx);
abtar_status abtar_writer_add_dir(abtar_writer *writer, const char *archive_path, uint32_t mode, int64_t mtime);
abtar_status abtar_writer_add_symlink(abtar_writer *writer, const char *archive_path, const char *link_target, int64_t mtime);
abtar_status abtar_writer_add_file(abtar_writer *writer, const char *archive_path, const char *source_path, uint32_t mode, int64_t mtime);
abtar_status abtar_writer_finish(abtar_writer *writer);
void abtar_writer_cancel(abtar_writer *writer);

abtar_status abtar_reader_open(const char *path, abtar_reader **out_reader);
void abtar_reader_set_progress(abtar_reader *reader, abtar_progress_fn fn, void *ctx);
abtar_status abtar_reader_next(abtar_reader *reader, abtar_entry *out_entry);
abtar_status abtar_reader_slurp_current(abtar_reader *reader, void **out_bytes, int64_t *out_size, int64_t max_size);
abtar_status abtar_reader_extract_current(abtar_reader *reader, const char *dest_root);
void abtar_reader_close(abtar_reader *reader);

#ifdef __cplusplus
}
#endif

#endif
