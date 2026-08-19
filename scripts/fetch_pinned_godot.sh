#!/usr/bin/env bash
set -euo pipefail

VERSION="4.7.1-stable"
ARCHIVE="Godot_v4.7.1-stable_linux.x86_64.zip"
BINARY="Godot_v4.7.1-stable_linux.x86_64"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"
DEST="${1:-${FMD_GODOT_CACHE:-$HOME/.cache/fmd-godot/${VERSION}}}"
OFFLINE_ARCHIVE="${FMD_GODOT_ARCHIVE:-}"
OFFLINE_SUMS="${FMD_GODOT_SHA512_MANIFEST:-}"
mkdir -p "$DEST"

archive_path="$DEST/$ARCHIVE"
sums_path="$DEST/SHA512-SUMS.txt"
binary_path="$DEST/$BINARY"

copy_offline_inputs() {
  if [[ -z "$OFFLINE_ARCHIVE" || -z "$OFFLINE_SUMS" ]]; then
    echo "ERROR: FMD_GODOT_ARCHIVE and FMD_GODOT_SHA512_MANIFEST must be provided together" >&2
    exit 2
  fi
  if [[ ! -f "$OFFLINE_ARCHIVE" || ! -f "$OFFLINE_SUMS" ]]; then
    echo "ERROR: offline Godot archive or SHA512 manifest is missing" >&2
    exit 2
  fi
  cp "$OFFLINE_ARCHIVE" "$archive_path.offline.tmp"
  mv "$archive_path.offline.tmp" "$archive_path"
  cp "$OFFLINE_SUMS" "$sums_path.offline.tmp"
  mv "$sums_path.offline.tmp" "$sums_path"
  echo "Using caller-provided pinned Godot archive and SHA512 manifest." >&2
}

download_official_inputs() {
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required to fetch pinned Godot" >&2; exit 127; }
  curl -fL --retry 3 --retry-delay 2 -o "$archive_path" "$BASE_URL/$ARCHIVE"
  curl -fL --retry 3 --retry-delay 2 -o "$sums_path" "$BASE_URL/SHA512-SUMS.txt"
}

if [[ ! -x "$binary_path" ]]; then
  command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip is required to unpack pinned Godot" >&2; exit 127; }
  command -v sha512sum >/dev/null 2>&1 || { echo "ERROR: sha512sum is required to verify pinned Godot" >&2; exit 127; }

  if [[ -n "$OFFLINE_ARCHIVE" || -n "$OFFLINE_SUMS" ]]; then
    copy_offline_inputs
  else
    download_official_inputs
  fi

  expected_line="$(grep -F "  $ARCHIVE" "$sums_path" | head -n 1 || true)"
  if [[ -z "$expected_line" ]]; then
    echo "ERROR: SHA512 manifest does not contain $ARCHIVE" >&2
    exit 2
  fi
  printf '%s\n' "$expected_line" | (cd "$DEST" && sha512sum -c - >&2)
  unzip -oq "$archive_path" -d "$DEST"
  chmod +x "$binary_path"
fi

version_output="$($binary_path --version 2>&1 | head -n 1)"
if [[ "$version_output" != 4.7.1* ]]; then
  echo "ERROR: pinned runtime reports unexpected version: $version_output" >&2
  exit 2
fi

printf '%s\n' "$binary_path"
