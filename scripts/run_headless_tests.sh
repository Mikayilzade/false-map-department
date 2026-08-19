#!/usr/bin/env sh
set -eu
GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --path "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)" --script res://tests/test_runner.gd
