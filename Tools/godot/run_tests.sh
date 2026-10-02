#!/usr/bin/env bash
# Runs the Godot-side test suite headless.
#   GODOT=/path/to/godot Tools/godot/run_tests.sh      (defaults to `godot` on PATH)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"

# A fresh checkout has no .godot/ cache yet, so class_name scripts are unknown
# until the project has been imported once.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tests/run_tests.gd
