#include "abtar.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#if defined(_WIN32)
#include <direct.h>
#include <io.h>
#define ab_mkdir(path) _mkdir(path)
#else
#include <fcntl.h>
#include <unistd.h>
#define ab_mkdir(path) mkdir((path), 0755)
#endif

#ifndef ABTAR_USTAR_MAX_SIZE
#define ABTAR_USTAR_MAX_SIZE 8589934591LL
#endif

#define ABTAR_PATH_MAX 16384

struct abtar_writer {
    FILE *fp;
    abtar_progress_fn progress;
    void *progress_ctx;
    abtar_cancel_fn cancel;
    void *cancel_ctx;
    int64_t payload_written;
};

struct abtar_reader {
    FILE *fp;
    abtar_progress_fn progress;
    void *progress_ctx;
    int64_t payload_written;
    int payload_pending;
    int64_t payload_size;
    int64_t payload_left;
    char path_buf[ABTAR_PATH_MAX];
    char link_buf[ABTAR_PATH_MAX];
    char pax_path[ABTAR_PATH_MAX];
    char pax_link[ABTAR_PATH_MAX];
    int has_pax_path;
    int has_pax_link;
    int has_pax_size;
    int64_t pax_size;
    abtar_entry current;
};

static abtar_status write_exact(FILE *fp, const void *bytes, size_t size) {
    const char *cursor = (const char *)bytes;
    size_t done = 0;
    while (done < size) {
        size_t wrote = fwrite(cursor + done, 1, size - done, fp);
        if (wrote == 0) {
            return ABTAR_ERR_IO;
        }
        done += wrote;
    }
    return ABTAR_OK;
}

static abtar_status read_exact(FILE *fp, void *bytes, size_t size) {
    char *cursor = (char *)bytes;
    size_t done = 0;
    while (done < size) {
        size_t got = fread(cursor + done, 1, size - done, fp);
        if (got == 0) {
            if (feof(fp)) {
                return ABTAR_ERR_FORMAT;
            }
            return ABTAR_ERR_IO;
        }
        done += got;
    }
    return ABTAR_OK;
}

static int cancelled(const abtar_writer *writer) {
    return writer->cancel && writer->cancel(writer->cancel_ctx);
}

static int is_ascii_path(const char *text) {
    const unsigned char *cursor = (const unsigned char *)text;
    if (!cursor || !cursor[0]) {
        return 0;
    }
    for (; *cursor; cursor++) {
        if (*cursor < 32 || *cursor > 126) {
            return 0;
        }
    }
    return 1;
}

static void length_trim_slash(char *path) {
    size_t length = strlen(path);
    while (length > 0 && path[length - 1] == '/') {
        path[length - 1] = '\0';
        length--;
    }
}

