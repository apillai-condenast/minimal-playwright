#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"$SCRIPTS/validate-scripts.sh"
prerequisites
[[ $(jq -S . "$ROOT/.pi/mcp.json") == "$(expected_config | jq -S .)" ]] || fail 'MCP configuration mismatch; run setup.sh.'
jq -e --arg spec "npm:pi-mcp-adapter@$ADAPTER_VERSION" '.packages | index($spec) != null' "$ROOT/.pi/settings.json" >/dev/null || fail 'Adapter is not registered locally.'
[[ $(jq -r .version "$ROOT/.pi/npm/node_modules/pi-mcp-adapter/package.json") == "$ADAPTER_VERSION" ]] || fail 'Adapter installation/version mismatch.'
[[ $(jq -r .version "$ROOT/.runtime/node_modules/@playwright/mcp/package.json") == "$MCP_VERSION" ]] || fail 'Playwright MCP installation/version mismatch.'
cli="$ROOT/.runtime/node_modules/.bin/playwright-mcp"
"$cli" --version | grep -F "$MCP_VERSION" >/dev/null
help=$("$cli" --help)
[[ "$help" == *--cdp-endpoint* ]] || fail 'MCP CLI lacks CDP attachment support.'
printf 'Setup validation passed (Node %s, MCP %s, adapter %s). No browser attachment tested.\n' "$(node --version)" "$MCP_VERSION" "$ADAPTER_VERSION"
