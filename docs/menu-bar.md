# Menu Bar App

The menu bar app is a native Swift/AppKit presentation layer for UpdateBar.

Current scope:

- prefers direct `UpdateBarCore` calls through `CoreMenuBarService`
- keeps `UpdateBarCLIClient` as a subprocess fallback with JSON-only contracts
- shows outdated items separately from recipes that need command approval
- shows command text before approve/revoke actions
- supports check now, update selected, update all approved outdated, approve/revoke command fields,
  cancel current action, open TUI, open config, view logs, and quit

Build a local unsigned app:

```bash
Scripts/package-app.sh
open dist/UpdateBar.app
```

Install the published unsigned app with Homebrew:

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
UPDATEBAR_CLI=.build/debug/updatebar .build/debug/updatebar-menubar
```

Use the fallback adapter explicitly:

```bash
UPDATEBAR_MENUBAR_ADAPTER=cli UPDATEBAR_BIN=.build/debug/updatebar .build/debug/updatebar-menubar
```

View logs from the menu bar app at `~/Library/Logs/UpdateBar/updatebar-menubar.log`.
If that file does not exist yet, the menu item opens the UpdateBar home directory.
Recent logs are retained automatically with a rotating local cap.

The app is currently unsigned. If macOS blocks the first launch, Control-click
`UpdateBar.app` in Finder, choose Open, then confirm Open. Developer ID signing,
notarization, and stapling are deferred until the Apple Developer Program
go/no-go decision.

`Open Config` opens `~/.updatebar/config.toml` when it exists; if the file is not
present, it opens the UpdateBar home directory instead.

Troubleshooting a missing icon:

```bash
pkill -f UpdateBar
UPDATEBAR_BIN=/full/path/to/updatebar ./dist/UpdateBar.app/Contents/MacOS/UpdateBar \
  >/tmp/updatebar-menubar.log 2>&1 &
sleep 2
tail -n 60 /tmp/updatebar-menubar.log
```

When `UpdateBarMenuBar: UpdateBarMenuBar main starting` is not printed, the binary
isn't launching. If it starts but no menu icon appears, try:

```bash
open dist/UpdateBar.app
pgrep -ax UpdateBar
```
