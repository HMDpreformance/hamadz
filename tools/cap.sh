#!/bin/bash
# Audio capture for analysis: tools/cap.sh "<AH_DEV spec>" out.wav
# Renders the game through Godot's movie writer (deterministic, offline) and keeps the audio.
cd "$(dirname "$0")/.."
T=$(mktemp -d)
AH_DEV="$1" timeout 900 xvfb-run -a -s "-screen 0 640x360x24" /home/claude/tools/godot --rendering-method mobile --resolution 320x180 --write-movie $T/c.avi --fixed-fps 30 2>&1 | grep -E "SIM|SCRIPT ERROR|^ERROR" | grep -v "resources still"
ffmpeg -y -loglevel error -i $T/c.avi -vn "$2"
rm -rf $T
