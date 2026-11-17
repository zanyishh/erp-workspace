#!/bin/zsh
# GPL-3.0; see the workspace LICENSE and NOTICE.md.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
compose=(docker --context colima-erp compose -p erp-baseline -f infrastructure/erpnext/compose.yaml --profile native-test)
# Recreate only the synthetic frontend when its read-only configuration changes.
"${compose[@]}" up -d --no-deps --force-recreate native-test-frontend
"${compose[@]}" exec -T native-test-frontend nginx -t
"${compose[@]}" exec -T native-test-frontend nginx -s reload
