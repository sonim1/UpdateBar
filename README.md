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

Releases from v0.3.0 are signed with a Developer ID certificate and notarized
by Apple, so the app opens without Gatekeeper warnings.
The `updatebar-app` cask installs the app only; install the formula for the `updatebar` CLI.
All supported install paths are summarized in [docs/install.md](docs/install.md).

## Install From Source

```bash
swift build -c release --product updatebar
cp .build/release/updatebar ~/.local/bin/updatebar
```

Or use the local installer:

```bash
Scripts/install-local.sh

# Optional: change install directory
UPDATEBAR_INSTALL_PREFIX="$HOME/.local/bin" Scripts/install-local.sh
```

For development checks from a source checkout, use the same gate as CI:

```bash
Scripts/quality-gate.sh
```

On macOS, the gate prefers `/Applications/Xcode.app` when available so SwiftPM
can find `XCTest`. If direct `swift test` fails, set `DEVELOPER_DIR` or see
[docs/troubleshooting.md](docs/troubleshooting.md).

### Install from GitHub (single command)

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash

# Or install a specific version:
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash -s -- v0.6.0

# Optional: change install directory
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | UPDATEBAR_INSTALL_PREFIX="$HOME/.local/bin" bash
```

Published prebuilt CLI archives currently cover Apple Silicon macOS and Linux
x86_64. Other platforms should build from source.
The installer downloads the matching release archive with `curl`, extracts it
with `tar`, and verifies the `.sha256` checksum with `shasum` or `sha256sum`
before installing `updatebar`.

### Menu bar app

`updatebar-menubar` ships as an optional macOS wrapper. Release tags publish the
signed and notarized Apple Silicon asset
`UpdateBar-<version>-macos-arm64.dmg`; `Scripts/package-app.sh` builds the local
app bundle used by the DMG release builder.
It prefers direct `UpdateBarCore` calls, keeps a CLI subprocess fallback, and exposes:

- check now
- refresh status
- update selected
- update all approved outdated
- per-command approve/revoke
- open TUI
- open config
- view logs
- quit

Build a local development app (not a public release artifact):

```bash
SPARKLE_PUBLIC_ED_KEY="$UPDATEBAR_RELEASE_SPARKLE_PUBLIC_KEY" Scripts/package-app.sh
open dist/UpdateBar.app
```

### Ink TUI

The terminal UI lives in `tui/` and consumes the Swift CLI JSON/JSONL contracts.
It supports status, checks, updates, and scan/select registration.

```bash
swift build --product updatebar
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_BIN=$PWD/.build/debug/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js .build/debug/updatebar tui
```

## Quick Start

```bash
# See what UpdateBar can discover without changing state.
updatebar scan

# Select discovered tools to register as untrusted recipes.
updatebar init

# Or register candidates directly with stable ids from scan output.
updatebar init --select <candidate-id-from-scan>

# Review command fields before running checks or updates. Follow the approval commands it prints.
updatebar approvals <id-from-init>

# Inspect state without running checks.
updatebar status --json

# Refresh versions. Exit code 10 means outdated items were found.
updatebar check

# Run approved updates only.
updatebar update --yes
```

For agent-authored or hand-written recipes:

```bash
updatebar guide agent
updatebar schema
updatebar template recipe --kind npm --id demo-tool --name "Demo Tool" --source demo-tool > recipe.json
updatebar validate recipe.json --json
updatebar add --from recipe.json --dry-run --json
```

Manual JSON import is also supported:

```bash
updatebar import Fixtures/manifests/untrusted-import.json --json
```

## Scope

v1 ships the CLI first, with optional Ink TUI and macOS Menu Bar presentation layers over the same core behavior.
Built-in AI generation, OAuth providers, and local LLM providers are removed by design — recipe authoring belongs to external agents. Sync, community registries, recipe signing, and `diff` are not planned until real external demand appears. Current architecture notes live in [current-architecture.md](current-architecture.md); [next-plan.md](next-plan.md) is retained as historical planning context.

UpdateBar has no telemetry.

## Agent Command Editing

External agents can inspect and correct one command field without a TTY:

```bash
updatebar approvals demo-tool --json
updatebar edit demo-tool --field check.cmd --from check-command.txt --json
updatebar approvals demo-tool --json
```

Editing validates the complete recipe and invalidates affected approvals. It
never approves or executes the new command; approval remains a separate,
explicit action after review.

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Contributing notes live in [CONTRIBUTING.md](CONTRIBUTING.md).
Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
Architecture notes live in [docs/architecture.md](docs/architecture.md).
Troubleshooting lives in [docs/troubleshooting.md](docs/troubleshooting.md).
