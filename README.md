# Minimal Pi + Playwright MCP + visible/headless Chrome

Self-contained **macOS** setup. All executable setup/validation logic is Bash
(with jq for JSON); no Python or custom JavaScript scripts. Run Pi **from this
folder**, not the parent checkout. Copy the whole folder to reuse elsewhere.
`setup.sh` and this `README.md` stay at the root; all supporting shell scripts
are in `scripts/`. Runtime, profile, and screenshot paths remain at this root.

## Prerequisites

Install Google Chrome in `/Applications`, Node **22** with npm, jq, and Pi.
Bash, curl, lsof, ps, and open are also required. For example, with your approved
package manager / nvm installation:

```sh
cd minimal
nvm install
nvm use
brew install jq                         # if missing
npm install -g --ignore-scripts @earendil-works/pi-coding-agent # if missing
./setup.sh
```

`./setup.sh` is the single setup entry point. It checks every shell script,
checks prerequisites, creates `.pi/mcp.json`, installs project-local
`pi-mcp-adapter@2.27.0`, installs `@playwright/mcp@0.0.83` into `.runtime/`, and
validates the installed CLI/configuration. It then tests **both modes** in order:
visible Chrome, followed by headless Chrome, each freshly started at `about:blank`.
In each mode, a shell-driven Playwright MCP test opens a **new tab** at
`https://example.com`, waits for its documentation-example body text, and verifies
its URL and “Example Domain” title through CDP. The launcher process arguments
are checked to ensure the requested mode is active. Each mode then resizes to
1500 × 840 and saves a full-page PNG under `test_screenshots/`, for example
`test_screenshot_headless_20261015T120000Z_12345.png`. Names include the mode,
UTC timestamp, and process ID. Setup checks the file is nonempty with a PNG
signature. Screenshots are Git-ignored and retained after browser cleanup;
previous screenshots are never removed by setup.

After each mode, setup stops its transient Playwright MCP process, closes all
automation tabs, and stops Chrome, preserving the local profile. Cleanup also
runs on failure or interruption. **Save work in the automation browser first:**
setup closes any verified existing automation instance before starting tests.
Other Chrome instances and Pi-owned MCP processes are not killed.

The final line is `Setup complete: SUCCESS` (with a summary) only after both
modes and cleanup pass. Any failure ends with `Setup complete: ERROR`, the exit
status, and a nonzero shell exit code. Setup always tests both modes; it takes
no mode-selection flag.
These pins match the inspected adapter and parent repository's MCP version.
It does **not** install Chrome, Node, Pi, or browser binaries, or authenticate you.
Installation requires network access on first run; the live test requires
HTTPS access to example.com on every run. Review third-party package
trust prompts: Pi extensions run with your user privileges.

Repeat setup to repair missing installations. Conflicting configuration or
adapter registrations fail instead of being silently overwritten. MCP paths
are absolute: after moving this folder, review/update the generated
`.pi/mcp.json` before rerunning setup. `.runtime/package-lock.json` is retained
locally for subsequent npm installs; transitive dependencies are not pinned in
this checkout. Do not run setup concurrently.

## Start, attach, stop

1. Start `pi` here. Authenticate the model provider locally with `/login` and
   choose `/model`. Review project trust. If Pi was already running here, use
   `/reload` after setup and confirm the adapter is loaded (`/mcp`). Shell setup
   has already verified live Playwright attachment; this checks Pi integration. Restart
   from this folder if it is not. Do not use `--no-extensions` or filter out MCP.
2. Setup has closed its test Chrome. Start Chrome again for actual use:

   ```sh
   ./scripts/start-chrome.sh
   # Or: ./scripts/start-chrome.sh 'https://your-approved-target.example'
   # Or, instead of visible Chrome:
   # ./scripts/start-chrome.sh --headless 'https://example.com'
   ./scripts/validate-chrome.sh
   # ./scripts/validate-playwright.sh  # opens/tests example.com in the running mode
   ```

3. In Pi run `/mcp reconnect playwright`, then ask:

   > Read the Playwright MCP instructions. Use browser_tabs with action list
   > to attach to the existing Chrome at http://127.0.0.1:9223. Do not launch
   > another browser. Confirm the intended tab, resize to 1500 × 840 and verify
   > window.innerWidth and window.innerHeight. Do not navigate or capture app
   > content until I approve the target.

   Tool names normally appear as `playwright_browser_tabs`,
   `playwright_browser_resize`, and `playwright_browser_evaluate`. If not yet
   visible, use the adapter's `mcp` search/describe tools to discover them.
   `scripts/mcp-server.sh` always passes `--cdp-endpoint` to Playwright, so MCP attaches
   to this Chrome rather than launching its own. A successful **browser_tabs
   tool call** confirms Pi's own attachment. Setup has already performed the
   same call through a transient MCP server from shell; MCP discovery or the
   HTTP CDP check alone is not proof of attachment.
