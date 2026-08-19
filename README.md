<p align="center">
  <img src="Assets/AppIcon/UpdateBar.png" alt="UpdateBar app icon" width="128" />
</p>

<h1 align="center">UpdateBar</h1>

<p align="center">
  <strong>Track and update local tools through commands you explicitly trust.</strong>
</p>

---

## What UpdateBar Does

UpdateBar tracks local tools, CLIs, packages, and custom install targets from a
recipe manifest. It can discover supported tools, compare installed and latest
versions, and run approved update commands from the CLI, an optional terminal
UI, or a native macOS menu bar app.

- `scan` discovers local tools without changing UpdateBar state.
- `init` registers only the candidates you select.
- `status` reads saved state without running commands or network requests.
- `check` refreshes installed and latest versions.
- `update` runs only approved commands for outdated items.

Recipes created by users or external agents pass through the same validation,
trust, and approval boundary. Start with `updatebar guide agent` when authoring
recipes through an agent.

## Safety By Design

Imported and discovered recipes begin untrusted. UpdateBar does not auto-approve
commands, and editing an approved command invalidates its fingerprint.

Approved commands are not sandboxed. They run with your user privileges after
explicit approval, using an allowlisted environment plus time and output limits.
Read [Security](docs/security.md) before approving commands from an unfamiliar
source.

UpdateBar has no telemetry.

## Requirements

- macOS 13 or later for the menu bar app
- macOS on Apple Silicon or Linux x86_64 for published CLI binaries
- Swift 6 toolchain for source builds
- Node.js and npm only when building the optional Ink TUI from source

## Install With Homebrew

Install the macOS menu bar app and bundled `updatebar` CLI:

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

For a CLI-only installation:

```bash
brew install --formula sonim1/tap/updatebar
```

Published macOS releases are signed with a Developer ID certificate and
notarized by Apple. See [docs/install.md](docs/install.md) for upgrades,
uninstallation, GitHub Release binaries, and supported architectures.

## Install From Source

Build and install the CLI:

```bash
swift build -c release --product updatebar
cp .build/release/updatebar ~/.local/bin/updatebar
```

Or use the local installer:

```bash
Scripts/install-local.sh
```

Run the same verification gate used by CI before contributing:

```bash
Scripts/quality-gate.sh
```

On macOS, the gate prefers `/Applications/Xcode.app` so SwiftPM can find
`XCTest`. If direct `swift test` fails, set `DEVELOPER_DIR` or see
[Troubleshooting](docs/troubleshooting.md).

### Install from GitHub (single command)

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash
```

The installer uses `curl` and `tar`, then verifies the archive checksum with
`shasum` or `sha256sum` before installing `updatebar`.

### Menu bar app

The optional native macOS app provides check now, refresh status, selected or
bulk updates, command approval management, a dashboard, logs, settings, and
Sparkle app updates. The Homebrew cask installs the app and links its bundled
CLI onto your Homebrew `PATH`.

Current releases publish `UpdateBar-<version>-macos-arm64.dmg`. The historical
v0.6.1 release used `UpdateBar-0.6.1-macos-arm64.app.tar.gz`.

Build a local development app (not a public release artifact):

```bash
SPARKLE_PUBLIC_ED_KEY="$UPDATEBAR_RELEASE_SPARKLE_PUBLIC_KEY" Scripts/package-app.sh
open dist/UpdateBar.app
```

See [Menu Bar App](docs/menu-bar.md) for behavior, local development, and logs.

### Ink TUI

The optional Ink TUI consumes the Swift CLI's JSON and JSONL interfaces.

```bash
swift build --product updatebar
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_BIN=$PWD/.build/debug/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js .build/debug/updatebar tui
```

See [TUI documentation](tui/README.md) for installation and development.

## Quick Start

```bash
# Discover tools without changing state.
updatebar scan

# Select candidates interactively, or register one stable candidate id.
updatebar init
updatebar init --select <candidate-id-from-scan>

# Review command fields. Follow the approval commands it prints.
updatebar approvals <id-from-init>

# Inspect saved state, refresh versions, then run approved updates.
updatebar status --json
updatebar check
updatebar update --yes
```

For hand-written or agent-authored recipes:

```bash
updatebar guide agent
updatebar schema
updatebar template recipe --kind npm --id demo-tool --name "Demo Tool" --source demo-tool > recipe.json
updatebar validate recipe.json --json
updatebar add --from recipe.json --dry-run --json
```

## Scope

UpdateBar ships a Swift CLI, an optional Ink TUI, and a native macOS menu bar
app over the same core behavior. Built-in AI generation, OAuth providers, local
LLM providers, sync, community registries, and recipe signing are outside the
current product scope.

## Documentation

- [Landing page](docs/index.html) — a visual introduction to trusted tool tracking and updates
- [Documentation index](docs/README.md) — guides, references, architecture, and operations
- [Installation](docs/install.md) — install, upgrade, verify, and uninstall
- [Development](docs/development.md) — local setup, builds, tests, and quality gates
- [CLI reference](docs/cli.md) — commands, options, output, and exit codes
- [Menu bar app](docs/menu-bar.md) — app behavior, development, and diagnostics
- [Manifest](docs/manifest.md) — recipe and manifest format
- [Security](docs/security.md) — trust, approvals, secrets, and execution limits
- [Architecture](docs/architecture.md) — core, CLI, TUI, and menu bar boundaries
- [Release workflow](docs/release-workflow.md) — concise release and recovery guide
- [Troubleshooting](docs/troubleshooting.md) — common installation and runtime failures

Contributing guidelines live in [CONTRIBUTING.md](CONTRIBUTING.md). Release
history lives in [CHANGELOG.md](CHANGELOG.md).

### Release Maintainer Setup

UpdateBar shares the `sonim1-homebrew-release` GitHub App across
`sonim1/UpdateBar`, `sonim1/switchtab`, and `sonim1/homebrew-tap`. Configure its
repository and release-environment credentials directly from the original key:

```bash
gh variable set --repo sonim1/UpdateBar VERSION_GITHUB_APP_ID --body "4403130"
gh secret set --repo sonim1/UpdateBar VERSION_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem
gh variable set --env release --repo sonim1/UpdateBar TAP_GITHUB_APP_ID --body "4403130"
gh secret set --env release --repo sonim1/UpdateBar TAP_GITHUB_APP_PRIVATE_KEY < /path/to/github-app-private-key.pem
```

See [Release reference](docs/release.md) for the complete credential, signing,
publication, and recovery procedures.
