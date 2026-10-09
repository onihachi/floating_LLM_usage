#!/usr/bin/env bash
# Builds LLMUsageFloat.app into ./build using the Swift Package Manager.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LLMUsageFloat"
CONFIG="${1:-release}"

swift build -c "$CONFIG"

BIN=".build/$CONFIG/$APP_NAME"
APP="build/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so Keychain access prompts behave consistently between launches.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
echo "Run:   open \"$APP\""
