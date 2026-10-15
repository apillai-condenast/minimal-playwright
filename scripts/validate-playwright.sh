#!/usr/bin/env bash
# Actual Playwright MCP -> CDP smoke test, without Pi or custom JS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$SCRIPTS/mcp-rpc.sh"
[[ $# == 0 ]] || fail 'Usage: ./scripts/validate-playwright.sh'
"$SCRIPTS/validate-setup.sh"
"$SCRIPTS/validate-chrome.sh"
umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/minimal-mcp.XXXXXX")
server_pid=''
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$server_pid" ]]; then
    kill -TERM "$server_pid" 2>/dev/null || true
    for ((i=0; i<5; i++)); do
      kill -0 "$server_pid" 2>/dev/null || break
      sleep 1
    done
    # Only our transient MCP child; never signal Chrome here.
    kill -KILL "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  exec 3>&- 4>&-
  rm -rf "$work"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkfifo "$work/request" "$work/response"
# Open each end separately: Node may set its descriptors nonblocking.
# Sharing a read/write descriptor with Bash causes EAGAIN on macOS.
"$SCRIPTS/mcp-server.sh" <"$work/request" >"$work/response" 2>"$work/stderr" &
server_pid=$!
exec 3>"$work/request"
exec 4<"$work/response"
echo 'Testing MCP initialization...'
reply=$(mcp_request 1 initialize '{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"minimal-shell-validation","version":"1.0.0"}}')
jq -e '.result.protocolVersion == "2024-11-05" and (.result.capabilities.tools | type == "object")' <<< "$reply" >/dev/null || fail 'Unexpected MCP initialization/capabilities.'
printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' >&3
echo 'Discovering Playwright tools...'
reply=$(mcp_request 2 tools/list '{}')
jq -e '[.result.tools[].name] as $names | ["browser_tabs", "browser_wait_for", "browser_resize", "browser_take_screenshot"] | all(.[]; . as $name | $names | index($name) != null)' <<< "$reply" >/dev/null || fail 'Required tab/wait/resize/screenshot tools are missing.'
reply=$(mcp_request 3 tools/call '{"name":"browser_tabs","arguments":{"action":"list"}}')
jq -e '.result.content | any(.[]; .type == "text" and (.text | length > 0))' <<< "$reply" >/dev/null || fail 'Empty browser_tabs result.'
# Open a NEW tab through Playwright, never navigate an existing user tab.
echo 'Opening a new example.com tab through Playwright...'
reply=$(mcp_request 4 tools/call '{"name":"browser_tabs","arguments":{"action":"new","url":"https://example.com"}}')
echo 'Waiting for example.com documentation text...'
reply=$(mcp_request 5 tools/call '{"name":"browser_wait_for","arguments":{"text":"This domain is for use in documentation examples"}}')
jq -e '.result.content | any(.[]; .type == "text" and (.text | contains("This domain is for use in documentation examples")))' <<< "$reply" >/dev/null || fail 'Playwright did not confirm example.com documentation text.'
# Confirm the owned endpoint survived and independently verify URL/title via CDP.
check_cdp
curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$ENDPOINT/json/list" |
  jq -e 'any(.[]; .type == "page" and (.url == "https://example.com/" or .url == "https://example.com") and .title == "Example Domain")' >/dev/null || fail 'Expected example.com URL/title not found in the verified Chrome.'
browser_pid=$(owned_pid)
browser_command=$(ps -ww -p "$browser_pid" -o command=)
mode=visible
if [[ "$browser_command" == *' --headless'* ]]; then mode=headless; fi
mkdir -p "$ROOT/test_screenshots"
screenshot="$ROOT/test_screenshots/test_screenshot_${mode}_$(date -u +%Y%m%dT%H%M%SZ)_$$.png"
echo "Saving $mode screenshot: $screenshot"
reply=$(mcp_request 6 tools/call '{"name":"browser_resize","arguments":{"width":1500,"height":840}}')
params=$(jq -cn --arg filename "$screenshot" '{name:"browser_take_screenshot",arguments:{filename:$filename,type:"png",fullPage:true,scale:"css"}}')
reply=$(mcp_request 7 tools/call "$params")
[[ -s "$screenshot" ]] || fail "Screenshot missing or empty: $screenshot"
magic=$(od -An -tx1 -N8 "$screenshot" | tr -d ' \n')
[[ "$magic" == 89504e470d0a1a0a ]] || fail "Screenshot is not a PNG: $screenshot"
echo 'PASS: MCP handshake, Playwright attachment, example.com content/URL/title, and timestamped PNG screenshot.'
echo 'Transient MCP server disconnected. Chrome and the example.com test tab remain open; existing tabs preserved.'
