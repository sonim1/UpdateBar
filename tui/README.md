# UpdateBar TUI

Ink terminal UI for UpdateBar.

## Run From Source

```bash
npm install
npm run build
UPDATEBAR_BIN=../.build/debug/updatebar npm start
```

## Install Locally

```bash
npm install
npm run build
npm link
UPDATEBAR_BIN=/full/path/to/updatebar updatebar tui
```

`updatebar-tui` continues to be supported for environments where only the
standalone TUI binary is available.

The TUI calls the Swift CLI through JSON/JSONL contracts. It does not import
Swift libraries.

The first-run flow is available from `Scan & Add`: scan installed tools, select
full candidates with space, register them with enter, and use `a`/`A` to bulk
select or clear.

Scan screen keys:

- `↑`/`↓` navigate candidates
- `space` toggle current candidate (full candidates only)
- `a` select all importable candidates
- `A` clear all selected candidates
- `enter` register selected
- `m` return to menu
