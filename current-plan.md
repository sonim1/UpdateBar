# UpdateBar — Current Plan: CLI-First + Optional Menu Bar

Status: historical decision plan as of 2026-06-15. It records the product
direction that led to the current implementation; use `README.md`,
`docs/architecture.md`, and `current-architecture.md` for current operating
state.

This plan intentionally replaces the previous AI/OpenRouter-centric direction with a simpler product stance:

> **UpdateBar provides a safe, scriptable CLI for tracking and updating tools. It does not generate recipes or commands itself. External AI agents such as Codex, Claude Code, Gemini CLI, or any other harness may use the CLI and docs to help users author recipes.**

---

## 1. Product decision

### Decision

UpdateBar should be **CLI-first with an optional macOS menu bar client**.

Remove the built-in AI/OpenRouter recipe generation path from the core product.

Instead, make the CLI highly usable by humans **and** external AI coding agents through:

- clear help output
- stable command contracts
- examples
- recipe templates
- validation and diagnostics
- machine-readable JSON output
- an agent-facing guide that explains how to safely use `updatebar`

### Non-goals for the current phase

Do not build these yet:

- Sparkle updater
- CLI-distributed sync between machines
- native notifications
- built-in OpenRouter integration
- built-in OAuth provider integrations
- local LLM provider integration
- AI-generated recipes inside UpdateBar
- community registry
- multi-machine sync

What exists now:

- CLI command set (`add`, `check`, `status`, `update`, approvals, import/export, etc.)
- optional macOS menu bar app target in the same repo/build pipeline, using the
  direct UpdateBarCore adapter by default
- optional LaunchAgent helper (`updatebar background`) for read-only periodic check
- Homebrew CLI release packaging for macOS

These can be reconsidered later, but they should not block the CLI-first version.

---

## 2. New product philosophy

Previous implicit philosophy:

> UpdateBar can use AI to generate recipes for the user.

New philosophy:

> UpdateBar does not invent commands. UpdateBar tracks and runs commands that the user, or a user-chosen external agent, explicitly defines and approves.

This gives a cleaner security model:

```text
User or external agent writes recipe
    |
    v
UpdateBar validates recipe
    |
    v
UpdateBar stores recipe as untrusted unless explicitly approved
    |
    v
UpdateBar only runs exact approved command fingerprints
```

UpdateBar should not care whether the recipe was authored by:

- the user manually
- Codex CLI
- Claude Code
- Gemini CLI
- OpenCode
- Cursor
- a shell script
- a copied example
- a future registry

UpdateBar's job is to provide the safe execution/validation layer, not the AI authoring layer.

UpdateBarCore is the source of truth for manifest/state/config handling,
validation, trust, check, status, and update behavior. The Swift CLI, Ink TUI,
and macOS Menu Bar are presentation layers around that core; the native menu bar
may use direct UpdateBarCore calls instead of shelling out when it can stay on
the same typed service boundary.

---

## 3. Why remove built-in AI/OpenRouter

Built-in OpenRouter adds scope and security surface that is not essential to the core CLI.

Removing it eliminates or reduces:

- OpenRouter API key storage
- provider config/model config
- Keychain credential complexity for AI providers
- plaintext provider secret fallback
- prompt injection concerns inside UpdateBar
- schema-constrained generation failures
- ambiguity around whether generated commands are trustworthy
- extra network calls from the core CLI
- secret redaction requirements for provider tokens
- provider-specific tests and docs

The core problem remains valuable without built-in AI:

```text
Track current versions.
Resolve latest versions.
Show status.
Run approved update commands.
Validate recipes.
Import/export recipe definitions.
```

External agents can still help users create recipes, but UpdateBar does not need to own that workflow internally.

---

## 4. Agent-friendly CLI direction

The replacement for built-in AI should be **agent-friendly documentation and command design**.

Goal:

> If a user tells Codex/Claude/Gemini “add this tool to UpdateBar,” the agent should be able to discover the correct UpdateBar workflow from local help/docs and use the CLI safely.

### Required agent-facing surfaces

Add or improve:

