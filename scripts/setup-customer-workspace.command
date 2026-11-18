#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
if ! colima status --profile erp >/dev/null 2>&1; then
  colima start --profile erp --cpu 2 --memory 3 --disk 8 --root-disk 4 --vm-type vz --activate=false --ssh-config=false
fi
compose=(docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml)
"${compose[@]}" up -d backend queue-short queue-long
python3 scripts/provision-customer-site.py
"${compose[@]}" --profile customer up -d native-test-backend customer-frontend
printf 'Separate customer workspace: http://127.0.0.1:8082\n'
