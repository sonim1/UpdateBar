# UpdateBar

UpdateBar is a safe, scriptable CLI for tracking and updating user-approved recipes covering local tools, CLIs, packages, and custom install targets. It keeps a manifest of registered items, checks current/latest versions on demand, and only runs update commands that have been explicitly trusted.

UpdateBar can scan local package managers for untrusted recipe candidates and register only the ones you select. It does not auto-trust commands. External agents (or you) can still author recipe JSON; UpdateBar remains the validation, trust, and execution boundary. Run `updatebar guide agent` for the agent workflow.

## Install With Homebrew

```bash
brew tap sonim1/tap
brew install sonim1/tap/updatebar
```

Install the optional macOS menu bar app:

```bash
brew install --cask sonim1/tap/updatebar-app
```

The app cask is currently unsigned. If macOS blocks the first launch,
Control-click `UpdateBar.app` in Finder, choose Open, then confirm Open.
The `updatebar-app` cask installs the app only; install the formula for the `updatebar` CLI.

## Install From Source

```bash
swift build -c release --product updatebar
cp .build/release/updatebar ~/.local/bin/updatebar
```

Or use the local installer:

```bash
Scripts/install-local.sh
```

### Install from GitHub (single command)

```bash
bash Scripts/install-release.sh

# Or install a specific version:
bash Scripts/install-release.sh v0.2.0

# Optional: change install directory
UPDATEBAR_INSTALL_PREFIX="$HOME/.local/bin" bash Scripts/install-release.sh
```

Published prebuilt CLI archives currently cover Apple Silicon macOS and Linux
x86_64. Other platforms should build from source.

### Menu bar app

`updatebar-menubar` ships as an optional macOS wrapper. Release tags publish an unsigned Apple Silicon app archive, and `Scripts/package-app.sh` builds the same local bundle from source.
It prefers direct `UpdateBarCore` calls, keeps a CLI subprocess fallback, and exposes:

- check now
- update selected
- update all approved outdated
- per-command approve/revoke
- open TUI
- open config
- view logs
- quit

Build a local unsigned app:

```bash
Scripts/package-app.sh
open dist/UpdateBar.app
```

### Ink TUI

The terminal UI lives in `tui/` and consumes the Swift CLI JSON/JSONL contracts.
It supports status, checks, updates, and scan/select registration.

```bash
cd tui
npm install
npm run build
UPDATEBAR_BIN=../.build/debug/updatebar npm start
```

## Quick Start

```bash
updatebar scan
updatebar init
# or add scan candidates directly:
updatebar init --select <candidate-id-from-scan>
updatebar guide agent
updatebar schema
printf 'demo-tool 1.0.0' > demo-tool-version.txt
cat > recipe.json <<'JSON'
{
  "id": "demo-tool",
  "name": "Demo Tool",
  "category": "demo",
  "path": null,
  "source": { "kind": "custom", "ref": "demo-tool", "branch": null },
  "version_scheme": "semver",
  "check": { "cmd": "cat demo-tool-version.txt" },
  "latest": { "strategy": "cmd", "cmd": "printf 'demo-tool 1.1.0'", "pattern": null },
  "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
  "update": { "cmd": "printf 'demo-tool 1.1.0' > demo-tool-version.txt", "requires_write": true, "cwd": null },
  "pin": null,
  "enabled": true,
  "notify": true,
  "trust": { "level": "untrusted", "approved_commands": {} }
}
JSON
updatebar validate recipe.json --json
updatebar add --from recipe.json --dry-run --json
updatebar add --from recipe.json
updatebar approvals demo-tool --json
updatebar approve demo-tool --field check.cmd --json
updatebar approve demo-tool --field latest.cmd --json
updatebar approve demo-tool --field update.cmd --json
updatebar check --force --exit-zero-on-outdated
updatebar status --json --exit-zero-on-outdated
updatebar update --all --yes
```

Manual JSON import is also supported:

```bash
updatebar import Fixtures/manifests/untrusted-import.json --json
updatebar list --json
```

## Scope

v1 ships the CLI first, with optional Ink TUI and macOS Menu Bar presentation layers over the same core behavior.
Built-in AI generation, OAuth providers, and local LLM providers are removed by design — recipe authoring belongs to external agents. Sync, community registries, recipe signing, `diff`, and `doctor` are not planned until real external demand appears (see `next-plan.md`).

UpdateBar has no telemetry.

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
Architecture notes live in [docs/architecture.md](docs/architecture.md).
Troubleshooting lives in [docs/troubleshooting.md](docs/troubleshooting.md).
