# Troubleshooting

## Binary Not Found

Presentation layers resolve `updatebar` using the order in
[binary-resolution.md](binary-resolution.md). Prefer setting `UPDATEBAR_BIN` to
an executable Swift CLI path:

```bash
UPDATEBAR_BIN=/full/path/to/updatebar updatebar tui
```

## Homebrew Requires The Xcode License

If `brew tap sonim1/tap` or `brew install sonim1/tap/updatebar` stops with an
Xcode license error, accept the local Xcode license and rerun the Homebrew
command:

```bash
sudo xcodebuild -license accept
brew tap sonim1/tap
brew install sonim1/tap/updatebar
```

If `xcodebuild` is not available, install the command line tools first:

```bash
xcode-select --install
```

## Swift Test Cannot Find XCTest

On macOS, `swift test` may fail with `no such module 'XCTest'` when
`xcode-select` points at Command Line Tools instead of the full Xcode bundle.
The full quality gate handles this automatically when Xcode is installed:

```bash
Scripts/quality-gate.sh
```

For a quick Swift-only test run, point SwiftPM at Xcode explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

If that still fails, check that the selected developer directory actually
contains XCTest:

```bash
xcode-select -p
find /Applications/Xcode.app /Library/Developer -name XCTest.framework 2>/dev/null
```

When no `XCTest.framework` is found, reinstall or finish installing full Xcode,
then rerun `Scripts/quality-gate.sh`.

## Invalid JSON Or JSONL

Machine-readable commands reserve stdout for JSON or JSONL only. Structured
errors are returned as JSON error envelopes or JSONL events; human-only errors
go to stderr. If a TUI or script reports invalid JSON, rerun the underlying
command and inspect stdout/stderr separately:

```bash
updatebar status --json >stdout.json 2>stderr.log
updatebar update --yes --json-stream >events.jsonl 2>stderr.log
```

Every JSONL line should parse independently as one JSON object.
For JSONL commands, look for a `failed` event before reading stderr; stderr may
be empty when the failure was already represented structurally.

## Corrupt Store Files

UpdateBar does not have an automatic repair command yet. If a command reports a
corrupt `state.json` or `manifest.json`, recover manually from the UpdateBar home
directory. By default this is `~/.updatebar`; when `UPDATEBAR_HOME` is set, use
that directory instead.

Make a backup before deleting or replacing anything:

```bash
cp -R "${UPDATEBAR_HOME:-$HOME/.updatebar}" "${UPDATEBAR_HOME:-$HOME/.updatebar}.backup"
```

If only `state.json` is corrupt, move it aside and rebuild state by running
checks:

```bash
mv "${UPDATEBAR_HOME:-$HOME/.updatebar}/state.json" "${UPDATEBAR_HOME:-$HOME/.updatebar}/state.json.corrupt"
updatebar check --exit-zero-on-outdated
```

If `manifest.json` is corrupt, do not delete it first. Copy it aside, inspect the
backup, and validate any repaired manifest before importing it:

```bash
cp "${UPDATEBAR_HOME:-$HOME/.updatebar}/manifest.json" /tmp/updatebar-manifest-corrupt.json
updatebar validate /tmp/repaired-manifest.json --json
updatebar import /tmp/repaired-manifest.json --replace --json
```

When a manifest cannot be repaired, recreate recipes with `updatebar scan`,
`updatebar init`, `updatebar template recipe`, or `updatebar add --from`.

## Menu Bar App Has No Icon

Launch the packaged binary from Terminal and inspect stderr:

```bash
Scripts/menubar-smoke-test.sh
```

If you need a manual check, rerun with logs redirected:

```bash
pkill -f UpdateBar
./dist/UpdateBar.app/Contents/MacOS/UpdateBar >/tmp/updatebar-menubar.log 2>&1 &
sleep 2
tail -n 80 /tmp/updatebar-menubar.log
```

For an installed app outside a source checkout, point `APP` at the bundle you
opened. For example, use `APP=~/UpdateBar.app` if you copied it to your home
directory:

```bash
APP=${APP:-/Applications/UpdateBar.app}
pkill -f "$APP/Contents/MacOS/UpdateBar" 2>/dev/null || true
UPDATEBAR_BIN="$APP/Contents/Resources/updatebar" \
  "$APP/Contents/MacOS/UpdateBar" >/tmp/updatebar-menubar.log 2>&1 &
sleep 2
pgrep -ax UpdateBar
tail -n 80 /tmp/updatebar-menubar.log
```

If Open TUI is available but not launching, check `UPDATEBAR_BIN` and that a TUI
binary is reachable by one of:

- `UPDATEBAR_TUI` environment variable (explicit executable path),
- bundled CLI path as `UPDATEBAR_BIN` (`UPDATEBAR_BIN tui`),
- `updatebar-tui` on `PATH`.

## Open TUI Does Nothing

The Menu Bar app opens Terminal and runs `UPDATEBAR_TUI` if set. If not set, it
falls back to `UPDATEBAR_BIN tui`, then `updatebar-tui` on `PATH` with a setup
message. From the repository root, build the TUI and point `UPDATEBAR_TUI` at
the generated executable:

```bash
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_TUI=$PWD/tui/dist/index.js updatebar tui
```

Then choose `Open TUI` from the Menu Bar menu.