4. For an authenticated app, wait for the user to log in and explicitly
   confirm the intended account; verify the application's displayed identity
   before exploring. Do not request credentials in chat. For full exploration,
   follow the parent `README.md` and `exploration.md` approval/login protocol.
   This minimal bootstrap intentionally tests Chrome startup and example.com
   navigation before reload, as requested; it does not explore your application.
5. Close only this automation Chrome when finished:

   ```sh
   ./scripts/stop-chrome.sh --dry-run
   ./scripts/stop-chrome.sh
   ```

Quitting Pi does not stop Chrome. Stop verifies the listening PID, executable,
profile path and port, closes **all page tabs in that automation instance** via
CDP, confirms no page tabs remain, then sends TERM. If tabs cannot be closed,
it reports failure instead of terminating Chrome. It never uses `killall`,
force-kills, or deletes the profile. Save any work first. Without a CDP
listener it cannot safely identify Chrome and leaves it alone.

## Local state and safety

- Persistent profile: `minimal/automation_user_data_dir/`, private on creation,
  Git-ignored. Chrome uses its local `Default` profile; **never sign in to a
  Chrome/Google profile**. Startup waits only for CDP, not profile login or an
  existing page. Application login is separate. App sessions survive restarts;
  never commit/share this folder.
- CDP: loopback-only `127.0.0.1:9223` (different from the parent setup's 9222).
  CDP grants browser control without authentication. Never expose/forward it.
- Busy ports and active/uncertain profile locks fail closed. A lock naming this
  host and an absent PID is left for Chrome itself to recover; scripts never
  delete profile locks. Validate ownership before reuse; never kill unknown listeners. To reuse an already
  running instance, run `scripts/validate-chrome.sh` and then attach in Pi directly.
- Setup changes only this folder's runtime/config, plus normal npm/Pi caches
  and trust records. It does not alter the parent's scripts or configuration.
- Chrome's window-size flag is not a viewport guarantee; verify via Playwright.
- Generated profile/runtime/config and default MCP artifacts are ignored.
  Other screenshots/reports may contain secrets: choose an ignored destination
  and inspect before sharing. Do not capture login traffic or authentication data.

## Validation

```sh
./scripts/validate-scripts.sh   # executable bits + bash -n; optional ShellCheck
./scripts/test.sh               # offline input/ownership + MCP response/error tests
./scripts/validate-setup.sh      # prerequisites, config, adapter pin, MCP CLI
./scripts/validate-chrome.sh     # live process/profile ownership + CDP endpoints
./scripts/validate-playwright.sh # example.com attachment/content/URL/title/screenshot
```

`./setup.sh` runs **all of these checks**, including Chrome startup and live
Playwright attachment, before asking for `/reload`. Only `scripts/test.sh` is offline.
The live test uses Bash FIFOs and jq to speak newline-delimited JSON-RPC to
`scripts/mcp-server.sh`: initialize, send the initialized notification, discover
`browser_tabs`/`browser_wait_for`, list tabs, open a new example.com tab, and
wait for “This domain is for use in documentation examples”. CDP independently
checks its URL and “Example Domain” title (the title need not appear in the body).
Each request has a 60-second deadline; protocol errors, tool errors, blocked
navigation, missing expected content, or missing/invalid screenshots fail setup.
It does not log in or print tab inventories. It captures only the example.com
test page; both mode screenshots are retained in `test_screenshots/`. Playwright may save navigation snapshots
under the Git-ignored `.playwright-mcp/` directory. Private temporary
protocol/stderr files are removed on exit; the transient MCP process is stopped.
When called by setup, Chrome is closed on success or failure; its profile is
always preserved. Running `scripts/validate-playwright.sh` standalone stops only its
own MCP process and leaves Chrome open for inspection. A busy port owned by
another process is rejected, never killed or reused. Setup closes a verified
existing automation browser first, then tests fresh visible and headless launches.
No broad process-name kills are used. Standalone `scripts/start-chrome.sh --headless`
uses the same local profile/CDP port; stop the current browser before switching
modes. Headless startup diagnostics are in `.runtime/chrome-headless.log`.

The remaining manual check is specifically Pi's extension loading/trust and
its own MCP connection. Shell cannot prove the current interactive Pi session
reloaded its tools. Use `/reload`, run `./scripts/start-chrome.sh`, then use
`/mcp reconnect playwright` and the Pi browser-tabs check above. No provider credentials are needed for shell tests.
