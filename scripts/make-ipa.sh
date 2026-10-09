#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${THEOS_STAGING_DIR:-}"

if [[ -z "${STAGE}" || ! -d "${STAGE}" ]]; then
  echo "THEOS_STAGING_DIR is not a directory: ${STAGE}" >&2
  exit 1
fi

APP="$(find "${STAGE}" -name "AppBackup.app" -type d -print -quit)"
if [[ -z "${APP}" ]]; then
  echo "Could not find AppBackup.app under ${STAGE}" >&2
  find "${STAGE}" -maxdepth 4 -print >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
mkdir -p "${WORKDIR}/Payload"
cp -R "${APP}" "${WORKDIR}/Payload/AppBackup.app"
mkdir -p "${ROOT}/packages"
rm -f "${ROOT}/packages/AppBackup.ipa"
(
  cd "${WORKDIR}"
  zip -qry "${ROOT}/packages/AppBackup.ipa" Payload
)
rm -rf "${WORKDIR}"
echo "Created ${ROOT}/packages/AppBackup.ipa"
