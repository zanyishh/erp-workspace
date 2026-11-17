#!/bin/zsh
# GPL-3.0; see the workspace LICENSE and NOTICE.md.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
case "${1:-}" in
  ""|--install-only) ;;
  *) print -u2 'Use erp-workspace.command or erp-workspace.command --install-only.'; exit 2 ;;
esac
scripts/setup-native-test.command
python3 scripts/provision-local-workspace.py
if [[ -f .local/customer-workspace/target-bindings.json ]]; then
  scripts/setup-customer-workspace.command
  python3 scripts/provision-customer-profile.py
fi
mkdir -p .local/runtime "$HOME/Applications"
fingerprint="$(python3 scripts/app-fingerprint.py client)"
built="$PWD/apps/erp_client/build/macos/Build/Products/Release/ERP Workspace.app"
installed="$HOME/Applications/ERP Workspace Local.app"
marker='org.localerp.workspace.launcher'
if [[ -e "$installed" && "$(xattr -p "$marker" "$installed" 2>/dev/null || true)" != "$PWD" ]]; then
  print -u2 "An existing application already uses $installed. It was preserved. Choose another location for that application before running the local installer."
  exit 1
fi
if [[ ! -d "$installed" || ! -f .local/runtime/local-client-fingerprint || "$(cat .local/runtime/local-client-fingerprint)" != "$fingerprint" ]] || ! codesign --verify --deep --strict "$installed" 2>/dev/null; then
  (cd apps/erp_client && python3 ../../scripts/flutter_toolchain.py --suppress-analytics build macos --release --dart-define=ERP_LOCAL_WORKSPACE=true --dart-define=ERP_SERVER=http://127.0.0.1:8081)
  codesign --verify --deep --strict "$built"
  staging="$(mktemp -d "$HOME/Applications/.erp-local.XXXXXX")"
  trap 'if [[ -d "$staging/old.app" && ! -e "$installed" ]]; then mv "$staging/old.app" "$installed"; fi; /bin/rm -rf "$staging"' EXIT
  ditto "$built" "$staging/new.app"
  xattr -w "$marker" "$PWD" "$staging/new.app"
  codesign --verify --deep --strict "$staging/new.app"
  if [[ -d "$installed" ]]; then mv "$installed" "$staging/old.app"; fi
  mv "$staging/new.app" "$installed"
  print -r -- "$fingerprint" > .local/runtime/local-client-fingerprint
fi
if [[ "${1:-}" == '--install-only' ]]; then
  print -r -- "Installed $installed"
  exit 0
fi
for attempt in {1..30}; do
  if curl -fsS --max-time 2 http://127.0.0.1:8081/api/method/ping >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
open "$installed"
