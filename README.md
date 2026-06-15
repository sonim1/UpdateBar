# UpdateBar

UpdateBar is a safe, scriptable CLI for tracking and updating user-approved recipes covering local tools, CLIs, packages, and custom install targets. It keeps a manifest of registered items, checks current/latest versions on demand, and only runs update commands that have been explicitly trusted.

UpdateBar does not generate recipes or commands itself. External agents (or you) author recipe JSON; UpdateBar remains the validation, trust, and execution boundary. Run `updatebar guide agent` for the agent workflow.

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
TAG=$(curl -fsSL https://api.github.com/repos/sonim1/UpdateBar/releases/latest | awk -F'\"' '/"tag_name"/{print $4; exit}'); ARCH=$(uname -m | sed 's/aarch64/arm64/; s/amd64/x86_64/'); ARCHIVE="updatebar-${TAG#v}-macos-${ARCH}.tar.gz"; curl -fsSL -o /tmp/$ARCHIVE https://github.com/sonim1/UpdateBar/releases/download/$TAG/$ARCHIVE && mkdir -p /tmp/updatebar && tar -xzf /tmp/$ARCHIVE -C /tmp/updatebar && sudo install -m 755 /tmp/updatebar/updatebar-${TAG#v}/updatebar /usr/local/bin/updatebar && updatebar version --json
```

If your shell is not macOS or you prefer not to use a temp location, adjust `ARCHIVE` and prefix with your preferred install path.

### Menu bar app

`updatebar-menubar` ships as an optional macOS wrapper around the CLI in the same release pipeline (`Scripts/package-app.sh`).
It uses the bundled or environment-selected `updatebar` binary and exposes:

- check now
- update selected
- update all approved outdated
- per-command approve/revoke
- reveal manifest
- quit

Build a local unsigned app:

```bash
Scripts/package-app.sh
open dist/UpdateBar.app
```

## Quick Start

```bash
updatebar guide agent
updatebar schema --json
updatebar template recipe --kind npm --id example-npm-tool --source example-npm-tool > recipe.json
updatebar validate recipe.json --json
updatebar add --from recipe.json --dry-run --json
updatebar add --from recipe.json
updatebar approvals example-npm-tool --json
updatebar approve example-npm-tool --field update.cmd --json
updatebar check
updatebar status --json
updatebar update --all --yes
```

Manual JSON import is also supported:

```bash
updatebar import Fixtures/manifests/untrusted-import.json --json
updatebar list --json
```

## Scope

v1 ships the CLI first, with an optional macOS menu bar app that reads only CLI status snapshots and runs user-approved actions.
Built-in AI generation, OAuth providers, and local LLM providers are removed by design — recipe authoring belongs to external agents. Sync, community registries, recipe signing, `diff`, and `doctor` are not planned until real external demand appears (see `next-plan.md`).

UpdateBar has no telemetry.

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
