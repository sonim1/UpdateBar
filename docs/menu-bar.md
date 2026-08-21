# Menu Bar App

The menu bar app is a native Swift/AppKit presentation layer for UpdateBar.
Clicking the status item opens a native `NSMenu`.
The menu follows the macOS system appearance and is rebuilt from current state using
standard menu items, separators, submenus, application icons, and checkmarks.

Current scope:

- prefers direct `UpdateBarCore` calls through `CoreMenuBarService`
- keeps `UpdateBarCLIClient` as a subprocess fallback with JSON-only contracts
- shows outdated items separately from services requiring command approval, with
  per-item update actions
- presents command approval as one native submenu row per service; its right-hand
  submenu exposes per-field approve/revoke actions; exact command text and cwd
  appear only in confirmation
- provides `Check Now` and `Update All`, Refresh Status, Dashboard, Manage Items,
  Scan & Add, Settings, About, app-update check, and Quit through native menu
  items; Update All is disabled when there are no outdated items
- starts individual updates and Update All immediately without a modal confirmation;
  command approvals and revocations still require confirmation
- watches the CLI-owned manifest, state, config, and history files and refreshes
  the visible menu automatically when they change
- augments the restricted environment of a Finder-launched app with common
  Homebrew, npm version-manager, Cargo, Bun, and mise executable paths
- replaces actionable rows with `Checking for updates...`, Dashboard, and Quit
  while a refresh is in flight, so stale update and approval actions cannot run
- keeps every row rendered while an action is in flight. Items being updated
  read `— updating…`, items still queued read `— queued`, and finished items
  read `— done`. Check Now, Refresh Status, Update All, and the per-item update
  and approval actions are disabled for the duration; Dashboard, Manage Items,
  Scan & Add, Settings, About, app-update check, and Quit stay available
- shows the active title with a completed/total count plus `Stop After Current`,
  which lets the running command finish and starts nothing new. There is no
  hard cancel in the menu bar: killing a half-finished package manager leaves
  state UpdateBar cannot describe. A hung update command therefore blocks the
  action until the 30 minute execution timeout, and quitting the app is the
  only earlier escape. `updatebar update` in a terminal still hard-cancels on
  Ctrl-C
- updates several items at once, capped by `update.max_concurrent` (default 3).
  Two recipes whose `update.cmd` invokes the same tool never run at the same
  time
- under `UPDATEBAR_MENUBAR_ADAPTER=cli`, the opt-in subprocess adapter, there is
  no per-item progress; the menu shows only the coarse running state, which is
  expected rather than a regression

`Dashboard` opens the Dashboard window directly. A left sidebar switches between
Overview, Items, Scan & Add, Logs, Settings, and About in the same Dashboard window, with each section
using native macOS UI. The sidebar, Items, Scan & Add, and Logs use AppKit controls;
Overview, Settings, and About are SwiftUI-hosted. The sidebar footer shows a single
update summary when updates are available. It stays within the sidebar width and
opens Items without starting an update; individual names, versions, and update actions
live in Items.
Overview shows pending-update and
awaiting-approval counts, last check/update times, and a bar chart of successful
updates over the last four weeks (from `~/.updatebar/history.jsonl`). Logs shows
the newest persisted update and check events first, including update result and
version transition. Items lists every registered item grouped by category with
a separate enable/disable checkbox. Eligible outdated rows also provide a
row-level Update action. Users can select one or more eligible rows and run
Update Selected; only outdated items are selectable. Current, disabled, pinned,
checking, errored, and approval-blocked rows explain why updating is unavailable.
Dashboard updates share the menu bar's global action state, progress, bounded
parallelism, and Stop After Current behavior. `Manage Items...` opens that
Dashboard window with Items selected, and
`Scan & Add` opens it with Scan & Add selected, so neither action creates another
panel. Scan & Add scans only when you press Scan. Checking an available candidate
registers it immediately without approving any commands. Unchecking disables it
without deleting it, and checking it again re-enables the same item. While the
Dashboard window is visible, UpdateBar appears in Cmd-Tab and the Dock. Closing
the last visible titled UpdateBar window returns the process to menu-bar-only
mode.

If an operation or status refresh fails, the status badge changes to `!` and the
app directly assigns a native error-recovery menu. Refresh Status, Check Now,
Dashboard, item management, settings, app-update check, and Quit remain
reachable.

Build a local unsigned app:

```bash
Scripts/package-app.sh
Scripts/menubar-smoke-test.sh
open dist/UpdateBar.app
```

Install the published app with Homebrew:

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

The `updatebar-app` cask installs `UpdateBar.app` and links the bundled
`updatebar` CLI onto your Homebrew `PATH`. Use
`brew install --formula sonim1/tap/updatebar` only for a CLI-only installation.

For development without packaging:

```bash
swift build --product updatebar
swift build --product updatebar-menubar
UPDATEBAR_BIN=.build/debug/updatebar .build/debug/updatebar-menubar
```

Use the fallback adapter explicitly:

```bash
UPDATEBAR_MENUBAR_ADAPTER=cli UPDATEBAR_BIN=.build/debug/updatebar .build/debug/updatebar-menubar
```

Open Dashboard → Logs to view update and check history. Menu-bar diagnostic output
is still retained at `~/Library/Logs/UpdateBar/updatebar-menubar.log` for support.
Long item lists in the menu are compacted with overflow summaries.
Recent logs are retained automatically with a rotating local cap.

Releases from v0.3.0 are signed with a Developer ID certificate and notarized
by Apple. Local `Scripts/package-app.sh` builds stay unsigned unless the
signing environment variables are provided.

TUI is not exposed by the menu bar. Run `updatebar tui` directly in a terminal
when you need it. Install the TUI with
`brew install sonim1/tap/updatebar-tui`, or set `UPDATEBAR_TUI` to a dev-built
executable to override the `PATH` lookup.

`Settings` opens the shared Dashboard window on the General and Updates sections.
It edits the active UpdateBar configuration (by default `HOME/.updatebar/config.toml`)
(`UPDATEBAR_HOME` can point to an alternate data directory) and exposes Sparkle's
app-update check. The legacy `Open Config` menu action now routes to `Settings`.
`About` shows the app version, build,
support contact, and acknowledgments without duplicating dashboard statistics.

Troubleshooting a missing icon:

```bash
Scripts/menubar-smoke-test.sh
LOG_PATH=/tmp/updatebar-menubar.log
UPDATEBAR_BIN=/full/path/to/updatebar ./dist/UpdateBar.app/Contents/MacOS/UpdateBar \
  >"$LOG_PATH" 2>&1 &
MENUBAR_PID=$!
sleep 2
kill "$MENUBAR_PID" 2>/dev/null || true
wait "$MENUBAR_PID" 2>/dev/null || true
tail -n 60 "$LOG_PATH"
```

When `UpdateBarMenuBar: UpdateBarMenuBar main starting` is not printed, the binary
isn't launching. If it starts but no menu icon appears, try:

```bash
open dist/UpdateBar.app
pgrep -ax UpdateBar
```

The menu bar app intentionally runs as an accessory process (`LSUIElement=true`).
It is normal that Dock and Command-Tab do not show an icon while only the status
menu is visible. Opening `Dashboard...`, `Settings...`, or `About UpdateBar`
switches the app to
regular mode so Dock and Command-Tab visibility appears for that window, then
returns to accessory mode when the last titled window closes.
