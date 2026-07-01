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
UPDATEBAR_BIN=/full/path/to/updatebar updatebar-tui
```

The TUI calls the Swift CLI through JSON/JSONL contracts. It does not import
Swift libraries.
