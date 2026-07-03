# Troubleshooting

## Binary Not Found

Presentation layers resolve `updatebar` using the order in
[binary-resolution.md](binary-resolution.md). Prefer setting `UPDATEBAR_BIN` to
an executable Swift CLI path:

```bash
UPDATEBAR_BIN=/full/path/to/updatebar updatebar tui
```

## Invalid JSON Or JSONL

Machine-readable commands reserve stdout for JSON or JSONL only. Human errors go
to stderr. If a TUI or script reports invalid JSON, rerun the underlying command
and inspect stdout/stderr separately:

```bash
updatebar status --json >stdout.json 2>stderr.log
updatebar update --yes --json-stream >events.jsonl 2>stderr.log
```

Every JSONL line should parse independently as one JSON object.

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