```text
updatebar help
updatebar guide recipe
updatebar guide agent
updatebar schema
updatebar validate --explain <file>
updatebar add --from <recipe.json> --dry-run --json
updatebar approvals <id>
updatebar approve <id> [--field <field>]
updatebar revoke <id> --field <field>
```

Possible command shape:

```text
updatebar guide agent
updatebar guide recipe
updatebar template recipe --kind github_release
updatebar template recipe --kind npm
updatebar template recipe --kind brew
```

Exact names can be refined, but the key is that the CLI itself should expose enough guidance for external agents to use it correctly.

---

## 5. Agent workflow target

External AI agents should follow this workflow:

```text
1. Inspect the user's tool/project.
2. Decide an appropriate UpdateBar recipe shape.
3. Generate a recipe JSON file.
4. Run `updatebar validate --explain recipe.json`.
5. Run `updatebar add --from recipe.json --dry-run --json`.
6. Show the user the command fields:
   - check.cmd, if present
   - latest.cmd, if present
   - update.cmd
7. Ask the user before approving commands.
8. Run `updatebar add --from recipe.json` without approval.
9. Run `updatebar approvals <id>` and approve exact fields only if the user agrees.
10. Run `updatebar check <id> --json` to verify behavior.
11. Report status and next steps.
```

Important rule for agents:

```text
Do not auto-approve command execution just because an AI generated the recipe.
```

---

## 6. Suggested `updatebar guide agent` content

The CLI should include a concise guide like this:

```text
UpdateBar agent guide
=====================

UpdateBar tracks tools using recipe JSON.
Recipes may contain shell commands. Treat those commands as sensitive.

When adding a recipe on behalf of a user:

1. Prefer non-command latest strategies when possible:
   - github_release
   - npm_registry
   - brew
   - git_tags
   - http_regex

2. Use check.file instead of check.cmd when possible.

3. If command fields are needed, keep them minimal and deterministic.

4. Always validate before adding:
   updatebar validate --explain recipe.json

5. Dry-run before writing:
   updatebar add --from recipe.json --dry-run --json

6. Do not approve commands silently.
   Show the user every command field and ask for confirmation.

7. After adding, verify:
   updatebar check <id> --json
   updatebar status --json

8. Never store provider/API secrets in recipes.
```

---

## 7. Recipe templates instead of AI generation

Instead of `add --ai`, provide templates that humans and agents can fill.

Examples:

```text
updatebar template recipe --kind github_release
updatebar template recipe --kind npm
updatebar template recipe --kind brew
updatebar template recipe --kind git_tags
updatebar template recipe --kind http_regex
updatebar template recipe --kind custom_command
```

Template output should be valid JSON with placeholder values and comments avoided, because JSON comments are invalid.

Example template strategy:

```json
{
  "id": "example-tool",
  "name": "Example Tool",
  "category": "devtools",
  "path": null,
  "source": {
    "kind": "github_release",
    "ref": "owner/repo",
    "branch": null
  },
  "version_scheme": "semver",
  "check": {
    "cmd": "example-tool --version"
  },
  "latest": {
    "strategy": "github_release",
    "cmd": null,
    "pattern": null
  },
  "version_parse": {
    "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)"
  },
  "update": {
    "cmd": "brew upgrade example-tool",
    "requires_write": true,
    "cwd": null
  },
  "pin": null,
  "enabled": true,
  "trust": {
    "level": "untrusted",
    "approved_commands": {}
  }
}
```

---

## 8. Commands to remove or simplify

Remove:

```text
updatebar add --ai
updatebar add --provider
```

Remove from Core:

```text
OpenRouterProvider
RecipePromptBuilder
SchemaConstrainedDecoder
CompletionProvider, if only used for OpenRouter
```

Remove or simplify config/auth fields that only exist for AI:

```text
provider.default
provider.model
OPENROUTER_API_KEY handling
openrouter-specific auth messages
```

Keep generic auth only if still needed for non-AI features. For example, GitHub token support for release checks may still be useful, but it should not be coupled to OpenRouter/provider abstractions.

