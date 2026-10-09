import sys
import tarfile


def main() -> None:
    path = sys.argv[1]
    unicode_name = "container/\u6587\u6863.txt"
    long_name = "container/" + ("p" * 240) + "/file.txt"
    with tarfile.open(path, "r:") as archive:
        names = {name.rstrip("/") for name in archive.getnames()}
        expected = {
            "manifest.plist",
            "container/Documents",
            "container/Documents/hello.txt",
            unicode_name,
            long_name,
            "container/Documents/empty.dat",
            "container/Documents/blob.bin",
            "container/Documents/sized.bin",
            "container/Documents/Sub",
            "container/Documents/link",
        }
        missing = expected - names
        if missing:
            raise SystemExit("missing entries: " + ", ".join(sorted(missing)))

        def read(name: str) -> bytes:
            extracted = archive.extractfile(name)
            if extracted is None:
                raise SystemExit("no content for " + name)
            return extracted.read()

        if read("manifest.plist") != b"manifest":
            raise SystemExit("manifest mismatch")
        if read("container/Documents/hello.txt") != b"hello":
            raise SystemExit("hello mismatch")
        if read(unicode_name) != b"unicode":
            raise SystemExit("unicode mismatch")
        if read(long_name) != b"long":
            raise SystemExit("long path mismatch")
        if read("container/Documents/empty.dat") != b"":
            raise SystemExit("empty mismatch")
        if read("container/Documents/blob.bin") != b"a" * 1000:
            raise SystemExit("blob mismatch")
        if read("container/Documents/sized.bin") != b"Z" * 200:
            raise SystemExit("sized mismatch")
        link = archive.getmember("container/Documents/link")
        if not link.issym() or link.linkname != "hello.txt":
            raise SystemExit("symlink mismatch: " + repr(link.linkname))
        if not archive.getmember("container/Documents/Sub").isdir():
            raise SystemExit("directory mismatch")
    print("python tarfile checks passed")


if __name__ == "__main__":
    main()
