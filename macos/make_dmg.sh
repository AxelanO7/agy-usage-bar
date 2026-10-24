#!/usr/bin/env bash
# Builds AgyUsageBar.app and packages it as a drag-to-Applications DMG and a zip (the zip is what scripts/install.sh downloads).
#   ./make_dmg.sh [output-dir]      default: ../dist
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-../dist}"

./make_app.sh
mkdir -p "$OUT"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R AgyUsageBar.app "$stage/"
ln -s /Applications "$stage/Applications"

rm -f "$OUT/AgyUsageBar-macos.dmg" "$OUT/AgyUsageBar-macos.zip"
hdiutil create -volname "Agy Usage Bar" -srcfolder "$stage" -ov -format UDZO "$OUT/AgyUsageBar-macos.dmg" > /dev/null
ditto -c -k --keepParent AgyUsageBar.app "$OUT/AgyUsageBar-macos.zip"
ls -lh "$OUT"