Potentially keep:

```text
GITHUB_TOKEN / GH_TOKEN support for GitHub latest strategy
```

But do not store GitHub tokens in recipe files.

---

## 9. Commands to improve

### `validate`

Current:

```text
updatebar validate <file> [--json]
```

Improve with:

```text
updatebar validate <file> --explain
updatebar validate <file> --json
```

`--explain` should provide actionable messages suitable for humans and agents.

### `add --from`

Keep:

```text
updatebar add --from recipe.json
updatebar add --from recipe.json --dry-run --json
cat recipe.json | updatebar add --from - --dry-run --json
```

`add` requires explicit recipe input through `--from`; the old prompt-based wizard is removed to keep the hidden support command deterministic and automation-friendly.

### Approval flow

`add --trust` is removed. Approval is explicit and separate:

```text
updatebar approve <id>
updatebar approve <id> --field check.cmd
updatebar approve <id> --field latest.cmd
updatebar approve <id> --field update.cmd
updatebar approvals <id>
updatebar revoke <id> --field update.cmd
```

This would make the agent workflow safer because adding and approving are separate operations.

---

## 10. Revised implementation roadmap

### M0 — Scope reset and AI removal

- Remove built-in OpenRouter/AI recipe generation.
- Remove `add --ai` and `--provider`.
- Remove provider model config if unused.
- Remove AI-specific auth paths and docs.
- Keep explicit add/import recipe flow.
- Ensure tests reflect CLI-only behavior.

Gate:

```text
swift test passes
updatebar add --from works
updatebar validate works
no OpenRouter references remain except maybe migration notes/changelog
```

### M1 — Security floor

- Remove `/bin/zsh -lc` for recipe execution.
- Stop using login shell for recipe commands.
- Replace env denylist with allowlist.
- Add cross-process FileLock for manifest/state read-modify-write spans.
- Ensure command output is still capped and redacted.
- Be honest in docs: current execution is approval-gated, not fully sandboxed unless sandbox is implemented.

Gate:

```text
recipe commands cannot see common secret env vars
shell startup files do not re-inject secrets into recipe commands
concurrent check/update does not corrupt state
```

### M2 — Agent-facing help and templates

- Add `help agent` or `guide agent`.
- Add recipe templates.
- Improve validation messages.
- Add examples for common recipe types.
- Document safe external-agent workflow.

Gate:

```text
An external coding agent can create a valid recipe using only local help/docs and CLI commands.
```

### M3 — CLI UX hardening

- Improve JSON output contracts.
- Add stdin support where useful.
- Add shell completions if not present.
- Improve `status`, `check`, and `update` error messages.
- Add `doctor` only if it is deterministic/non-AI, or defer it.

### M4 — Optional future surfaces

Only after the CLI is solid:

- signed recipe support
- community examples catalog
- registry browsing/installing
- background check examples using launchd/systemd, still check-only
- GUI/menu bar app, if/when public signed distribution is ready (local unsigned build already shipped for validation)

---

## 11. Security stance after this decision

UpdateBar should be described as:

```text
A CLI that runs user-approved local update recipes.
```

Not as:

```text
An AI updater.
A sandboxed package manager.
A background auto-updater.
```

Security guarantees to aim for:

```text
- imported recipes are untrusted by default
- commands require exact fingerprint approval
- changed commands invalidate approval
- secrets are not passed to recipe child processes by default
- command output is capped
- update commands require explicit user action
- unattended execution, if ever added, is check-only
```

Security claims to avoid until implemented:

```text
- fully sandboxed
- safe to run arbitrary recipes
- trusted publisher means safe to execute
- AI-generated commands are safe
```

---

## 12. Recommended final stance

For v0.1/v0.2:

```text
UpdateBar is a CLI-first tool.
It does not include built-in AI generation.
It is designed to be easy for both humans and external AI agents to use.
Agents can author recipes, but UpdateBar remains the validation, trust, and execution boundary.
```

This keeps the product small, explainable, and secure enough to harden before adding larger surfaces like GUI, daemon, registry, or sync.
