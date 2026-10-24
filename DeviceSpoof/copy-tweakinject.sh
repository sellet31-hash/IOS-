#!/bin/bash
set -eu
root="${1:-${THEOS_STAGING_DIR:-}}"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  echo "THEOS_STAGING_DIR was not passed to copy-tweakinject.sh"
  exit 1
fi
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
