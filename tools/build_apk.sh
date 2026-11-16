#!/bin/bash
# Builds the Android APK from the command line.
#   GODOT=/path/to/godot [VER=0.20] tools/build_apk.sh [debug|release]
# Every build auto-increments the Android versionCode so the install always
# takes on-device (Android refuses to replace an app with the same code).
# The on-screen menu label (project.godot application/config/version) is set to
# "<name> b<code>" so it is unique per build and Hamad can confirm what he ran.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-debug}"
mkdir -p build

CODE=$(grep -oP 'version/code=\K[0-9]+' export_presets.cfg)
NEWCODE=$((CODE + 1))
NAME="${VER:-$(grep -oP 'version/name="\K[^"]+' export_presets.cfg)}"
LABEL="$NAME b$NEWCODE"

sed -i "s|version/code=.*|version/code=$NEWCODE|" export_presets.cfg
sed -i "s|version/name=.*|version/name=\"$NAME\"|" export_presets.cfg
sed -i "s|config/version=.*|config/version=\"$LABEL\"|" project.godot
echo "Building versionCode=$NEWCODE  versionName=$NAME  label=\"$LABEL\""

OUT="build/AfterHours-v${NAME}-b${NEWCODE}.apk"
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-$MODE "Android" "$OUT"
# also keep the stable-name copy for anything that expects it
cp "$OUT" build/AfterHours-StreetSyndicate.apk
ls -la "$OUT"
