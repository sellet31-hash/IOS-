#include "../src/abtar.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define make_dir(path) _mkdir(path)
#else
#include <sys/stat.h>
#define make_dir(path) mkdir((path), 0755)
#endif

static int failures = 0;

static void expect(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

static int write_file(const char *path, const void *bytes, size_t size) {
    FILE *file = fopen(path, "wb");
    if (!file) {
        return -1;
    }
    if (size > 0 && fwrite(bytes, 1, size, file) != size) {
        fclose(file);
        return -1;
    }
    if (fclose(file) != 0) {
        return -1;
    }
    return 0;
}

static int read_file(const char *path, char *buffer, size_t capacity, size_t *out_size) {
    FILE *file = fopen(path, "rb");
    size_t got;
    if (!file) {
        return -1;
    }
    got = fread(buffer, 1, capacity, file);
    fclose(file);
    *out_size = got;
    return 0;
}

static int slurp_is(abtar_reader *reader, const void *expected, size_t expected_size) {
    void *bytes = NULL;
    int64_t size = 0;
    abtar_status status = abtar_reader_slurp_current(reader, &bytes, &size, 2 * 1024 * 1024);
    int matches = status == ABTAR_OK && size == (int64_t)expected_size && memcmp(bytes, expected, expected_size) == 0;
    free(bytes);
    return matches;
}

static int cancel_immediately(void *ctx) {
    (void)ctx;
    return 1;
}

int main(int argc, char **argv) {
    const char *root = argc > 1 ? argv[1] : "test-out";
    char source_dir[512];
    char archive_path[512];
    char extracted_dir[512];
    char hello_path[512];
    char unicode_source[512];
    char long_source[512];
    char empty_source[512];
    char blob_source[512];
    char sized_source[512];
    char manifest_source[512];
    char long_archive_path[512];
    char extracted_hello[512];
    char corrupt_path[512];
    char blob[1000];
    char sized[200];
    char hello_buffer[32];
    size_t hello_size = 0;
    const char *unicode_archive = "container/\xe6\x96\x87\xe6\xa1\xa3.txt";
    abtar_writer *writer = NULL;
    abtar_reader *reader = NULL;
    abtar_entry entry;
    abtar_status status;
    int index;

    memset(blob, 'a', sizeof(blob));
    memset(sized, 'Z', sizeof(sized));
    memset(long_archive_path, 0, sizeof(long_archive_path));
    memcpy(long_archive_path, "container/", 10);
    memset(long_archive_path + 10, 'p', 240);
    memcpy(long_archive_path + 250, "/file.txt", 9);

    snprintf(source_dir, sizeof(source_dir), "%s/files", root);
    snprintf(archive_path, sizeof(archive_path), "%s/sample.tar", root);
    snprintf(extracted_dir, sizeof(extracted_dir), "%s/extracted", root);
    snprintf(corrupt_path, sizeof(corrupt_path), "%s/corrupt.tar", root);
    snprintf(hello_path, sizeof(hello_path), "%s/hello.txt", source_dir);
    snprintf(unicode_source, sizeof(unicode_source), "%s/unicode.txt", source_dir);
    snprintf(long_source, sizeof(long_source), "%s/long.txt", source_dir);
    snprintf(empty_source, sizeof(empty_source), "%s/empty.dat", source_dir);
    snprintf(blob_source, sizeof(blob_source), "%s/blob.bin", source_dir);
    snprintf(sized_source, sizeof(sized_source), "%s/sized.bin", source_dir);
    snprintf(manifest_source, sizeof(manifest_source), "%s/manifest.plist", source_dir);
    snprintf(extracted_hello, sizeof(extracted_hello), "%s/container/Documents/hello.txt", extracted_dir);

    make_dir(root);
    make_dir(source_dir);
    expect(write_file(manifest_source, "manifest", 8) == 0, "write manifest");
    expect(write_file(hello_path, "hello", 5) == 0, "write hello");
    expect(write_file(unicode_source, "unicode", 7) == 0, "write unicode");
    expect(write_file(long_source, "long", 4) == 0, "write long");
    expect(write_file(empty_source, "", 0) == 0, "write empty");
    expect(write_file(blob_source, blob, sizeof(blob)) == 0, "write blob");
    expect(write_file(sized_source, sized, sizeof(sized)) == 0, "write sized");

    status = abtar_writer_create(archive_path, &writer);
    expect(status == ABTAR_OK, "create archive");
    if (status == ABTAR_OK) {
        expect(abtar_writer_add_file(writer, "manifest.plist", manifest_source, 0644, 1700000000) == ABTAR_OK, "add manifest");
        expect(abtar_writer_add_dir(writer, "container/Documents", 0755, 1700000000) == ABTAR_OK, "add documents dir");
        expect(abtar_writer_add_file(writer, "container/Documents/hello.txt", hello_path, 0644, 1700000000) == ABTAR_OK, "add hello");
        expect(abtar_writer_add_file(writer, unicode_archive, unicode_source, 0644, 1700000000) == ABTAR_OK, "add unicode");
        expect(abtar_writer_add_file(writer, long_archive_path, long_source, 0644, 1700000000) == ABTAR_OK, "add long path");
        expect(abtar_writer_add_file(writer, "container/Documents/empty.dat", empty_source, 0644, 1700000000) == ABTAR_OK, "add empty");
        expect(abtar_writer_add_file(writer, "container/Documents/blob.bin", blob_source, 0644, 1700000000) == ABTAR_OK, "add blob");
        expect(abtar_writer_add_file(writer, "container/Documents/sized.bin", sized_source, 0644, 1700000000) == ABTAR_OK, "add sized");
        expect(abtar_writer_add_dir(writer, "container/Documents/Sub", 0755, 1700000000) == ABTAR_OK, "add subdir");
        expect(abtar_writer_add_symlink(writer, "container/Documents/link", "hello.txt", 1700000000) == ABTAR_OK, "add symlink");
        expect(abtar_writer_add_file(writer, "../evil.txt", hello_path, 0644, 1700000000) == ABTAR_ERR_PATH, "reject traversal");
        status = abtar_writer_finish(writer);
        writer = NULL;
        expect(status == ABTAR_OK, "finish archive");
    }

    status = abtar_reader_open(archive_path, &reader);
    expect(status == ABTAR_OK, "open archive");
    if (status == ABTAR_OK) {
        const char *paths[] = {
            "manifest.plist",
            "container/Documents",
            "container/Documents/hello.txt",
            unicode_archive,
            long_archive_path,
            "container/Documents/empty.dat",
            "container/Documents/blob.bin",
            "container/Documents/sized.bin",
            "container/Documents/Sub",
            "container/Documents/link"
        };
        for (index = 0; index < 10; index++) {
            status = abtar_reader_next(reader, &entry);
            expect(status == ABTAR_OK, "next entry");
            if (status != ABTAR_OK) {
                break;
            }
            expect(strcmp(entry.path, paths[index]) == 0, paths[index]);
            if (index == 0) {
                expect(slurp_is(reader, "manifest", 8), "manifest bytes");
            } else if (index == 2) {
                expect(slurp_is(reader, "hello", 5), "hello bytes");
            } else if (index == 3) {
                expect(slurp_is(reader, "unicode", 7), "unicode bytes");
            } else if (index == 4) {
                expect(slurp_is(reader, "long", 4), "long bytes");
            } else if (index == 5) {
                expect(entry.size == 0 && entry.typeflag == '0', "empty metadata");
            } else if (index == 6) {
                expect(entry.size == 1000, "blob size");
                expect(slurp_is(reader, blob, sizeof(blob)), "blob bytes");
            } else if (index == 7) {
                expect(entry.size == 200, "sized size");
                expect(slurp_is(reader, sized, sizeof(sized)), "sized bytes");
            } else if (index == 1 || index == 8) {
                expect(entry.typeflag == '5', "directory type");
            } else if (index == 9) {
                expect(entry.typeflag == '2', "symlink type");
                expect(entry.link_target && strcmp(entry.link_target, "hello.txt") == 0, "symlink target");
            }
        }
        expect(abtar_reader_next(reader, &entry) == ABTAR_EOF, "end of archive");
        abtar_reader_close(reader);
        reader = NULL;
    }

    make_dir(extracted_dir);
    status = abtar_reader_open(archive_path, &reader);
    expect(status == ABTAR_OK, "reopen for extract");
    if (status == ABTAR_OK) {
        while ((status = abtar_reader_next(reader, &entry)) == ABTAR_OK) {
            if (entry.typeflag == '2') {
                continue;
            }
            if (strchr(entry.path, '\xe6') != NULL || strlen(entry.path) > 200) {
                continue;
            }
            status = abtar_reader_extract_current(reader, extracted_dir);
            expect(status == ABTAR_OK, "extract entry");
            if (status != ABTAR_OK) {
                fprintf(stderr, "extract failed for %s\n", entry.path);
                break;
            }
        }
        expect(status == ABTAR_EOF, "extract finished");
        abtar_reader_close(reader);
    }
    expect(read_file(extracted_hello, hello_buffer, sizeof(hello_buffer), &hello_size) == 0, "read extracted hello");
    expect(hello_size == 5 && memcmp(hello_buffer, "hello", 5) == 0, "extracted hello matches");

    {
        FILE *source = fopen(archive_path, "rb");
        FILE *dest = fopen(corrupt_path, "wb");
        unsigned char buffer[4096];
        size_t got;
        expect(source && dest, "open corrupt copy");
        if (source && dest) {
            got = fread(buffer, 1, sizeof(buffer), source);
            if (got > 20) {
                buffer[20] ^= 0x20;
            }
            fwrite(buffer, 1, got, dest);
            while ((got = fread(buffer, 1, sizeof(buffer), source)) > 0) {
                fwrite(buffer, 1, got, dest);
            }
        }
        if (source) fclose(source);
        if (dest) fclose(dest);
        status = abtar_reader_open(corrupt_path, &reader);
        expect(status == ABTAR_OK, "open corrupt");
        if (status == ABTAR_OK) {
            expect(abtar_reader_next(reader, &entry) == ABTAR_ERR_FORMAT, "corrupt checksum");
            abtar_reader_close(reader);
        }
    }

    status = abtar_writer_create(corrupt_path, &writer);
    expect(status == ABTAR_OK, "create cancel archive");
    if (status == ABTAR_OK) {
        abtar_writer_set_cancel(writer, cancel_immediately, NULL);
        expect(abtar_writer_add_file(writer, "container/Documents/hello.txt", hello_path, 0644, 1700000000) == ABTAR_ERR_CANCELLED, "cancel write");
        abtar_writer_cancel(writer);
    }

    if (failures) {
        fprintf(stderr, "%d checks failed\n", failures);
        return 1;
    }
    printf("abtar checks passed\n");
    return 0;
}