static int path_is_unsafe(const char *path) {
    const char *cursor;
    if (!path || !path[0]) {
        return 1;
    }
    if (strchr(path, '\n') || strchr(path, '\r')) {
        return 1;
    }
    if (path[0] == '/' || path[0] == '\\') {
        return 1;
    }
    if (((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':') {
        return 1;
    }
    if (strlen(path) >= ABTAR_PATH_MAX) {
        return 1;
    }
    cursor = path;
    while (*cursor) {
        const char *slash = strchr(cursor, '/');
        size_t length = slash ? (size_t)(slash - cursor) : strlen(cursor);
        if (memchr(cursor, '\\', length)) {
            return 1;
        }
        if (length == 2 && cursor[0] == '.' && cursor[1] == '.') {
            return 1;
        }
        if (!slash) {
            break;
        }
        cursor = slash + 1;
    }
    return 0;
}

static int put_octal(char *destination, int width, uint64_t value) {
    char temporary[64];
    int written = snprintf(temporary, sizeof(temporary), "%0*llo", width - 1, (unsigned long long)value);
    if (written != width - 1) {
        return -1;
    }
    memcpy(destination, temporary, (size_t)width - 1);
    destination[width - 1] = '\0';
    return 0;
}

static int split_ustar_name(const char *path, char name[100], char prefix[155]) {
    size_t length = strlen(path);
    const char *slash;
    size_t prefix_length;
    size_t name_length;
    memset(name, 0, 100);
    memset(prefix, 0, 155);
    if (length <= 100) {
        memcpy(name, path, length);
        return 0;
    }
    if (length > 255) {
        return -1;
    }
    slash = path + (length - 100);
    while (*slash && *slash != '/') {
        slash++;
    }
    if (*slash != '/') {
        return -1;
    }
    prefix_length = (size_t)(slash - path);
    name_length = length - prefix_length - 1;
    if (prefix_length == 0 || prefix_length > 155 || name_length == 0 || name_length > 100) {
        return -1;
    }
    memcpy(prefix, path, prefix_length);
    memcpy(name, slash + 1, name_length);
    return 0;
}

static void put_checksum(unsigned char block[512]) {
    unsigned sum = 0;
    char temporary[16];
    int index;
    memset(block + 148, ' ', 8);
    for (index = 0; index < 512; index++) {
        sum += block[index];
    }
    snprintf(temporary, sizeof(temporary), "%06o", sum);
    memcpy(block + 148, temporary, 6);
    block[154] = '\0';
    block[155] = ' ';
}

static abtar_status write_padding(FILE *fp, int64_t size) {
    char zeros[512];
    int pad = (int)((512 - (size % 512)) % 512);
    if (pad == 0) {
        return ABTAR_OK;
    }
    memset(zeros, 0, sizeof(zeros));
    return write_exact(fp, zeros, (size_t)pad);
}

static abtar_status write_header(FILE *fp, const char *name, const char *prefix, const char *linkname, int64_t size, int64_t mtime, uint32_t mode, char typeflag) {
    unsigned char block[512];
    uint64_t stored_size = size < 0 ? 0 : (uint64_t)size;
    memset(block, 0, sizeof(block));
    if (name) {
        strncpy((char *)block, name, 100);
    }
    if (put_octal((char *)block + 100, 8, mode & 0777) != 0) {
        return ABTAR_ERR_FORMAT;
    }
    if (put_octal((char *)block + 108, 8, 0) != 0 || put_octal((char *)block + 116, 8, 0) != 0) {
        return ABTAR_ERR_FORMAT;
    }
    if (size < 0 || put_octal((char *)block + 124, 12, stored_size) != 0) {
        memset(block + 124, '0', 11);
        block[135] = '\0';
    }
    if (put_octal((char *)block + 136, 12, mtime > 0 ? (uint64_t)mtime : 0) != 0) {
        return ABTAR_ERR_FORMAT;
    }
    block[156] = (unsigned char)typeflag;
    if (linkname) {
        strncpy((char *)block + 157, linkname, 100);
    }
    memcpy(block + 257, "ustar", 5);
    block[262] = '\0';
    block[263] = '0';
    block[264] = '0';
    memcpy(block + 265, "mobile", 6);
    memcpy(block + 297, "mobile", 6);
    if (put_octal((char *)block + 329, 8, 0) != 0 || put_octal((char *)block + 337, 8, 0) != 0) {
        return ABTAR_ERR_FORMAT;
    }
    if (prefix) {
        strncpy((char *)block + 345, prefix, 155);
    }
    put_checksum(block);
    return write_exact(fp, block, 512);
}

static int append_pax_record(char *destination, size_t capacity, size_t *used, const char *key, const char *value) {
    size_t key_length = strlen(key);
    size_t value_length = strlen(value);
    size_t digits = 1;
    size_t total = 0;
    int wrote;
    while (digits <= 12) {
        size_t width = 1;
        size_t probe;
        total = digits + 1 + key_length + 1 + value_length + 1;
        probe = total;
        while (probe >= 10) {
            width++;
            probe /= 10;
        }
        if (width == digits) {
            break;
        }
        digits = width;
    }
    if (digits > 12) {
        return -1;
    }
    if (*used + total + 1 > capacity) {
        return -1;
    }
    wrote = snprintf(destination + *used, capacity - *used, "%zu %s=%s\n", total, key, value);
    if (wrote < 0 || (size_t)wrote != total) {
        return -1;
    }
    *used += (size_t)wrote;
    return 0;
}

static abtar_status emit_entry(abtar_writer *writer, const char *archive_path, const char *link_target, int64_t size, int64_t mtime, uint32_t mode, char typeflag) {
    char stored[ABTAR_PATH_MAX];
    char name[100];
    char prefix[155];
    char linkname[100];
    char body[32768];
    char size_text[32];
    size_t body_used = 0;
    int need_path = 0;
    int need_link = 0;
    int need_size = 0;
    abtar_status status;
    size_t length;

    if (path_is_unsafe(archive_path)) {
        return ABTAR_ERR_PATH;
    }
    if (link_target && (strchr(link_target, '\n') || strlen(link_target) >= ABTAR_PATH_MAX)) {
        return ABTAR_ERR_PATH;
    }
    length = strlen(archive_path);
    if (length + 2 >= sizeof(stored)) {
        return ABTAR_ERR_PATH;
    }
    memcpy(stored, archive_path, length + 1);
    if (typeflag == '5' && stored[length - 1] != '/') {
        stored[length] = '/';
        stored[length + 1] = '\0';
    }

    memset(name, 0, sizeof(name));
    memset(prefix, 0, sizeof(prefix));
    memset(linkname, 0, sizeof(linkname));
    need_size = size > ABTAR_USTAR_MAX_SIZE;
    if (!is_ascii_path(stored) || split_ustar_name(stored, name, prefix) != 0) {
        need_path = 1;
    }
    if (link_target) {
        if (!is_ascii_path(link_target) || strlen(link_target) > 100) {
            need_link = 1;
        } else {
            memcpy(linkname, link_target, strlen(link_target));
        }
    }
    if (need_path || need_link || need_size) {
        if (need_path && append_pax_record(body, sizeof(body), &body_used, "path", stored) != 0) {
            return ABTAR_ERR_PATH;
        }
        if (need_link && append_pax_record(body, sizeof(body), &body_used, "linkpath", link_target) != 0) {
            return ABTAR_ERR_PATH;
        }
        if (need_size) {
            snprintf(size_text, sizeof(size_text), "%lld", (long long)size);
            if (append_pax_record(body, sizeof(body), &body_used, "size", size_text) != 0) {
                return ABTAR_ERR_FORMAT;
            }
        }
        if (need_path) {
            memset(name, 0, sizeof(name));
            memset(prefix, 0, sizeof(prefix));
            memcpy(name, "entry", 5);
        }
        if (need_link) {
            memset(linkname, 0, sizeof(linkname));
            memcpy(linkname, "link", 4);
        }
        status = write_header(writer->fp, "@PaxHeader", "", "", (int64_t)body_used, mtime, 0644, 'x');
        if (status != ABTAR_OK) {
            return status;
        }
        status = write_exact(writer->fp, body, body_used);
        if (status != ABTAR_OK) {
            return status;
        }
        status = write_padding(writer->fp, (int64_t)body_used);
        if (status != ABTAR_OK) {
            return status;
        }
    }
    return write_header(writer->fp, name, prefix, linkname, need_size ? -1 : size, mtime, mode ? mode : (typeflag == '5' ? 0755 : 0644), typeflag);
}

static void clear_pax(abtar_reader *reader) {
    reader->has_pax_path = 0;
    reader->has_pax_link = 0;
    reader->has_pax_size = 0;
    reader->pax_size = 0;
    reader->pax_path[0] = '\0';
    reader->pax_link[0] = '\0';
}

static abtar_status discard_bytes(FILE *fp, int64_t size) {
    char buffer[8192];
    while (size > 0) {
        size_t chunk = size > (int64_t)sizeof(buffer) ? sizeof(buffer) : (size_t)size;
        abtar_status status = read_exact(fp, buffer, chunk);
        if (status != ABTAR_OK) {
            return status;
        }
        size -= (int64_t)chunk;
    }
    return ABTAR_OK;
}

static abtar_status skip_payload(abtar_reader *reader) {
    abtar_status status;
    int pad;
    if (!reader->payload_pending) {
        return ABTAR_OK;
    }
    status = discard_bytes(reader->fp, reader->payload_left);
    if (status != ABTAR_OK) {
        return status;
    }
    pad = (int)((512 - (reader->payload_size % 512)) % 512);
    status = discard_bytes(reader->fp, pad);
    reader->payload_pending = 0;
    reader->payload_left = 0;
    return status;
}

static int64_t parse_octal(const unsigned char *field, int width) {
    int64_t value = 0;
    int index;
    for (index = 0; index < width; index++) {
        unsigned char byte = field[index];
        if (byte == '\0' || byte == ' ') {
            continue;
        }
        if (byte < '0' || byte > '7') {
            break;
        }
        value = (value << 3) + (byte - '0');
    }
    return value;
}

static int64_t parse_numeric(const unsigned char *field, int width) {
    int64_t value = 0;
    int index;
    if (field[0] == 0x80 || field[0] == 0xFF) {
        for (index = 1; index < width; index++) {
            value = (value << 8) | field[index];
        }
        if (field[0] == 0xFF) {
            value = -value;
        }
        return value;
    }
    return parse_octal(field, width);
}

static int checksum_matches(const unsigned char block[512]) {
    unsigned sum = 0;
    unsigned stored = 0;
    int index;
    int started = 0;
    for (index = 0; index < 512; index++) {
        if (index >= 148 && index < 156) {
            sum += (unsigned)' ';
        } else {
            sum += block[index];
        }
    }
    for (index = 148; index < 156; index++) {
        unsigned char byte = block[index];
        if (byte == '\0' || byte == ' ') {
            if (started) {
                break;
            }
            continue;
        }
        if (byte < '0' || byte > '7') {
            return 0;
        }
        started = 1;
        stored = stored * 8u + (unsigned)(byte - '0');
    }
    return stored == sum;
}

static void copy_field(char *destination, size_t capacity, const char *source, size_t source_length) {
    size_t length = 0;
    while (length < source_length && length + 1 < capacity && source[length] != '\0') {
        length++;
    }
    memcpy(destination, source, length);
    destination[length] = '\0';
}

static int parse_pax_body(char *body, size_t length, abtar_reader *reader) {
    size_t index = 0;
    while (index < length) {
        char *end = NULL;
        unsigned long record_length;
        char *record;
        char *separator;
        char *key;
        char *value;
        if (body[index] == '\0') {
            break;
        }
        record_length = strtoul(body + index, &end, 10);
        if (end == body + index || *end != ' ' || record_length < 5 || index + record_length > length) {
            return -1;
        }
        record = body + index;
        if (record[record_length - 1] != '\n') {
            return -1;
        }
        record[record_length - 1] = '\0';
        separator = strchr(end + 1, '=');
        if (!separator) {
            return -1;
        }
        *separator = '\0';
        key = end + 1;
        value = separator + 1;
        if (strcmp(key, "path") == 0) {
            if (strlen(value) >= sizeof(reader->pax_path)) {
                return -1;
            }
            memcpy(reader->pax_path, value, strlen(value) + 1);
            reader->has_pax_path = 1;
        } else if (strcmp(key, "linkpath") == 0) {
            if (strlen(value) >= sizeof(reader->pax_link)) {
                return -1;
            }
            memcpy(reader->pax_link, value, strlen(value) + 1);
            reader->has_pax_link = 1;
        } else if (strcmp(key, "size") == 0) {
            int64_t parsed = 0;
            const char *cursor = value;
            if (*cursor == '+') {
                cursor++;
            }
            while (*cursor >= '0' && *cursor <= '9') {
                parsed = parsed * 10 + (*cursor - '0');
                cursor++;
            }
            reader->pax_size = parsed;
            reader->has_pax_size = 1;
        }
        index += record_length;
    }
    return 0;
}

static int join_destination(char *destination, size_t capacity, const char *root, const char *relative) {
    size_t root_length = strlen(root);
    size_t relative_length;
    while (root_length > 0 && (root[root_length - 1] == '/' || root[root_length - 1] == '\\')) {
        root_length--;
    }
    while (*relative == '/') {
        relative++;
    }
    relative_length = strlen(relative);
    if (root_length + 1 + relative_length + 1 > capacity) {
        return -1;
    }
    memcpy(destination, root, root_length);
    destination[root_length] = '/';
    memcpy(destination + root_length + 1, relative, relative_length + 1);
    return 0;
}

static abtar_status ensure_directory(const char *directory) {
    char buffer[ABTAR_PATH_MAX];
    size_t length = strlen(directory);
    size_t index;
    if (length == 0 || length >= sizeof(buffer)) {
        return ABTAR_ERR_PATH;
    }
    memcpy(buffer, directory, length + 1);
    for (index = 1; index < length; index++) {
        if (buffer[index] == '/' || buffer[index] == '\\') {
            buffer[index] = '\0';
            if (buffer[0] != '\0' && ab_mkdir(buffer) != 0 && errno != EEXIST) {
                return ABTAR_ERR_IO;
            }
            buffer[index] = '/';
        }
    }
    if (ab_mkdir(buffer) != 0 && errno != EEXIST) {
        return ABTAR_ERR_IO;
    }
    return ABTAR_OK;
}

static abtar_status ensure_parent(const char *file_path) {
    char buffer[ABTAR_PATH_MAX];
    char *slash;
    size_t length = strlen(file_path);
    if (length == 0 || length >= sizeof(buffer)) {
        return ABTAR_ERR_PATH;
    }
    memcpy(buffer, file_path, length + 1);
    slash = strrchr(buffer, '/');
    if (!slash) {
        slash = strrchr(buffer, '\\');
    }
    if (!slash) {
        return ABTAR_OK;
    }
    *slash = '\0';
    if (buffer[0] == '\0') {
        return ABTAR_OK;
    }
    return ensure_directory(buffer);
}

static void report_progress(abtar_reader *reader, int64_t amount) {
    reader->payload_written += amount;
    if (reader->progress) {
        reader->progress(reader->progress_ctx, reader->payload_written);
    }
}

static void report_writer_progress(abtar_writer *writer, int64_t amount) {
    writer->payload_written += amount;
    if (writer->progress) {
        writer->progress(writer->progress_ctx, writer->payload_written);
    }
}

abtar_status abtar_writer_create(const char *path, abtar_writer **out_writer) {
    abtar_writer *writer;
    FILE *fp;
    if (!path || !out_writer) {
        return ABTAR_ERR_PATH;
    }
    fp = fopen(path, "wb");
    if (!fp) {
        return ABTAR_ERR_IO;
    }
    writer = (abtar_writer *)calloc(1, sizeof(*writer));
    if (!writer) {
        fclose(fp);
        return ABTAR_ERR_NOMEM;
    }
    writer->fp = fp;
    *out_writer = writer;
    return ABTAR_OK;
}

void abtar_writer_set_progress(abtar_writer *writer, abtar_progress_fn fn, void *ctx) {
    if (!writer) {
        return;
    }
    writer->progress = fn;
    writer->progress_ctx = ctx;
}

void abtar_writer_set_cancel(abtar_writer *writer, abtar_cancel_fn fn, void *ctx) {
    if (!writer) {
        return;
    }
    writer->cancel = fn;
    writer->cancel_ctx = ctx;
}

abtar_status abtar_writer_add_dir(abtar_writer *writer, const char *archive_path, uint32_t mode, int64_t mtime) {
    if (!writer || !writer->fp) {
        return ABTAR_ERR_IO;
    }
    if (cancelled(writer)) {
        return ABTAR_ERR_CANCELLED;
    }
    return emit_entry(writer, archive_path, NULL, 0, mtime, mode ? mode : 0755, '5');
}

abtar_status abtar_writer_add_symlink(abtar_writer *writer, const char *archive_path, const char *link_target, int64_t mtime) {
    if (!writer || !writer->fp) {
        return ABTAR_ERR_IO;
    }
    if (!link_target || !link_target[0]) {
        return ABTAR_ERR_PATH;
    }
    if (cancelled(writer)) {
        return ABTAR_ERR_CANCELLED;
    }
    return emit_entry(writer, archive_path, link_target, 0, mtime, 0777, '2');
}

abtar_status abtar_writer_add_file(abtar_writer *writer, const char *archive_path, const char *source_path, uint32_t mode, int64_t mtime) {
    FILE *input = NULL;
    abtar_status status;
    int64_t size;
    char buffer[262144];
#if defined(_WIN32)
    struct __stat64 info;
    int descriptor = -1;
#else
    struct stat info;
    int descriptor = -1;
#endif
    if (!writer || !writer->fp || !source_path) {
        return ABTAR_ERR_IO;
    }
    if (cancelled(writer)) {
        return ABTAR_ERR_CANCELLED;
    }
#if defined(_WIN32)
    input = fopen(source_path, "rb");
    if (!input) {
        return ABTAR_ERR_IO;
    }
    descriptor = _fileno(input);
    if (_fstat64(descriptor, &info) != 0) {
        fclose(input);
        return ABTAR_ERR_IO;
    }
#else
    descriptor = open(source_path, O_RDONLY | O_NOFOLLOW);
    if (descriptor < 0) {
        return ABTAR_ERR_IO;
    }
    input = fdopen(descriptor, "rb");
    if (!input) {
        close(descriptor);
        return ABTAR_ERR_IO;
    }
    if (fstat(descriptor, &info) != 0) {
        fclose(input);
        return ABTAR_ERR_IO;
    }
#endif
    size = (int64_t)info.st_size;
    if (size < 0) {
        fclose(input);
        return ABTAR_ERR_IO;
    }
    status = emit_entry(writer, archive_path, NULL, size, mtime, mode ? mode : 0644, '0');
    if (status != ABTAR_OK) {
        fclose(input);
        return status;
    }
    while (size > 0) {
        size_t chunk = size > (int64_t)sizeof(buffer) ? sizeof(buffer) : (size_t)size;
        size_t got;
        if (cancelled(writer)) {
            fclose(input);
            return ABTAR_ERR_CANCELLED;
        }
        got = fread(buffer, 1, chunk, input);
        if (got != chunk) {
            fclose(input);
            return ABTAR_ERR_IO;
        }
        status = write_exact(writer->fp, buffer, got);
        if (status != ABTAR_OK) {
            fclose(input);
            return status;
        }
        size -= (int64_t)got;
        report_writer_progress(writer, (int64_t)got);
    }
    fclose(input);
    return write_padding(writer->fp, (int64_t)info.st_size);
}

abtar_status abtar_writer_finish(abtar_writer *writer) {
    char zeros[1024];
    abtar_status status = ABTAR_OK;
    if (!writer) {
        return ABTAR_ERR_IO;
    }
    if (writer->fp) {
        memset(zeros, 0, sizeof(zeros));
        status = write_exact(writer->fp, zeros, sizeof(zeros));
        if (fclose(writer->fp) != 0 && status == ABTAR_OK) {
            status = ABTAR_ERR_IO;
        }
        writer->fp = NULL;
    }
    free(writer);
    return status;
}

void abtar_writer_cancel(abtar_writer *writer) {
    if (!writer) {
        return;
    }
    if (writer->fp) {
        fclose(writer->fp);
        writer->fp = NULL;
    }
    free(writer);
}

abtar_status abtar_reader_open(const char *path, abtar_reader **out_reader) {
    abtar_reader *reader;
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return ABTAR_ERR_IO;
    }
    reader = (abtar_reader *)calloc(1, sizeof(*reader));
    if (!reader) {
        fclose(fp);
        return ABTAR_ERR_NOMEM;
    }
    reader->fp = fp;
    *out_reader = reader;
    return ABTAR_OK;
}

void abtar_reader_set_progress(abtar_reader *reader, abtar_progress_fn fn, void *ctx) {
    if (!reader) {
        return;
    }
    reader->progress = fn;
    reader->progress_ctx = ctx;
}

abtar_status abtar_reader_next(abtar_reader *reader, abtar_entry *out_entry) {
    if (!reader || !reader->fp || !out_entry) {
        return ABTAR_ERR_IO;
    }
    if (reader->payload_pending) {
        abtar_status skipped = skip_payload(reader);
        if (skipped != ABTAR_OK) {
            return skipped;
        }
    }
    for (;;) {
        unsigned char block[512];
        size_t got = fread(block, 1, 512, reader->fp);
        char typeflag;
        char ustar_name[101];
        char ustar_prefix[156];
        char ustar_link[101];
        int64_t header_size;
        int64_t entry_size;
        int all_zero = 1;
        size_t index;
        if (got == 0) {
            return ABTAR_EOF;
        }
        if (got < 512) {
            return ABTAR_ERR_FORMAT;
        }
        for (index = 0; index < 512; index++) {
            if (block[index] != 0) {
                all_zero = 0;
                break;
            }
        }
        if (all_zero) {
            return ABTAR_EOF;
        }
        if (!checksum_matches(block)) {
            return ABTAR_ERR_FORMAT;
        }
        typeflag = (char)block[156];
        if (typeflag == '\0') {
            typeflag = '0';
        }
        header_size = parse_numeric(block + 124, 12);
        if (typeflag == 'x' || typeflag == 'g' || typeflag == 'L' || typeflag == 'K') {
            char *body = (char *)malloc((size_t)header_size + 1);
            abtar_status status;
            int pad;
            if (header_size < 0 || header_size > 32 * 1024 * 1024) {
                return ABTAR_ERR_FORMAT;
            }
            if (!body) {
                return ABTAR_ERR_NOMEM;
            }
            status = read_exact(reader->fp, body, (size_t)header_size);
            if (status != ABTAR_OK) {
                free(body);
                return status;
            }
            body[header_size] = '\0';
            pad = (int)((512 - (header_size % 512)) % 512);
            status = discard_bytes(reader->fp, pad);
            if (status != ABTAR_OK) {
                free(body);
                return status;
            }
            if (typeflag == 'x' || typeflag == 'g') {
                if (parse_pax_body(body, (size_t)header_size, reader) != 0) {
                    free(body);
                    return ABTAR_ERR_FORMAT;
                }
            } else if (typeflag == 'L') {
                if ((size_t)header_size >= sizeof(reader->pax_path)) {
                    free(body);
                    return ABTAR_ERR_FORMAT;
                }
                memcpy(reader->pax_path, body, (size_t)header_size);
                reader->pax_path[header_size] = '\0';
                reader->has_pax_path = 1;
            } else {
                if ((size_t)header_size >= sizeof(reader->pax_link)) {
                    free(body);
                    return ABTAR_ERR_FORMAT;
                }
                memcpy(reader->pax_link, body, (size_t)header_size);
                reader->pax_link[header_size] = '\0';
                reader->has_pax_link = 1;
            }
            free(body);
            continue;
        }

        copy_field(ustar_name, sizeof(ustar_name), (const char *)block, 100);
        copy_field(ustar_prefix, sizeof(ustar_prefix), (const char *)block + 345, 155);
        copy_field(ustar_link, sizeof(ustar_link), (const char *)block + 157, 100);
        reader->path_buf[0] = '\0';
        if (ustar_prefix[0]) {
            snprintf(reader->path_buf, sizeof(reader->path_buf), "%s/%s", ustar_prefix, ustar_name);
        } else {
            snprintf(reader->path_buf, sizeof(reader->path_buf), "%s", ustar_name);
        }
        if (reader->has_pax_path) {
            snprintf(reader->path_buf, sizeof(reader->path_buf), "%s", reader->pax_path);
        }
        length_trim_slash(reader->path_buf);
        if (reader->has_pax_link) {
            snprintf(reader->link_buf, sizeof(reader->link_buf), "%s", reader->pax_link);
        } else {
            snprintf(reader->link_buf, sizeof(reader->link_buf), "%s", ustar_link);
        }
        entry_size = reader->has_pax_size ? reader->pax_size : header_size;
        if (path_is_unsafe(reader->path_buf)) {
            clear_pax(reader);
            return ABTAR_ERR_PATH;
        }
        memset(&reader->current, 0, sizeof(reader->current));
        reader->current.path = reader->path_buf;
        reader->current.link_target = (typeflag == '2') ? reader->link_buf : NULL;
        reader->current.size = typeflag == '0' ? entry_size : 0;
        reader->current.mtime = parse_numeric(block + 136, 12);
        reader->current.mode = (uint32_t)parse_numeric(block + 100, 8);
        reader->current.typeflag = typeflag;
        clear_pax(reader);
        if (typeflag == '0' && entry_size > 0) {
            reader->payload_pending = 1;
            reader->payload_size = entry_size;
            reader->payload_left = entry_size;
        } else {
            reader->payload_pending = 0;
            reader->payload_size = 0;
            reader->payload_left = 0;
        }
        *out_entry = reader->current;
        return ABTAR_OK;
    }
}

abtar_status abtar_reader_slurp_current(abtar_reader *reader, void **out_bytes, int64_t *out_size, int64_t max_size) {
    unsigned char *buffer;
    abtar_status status;
    int pad;
    if (!reader || !reader->payload_pending || reader->current.typeflag != '0') {
        return ABTAR_ERR_FORMAT;
    }
    if (reader->payload_size > max_size) {
        status = skip_payload(reader);
        return status == ABTAR_OK ? ABTAR_ERR_FORMAT : status;
    }
    buffer = (unsigned char *)malloc((size_t)reader->payload_size + 1);
    if (!buffer) {
        return ABTAR_ERR_NOMEM;
    }
    status = read_exact(reader->fp, buffer, (size_t)reader->payload_size);
    if (status != ABTAR_OK) {
        free(buffer);
        return status;
    }
    buffer[reader->payload_size] = '\0';
    pad = (int)((512 - (reader->payload_size % 512)) % 512);
    status = discard_bytes(reader->fp, pad);
    if (status != ABTAR_OK) {
        free(buffer);
        return status;
    }
    reader->payload_pending = 0;
    reader->payload_left = 0;
    report_progress(reader, reader->payload_size);
    *out_bytes = buffer;
    if (out_size) {
        *out_size = reader->payload_size;
    }
    return ABTAR_OK;
}

abtar_status abtar_reader_extract_current(abtar_reader *reader, const char *dest_root) {
    char destination[ABTAR_PATH_MAX];
    FILE *output = NULL;
    abtar_status status;
    int pad;
    if (!reader || !dest_root || !reader->current.path) {
        return ABTAR_ERR_PATH;
    }
    if (join_destination(destination, sizeof(destination), dest_root, reader->current.path) != 0) {
        return ABTAR_ERR_PATH;
    }
    if (reader->current.typeflag == '5') {
        return ensure_directory(destination);
    }
    if (reader->current.typeflag == '2') {
#if defined(_WIN32)
        (void)destination;
        return ABTAR_ERR_UNSUPPORTED;
#else
        status = ensure_parent(destination);
        if (status != ABTAR_OK) {
            return status;
        }
        unlink(destination);
        if (symlink(reader->current.link_target ? reader->current.link_target : "", destination) != 0) {
            return ABTAR_ERR_IO;
        }
        return ABTAR_OK;
#endif
    }
    if (reader->current.typeflag != '0') {
        return ABTAR_ERR_UNSUPPORTED;
    }
    status = ensure_parent(destination);
    if (status != ABTAR_OK) {
        return status;
    }
    output = fopen(destination, "wb");
    if (!output) {
        return ABTAR_ERR_IO;
    }
    while (reader->payload_left > 0) {
        char buffer[262144];
        size_t chunk = reader->payload_left > (int64_t)sizeof(buffer) ? sizeof(buffer) : (size_t)reader->payload_left;
        status = read_exact(reader->fp, buffer, chunk);
        if (status != ABTAR_OK) {
            fclose(output);
            return status;
        }
        status = write_exact(output, buffer, chunk);
        if (status != ABTAR_OK) {
            fclose(output);
            return status;
        }
        reader->payload_left -= (int64_t)chunk;
        report_progress(reader, (int64_t)chunk);
    }
    if (fclose(output) != 0) {
        return ABTAR_ERR_IO;
    }
    pad = (int)((512 - (reader->payload_size % 512)) % 512);
    status = discard_bytes(reader->fp, pad);
    reader->payload_pending = 0;
#if !defined(_WIN32)
    if (reader->current.mode) {
        chmod(destination, reader->current.mode & 0777);
    }
#endif
    return status;
}

void abtar_reader_close(abtar_reader *reader) {
    if (!reader) {
        return;
    }
    if (reader->fp) {
        fclose(reader->fp);
    }
    free(reader);
}
