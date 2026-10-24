#!/bin/bash
set -eu
root="${THEOS_STAGING_DIR}"
libdir="$root/Library/MobileSubstrate/DynamicLibraries"
inject="$root/usr/lib/TweakInject"
if [ ! -f "$libdir/DeviceSpoof.dylib" ]; then
  libdir="$root/var/jb/Library/MobileSubstrate/DynamicLibraries"
  inject="$root/var/jb/usr/lib/TweakInject"
fi
if [ ! -f "$libdir/DeviceSpoof.dylib" ]; then
  echo "DeviceSpoof dylib missing from staging: $root"
  find "$root" -name 'DeviceSpoof.*' -print || true
  exit 1
fi
mkdir -p "$inject"
cp "$libdir/DeviceSpoof.dylib" "$libdir/DeviceSpoof.plist" "$inject/"
