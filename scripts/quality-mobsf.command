#!/bin/zsh
# A dormant native local tool. Starting it is a separate, explicit action.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
exec python3 scripts/quality/mobsf_service.py "$@"
