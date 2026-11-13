#!/bin/zsh
# GPL-3.0; see the workspace LICENSE and NOTICE.md.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
scripts/setup-native-test.command
APP_PATH="$PWD/apps/erp_client/build/macos/Build/Products/Release/ERP Workspace.app"
mkdir -p .local/runtime
ERP_CLIENT_FINGERPRINT="$(python3 scripts/app-fingerprint.py client)"
if [[ ! -f .local/runtime/client-fingerprint ]] || [[ "$(cat .local/runtime/client-fingerprint)" != "$ERP_CLIENT_FINGERPRINT" ]] || [[ ! -d "$APP_PATH" ]] || ! codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
  (cd apps/erp_client && flutter build macos --release)
  python3 scripts/app-fingerprint.py client > .local/runtime/client-fingerprint
fi
codesign --verify --deep --strict "$APP_PATH"
for attempt in {1..30}; do
  if curl -fsS --max-time 2 http://localhost:8081/api/method/ping >/dev/null 2>&1; then
    open "$APP_PATH"
    exit 0
  fi
  sleep 2
done
printf 'ERPNext is still starting. Use Refresh in the workspace shortly.\n'
open "$APP_PATH"
