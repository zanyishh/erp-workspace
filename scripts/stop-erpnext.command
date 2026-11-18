#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml stop
colima stop --profile erp
