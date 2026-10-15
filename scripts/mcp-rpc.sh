#!/usr/bin/env bash
# Source from a caller with request FD 3 and response FD 4 open.
# MCP stdio uses one JSON-RPC message per line, not Content-Length framing.
mcp_request() {
  local id=$1 method=$2 params=$3 line remaining deadline
  jq -cn --argjson id "$id" --arg method "$method" --argjson params "$params" \
    '{jsonrpc:"2.0",id:$id,method:$method,params:$params}' >&3
  deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    IFS= read -r -t "$remaining" line <&4 || {
      echo "MCP response missing/timed out: $method" >&2; return 1;
    }
    jq -e 'type == "object" and .jsonrpc == "2.0"' <<< "$line" >/dev/null || {
      echo 'Invalid MCP stdout framing/JSON.' >&2; return 1;
    }
    if jq -e --argjson id "$id" 'has("id") and .id == $id' <<< "$line" >/dev/null; then
      jq -e 'has("result") and (has("error") | not) and (.result.isError != true)' <<< "$line" >/dev/null || {
        echo "MCP request failed: $method (response suppressed to avoid exposing browser content)" >&2
        if jq -e 'has("error")' <<< "$line" >/dev/null; then
          jq -r '.error | "JSON-RPC error \(.code): \(.message)"' <<< "$line" >&2
        fi
        # Print error-summary lines only, not snapshots or tab inventories.
        jq -r '.result.content[]? | select(.type == "text") | .text | split("\n")[] | select(test("^[A-Za-z]*Error:"))' <<< "$line" >&2
        # Surface safe Chromium error codes without URLs, snapshots or account data.
        jq -r '[.result.content[]? | select(.type == "text") | .text | scan("net::ERR_[A-Z0-9_]+") ] | unique[]' <<< "$line" >&2
        return 1
      }
      printf '%s\n' "$line"
      return 0
    fi
    # Allow notifications only; unexpected replies/server requests fail closed.
    jq -e '(has("id") | not) and (.method | type == "string")' <<< "$line" >/dev/null || {
      echo 'Unexpected MCP message.' >&2; return 1;
    }
  done
  echo "MCP deadline exceeded: $method" >&2
  return 1
}
