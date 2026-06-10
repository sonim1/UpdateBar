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

v1 ships the CLI and a stable `status --json` contract for future menu bar use. Built-in AI generation, OAuth providers, and local LLM providers are removed by design — recipe authoring belongs to external agents. Sync, community registries, recipe signing, `diff`, and `doctor` are not planned until real external demand appears (see `next-plan.md`).

UpdateBar has no telemetry.

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
