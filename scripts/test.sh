#!/usr/bin/env bash
# Offline regression tests: no installs, browser launch, network, or signals.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"$SCRIPTS/validate-scripts.sh"
command -v jq >/dev/null || fail 'Tests require jq.'
expected_config | jq -e --arg command "$SCRIPTS/mcp-server.sh" '.mcpServers.playwright | .command == $command and .directTools == true' >/dev/null
for url in file:///etc/passwd javascript:alert invalid; do
  if "$SCRIPTS/start-chrome.sh" "$url" >/dev/null 2>&1; then
    fail "Accepted invalid URL: $url"
  fi
done
if "$SCRIPTS/stop-chrome.sh" --force >/dev/null 2>&1; then fail 'Accepted unsafe stop option'; fi
if "$SCRIPTS/start-chrome.sh" --headless file:///etc/passwd >/dev/null 2>&1; then fail 'Headless accepted invalid URL'; fi
if output=$("$ROOT/setup.sh" --invalid 2>&1); then fail 'Setup accepted invalid flag'; fi
[[ "$output" == *'Setup complete: ERROR'* ]] || fail 'Setup failure summary missing'
listener() { echo 12345; }
ps() { printf '%s\n' "$mock_command"; }
mock_command="$CHROME --user-data-dir=$PROFILE --remote-debugging-address=127.0.0.1 --remote-debugging-port=$PORT --no-first-run"
[[ $(owned_pid) == 12345 ]] || fail 'Rejected owned Chrome.'
for mock_command in "/bin/unrelated --remote-debugging-port=$PORT" "$CHROME --user-data-dir=/other --remote-debugging-port=$PORT --no-first-run"; do
  if (owned_pid) >/dev/null 2>&1; then fail 'Accepted unrelated listener'; fi
done
listener() { printf '12345\n67890\n'; }
if (owned_pid) >/dev/null 2>&1; then fail 'Accepted multiple listeners'; fi
listener() { :; }
if (owned_pid) >/dev/null 2>&1; then fail 'Accepted missing listener'; fi
source "$SCRIPTS/mcp-rpc.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/minimal-rpc-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
exec 3>"$work/requests"
printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/message"}' '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}' > "$work/responses"
exec 4<"$work/responses"
reply=$(mcp_request 1 ping '{}')
jq -e '.result.ok == true' <<< "$reply" >/dev/null
jq -e '.method == "ping" and .id == 1' "$work/requests" >/dev/null
for response in \
  '{"jsonrpc":"2.0","id":1,"error":{"code":-1}}' \
  '{"jsonrpc":"2.0","id":1,"result":{"isError":true}}' \
  '{"jsonrpc":"2.0","id":2,"result":{}}' \
  'not JSON'; do
  printf '%s\n' "$response" > "$work/responses"
  exec 4<"$work/responses"
  if (mcp_request 1 ping '{}') >/dev/null 2>&1; then fail 'Accepted invalid MCP response'; fi
done
: > "$work/responses"
exec 4<"$work/responses"
if (mcp_request 1 ping '{}') >/dev/null 2>&1; then fail 'Accepted missing MCP response'; fi
exec 3>&- 4>&-
echo 'Offline regression tests passed (including MCP protocol success/error/EOF cases).'
