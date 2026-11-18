#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
case "${1:-}" in
  ""|--recover) ;;
  *) print -u2 'Use setup-customer-workspace.command or setup-customer-workspace.command --recover.'; exit 2 ;;
esac
if ! colima status --profile erp >/dev/null 2>&1; then
  colima start --profile erp --cpu 2 --memory 3 --disk 8 --root-disk 4 --vm-type vz --activate=false --ssh-config=false
fi
compose=(docker --context colima-erp compose -p erp-baseline -f infrastructure/erpnext/compose.yaml)

if [[ "${1:-}" == '--recover' ]]; then
  ping_customer() {
    curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1:8082/api/method/ping 2>/dev/null |
      /usr/bin/grep -Eq '"message"[[:space:]]*:[[:space:]]*"pong"'
  }
  if ping_customer; then
    print 'The local knitting service is ready.'
    exit 0
  fi
  if ! "${compose[@]}" exec -T backend test -f sites/customer-migration.localhost/site_config.json; then
    print -u2 'The existing customer site could not be verified. Recovery stopped before restarting any containers.'
    exit 1
  fi
  "${compose[@]}" --profile customer up -d native-test-backend customer-frontend
  if ! ping_customer; then
    "${compose[@]}" --profile customer restart native-test-backend customer-frontend
  fi
  for ((attempt=1; attempt<=20; attempt++)); do
    if ping_customer; then
      print 'The local knitting service is ready.'
      exit 0
    fi
    sleep 1
  done
  umask 077
  mkdir -p .local/runtime
  log=.local/runtime/customer-recovery.log
  "${compose[@]}" --profile customer logs --no-color --tail 100 native-test-backend customer-frontend db redis-cache > "$log" 2>&1 || true
  print -u2 "The customer service is still failing. Diagnostic log: $PWD/$log"
  exit 1
fi

"${compose[@]}" up -d backend queue-short queue-long
python3 scripts/provision-customer-site.py
"${compose[@]}" --profile customer up -d native-test-backend customer-frontend
printf 'Separate customer workspace: http://127.0.0.1:8082\n'
