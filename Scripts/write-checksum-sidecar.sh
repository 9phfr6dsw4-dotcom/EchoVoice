#!/usr/bin/env bash
set -euo pipefail

ZIP_INPUT="${1:?Usage: write-checksum-sidecar.sh ZIP_PATH}"
ZIP_NAME="$(basename "$ZIP_INPUT")"
ZIP_PARENT="$(dirname "$ZIP_INPUT")"
ZIP_DIR="$(cd "$ZIP_PARENT" && pwd -P)"
ZIP_PATH="$ZIP_DIR/$ZIP_NAME"
SIDECAR_PATH="$ZIP_PATH.sha256"

[[ -f "$ZIP_PATH" && ! -L "$ZIP_PATH" ]] || { printf 'ZIP must be a regular, non-symlink file: %s\n' "$ZIP_PATH" >&2; exit 2; }
if [[ -L "$SIDECAR_PATH" ]]; then
  printf 'Refusing symlinked checksum sidecar: %s\n' "$SIDECAR_PATH" >&2
  exit 2
fi
if [[ -e "$SIDECAR_PATH" && ! -f "$SIDECAR_PATH" ]]; then
  printf 'Checksum sidecar is not a regular file: %s\n' "$SIDECAR_PATH" >&2
  exit 2
fi

if command -v shasum >/dev/null 2>&1; then
  CHECKSUM_COMMAND=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
  CHECKSUM_COMMAND=(sha256sum)
else
  printf '%s\n' 'Neither shasum nor sha256sum is available.' >&2
  exit 2
fi

TEMP_SIDECAR="$(mktemp "$ZIP_DIR/.${ZIP_NAME}.sha256.XXXXXX")"
trap 'rm -f "$TEMP_SIDECAR"' EXIT
(
  cd "$ZIP_DIR"
  "${CHECKSUM_COMMAND[@]}" "$ZIP_NAME"
) > "$TEMP_SIDECAR"
mv -f "$TEMP_SIDECAR" "$SIDECAR_PATH"
trap - EXIT
printf 'Wrote downloadable checksum sidecar: %s\n' "$SIDECAR_PATH"
