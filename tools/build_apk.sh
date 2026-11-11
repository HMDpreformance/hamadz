#!/bin/bash
# Builds the Android APK from the command line.
#   GODOT=/path/to/godot tools/build_apk.sh [debug|release]
# Requirements: Godot 4.4.1 + matching export templates, and Android SDK paths
# set in the editor settings (Editor > Editor Settings > Export > Android).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${1:-debug}"
mkdir -p build
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-$MODE "Android" build/AfterHours-StreetSyndicate.apk
ls -la build/*.apk
