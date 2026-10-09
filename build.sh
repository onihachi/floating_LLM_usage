#!/usr/bin/env bash
# Builds LLMUsageFloat.app into ./build using the Swift Package Manager.
#
# Usage:
#   ./build.sh           release build -> build/LLMUsageFloat.app
#   ./build.sh debug     debug build   -> build/LLMUsageFloat.app
#   ./build.sh install   release build, then copy to ~/Applications/LLMUsageFloat.app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LLMUsageFloat"
MODE="build"
if [ "${1:-}" = "install" ]; then
    MODE="install"
    CONFIG="release"
else
    CONFIG="${1:-release}"
fi

swift build -c "$CONFIG"

BIN=".build/$CONFIG/$APP_NAME"
APP="build/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sign with a self-signed "LLMUsageFloat" code-signing certificate when one is
# installed: its identity is stable across rebuilds, so the Keychain "Always
# Allow" grant survives a rebuild. Otherwise fall back to an ad-hoc signature,
# which changes with every build (the grant is lost each time).
SIGN_LABEL="ad-hoc"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if grep -q '"[^"]*LLMUsageFloat[^"]*"' <<<"$IDENTITIES"; then
    if SIGN_OUTPUT="$(codesign --force --sign "LLMUsageFloat" --timestamp=none "$APP" 2>&1)"; then
        SIGN_LABEL="LLMUsageFloat (自己署名証明書)"
    else
        echo "警告: LLMUsageFloat 証明書での署名に失敗したため ad-hoc 署名にします" >&2
        echo "$SIGN_OUTPUT" >&2
    fi
fi
if [ "$SIGN_LABEL" = "ad-hoc" ]; then
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "署名: $SIGN_LABEL"

echo "Built: $APP"

if [ "$MODE" = "install" ]; then
    INSTALL_DIR="$HOME/Applications"
    INSTALLED="$INSTALL_DIR/$APP_NAME.app"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    echo "インストール先: ~/Applications/$APP_NAME.app"
    echo "Run:   open ~/Applications/$APP_NAME.app"
else
    echo "Run:   open \"$APP\""
fi
