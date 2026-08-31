#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="4.7.1-stable"
CACHE="${FMD_GODOT_CACHE:-$HOME/.cache/fmd-godot/$VERSION}"
TEMPLATE_ARCHIVE="Godot_v4.7.1-stable_export_templates.tpz"
BASE_URL="https://github.com/godotengine/godot-builds/releases/download/$VERSION"
BUILD_DIR="$ROOT/build/windows"
PACKAGE="$ROOT/build/FalseMapDepartment-Windows-x86_64-owner-playtest.zip"

GODOT_BIN="${GODOT_BIN:-$($ROOT/scripts/fetch_pinned_godot.sh "$CACHE")}" 
mkdir -p "$CACHE" "$HOME/.local/share/godot/export_templates/4.7.1.stable" "$BUILD_DIR"

if [[ ! -f "$CACHE/$TEMPLATE_ARCHIVE" ]]; then
  curl -fL --retry 3 --retry-delay 2 -o "$CACHE/$TEMPLATE_ARCHIVE" "$BASE_URL/$TEMPLATE_ARCHIVE"
fi
if [[ ! -f "$CACHE/SHA512-SUMS.txt" ]]; then
  curl -fL --retry 3 --retry-delay 2 -o "$CACHE/SHA512-SUMS.txt" "$BASE_URL/SHA512-SUMS.txt"
fi
expected="$(rg -F "  $TEMPLATE_ARCHIVE" "$CACHE/SHA512-SUMS.txt" | head -1)"
[[ -n "$expected" ]] || { echo "Missing template checksum" >&2; exit 2; }
printf '%s\n' "$expected" | (cd "$CACHE" && sha512sum -c -)
unzip -oq "$CACHE/$TEMPLATE_ARCHIVE" -d "$CACHE/templates"
cp -f "$CACHE/templates/templates/"* "$HOME/.local/share/godot/export_templates/4.7.1.stable/"

rm -f "$BUILD_DIR/FalseMapDepartment.exe" "$PACKAGE"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "Windows Desktop" "$BUILD_DIR/FalseMapDepartment.exe"
test -s "$BUILD_DIR/FalseMapDepartment.exe"
(cd "$BUILD_DIR" && zip -9 "$PACKAGE" FalseMapDepartment.exe)
sha256sum "$BUILD_DIR/FalseMapDepartment.exe" "$PACKAGE"
