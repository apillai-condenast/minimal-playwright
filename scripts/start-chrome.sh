#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
headless=false
if [[ ${1:-} == --headless ]]; then headless=true; shift; fi
[[ $# -le 1 ]] || fail 'Usage: ./scripts/start-chrome.sh [--headless] [http(s)://URL]'
url=${1:-about:blank}
case "$url" in http://*|https://*|about:blank) ;; *) fail 'Expected HTTP(S) URL or about:blank.' ;; esac
"$SCRIPTS/validate-setup.sh"
[[ -z $(listener) ]] || fail "Port $PORT is occupied. Run validate-chrome.sh; no automatic reuse or killing."
if [[ -e "$PROFILE/SingletonLock" || -L "$PROFILE/SingletonLock" ]]; then
  lock=$(readlink "$PROFILE/SingletonLock") || fail 'Unrecognized profile lock; inspect manually.'
  lock_pid=${lock##*-}
  lock_host=${lock%-*}
  [[ "$lock_host" == "$(hostname)" && "$lock_pid" =~ ^[0-9]+$ ]] || fail 'Profile lock ownership is uncertain; inspect manually.'
  if ps -p "$lock_pid" >/dev/null 2>&1; then
    fail "Profile lock PID $lock_pid is still running; close its Chrome first."
  fi
  echo "Stale local profile lock (PID $lock_pid is absent); letting Chrome recover it."
fi
umask 077
mkdir -p "$PROFILE"
echo "Starting local Chrome profile (headless=$headless; no Chrome sign-in required): $PROFILE"
args=(--user-data-dir="$PROFILE" --profile-directory=Default
  --remote-debugging-address=127.0.0.1 --remote-debugging-port="$PORT"
  --window-size=1500,840 --no-first-run --no-default-browser-check)
if [[ "$headless" == true ]]; then
  mkdir -p "$ROOT/.runtime"
  nohup "$CHROME" "${args[@]}" --headless=new "$url" </dev/null >"$ROOT/.runtime/chrome-headless.log" 2>&1 &
else
  open -na '/Applications/Google Chrome.app' --args "${args[@]}" "$url"
fi
echo "Waiting for Chrome CDP at $ENDPOINT (not profile login)..."
for ((i=0; i<30; i++)); do
  if (check_cdp) >/dev/null 2>&1; then
    echo "Chrome ready: $ENDPOINT; profile: $PROFILE"
    exit 0
  fi
  if (( i % 5 == 0 )); then
    echo "CDP not ready yet (attempt $((i + 1))/30)..."
  fi
  sleep 1
done
(check_cdp) || true
fail 'Chrome/CDP readiness timed out; no Chrome sign-in is required. Inspect the endpoint error above. No processes were killed.'
