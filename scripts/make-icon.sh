#!/usr/bin/env bash
set -euo pipefail

# Regenerates icon/AppIcon.icns from icon/AppIcon.png. Run this after changing
# the artwork; make-app.sh only copies the finished .icns.
cd "$(dirname "$0")/.."

SOURCE="icon/AppIcon.png"
ICONSET="icon/AppIcon.iconset"
ICNS="icon/AppIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
    echo "No $SOURCE found — nothing to do." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Building icon renderer..."
swiftc -O -target "arm64-apple-macosx14.0" -o "$WORK/round-icon" scripts/round-icon.swift

echo "Rendering icon slices..."
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() { # <pixels> <iconset file name>
    "$WORK/round-icon" "$SOURCE" "$ICONSET/$2" "$1"
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil --convert icns "$ICONSET" --output "$ICNS"
echo "Built $ICNS"
