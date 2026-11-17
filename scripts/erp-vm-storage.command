#!/bin/zsh
# GPL-3.0; see LICENSE and NOTICE.md. Default action is read-only.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
exec python3 scripts/erp_vm_storage.py "$@"
