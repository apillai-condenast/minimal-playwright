#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"
cleanup_needed=false
finish() {
  local status=$?
  trap - EXIT
  if [[ "$cleanup_needed" == true ]]; then
    echo 'Cleaning up automation Chrome (profile preserved)...'
    if ! "$SCRIPTS/stop-chrome.sh"; then
      echo 'ERROR: Chrome cleanup failed; inspect the automation browser manually.' >&2
      [[ $status != 0 ]] || status=1
    fi
  fi
  if [[ $status == 0 ]]; then
    echo 'Setup complete: SUCCESS — visible and headless example.com tests and screenshots passed; test Chrome and Playwright stopped.'
  else
    echo "Setup complete: ERROR — exit $status. See the failing step above; setup is not validated." >&2
  fi
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ $# == 0 ]] || fail 'Usage: ./setup.sh (always tests both visible and headless modes)'
"$SCRIPTS/test.sh"
prerequisites
umask 077
mkdir -p "$ROOT/.pi" "$ROOT/.runtime" "$PROFILE"
# Never silently replace an existing project configuration.
if [[ -e "$ROOT/.pi/mcp.json" ]]; then
  [[ $(jq -S . "$ROOT/.pi/mcp.json") == "$(expected_config | jq -S .)" ]] || fail 'Existing .pi/mcp.json differs; review it manually (also check whether this folder moved).'
else
  expected_config > "$ROOT/.pi/mcp.json"
fi
cd "$ROOT"
# Project-local scope takes precedence over a global adapter installation.
if [[ -e .pi/settings.json ]]; then
  jq -e --arg spec "npm:pi-mcp-adapter@$ADAPTER_VERSION" '
    (.packages // []) | all(.[]; (if type == "string" then . else .source end) as $s |
      (($s | contains("pi-mcp-adapter")) | not) or . == $spec)' .pi/settings.json >/dev/null ||
      fail 'Existing adapter registration differs or has filters; review .pi/settings.json manually.'
fi
pi install -l "npm:pi-mcp-adapter@$ADAPTER_VERSION"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --prefix "$ROOT/.runtime" --ignore-scripts --no-audit --no-fund --save-exact "@playwright/mcp@$MCP_VERSION"
"$SCRIPTS/validate-setup.sh"
cleanup_needed=true
# Both tests must use a fresh launch in the requested mode, not an unknown mode.
"$SCRIPTS/stop-chrome.sh"
for mode in visible headless; do
  echo "=== Testing $mode Chrome with example.com ==="
  if [[ "$mode" == headless ]]; then
    "$SCRIPTS/start-chrome.sh" --headless about:blank
  else
    "$SCRIPTS/start-chrome.sh" about:blank
  fi
  browser_pid=$(owned_pid)
  browser_command=$(ps -ww -p "$browser_pid" -o command=)
  if [[ "$mode" == headless ]]; then
    [[ "$browser_command" == *' --headless=new '* ]] || fail 'Headless mode not active.'
  else
    [[ "$browser_command" != *' --headless'* ]] || fail 'Expected visible Chrome, found headless.'
  fi
  "$SCRIPTS/validate-playwright.sh"
  "$SCRIPTS/stop-chrome.sh"
  echo "PASS: $mode mode and cleanup."
done
cleanup_needed=false
printf 'Start/restart Pi from %s and review project trust.\n' "$ROOT"
printf 'If already running here, /reload. Then run ./scripts/start-chrome.sh before /mcp reconnect playwright.\n'
