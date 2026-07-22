# Menu Bar App

The menu bar app is a native Swift/AppKit presentation layer for UpdateBar.
Clicking the status item opens a native `NSMenu`.
The menu follows the macOS system appearance and is rebuilt from current state using
standard menu items, separators, submenus, application icons, and checkmarks.

Current scope:

- prefers direct `UpdateBarCore` calls through `CoreMenuBarService`
- keeps `UpdateBarCLIClient` as a subprocess fallback with JSON-only contracts
- shows outdated items separately from recipes that need command approval, with
  per-item update and approve/revoke actions
- shows command text before approve/revoke actions
- provides `Check Now` and `Run Updates`, Refresh Status, Open TUI, Dashboard,
  Manage Items, Scan & Add, Open Config, View Logs, and Quit through native menu
  items; Run Updates is disabled when there are no outdated items
- expands Open TUI into a native submenu when multiple supported terminals are
  installed, with the selected terminal marked by a checkmark
- replaces actionable rows with `Checking for updates...`, Dashboard, and Quit
  while a refresh is in flight, so stale update and approval actions cannot run
- limits an active-action menu to Running, Cancel Current Action, Dashboard,
  View Logs, and Quit until the action finishes
- keeps bulk-update confirmation in the app dispatcher before approved update
  commands run

`Dashboard` opens the Dashboard window directly. A left sidebar switches between
Overview, Items, and Scan & Add in the same Dashboard window, with each section
using native macOS UI. The sidebar, Items, and Scan & Add use AppKit controls;
Overview is SwiftUI-hosted. Overview shows pending-update and
awaiting-approval counts, last check/update times, and a bar chart of successful
updates over the last four weeks (from `~/.updatebar/history.jsonl`). Items lists
every registered item grouped by category with an enable/disable checkbox per
item. `Manage Items...` opens that Dashboard window with Items selected, and
`Scan & Add` opens it with Scan & Add selected, so neither action creates another
panel. Scan & Add scans only when you press Scan. Checking an available candidate
registers it immediately without approving any commands. Unchecking disables it
without deleting it, and checking it again re-enables the same item. While the
Dashboard window is visible, UpdateBar appears in Cmd-Tab and the Dock. Closing
the last visible titled UpdateBar window returns the process to menu-bar-only
mode.

If an operation or status refresh fails, the status badge changes to `!` and the
app directly assigns a native error-recovery menu. Refresh Status, Check Now,
Open TUI, Dashboard, item management, configuration, logs, and Quit remain
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

The `updatebar-app` cask installs only `UpdateBar.app`. Install the CLI separately
with `brew install sonim1/tap/updatebar`.

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

View logs from the menu bar app at `~/Library/Logs/UpdateBar/updatebar-menubar.log`.
If that file does not exist yet, the menu item opens the UpdateBar home directory
instead. The same fallback is used by `Open Config`.
Long item lists in the menu are compacted with overflow summaries.
Recent logs are retained automatically with a rotating local cap.

Releases from v0.3.0 are signed with a Developer ID certificate and notarized
by Apple. Local `Scripts/package-app.sh` builds stay unsigned unless the
signing environment variables are provided.

Tip: `Open TUI` runs `updatebar tui` with the bundled CLI in your chosen
terminal. When more than one supported terminal is installed (Terminal, iTerm,
Ghostty, kitty, Alacritty, WezTerm, Warp, Rio), `Open TUI` expands into a
submenu of those terminals with each app's icon — pick one and the TUI opens
there; the last choice is marked.
Most terminals launch the shared `.command` file directly; Warp has no exec
flag, so the app writes a launch configuration to
`~/.warp/launch_configurations/updatebar-tui.yaml` and opens it via the
`warp://launch/` URI. Install the TUI with
`brew install sonim1/tap/updatebar-tui`, or set `UPDATEBAR_TUI` to a dev-built
executable to override the `PATH` lookup.

`Open Config` opens the active UpdateBar config file when it exists; by default
that is `HOME/.updatebar/config.toml`, and `UPDATEBAR_HOME` can point the app at
an alternate data directory. If the config file is not present, the app opens the
active UpdateBar home directory instead.

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
