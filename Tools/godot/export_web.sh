#!/usr/bin/env bash
# Exports the playable web build to build/web (index.html + wasm + pck).
# Needs the Godot 4.7 web export template (web_nothreads_release.zip) installed in
# ~/.local/share/godot/export_templates/4.7.2.stable/ — CI downloads it; in a cloud
# session `nix-build <nixpkgs> -A godot_4-export-templates-bin` provides it.
# Single-threaded build on purpose: GitHub Pages can't send the COOP/COEP headers
# that a threaded build needs.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
test -s build/web/index.pck && test -s build/web/index.wasm
ls -la build/web
