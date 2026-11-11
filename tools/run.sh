#!/bin/bash
# Dev runner: tools/run.sh "<AH_DEV spec>"  (renders with software Vulkan under Xvfb)
cd "$(dirname "$0")/.."
AH_DEV="$1" xvfb-run -a -s "-screen 0 1280x720x24" /home/claude/tools/godot --rendering-method mobile --resolution 1280x720 --audio-driver Dummy 2>&1 | grep -vE "JAVA_TOOL|^$|ALSA|alsa|audio driver|Godot Engine|Vulkan 1|llvmpipe"
