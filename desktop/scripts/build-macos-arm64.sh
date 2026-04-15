#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DESKTOP_DIR}/.." && pwd)"

TARGET_TRIPLE="aarch64-apple-darwin"
TAURI_TARGET_DIR="${DESKTOP_DIR}/src-tauri/target"
CANONICAL_OUTPUT_DIR="${DESKTOP_DIR}/build-artifacts/macos-arm64"
APP_BUNDLE_NAME="Claude Code Haha.app"
APP_BUNDLE_ID="com.claude-code-haha.desktop"

usage() {
  cat <<'EOF'
Build Claude Code Haha desktop for macOS Apple Silicon and output a DMG.

Usage:
  ./desktop/scripts/build-macos-arm64.sh [extra tauri build args...]

Environment:
  SKIP_INSTALL=1   Skip `bun install` in the repo root and desktop app.
  SIGN_BUILD=1     Remove the default `--no-sign` flag and allow signed builds.
  OPEN_OUTPUT=1    Open the canonical artifact output directory in Finder after a successful build.

Examples:
  ./desktop/scripts/build-macos-arm64.sh
  SKIP_INSTALL=1 ./desktop/scripts/build-macos-arm64.sh
  SIGN_BUILD=1 ./desktop/scripts/build-macos-arm64.sh --skip-stapling
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[build-macos-arm64] This script must run on macOS." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "[build-macos-arm64] This script is intended for Apple Silicon hosts (arm64)." >&2
  exit 1
fi

for command in bun cargo rustc codesign hdiutil; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "[build-macos-arm64] Missing required command: ${command}" >&2
    exit 1
  fi
done

if [[ "${SKIP_INSTALL:-0}" != "1" ]]; then
  echo "[build-macos-arm64] Installing root dependencies..."
  (cd "${REPO_ROOT}" && bun install)

  echo "[build-macos-arm64] Installing desktop dependencies..."
  (cd "${DESKTOP_DIR}" && bun install)
fi

TAURI_ARGS=(
  bunx
  tauri
  build
  --target
  "${TARGET_TRIPLE}"
  --bundles
  app,dmg
  --ci
)

if [[ "${SIGN_BUILD:-0}" != "1" ]]; then
  TAURI_ARGS+=(--no-sign)
fi

if [[ "$#" -gt 0 ]]; then
  TAURI_ARGS+=("$@")
fi

echo "[build-macos-arm64] Building DMG for ${TARGET_TRIPLE}..."
(
  cd "${DESKTOP_DIR}"
  export TAURI_ENV_TARGET_TRIPLE="${TARGET_TRIPLE}"
  "${TAURI_ARGS[@]}"
)

TARGETED_DMG_DIR="${TAURI_TARGET_DIR}/${TARGET_TRIPLE}/release/bundle/dmg"
FALLBACK_DMG_DIR="${TAURI_TARGET_DIR}/release/bundle/dmg"
TARGETED_APP_DIR="${TAURI_TARGET_DIR}/${TARGET_TRIPLE}/release/bundle/macos"
FALLBACK_APP_DIR="${TAURI_TARGET_DIR}/release/bundle/macos"
LEGACY_BUNDLE_ROOT="${TAURI_TARGET_DIR}/release/bundle"

mkdir -p "${CANONICAL_OUTPUT_DIR}"
find "${CANONICAL_OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

find_latest_file() {
  local search_dir="$1"
  local pattern="$2"
  if [[ -d "${search_dir}" ]]; then
    find "${search_dir}" -maxdepth 1 -type f -name "${pattern}" | sort | tail -n 1
  fi
}

find_latest_dir() {
  local search_dir="$1"
  local pattern="$2"
  if [[ -d "${search_dir}" ]]; then
    find "${search_dir}" -maxdepth 1 -type d -name "${pattern}" | sort | tail -n 1
  fi
}

LATEST_DMG="$(find_latest_file "${TARGETED_DMG_DIR}" '*.dmg')"
if [[ -z "${LATEST_DMG}" ]]; then
  LATEST_DMG="$(find_latest_file "${FALLBACK_DMG_DIR}" '*.dmg')"
fi

LATEST_APP="$(find_latest_dir "${TARGETED_APP_DIR}" '*.app')"
if [[ -z "${LATEST_APP}" ]]; then
  LATEST_APP="$(find_latest_dir "${FALLBACK_APP_DIR}" '*.app')"
fi

sign_app_bundle() {
  local app_bundle="$1"
  local sidecar_path="${app_bundle}/Contents/MacOS/claude-sidecar"

  if [[ -f "${sidecar_path}" ]]; then
    codesign --force --sign - --identifier "${APP_BUNDLE_ID}.sidecar" --timestamp=none "${sidecar_path}"
  fi

  codesign --force --deep --sign - --identifier "${APP_BUNDLE_ID}" --timestamp=none "${app_bundle}"
}

build_canonical_dmg() {
  local app_bundle="$1"
  local dmg_output="$2"
  local staging_dir

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/cc-haha-dmg.XXXXXX")"
  cp -R "${app_bundle}" "${staging_dir}/"
  ln -s /Applications "${staging_dir}/Applications"

  hdiutil create \
    -volname "Claude Code Haha" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDZO \
    "${dmg_output}" >/dev/null

  rm -rf "${staging_dir}"
}

if [[ -n "${LATEST_DMG}" ]]; then
  cp -f "${LATEST_DMG}" "${CANONICAL_OUTPUT_DIR}/"
fi

if [[ -n "${LATEST_APP}" ]]; then
  cp -R "${LATEST_APP}" "${CANONICAL_OUTPUT_DIR}/"
  sign_app_bundle "${CANONICAL_OUTPUT_DIR}/${APP_BUNDLE_NAME}"
  rm -f "${CANONICAL_OUTPUT_DIR}/"*.dmg
  build_canonical_dmg \
    "${CANONICAL_OUTPUT_DIR}/${APP_BUNDLE_NAME}" \
    "${CANONICAL_OUTPUT_DIR}/$(basename "${LATEST_DMG:-Claude Code Haha_0.1.0_aarch64.dmg}")"
fi

cat > "${CANONICAL_OUTPUT_DIR}/BUILD_INFO.txt" <<EOF
Target triple: ${TARGET_TRIPLE}
Canonical output: ${CANONICAL_OUTPUT_DIR}
Source DMG: ${LATEST_DMG:-not found}
Source app: ${LATEST_APP:-not found}
Built at: $(date '+%Y-%m-%d %H:%M:%S %z')
EOF

if [[ -d "${LEGACY_BUNDLE_ROOT}" ]]; then
  rm -rf "${LEGACY_BUNDLE_ROOT}"
fi

echo
echo "[build-macos-arm64] Build finished."
if [[ -n "${LATEST_DMG}" ]]; then
  echo "[build-macos-arm64] DMG source: ${LATEST_DMG}"
else
  echo "[build-macos-arm64] No DMG found in ${TARGETED_DMG_DIR} or ${FALLBACK_DMG_DIR}" >&2
fi

if [[ -n "${LATEST_APP}" ]]; then
  echo "[build-macos-arm64] App source: ${LATEST_APP}"
else
  echo "[build-macos-arm64] No .app found in ${TARGETED_APP_DIR} or ${FALLBACK_APP_DIR}" >&2
fi

echo "[build-macos-arm64] Canonical output: ${CANONICAL_OUTPUT_DIR}"
echo "[build-macos-arm64] Removed legacy bundle dir: ${LEGACY_BUNDLE_ROOT}"

if [[ "${OPEN_OUTPUT:-0}" == "1" ]]; then
  open "${CANONICAL_OUTPUT_DIR}"
fi
