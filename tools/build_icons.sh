#!/usr/bin/env bash
# Regenerates the macOS .icns and the Windows .ico from tools/make_icons.swift (macOS only: needs AppKit + iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
swift tools/make_icons.swift "$tmp"
iconutil -c icns "$tmp/AppIcon.iconset" -o macos/AppIcon.icns
python3 tools/png2ico.py windows/src/AgyUsageBar/app.ico "$tmp"/win-16.png "$tmp"/win-24.png "$tmp"/win-32.png "$tmp"/win-48.png "$tmp"/win-64.png "$tmp"/win-128.png "$tmp"/win-256.png
cp "$tmp/icon-1024.png" assets/icon.png
rm -rf "$tmp"
echo "done"
