#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
if ! colima status --profile erp >/dev/null 2>&1; then
  colima start --profile erp --cpu 2 --memory 3 --disk 8 --root-disk 4 --vm-type vz --activate=false --ssh-config=false
fi
compose=(docker --context colima-erp compose -f infrastructure/erpnext/compose.yaml)
"${compose[@]}" up -d backend queue-short queue-long
if ! "${compose[@]}" exec -T backend test -d sites/native-test.localhost; then
  "${compose[@]}" exec -T backend bench new-site native-test.localhost --db-root-username=root --db-root-password=admin --admin-password=admin --mariadb-user-host-login-scope='%' --install-app erpnext
fi
if ! "${compose[@]}" exec -T backend bench --site native-test.localhost list-apps | rg -q '^erp_extensions '; then
  "${compose[@]}" exec -T backend bench --site native-test.localhost install-app erp_extensions
fi
"${compose[@]}" exec -T backend bench --site native-test.localhost execute erp_extensions.setup.configure_test_site
"${compose[@]}" --profile native-test up -d native-test-backend native-test-frontend
printf 'Isolated Flutter verification server: http://localhost:8081\n'
