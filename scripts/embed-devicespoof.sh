#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${THEOS_STAGING_DIR:-}"
THEOS="${THEOS:-}"

if [[ -z "${THEOS}" || ! -d "${THEOS}" ]]; then
  echo "THEOS is not set" >&2
  exit 1
fi
if [[ -z "${STAGE}" || ! -d "${STAGE}" ]]; then
  echo "THEOS_STAGING_DIR is not a directory: ${STAGE}" >&2
  exit 1
fi

env -u THEOS_STAGING_DIR make -C "${ROOT}/DeviceSpoof" all FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

dylib=""
newest=0
while IFS= read -r -d '' file; do
  modified=$(stat -f %m "${file}")
  if (( modified > newest )); then
    newest=${modified}
    dylib=${file}
  fi
done < <(find "${ROOT}/DeviceSpoof/.theos" -type f -name DeviceSpoof.dylib ! -path '*/packages/*' -print0)

if [[ -z "${dylib}" || ! -f "${dylib}" ]]; then
  echo "DeviceSpoof.dylib was not built" >&2
  exit 1
fi

app="$(find "${STAGE}" -name AppBackup.app -type d -print -quit)"
if [[ -z "${app}" ]]; then
  echo "Could not find AppBackup.app under ${STAGE}" >&2
  exit 1
fi

cp -f "${dylib}" "${app}/DeviceSpoof.dylib"
cp -f "${ROOT}/DeviceSpoof/DeviceSpoof.plist" "${app}/DeviceSpoof.plist"
echo "Embedded ${dylib}"
