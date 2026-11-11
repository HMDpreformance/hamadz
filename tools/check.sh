#!/bin/bash
# Parses every script (with autoloads available) and prints GDScript errors.
cd "$(dirname "$0")/.."
/home/claude/tools/godot --headless --import >/dev/null 2>&1
AH_DEV="check" /home/claude/tools/godot --headless 2>&1 | grep -E -A1 "SCRIPT ERROR|^ERROR|FAILED|checked" | grep -vE "JAVA_TOOL|^--$|Compile Error|reload \(res://[a-z_/]*.gd:0\)" | awk '!seen[$0]++' | head -${1:-40}
