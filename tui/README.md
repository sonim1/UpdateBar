# UpdateBar TUI

Ink terminal UI for UpdateBar.

## Run From Source

From the repository root:

```bash
swift build --product updatebar
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_BIN=$PWD/.build/debug/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js .build/debug/updatebar tui
```

## Install Locally

From the repository root:

```bash
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_BIN=/full/path/to/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js updatebar tui
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

`Run Updates` opens a target-selection screen before confirmation. Outdated
items are selected by default, and the same `↑`/`↓`, `space`, `a`, `A`, and
`enter` keys let you choose exactly which approved outdated items to update.
