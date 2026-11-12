#!/bin/zsh
# GPL-3.0; see the workspace LICENSE and NOTICE.md.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
if ! colima status --profile erp >/dev/null 2>&1; then
  colima start --profile erp --cpu 2 --memory 3 --disk 8 --root-disk 4 --vm-type vz --activate=false --ssh-config=false
fi
export DOCKER_DEFAULT_PLATFORM=linux/arm64
docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml up -d
APP_PATH="$PWD/apps/erp_client/build/macos/Build/Products/Debug/ERP Workspace.app"
if [[ ! -d "$APP_PATH" ]]; then
  (cd apps/erp_client && flutter build macos --debug)
fi
for attempt in {1..30}; do
  if curl -fsS --max-time 2 http://localhost:8080/api/method/ping >/dev/null 2>&1; then
    open "$APP_PATH"
    exit 0
  fi
  sleep 2
done
printf 'ERPNext is still starting. Use Refresh in the workspace shortly.\n'
open "$APP_PATH"
