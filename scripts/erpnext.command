#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
if ! colima status --profile erp >/dev/null 2>&1; then
  colima start --profile erp --cpu 2 --memory 3 --disk 8 --root-disk 4 --vm-type vz --activate=false --ssh-config=false
fi
export DOCKER_DEFAULT_PLATFORM=linux/arm64
docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml up -d
for attempt in {1..30}; do
  if curl -fsS --max-time 2 http://localhost:8080/api/method/ping >/dev/null 2>&1; then
    open http://localhost:8080
    exit 0
  fi
  sleep 2
done
printf 'ERPNext is still initializing. Open http://localhost:8080 shortly.\n'
open http://localhost:8080
