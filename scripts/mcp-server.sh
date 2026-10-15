#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ $# == 0 ]] || fail 'This wrapper takes no arguments.'
cd "$ROOT"
exec "$ROOT/.runtime/node_modules/.bin/playwright-mcp" --cdp-endpoint "$ENDPOINT"
