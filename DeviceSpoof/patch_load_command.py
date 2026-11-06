import pathlib
import sys

old = b"@rpath/CydiaSubstrate.framework/CydiaSubstrate"
new = b"@loader_path/libellekit.dylib"
root = pathlib.Path(sys.argv[1])
found = list(root.rglob("DeviceSpoof.dylib"))
if not found:
    sys.exit("DeviceSpoof.dylib not found")
for path in found:
    data = path.read_bytes()
    if old not in data:
        sys.exit(f"substrate load command not found in {path}")
    path.write_bytes(data.replace(old, new + b"\x00" * (len(old) - len(new))))
    print(f"rewrote {path}")
