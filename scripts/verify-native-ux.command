#!/bin/zsh
# Build/launch the real macOS app against the isolated synthetic test service.
# This deliberately bypasses local-launch.json and every customer launcher.
set -euo pipefail
PROJECT_ROOT=${0:A:h:h}
cd "$PROJECT_ROOT/apps/erp_client"
FLUTTER_BIN=${FLUTTER_BIN:-/opt/homebrew/share/flutter/bin/flutter}
MODE=${1:-build}
NATIVE_PRODUCTS="$PROJECT_ROOT/.local/ux-implementation-2026-11-16/native-products"
APP_PATH="$NATIVE_PRODUCTS/Release/ERP Workspace.app"
VERIFY_APP="$PROJECT_ROOT/.local/ux-implementation-2026-11-16/ERP UX Verification.app"
BUILD_STAMP="$PROJECT_ROOT/.local/ux-implementation-2026-11-16/native-build.sha256"
case "$MODE" in
  build)
    # The normal Release folder may point at a preserved external build.
    # Scope products to this verification run without changing global settings.
    FLUTTER_XCODE_SYMROOT="$NATIVE_PRODUCTS" "$FLUTTER_BIN" build macos --release --no-pub \
      --dart-define=ERP_LOCAL_WORKSPACE=false \
      --dart-define=ERP_SERVER=http://127.0.0.1:8081
    mkdir -p "${BUILD_STAMP:h}"
    # A separate identity avoids attaching verification to an already-running
    # workspace instance or sharing its native application container.
    ditto "$APP_PATH" "$VERIFY_APP"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.localerp.workspace.uxverification' "$VERIFY_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName ERP UX Verification' "$VERIFY_APP/Contents/Info.plist"
    codesign --force --deep --sign - --preserve-metadata=entitlements,flags "$VERIFY_APP"
    shasum -a 256 "$VERIFY_APP/Contents/MacOS/ERP Workspace" \
      "$VERIFY_APP/Contents/Frameworks/App.framework/App" > "$BUILD_STAMP"
    ;;
  launch)
    [[ -d "$VERIFY_APP" && -f "$BUILD_STAMP" ]] || { print -u2 'Build the native UX verification app first.'; exit 1; }
    shasum -a 256 --check "$BUILD_STAMP"
    open -n "$VERIFY_APP"
    ;;
  *) print -u2 'Use build or launch.'; exit 1 ;;
esac
