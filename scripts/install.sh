#!/usr/bin/env bash
# Installs Agy Usage Bar (macOS menu bar app) from the latest GitHub release and starts it.
#   bash scripts/install.sh
# Environment: AGY_USAGE_DEST (default ~/Applications), AGY_USAGE_REPO (default AxelanO7/agy-usage-bar)
set -euo pipefail

REPO="${AGY_USAGE_REPO:-AxelanO7/agy-usage-bar}"
ASSET="AgyUsageBar-macos.zip"
DEST="${AGY_USAGE_DEST:-$HOME/Applications}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is for macOS. On Windows run scripts/install.ps1." >&2
  exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 13 ]; then
  echo "macOS 13 or newer is required (found $(sw_vers -productVersion))." >&2
  exit 1
fi

if ! command -v agy >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/agy" ] && [ ! -x /opt/homebrew/bin/agy ] && [ ! -x /usr/local/bin/agy ]; then
  echo "Note: the 'agy' command was not found. The app needs the Antigravity CLI installed and signed in."
  echo "      Installing the app anyway; it will show 'agy?' until agy is available."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $ASSET from github.com/$REPO (latest release)..."
curl -fL --progress-bar "https://github.com/$REPO/releases/latest/download/$ASSET" -o "$tmp/$ASSET"
ditto -x -k "$tmp/$ASSET" "$tmp/unzipped"
if [ ! -d "$tmp/unzipped/AgyUsageBar.app" ]; then
  echo "AgyUsageBar.app was not found inside the archive." >&2
  exit 1
fi

mkdir -p "$DEST"
pkill -x AgyUsageBar 2>/dev/null && sleep 1 || true
rm -rf "$DEST/AgyUsageBar.app"
ditto "$tmp/unzipped/AgyUsageBar.app" "$DEST/AgyUsageBar.app"
# Files fetched with curl are not quarantined, but clear the flag in case the archive was downloaded another way.
xattr -dr com.apple.quarantine "$DEST/AgyUsageBar.app" 2>/dev/null || true

open "$DEST/AgyUsageBar.app"
echo "Installed to $DEST/AgyUsageBar.app and started."
echo "Click the ring in the menu bar. To start it at every login: gear icon -> Launch at login."
