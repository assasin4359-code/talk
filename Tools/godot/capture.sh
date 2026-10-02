#!/usr/bin/env bash
# Software-rendered screenshot of the village (no GPU needed). Cloud sessions: source
# Tools/godot/install_godot_nix.sh first so GODOT and GODOT_RENDER_ENV are set.
#   Tools/godot/capture.sh <view> <stage> <cycle> <out.png>
#   Tools/godot/capture.sh spawn S02_GateClosed 2 /tmp/gate_closed.png
# Views: spawn square gate foyer tavern smithy sign overview (tests/visual/capture.gd)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
VIEW="${1:-spawn}"; STAGE="${2:-S01_Arrival}"; CYCLE="${3:-1}"; OUT="${4:-$PWD/capture.png}"
# shellcheck disable=SC2086
env ${GODOT_RENDER_ENV:-} xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path . --rendering-driver vulkan --audio-driver Dummy --resolution 1280x720 \
  --script res://tests/visual/capture.gd -- --view "$VIEW" --stage "$STAGE" --cycle "$CYCLE" --out "$OUT" \
  2>&1 | grep -E "captured|ERROR|SCRIPT" || true
