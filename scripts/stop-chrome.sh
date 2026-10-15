#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ $# == 0 || ( $# == 1 && $1 == --dry-run ) ]] || fail 'Usage: ./scripts/stop-chrome.sh [--dry-run]'
prerequisites
if [[ -z $(listener) ]]; then
  echo 'No CDP listener; nothing stopped. If Chrome is still open, close its automation window manually.'
  exit 0
fi
pid=$(owned_pid)
if [[ ${1:-} == --dry-run ]]; then
  echo "Would close all tabs in verified automation Chrome PID $pid, then send TERM; profile preserved."
  exit 0
fi
echo "Closing all tabs in verified automation Chrome PID $pid..."
# Use CDP's HTTP target-close API; no extra Playwright process is needed.
# Re-read targets to confirm closure, including tabs opened during shutdown.
closed=false
for ((attempt=0; attempt<30; attempt++)); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo 'Chrome exited after closing its tabs; profile preserved.'
    exit 0
  fi
  [[ $(owned_pid) == "$pid" ]] || fail 'Listener changed; refusing to close tabs.'
  targets=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$ENDPOINT/json/list") || fail 'Cannot list Chrome tabs; refusing to stop before confirming closure.'
  jq -e 'type == "array"' <<< "$targets" >/dev/null || fail 'Invalid CDP target list.'
  ids=$(jq -r '.[] | select(.type == "page") | .id | @uri' <<< "$targets")
  if [[ -z "$ids" ]]; then
    closed=true
    break
  fi
  while IFS= read -r id; do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    [[ $(owned_pid) == "$pid" ]] || fail 'Listener changed; refusing to close tabs.'
    # A target may close concurrently. Re-list next iteration to verify the outcome.
    curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$ENDPOINT/json/close/$id" >/dev/null || true
  done <<< "$ids"
  sleep 1
done
[[ "$closed" == true ]] || fail 'Tabs did not all close within 30 attempts; Chrome was not terminated.'
echo 'All tabs closed. Stopping automation Chrome...'
[[ $(owned_pid) == "$pid" ]] || fail 'Listener changed; refusing to stop.'
kill -TERM "$pid"
for ((i=0; i<30; i++)); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo 'Chrome stopped; profile preserved.'
    exit 0
  fi
  sleep 1
done
fail 'Chrome has not exited; inspect manually. No force-kill performed.'
