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

The local app is intentionally unsigned. Developer ID signing, notarization,
stapling, and the Homebrew cask are deferred until the Apple Developer Program
go/no-go decision.

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
