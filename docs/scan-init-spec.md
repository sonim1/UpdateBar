# UpdateBar Scan & Guided Init Spec

## Goal

`updatebar scan` discovers installed local tools without changing files. `updatebar init`
uses scan results to let the user choose which tools to register.

## Product Rules

- `scan` is read-only. It never writes `manifest.json`, `state.json`, config, or approval data.
- `init` is the only command in this feature family that may add recipes.
- Generated recipes are always `untrusted` and have empty `approved_commands`.
- Detection source and product category are separate concepts.
- Secret-bearing config values are never stored or printed.

## Candidate Shape

Each scan result is a candidate:

```json
{
  "id": "brew.jq",
  "name": "jq",
  "detector": "brew",
  "category": "shell-utility",
  "capability": "full",
  "confidence": "high",
  "installed_version": "1.7.1",
  "source_ref": "jq",
  "recipe": {}
}
```

Fields:

- `id`: stable scan id, prefixed by detector.
- `name`: display name.
- `detector`: where UpdateBar found it.
- `category`: user-facing domain group.
- `capability`: how complete the generated management path is.
- `confidence`: confidence that the candidate maps to the installed tool.
- `installed_version`: best-effort current version.
- `source_ref`: package/formula/tool reference used by the detector.
- `recipe`: present only when `capability` is `full`.

## Detectors

### v1

- `brew`: reads manually installed leaves with `brew leaves --installed-on-request`,
  then resolves versions with `brew list --formula --versions`.
- `npm_global`: reads `npm ls -g --depth=0 --json`.
- `known`: checks a curated list of common developer tools on `PATH`.
- `codex_skill`: scans `~/.codex/skills` and `~/.agents/skills` for skill
  directories that contain `SKILL.md`.
- `mcp_config`: scans Claude/Codex/Cursor MCP config names and command paths,
  never env values.

### Later

- `git_checkout`: scans explicitly configured local git checkouts.

## Categories

User-facing categories:

- `ai-agent`: Claude Code, Codex, Gemini CLI, OpenCode, Aider, gstack, rtk, agent-browser.
- `package-manager`: brew, npm, pnpm, yarn, bun, pipx, uv, cargo, rustup.
- `runtime-sdk`: node, python, ruby, go, rust, swift, java.
- `cloud-devops`: gh, aws, gcloud, vercel, wrangler, flyctl, kubectl, docker, terraform.
- `shell-utility`: jq, ripgrep, fd, fzf, bat, eza, zoxide, starship, tmux.
- `mcp-server`: MCP config entries.
- `codex-skill`: local skill bundles.
- `library`: globally installed package without a clear CLI identity.

Versioned formulae such as `node@22` or `python@3.12` are categorized by their
base tool name. Scoped npm agent packages such as `@openai/codex` are categorized
by their package leaf name. Unknown brew formulae default to `shell-utility`.
Unknown npm globals default to `library`.
Unknown category values are rejected before detectors run.

## Capabilities

- `full`: scan can generate check, latest, and update recipe fields.
- `check-only`: scan can identify the tool and current version, but cannot safely update it.
- `metadata-only`: scan can identify the entry but cannot safely generate a recipe.
- `unsupported`: scan found something too noisy or risky to manage.

v1 only generates recipes for `full` candidates. `check-only` and `metadata-only`
are listed for review but not importable until manual-update recipes exist.

## v1 Recipe Generation

### Brew

- `source.kind`: `brew`
- `source.ref`: formula name
- `version_scheme`: `calver`
- `check.cmd`: `brew list --versions <formula>`
- `latest.strategy`: `brew`
- `version_parse.regex`: `([0-9][0-9A-Za-z._+-]*)`
- `update.cmd`: `brew upgrade <formula>`

### npm global

- `source.kind`: `npm`
- `source.ref`: package name
- `version_scheme`: `semver`
- `check.cmd`: `npm ls -g --depth=0 <package> --json`
- `latest.strategy`: `npm_registry`
- `version_parse.regex`: `"version"\\s*:\\s*"([^"]+)"`
- `update.cmd`: `npm install -g <package>@latest`

## CLI

```bash
updatebar scan
updatebar scan --json
updatebar scan --category ai-agent
updatebar scan --category " cloud devops "
updatebar scan --category clouddevops
updatebar init
updatebar init --select brew.gh,npm.typescript
updatebar init --category ai-agent
```

Human `scan` output is tab-separated with `ITEM`, `ID`, `CATEGORY`, `SOURCE`,
and `CAPABILITY` columns. Review-only rows append `REF` when a source reference
is available. The output is read-only; use `init` to choose and register items.
It includes importable candidate ids, the interactive `updatebar init` command,
and a ready-to-run `updatebar init --select all` command. `init --select`
accepts those ids exactly.
When human `scan` output has no rows, it prints `No candidates found`. If the
empty result came from a category filter, it suggests retrying `updatebar scan`
without `--category`.

Human output groups candidates into:

- `Recommended`: `full` capability.
- `Needs Review`: `check-only` or `metadata-only`.

Example `scan` table:

```text
Recommended
ITEM	ID	CATEGORY	SOURCE	CAPABILITY
[1] gh 2.74.0	brew.gh	cloud-devops	brew	full
```

JSON output prints:

```json
{
  "candidates": [],
  "errors": []
}
```

## Guided Init

`updatebar init` reuses scan results, shows numbered `full` candidates, and adds
only selected recipes. It does not approve commands.
If scan finds only review-only candidates for a filtered category, `init`
refuses to import them and points the user back to `updatebar scan --category`
for review, or to `updatebar scan` without `--category` to look for importable
candidates.
Scan detector errors are preserved when `init` cannot find importable
candidates, so failed local tool detection is visible in human and JSON errors.

Initial UX:

```text
Found 12 importable candidate(s)

Recommended
ITEM	ID	CATEGORY	SOURCE
[1] gh 2.74.0	brew.gh	cloud-devops	brew
[2] jq 1.7.1	brew.jq	shell-utility	brew

Select items to add (numbers, ids, or all): 1 2
```

Headless UX:

```bash
updatebar init --select brew.gh,brew.jq
updatebar init --replace --select npm.typescript
```

`all` must be used by itself and cannot be combined with explicit ids or numbers.
`init --json` requires `--select` so stdout remains a single JSON payload.

Duplicate ids are skipped by default. `--replace` overwrites existing recipes.
Unsupported `check-only` and `metadata-only` candidates are visible in `scan`
but rejected by `init`.

Non-goals for v1:

- TUI checkbox UI.
- MCP config recipe generation.
- Skill update support.
- Automatic approvals.
- PATH-wide binary inventory.
