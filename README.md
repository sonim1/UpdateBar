# UpdateBar

UpdateBar is a safe, scriptable CLI for tracking and updating user-approved recipes covering local tools, CLIs, packages, and custom install targets. It keeps a manifest of registered items, checks current/latest versions on demand, and only runs update commands that have been explicitly trusted.

UpdateBar can scan local package managers for untrusted recipe candidates, but it does not auto-register or auto-trust them. External agents (or you) can still author recipe JSON; UpdateBar remains the validation, trust, and execution boundary. Run `updatebar guide agent` for the agent workflow.

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
OS=$(uname -s); CPU=$(uname -m); case "$OS/$CPU" in Darwin/arm64|Darwin/aarch64) PLATFORM=macos; ARCH=arm64 ;; Linux/x86_64|Linux/amd64) PLATFORM=linux; ARCH=x86_64 ;; *) echo "No prebuilt UpdateBar archive for $OS/$CPU; build from source instead." >&2; exit 1 ;; esac; URL=$(curl -fsSL https://api.github.com/repos/sonim1/UpdateBar/releases | awk -F'\"' -v platform="$PLATFORM" -v arch="$ARCH" '$2=="browser_download_url" && $4 ~ "/updatebar-[0-9][^\"]*-" platform "-" arch "\\.tar\\.gz$" { print $4; exit }'); test -n "$URL" || { echo "No CLI archive found for $PLATFORM/$ARCH; build from source instead." >&2; exit 1; }; TMP_DIR=$(mktemp -d); trap 'rm -rf "$TMP_DIR"' EXIT; mkdir -p "$TMP_DIR/dist"; ARCHIVE=$(basename "$URL"); curl -fsSL -o "$TMP_DIR/dist/$ARCHIVE" "$URL" && curl -fsSL -o "$TMP_DIR/dist/$ARCHIVE.sha256" "$URL.sha256" && (cd "$TMP_DIR" && { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -c "dist/$ARCHIVE.sha256"; else sha256sum -c "dist/$ARCHIVE.sha256"; fi; }) && tar -xzf "$TMP_DIR/dist/$ARCHIVE" -C "$TMP_DIR" && sudo install -m 755 "$TMP_DIR/updatebar" /usr/local/bin/updatebar && updatebar version --json
```

Published prebuilt archives currently cover Apple Silicon macOS. The tag workflow
also builds Linux x86_64 archives for the next release. Other platforms should
build from source.

### Menu bar app

`updatebar-menubar` ships as an optional macOS wrapper around the CLI. Release tags publish an unsigned Apple Silicon app archive, and `Scripts/package-app.sh` builds the same local bundle from source.
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
updatebar scan
updatebar guide agent
updatebar schema --json
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

v1 ships the CLI first, with an optional macOS menu bar app that reads only CLI status snapshots and runs user-approved actions.
Built-in AI generation, OAuth providers, and local LLM providers are removed by design — recipe authoring belongs to external agents. Sync, community registries, recipe signing, `diff`, and `doctor` are not planned until real external demand appears (see `next-plan.md`).

UpdateBar has no telemetry.

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
