#!/bin/zsh
# GPL-3.0; see the workspace LICENSE and NOTICE.md.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
case "${1:-}" in
  ""|--install-only) ;;
  *) print -u2 'Use erp-customer.command or erp-customer.command --install-only.'; exit 2 ;;
esac
if [[ ! -f .local/customer-workspace/target-bindings.json ]]; then
  print -u2 'Prepare and verify the separate customer workspace before opening this app.'
  exit 1
fi
scripts/setup-native-test.command
scripts/setup-customer-workspace.command
mkdir -p .local/runtime "$HOME/Applications"
launcher_fingerprint="$(shasum -a 256 scripts/erp-customer.command | cut -d ' ' -f 1)"
fingerprint="$(python3 scripts/app-fingerprint.py client)-$launcher_fingerprint"
built="$PWD/apps/erp_client/build/macos/Build/Products/Release/ERP Workspace.app"
installed="$HOME/Applications/ERP Workspace Customer.app"
marker='org.localerp.workspace.customer-launcher'
if [[ -e "$installed" && "$(xattr -p "$marker" "$installed" 2>/dev/null || true)" != "$PWD" ]]; then
  print -u2 "An existing application already uses $installed. It was preserved."
  exit 1
fi
if [[ ! -d "$installed" || ! -f .local/runtime/customer-client-fingerprint || "$(cat .local/runtime/customer-client-fingerprint)" != "$fingerprint" ]] || ! codesign --verify --deep --strict "$installed" 2>/dev/null; then
  (cd apps/erp_client && python3 ../../scripts/flutter_toolchain.py --suppress-analytics build macos --release --dart-define=ERP_LOCAL_WORKSPACE=false --dart-define=ERP_SERVER=http://127.0.0.1:8082)
  codesign --verify --deep --strict "$built"
  staging="$(mktemp -d "$HOME/Applications/.erp-customer.XXXXXX")"
  trap 'if [[ -d "$staging/old.app" && ! -e "$installed" ]]; then mv "$staging/old.app" "$installed"; fi; /bin/rm -rf "$staging"' EXIT
  ditto "$built" "$staging/new.app"
  xattr -w "$marker" "$PWD" "$staging/new.app"
  codesign --verify --deep --strict "$staging/new.app"
  if [[ -d "$installed" ]]; then mv "$installed" "$staging/old.app"; fi
  mv "$staging/new.app" "$installed"
  print -r -- "$fingerprint" > .local/runtime/customer-client-fingerprint
fi
if [[ "${1:-}" == '--install-only' ]]; then
  print -r -- "Installed $installed"
  exit 0
fi
open -n "$installed"
