# Menu Bar App

The menu bar app is a thin local wrapper around the bundled CLI.

Current M4 scope:

- reads state with `updatebar status --json --exit-zero-on-outdated`
- runs actions by invoking the bundled CLI subprocess
- never writes `manifest.json`, `state.json`, or config directly
- shows outdated items separately from recipes that need command approval
- supports check now, update selected, update all approved outdated, approve/revoke command fields,
  reveal manifest, and quit

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

The local app is intentionally unsigned. Developer ID signing, notarization,
stapling, and the Homebrew cask are deferred until the Apple Developer Program
go/no-go decision.
