#!/usr/bin/env bash
# Build AgyUsageBar.app (menu bar only, no Dock icon), universal (Apple Silicon + Intel), ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AgyUsageBar"

APP=AgyUsageBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgyUsageBar"
cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "OK: $PWD/$APP"
echo "Copy it to ~/Applications (or /Applications) so 'Launch at login' keeps working."
