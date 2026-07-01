# Troubleshooting

## Binary Not Found

Presentation layers resolve `updatebar` using the order in
[binary-resolution.md](binary-resolution.md). Prefer setting `UPDATEBAR_BIN` to
an executable Swift CLI path:

```bash
UPDATEBAR_BIN=/full/path/to/updatebar updatebar-tui
```

The legacy `UPDATEBAR_CLI` variable still works for the macOS Menu Bar app, but
new integrations should use `UPDATEBAR_BIN`.

## Invalid JSON Or JSONL

Machine-readable commands reserve stdout for JSON or JSONL only. Human errors go
to stderr. If a TUI or script reports invalid JSON, rerun the underlying command
and inspect stdout/stderr separately:

```bash
updatebar status --json >stdout.json 2>stderr.log
updatebar update --all --yes --json-stream >events.jsonl 2>stderr.log
```

Every JSONL line should parse independently as one JSON object.

## Menu Bar App Has No Icon

Launch the packaged binary from Terminal and inspect stderr:

```bash
pkill -f UpdateBar
./dist/UpdateBar.app/Contents/MacOS/UpdateBar >/tmp/updatebar-menubar.log 2>&1 &
sleep 2
tail -n 80 /tmp/updatebar-menubar.log
```

If the app starts but cannot find the CLI, set `UPDATEBAR_BIN` or use the
packaged app where `Contents/Resources/updatebar` exists.

## Open TUI Does Nothing

The Menu Bar app opens Terminal and runs `updatebar-tui` with `UPDATEBAR_BIN`
exported. Make sure the TUI package is installed or available on `PATH`:

```bash
cd tui
npm install
npm run build
npm link
```

Then choose `Open TUI` from the Menu Bar menu.
