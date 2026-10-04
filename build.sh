#!/bin/bash
# Builds FreePort.app.
#   ./build.sh                 build for this Mac
#   ./build.sh --universal     build a universal (Apple Silicon + Intel) binary
#   ./build.sh --install       build, install to /Applications and launch
# VERSION=1.2.3 ./build.sh     override the version (defaults to the latest git tag)
set -euo pipefail
cd "$(dirname "$0")"

APP="FreePort.app"
UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install)   INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "==> Compiling FreePort $VERSION"
if [ "$UNIVERSAL" = "1" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/FreePort"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/FreePort"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FreePort"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Generating icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
swift Resources/makeicon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier dev.local.freeport "$APP"
codesign --verify --strict "$APP"

if [ "$INSTALL" = "1" ]; then
  echo "==> Installing to /Applications"
  pkill -x FreePort 2>/dev/null || true
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  open "/Applications/$APP"
  echo "==> Running. Look for the plug icon in your menu bar."
else
  echo "==> Done: $PWD/$APP"
  echo "    ./build.sh --install  puts it in /Applications and launches it."
fi
