#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ -x "$ROOT/setup.sh" ]] || fail 'Missing or non-executable: setup.sh'
for name in lib mcp-server mcp-rpc start-chrome stop-chrome validate-scripts validate-setup validate-chrome validate-playwright test; do
  [[ -x "$SCRIPTS/$name.sh" ]] || fail "Missing or non-executable: $name.sh"
done
for script in "$ROOT/setup.sh" "$SCRIPTS"/*.sh; do
  bash -n "$script"
done
if command -v shellcheck >/dev/null; then
  shellcheck -x -P "$SCRIPTS:$ROOT" "$ROOT/setup.sh" "$SCRIPTS"/*.sh
else
  echo 'shellcheck unavailable (optional); Bash syntax checks passed.'
fi
