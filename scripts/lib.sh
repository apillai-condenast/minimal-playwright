#!/usr/bin/env bash
# Shared constants; all paths are independent of the caller's working directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPTS="$ROOT/scripts"
PROFILE="$ROOT/automation_user_data_dir"
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT=9223
ENDPOINT="http://127.0.0.1:$PORT"
MCP_VERSION=0.0.83
ADAPTER_VERSION=2.27.0
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
prerequisites() {
  [[ $(uname -s) == Darwin ]] || fail 'This setup supports macOS only.'
  local cmd
  for cmd in node npm pi jq curl lsof ps open; do
    command -v "$cmd" >/dev/null || fail "Missing prerequisite: $cmd (see README.md)"
  done
  [[ $(node --version) == v22.* ]] || fail 'Activate Node 22 first.'
  [[ -x "$CHROME" ]] || fail "Install Google Chrome at $CHROME"
}
listener() { lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u; }
owned_pid() {
  local pid command
  pid=$(listener) || fail "No Chrome CDP listener on $PORT; run start-chrome.sh."
  [[ "$pid" =~ ^[0-9]+$ ]] || fail "Expected exactly one listener on $PORT."
  command=$(ps -ww -p "$pid" -o command=)
  [[ "$command" == "$CHROME "* && "$command" == *" --user-data-dir=$PROFILE --"* && "$command" == *" --remote-debugging-port=$PORT "* ]] || fail "Port $PORT is not owned by this setup's Chrome; refusing."
  printf '%s\n' "$pid"
}
check_cdp() {
  owned_pid >/dev/null
  curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$ENDPOINT/json/version" |
    jq -e --arg prefix "ws://127.0.0.1:$PORT/devtools/browser/" '.webSocketDebuggerUrl | startswith($prefix)' >/dev/null
  curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$ENDPOINT/json/list" |
    jq -e 'type == "array"' >/dev/null
}
expected_config() {
  jq -n --arg command "$SCRIPTS/mcp-server.sh" '{mcpServers:{playwright:{command:$command,args:[],lifecycle:"lazy-keep-alive",requestTimeoutMs:60000,directTools:true}}}'
}
