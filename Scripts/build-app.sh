#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_DIR="$ROOT_DIR/build/MeetX.app"
BINARY_DIR="$ROOT_DIR/.build/$CONFIGURATION"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/MeetX" "$APP_DIR/Contents/MacOS/MeetX"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/voice-svgrepo-com.svg" "$APP_DIR/Contents/Resources/voice-svgrepo-com.svg"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

printf '%s\n' "$APP_DIR"
