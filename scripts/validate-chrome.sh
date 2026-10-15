#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
prerequisites
check_cdp
printf 'Verified Chrome process/profile and CDP page endpoint at %s.\n' "$ENDPOINT"
echo 'This is not a Playwright attachment test. In Pi, call browser_tabs (action: list).'
