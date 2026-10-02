#!/usr/bin/env bash
# Installs Godot 4 (+ Mesa software rendering) in a Claude Code cloud container.
# github.com downloads are blocked there, but the Nix channel and binary cache
# are reachable. Not needed on a normal machine: just download Godot 4.7.
#
#   source Tools/godot/install_godot_nix.sh   # exports GODOT and GODOT_RENDER_ENV
set -euo pipefail
DIR="${BTG_GODOT_DIR:-/tmp/btg-godot}"
mkdir -p "$DIR"
if [ ! -d "$DIR/nixpkgs" ]; then
  curl -sSL https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz -o "$DIR/nixexprs.tar.xz"
  mkdir -p "$DIR/nixpkgs" && tar -xJf "$DIR/nixexprs.tar.xz" -C "$DIR/nixpkgs" --strip-components=1
fi
[ -e "$DIR/godot" ] || nix-build "$DIR/nixpkgs" -A godot_4 -o "$DIR/godot" >/dev/null
[ -e "$DIR/mesa" ] || nix-build "$DIR/nixpkgs" -A mesa -o "$DIR/mesa" >/dev/null
export GODOT="$DIR/godot/bin/godot"
M="$(readlink -f "$DIR/mesa")"
# For rendering (screenshots) under xvfb-run, prefix commands with: env $GODOT_RENDER_ENV
export GODOT_RENDER_ENV="LD_LIBRARY_PATH=$M/lib VK_ICD_FILENAMES=$M/share/vulkan/icd.d/lvp_icd.x86_64.json __GLX_VENDOR_LIBRARY_NAME=mesa __EGL_VENDOR_LIBRARY_FILENAMES=$M/share/glvnd/egl_vendor.d/50_mesa.json LIBGL_DRIVERS_PATH=$M/lib/dri"
"$GODOT" --headless --version
