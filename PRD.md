# UpdateBar — Product Requirements Document

> Historical PRD snapshot. For current implementation decisions, see
> [`current-plan.md`](current-plan.md) and
> [`current-architecture.md`](current-architecture.md). For upcoming work, see
> [`next-plan.md`](next-plan.md).
> Do not use this file as the source of truth for new implementation work.
> Several OpenRouter/provider/sync assumptions below were superseded by the
> CLI-first reset.

| Item | Value |
|------|-------|
| Document status | Draft v1.1 (incorporates the second multi-perspective review: security trust model §22, state refresh model §9.1, menu bar contract consistency, exit codes, cross-platform behavior, and more) |
| Written | 2026-06-08 (revised 2026-06-09) |
| One-line definition | A CLI tool that lets users register anything, regardless of category, and track versions, update, and synchronize it from one place. Status and actions are also available from the macOS menu bar. |
| Core principle | Use LLMs only for registration and diagnosis; keep runtime behavior deterministic. The CLI comes first, and the menu bar is a thin client. |

## Table of Contents

1. [Overview / One-Line Definition](#1-overview--one-line-definition)
2. [Problem Statement](#2-problem-statement)
3. [Target Users and Personas](#3-target-users-and-personas)
4. [Core Usage Scenarios](#4-core-usage-scenarios-user-stories)
5. [Goals / Non-Goals](#5-goals--non-goals)
6. [Success Metrics](#6-success-metrics)
7. [Existing Solution Analysis](#7-existing-solution-analysis)
8. [Core Design Principles](#8-core-design-principles)
9. [System Architecture](#9-system-architecture)
10. [File Layout](#10-file-layout)
11. [Data Model](#11-data-model)
12. [CLI Surface](#12-cli-surface)
13. [Registration Flow (Two Paths)](#13-registration-flow-two-paths)
14. [LLM Provider Layer](#14-llm-provider-layer)
15. [Distribution and Packaging](#15-distribution-and-packaging)
16. [Cost](#16-cost)
17. [macOS Runtime and Permission Constraints](#17-macos-runtime-and-permission-constraints)
18. [Reference Mapping (RepoBar → UpdateBar)](#18-reference-mapping-repobar--updatebar)
19. [Constraints and Risks](#19-constraints-and-risks)
20. [Open Questions](#20-open-questions)
21. [Build Milestones (Roadmap)](#21-build-milestones-roadmap)
22. [Security Model — Recipe Trust Boundary](#22-security-model--recipe-trust-boundary)

---

## 1. Overview / One-Line Definition

**One-line definition:** UpdateBar is a CLI tool that lets users register anything, regardless of category, and track versions, update, and synchronize it from one place. Users can also view status and run actions from the macOS menu bar.

**Elevator pitch:** From skills and apps to plugins and MCP servers, we manually install an ever-growing variety of tools and update each one differently. UpdateBar registers all these heterogeneous items in one registry and defines each update method as a declarative recipe, bringing “what is outdated and how do I update it?” into one tool. The core is a deterministic, script-friendly CLI. A thin macOS menu bar client adds an “N updates” badge and one-click actions.

## 2. Problem Statement

As the tool ecosystem expands, the number and variety of things users must update have become difficult to control. The same pain points recur:

- **Too many kinds of tools to manage versions reliably** — Tools such as skill/harness, OpenClaw, Hermes, OpenDesign, Ouroboros, and Superpowers accumulate in different forms and from different sources.
- **Users forget what needs updating** — There is no single view showing which items are current or whether a new version exists.
- **Old versions remain in use** — Checking and updating are inconvenient, so users postpone them indefinitely.
- **Every tool updates differently** — One needs `git pull`, another uses `npm` or `brew`, and another must be cloned again. Users repeatedly have to remember each procedure.

**Examples of item diversity**

| Dimension | Examples |
|-----------|----------|
| Tools | skill/harness, OpenClaw, Hermes, OpenDesign, Ouroboros, Superpowers |
| Form factor | Skill, app, plugin, MCP server |
| Update mechanism | `git pull`, `npm`, `brew`, re-clone, and others |

The fundamental problem is not simply “users do not know the version.” It is that **there is no common layer for consistently tracking and updating heterogeneous items**.

## 3. Target Users and Personas

**Primary users:** Heavy users of AI-agent and developer-tool ecosystems, as well as general developers—especially people who frequently install and directly manage skills, plugins, MCP servers, and CLI tools.

**Persona 1 — Jiho (AI Workflow Builder)**

- A power user who combines multiple agent harnesses and skills into custom workflows.
- Uses a mixture of skills cloned from Git repositories, npm-installed CLIs, and Homebrew apps.
- Misses new releases or leaves tools untouched because the update procedure is hard to remember.
- Need: “I want one view of every tool I use and one click or command to bring it up to date.”

**Persona 2 — Minjun (CLI-First Developer)**

- Works primarily in the terminal and prefers tools that can be automated and scripted.
- Wants to integrate updates into CI or shell scripts and uses a GUI only as a secondary interface.
- Need: “A deterministic, scriptable interface must come first; a menu bar status view is enough as a complement.”

## 4. Core Usage Scenarios (User Stories)

**Scenario A — Register a new skill CLI and configure automatic tracking**

> As an AI workflow builder, when I register a newly installed skill CLI with UpdateBar, I want its version-check and update procedures configured automatically so I can track it without further effort.

**Scenario B — Update items individually or in bulk from a menu bar badge**

> As a user, when I see an “N updates” badge in the macOS menu bar, I want to click it and update items individually or all at once.

**Scenario C — Synchronize the same skill across several directories**

> As a heavy user, when the same skill is installed in multiple tool directories, I want the sync feature to reconcile them to one consistent version.

**Scenario D — Diagnose and recover from a broken update**

> As a user, when an update fails or leaves a tool broken, I want diagnostics and a recovery path that returns it to a working state.

## 5. Goals / Non-Goals

**Goals**

- **One registry for heterogeneous items** — Register and track skills, apps, plugins, MCP servers, and other forms in one registry.
- **Declarative, shareable update recipes** — Define version checks and update procedures declaratively so they can be shared and reused.
- **Deterministic checks and updates with optional LLM assistance** — Keep the default behavior deterministic and reproducible while optionally using an LLM for recipe authoring and diagnosis.
- **CLI first, menu bar as a thin client** — Keep core functionality and the source of truth in the CLI. The macOS menu bar app displays status and triggers actions.

**Non-goals for v1**

- **Not a replacement for language-runtime version managers** — It does not replace asdf, mise, or similar tools.
- **Not a package registry host** — It does not host or distribute packages.
- **No Windows/Linux menu bar client** — The core CLI may be cross-platform, but the menu bar client prioritizes macOS.

## 6. Success Metrics

These metrics measure whether the registration → tracking → updating loop works. Menu bar daily/weekly activity applies only if the menu bar is included in the release scope, depending on the v1 scope decision in §20 Q1. A CLI-only initial release uses the other four metrics.

| Metric | Definition | Meaning |
|--------|------------|---------|
| Registered item count | Number of items registered in UpdateBar per user/device | Adoption as a unified registry |
| Outdated → up-to-date conversion rate | Percentage of detected outdated items that are actually updated | How well the product solves continued use of old versions |
| AI registration success rate | Percentage of automatically or AI-assisted recipes that pass live tests for version checks and updates | Reliability of the registration experience |
| Menu bar daily/weekly activity | DAU/WAU of the menu bar client | Ongoing use of the persistent surface |
| Update executions | Number of updates run through the CLI or menu bar per period | Frequency of concrete actions produced by the tool |

## 7. Existing Solution Analysis

No single existing product precisely solves UpdateBar's target problem: registering heterogeneous items in one registry, tracking which are outdated, and updating each through a declarative recipe. Strong adjacent tools exist, but UpdateBar emerges only by combining their advantages.

| Product / Category | Strengths | Limitations from UpdateBar's Perspective |
|--------------------|-----------|------------------------------------------|
| **topgrade** | Detects and updates more than 50 tools, registers arbitrary custom update steps through TOML `[commands]`, and supports multiple platforms | Has no per-item registry or version tracking and does not show what is outdated. No menu bar. Runs everything without status distinctions. |
| **universal-skills-manager** | Finds and installs skills across Claude, Codex, Gemini, OpenClaw, and Hermes; synchronizes tools and shows which side is newer | Specialized for skills rather than arbitrary categories. |
| **McPick** | Manages install/update/enable for MCP servers and Claude Code plugins, synchronizes a registry, and provides a TUI | Limited to MCP servers and plugins. |
| **Claude Code native marketplace** | Official route for plugins, skills, and MCP servers, with a last-updated display | Confined to Claude Code rather than general-purpose. |
| **CodexBar** | Menu bar plus bundled CLI, more than 40 providers, extensible provider guides, and OAuth/API-key authentication | Tracks usage limits rather than versions, but is an excellent structural reference. |
| **asdf / mise / proto / vfox** | Extensible plugin-based version managers | Target language runtimes and developer tools rather than general skills or apps. |

**Conclusion:** A clear gap exists. **topgrade's custom-command model + per-item version tracking + CodexBar's menu bar/plugin structure** is UpdateBar.

## 8. Core Design Principles

The architecture rests on one proposition: **LLMs are used only for registration and diagnosis; runtime behavior is entirely deterministic.**

Version checks, comparisons, and updates always run through the same shell commands without calling an LLM. Once registered, an item can be checked hundreds of times without inference. This solves cost, latency, and reproducibility together. Even if the menu bar refreshes every minute, token usage remains zero, identical inputs produce identical outputs, and debugging stays simple.

LLMs are limited to natural-language or semi-structured tasks that are inconvenient for people:

1. **Infer a recipe during registration** — Convert the check and update procedures for an arbitrary tool, app, or skill into a declarative recipe.
2. **Summarize changelogs** — Summarize changes between the current and latest versions and identify breaking changes.
3. **Suggest recovery from update failures** — Diagnose errors and propose corrections.

This boundary defines responsibilities throughout the system. Inference happens once and requires human review; execution repeats unattended.

## 9. System Architecture

UpdateBar has three layers:

- **Menu bar (Swift, thin client)** — Handles only UI and user interaction. It contains no business logic, runs only its own `updatebar` CLI, and renders parsed `--json` output. It displays state rather than calculating it.
- **`updatebar` CLI (core engine)** — The single source of truth for all logic. Deterministic commands (`list`, `check`, `status`, `update`, `sync`, and recipe-management commands such as `pin`, `unpin`, `enable`, `disable`, `remove`, `edit`, `export`, and `import`) never call an LLM. Only `add`, `diff`, and `doctor` use the provider layer.
- **Provider interface** — Abstracts LLM calls. Local `ollama` is the default, with `codex` (`codex exec`) and `claude` (`claude -p`) as optional accelerators.

Two files persist state. `manifest.json` stores declarative item recipes, while `state.json` stores calculated current and latest versions.

```text
             macOS menu bar (Swift thin client)
                      │ runs its own CLI, parses --json
                      ▼
   ┌────────────────  updatebar (CLI)  ──────────────────┐
   │  Deterministic (no LLM)       Uses LLM              │
   │  list / check / status        add / diff / doctor   │
   │  update / sync                     │                │
   │       │                       Provider interface    │
   │       │                       ├ ollama (local)      │
   │       │                       ├ codex (codex exec)  │
   │       │                       └ claude (claude -p)  │
   │       ▼                                               │
   │  manifest.json (recipes)    state.json (versions)    │
   └───────────────────────────────────────────────────────┘
```

### 9.1 State Refresh Model (Separate `status` from `check`)

If frequently polled `status` directly invokes shell commands or network requests, it blocks for seconds and can hit rate limits. Therefore **reading (`status`) and refreshing (`check`) are strictly separated**.

- **`status`** is a **pure read** of `state.json`. It runs no shell commands, makes no network calls, never blocks, and immediately returns the last calculated snapshot.
- **`check`** performs the actual refresh. It runs in the background through the menu bar timer, cron/launchd, or an explicit CLI call, and populates `state.json`. Per-item `check`/`latest` lookups run in parallel under a **concurrency cap such as 8**.
- **TTL and freshness:** Compare each item's `last_checked` with `config.toml`'s `refresh_interval` and refresh only expired items. `status --refresh` ignores expiry and triggers a forced refresh without waiting for completion; affected items show `checking`.
- **Rate-limit avoidance:** Network strategies such as `github_release` and `git_tags` use per-strategy TTL caches and conditional requests with ETag/`304`. An optional token avoids GitHub's unauthenticated limit of 60 requests/hour. Failures use exponential backoff.

> Summary: the menu bar *reads* the cache; background `check` *fills* it. Network and shell work never belongs on the hot path.

## 10. File Layout

All persistent state is stored in three files under `~/.updatebar/`. The key is a strict separation between recipes (declarative definitions) and state (calculated values).

| File | Role | Created by | Shareability |
|------|------|------------|--------------|
| `~/.updatebar/manifest.json` | Per-item recipes declaring what to check and update, and how | Generated during LLM registration or entered manually | Declarative and shareable across machines |
| `~/.updatebar/state.json` | Current/latest versions and last-check time by ID | Calculated and written at runtime | Machine-local and gitignored |
| `~/.updatebar/config.toml` | Provider selection, refresh interval, and other user settings | User | Machine-local |

Recipes can therefore be copied or shared across teams and devices with `export`/`import`, while each device independently recalculates its own state. Moving a recipe never imports another machine's installation state.

**Draft `config.toml` keys**

```toml
[provider]
default = "ollama"            # ollama | codex | claude
github_token = ""             # optional: relax rate limits for latest-version strategies

[refresh]
interval = "6h"               # background check TTL, e.g. 30m, 6h, 1d
concurrency = 8               # maximum concurrent item checks

[security]
allow_import_exec = false     # whether imported recipe commands may run unattended; blocked by default (§22)
require_https_source = true   # reject plaintext HTTP sources

[notify]
enabled = true                # global notification toggle for notify:true items
```

Key formats and defaults will be finalized during milestone work.

## 11. Data Model

### 11.1 Item Recipe Schema

A recipe declaratively describes how to manage one item and is stored as an array element in `manifest.json`.

```json
{
  "id": "claude-code",
  "name": "Claude Code",
  "category": "cli",
  "path": "~/.local/bin/claude",
  "source": {
    "kind": "npm",
    "ref": "@anthropic-ai/claude-code",
    "branch": null
  },
  "version_scheme": "semver",
  "check": { "cmd": "claude --version" },
  "latest": {
    "strategy": "npm_registry",
    "cmd": null,
    "pattern": null
  },
  "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
  "update": {
    "cmd": "npm i -g @anthropic-ai/claude-code@latest",
    "requires_write": true,
    "cwd": null
  },
  "sync": null,
  "pin": null,
  "enabled": true,
  "notify": true
}
```

| Field | Meaning |
|-------|---------|
| `id` | Machine-friendly unique identifier. Commands and state address the item by this key. |
| `name` | Human-readable display name. |
| `category` | Free-form category such as `skill`, `app`, `plugin`, `mcp`, `cli`, or `dotfile`. Used for grouping/filtering; has no behavioral effect. |
| `path` | Local installation path, when applicable. |
| `source.kind` | One of `git`, `npm`, `github_release`, `brew`, `http`, or `custom`. |
| `source.ref` | Source identifier such as a repository URL, package name, or formula name. |
| `source.branch` | Branch tracked for Git sources, or `null` when not applicable. |
| `version_scheme` | One of `semver`, `commit`, `calver`, or `opaque`; determines comparison behavior. |
| `check` | How to obtain the current version: either `{cmd}` or `{file, query}` (oneOf). For JSON/YAML, `query` is a `jq` expression; for plain text, it is a regular expression with one capture group. |
| `latest` | Strategy for finding the latest version: `git_tags`, `git_head`, `npm_registry`, `github_release`, `brew`, `http_regex`, or `cmd`. `cmd` is required for the `cmd` strategy and `pattern` for `http_regex`. Default mappings are `git`→`git_tags`/`git_head`, `npm`→`npm_registry`, `github_release`→`github_release`, `brew`→`brew`, `http`→`http_regex`, and `custom`→`cmd`. |
| `version_parse` | Extracts a version string from raw output. One of `{ "regex": "<one-capture-group regex>" }` or `{ "jq": "<jq expression>" }`. |
| `update` | Update command (`cmd`), whether write access is needed (`requires_write`, default `true`), and working directory (`cwd`). |
| `sync` | Propagation settings for multiple locations: `targets[]`, `strategy` (`copy_newest`, `symlink`, or `cmd`), and `cmd`. |
| `pin` | Pins a specific version. Pinned items are excluded from updates and have status `pinned`. |
| `enabled` | Whether the item is enabled, default `true`. Disabled items skip checks and updates. |
| `notify` | Whether to notify when an update is available, default `true`. With the menu bar running, use its badge/dropdown; in CLI-only environments, optionally use macOS UserNotifications or a `check` summary line. `[notify].enabled` disables notifications globally. |

**Notes on `version_scheme`:** Skills and plugins often do not follow semver, so comparison differs by scheme.

- `semver` — Standard semantic-version ordering; the most accurate option.
- `commit` — Compare local and remote SHAs. Remote lookup requires network access and therefore follows the TTL/rate-limit model in §9.1. A difference means an update is available.
- `calver` — Date-based versions such as `2026.06` or `24.1.0`. Compare numeric tokens from left to right; downgrade irregular formats to `opaque`.
- `opaque` — Detect only whether two strings differ. Because direction is unknown, report `differs` rather than `outdated` to avoid treating downgrades or sidegrades as updates.

The model does not assume every item has a meaningful version number and exposes uncertainty directly in status.

> The canonical JSON Schema (draft 2020-12) is maintained separately with `$id: updatebar/item.schema.json`, `additionalProperties: false`, and `required: [id, name, category, version_scheme, check, latest, update]`. The example above is one valid instance.

### 11.2 `status` Output Schema

The deterministic `status` output is consumed directly by the menu bar. It serializes the cached `state.json` snapshot and returns immediately without network or shell work (§9.1).

```json
{
  "generated_at": "2026-06-08T09:00:00Z",
  "summary": { "total": 12, "outdated": 3, "errors": 1 },
  "items": [
    {
      "id": "claude-code",
      "name": "Claude Code",
      "category": "cli",
      "current": "1.4.2",
      "latest": "1.5.0",
      "status": "outdated",
      "pinned": false,
      "last_checked": "2026-06-08T08:59:40Z",
      "error": null
    }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `generated_at` | Snapshot creation time in ISO 8601. |
| `summary.total` | Total item count. |
| `summary.outdated` | Number of updateable items, excluding `pinned` and `disabled` items. |
| `summary.errors` | Number of items whose checks failed. |
| `items[].id` / `name` / `category` | Identity, display, and category fields from the recipe. |
| `items[].current` | Currently installed version. |
| `items[].latest` | Latest version found. |
| `items[].status` | One of `ok`, `outdated`, `differs`, `error`, `pinned`, `disabled`, or `checking`; determines menu bar icons and colors. |
| `items[].pinned` | Boolean pin state. It duplicates `status:"pinned"` intentionally: `pinned` records the fact, while `status` is the display state. |
| `items[].last_checked` | Time of the last check. |
| `items[].error` | Error message, or `null` when healthy. |

**Status producer and priority:** When several conditions apply, choose one `status` using **state overrides before version state**:

1. `disabled` — Always used when `enabled:false`; no check runs.
2. `pinned` — Used when a pin exists, even if a new version is available. Also record `pinned:true`.
3. `error` — Used when the latest check failed, with a message in `error`.
4. `checking` — Temporary state while a background `check` refreshes the item. `status --refresh` sets it when queued; completion replaces it with a version state.
5. Version state — Otherwise use `ok` when current, `outdated` when semver/calver has a newer version, or `differs` for unequal opaque values.

`summary.outdated` excludes `disabled` and `pinned` items. The menu bar badge equals `summary.outdated`. Counts for pinned, disabled, and checking are intentionally omitted from `summary`; the menu bar derives them from `items[]`.

This schema is the **CLI ↔ menu bar contract**. The menu bar needs only this format and remains insulated from internal implementation changes.

## 12. CLI Surface

Every UpdateBar feature is exposed through one CLI. All consumers, including the menu bar, use this surface.

| Command | LLM | Key options | Description |
|---------|:---:|-------------|-------------|
| `add` | Optional | `--from <path\|url>` `--manual` `--ai` (default) `--provider` `--dry-run` | Register an item. Default `--ai` infers a recipe; `--manual` is the human-entered fallback. |
| `list` | No | `--json` | List registered items. |
| `check` | No | `[id...]` `--json` | Check current/latest versions for selected or all items. |
| `status` | No | `--json` `--refresh` | Return aggregate menu bar status; `--refresh` forces rechecking. |
| `update` | No | `[id...\|--all]` `--yes` | Run updates while respecting pin, enabled, and requires_write. |
| `sync` | No | `[id...]` | Propagate items according to each recipe's sync configuration. |
| `diff` | Yes | `[id]` | Summarize current-to-latest changelogs and identify breaking changes. |
| `doctor` | Yes | `[id]` | Diagnose failed checks or updates and propose fixes. |
| `pin` / `unpin` | No | `<id> [version]` | Set or remove a version pin. |
| `enable` / `disable` | No | `<id>` | Enable or disable an item. |
| `remove` / `edit` | No | `<id>` | Delete or edit a recipe. |
| `export` / `import` | No | `[file]` | Export or import a shared manifest. |

The menu bar invokes only fast, deterministic, non-LLM commands such as `status`.

**Exit-code contract for scripts and CI:**

| Code | Meaning |
|------|---------|
| `0` | Success. For `check`/`status`, all items current also returns 0. |
| `1` | General execution error such as invalid arguments or a missing recipe. |
| `2` | Partial failure. Identify per-item causes through `items[].error` in JSON output. |
| `10` | `check`/`status` found updateable items, allowing CI to fail on outdated state. Disable with `--exit-zero-on-outdated`. |

`update` and `sync` return `0` when every action succeeds and `2` for partial failure. With `--json`, every command writes human messages to stderr and data to stdout.

## 13. Registration Flow (Two Paths)

New item registration has manual and AI paths, but both share one pipeline:

```text
Proposal (human or LLM)
  → schema validation
  → command review and approval by a human
  → sandboxed live test with network/filesystem/time limits
  → correction on failure
  → save
```

- **manual** — A human enters recipe fields to create the proposal.
- **ai** — An LLM analyzes a path or URL passed through `--from` and proposes a recipe.

The remaining steps are identical. The proposed recipe is first validated against the schema.

**Human confirmation must precede execution.** Live tests execute real shell commands, so every proposed command—whether inferred by AI or entered by a person—is shown in full and approved before running. The AI path can ingest untrusted repository READMEs or web pages containing prompt injections, so LLM-generated commands are never run unattended. See §22 for the threat model and isolation requirements.

Only approved commands enter the **sandboxed live test**. The system verifies that: (1) `check` returns a version string, (2) the `latest` strategy resolves a version, and (3) `update` is syntactically valid in dry-run mode. A dry run is **not a security boundary**, because a tool may ignore it. Tests therefore block undeclared network destinations and writes and enforce time/resource limits. On failure, the error can be returned to the LLM for correction, but **every corrected command requires fresh human approval**, reusing the `doctor` loop mechanism.

AI registration is easy because of **automatic testing plus an approval gate**, not because generation is inherently trustworthy. If the model does not converge, manual registration remains the fallback. Trust comes from mechanically verifying the behavior of human-approved commands, not from plausible-looking output.

## 14. LLM Provider Layer

Every LLM task reduces to one form: **“fill this schema.”** Recipe inference, changelog summaries, and failure diagnosis all request objects conforming to known JSON schemas. This keeps the Provider interface narrow. The following is language-neutral pseudocode; the real implementation is a Swift `protocol` in UpdateBarCore. TypeScript syntax is used only for readability and does not imply JavaScript at runtime.

```ts
interface CompletionRequest { prompt: string; schema: object; context?: string; maxRetries?: number; }
interface Provider {
  readonly name: string;
  complete(req: CompletionRequest): Promise<unknown>; // schema-valid object; retry then throw on failure
}
```

Reliability comes from a loop of **generation → schema validation → re-prompt with validation errors**, with three retries by default. A schema violation becomes context for the next attempt until it passes or reaches the retry limit.

- **codex** (`codex exec`) — Reuses the stored CLI login. Supports native schema enforcement through `--output-schema` and uses `--json` plus `--skip-git-repo-check`. Engine-level enforcement reduces retry frequency.
- **claude** (`claude -p`) — Supports `--output-format json` but no native schema flag, so the prompt includes the schema and output is validated afterward. Subscription pricing and terms for headless use may change and must be rechecked at launch. Automated access also has consumer-terms ambiguity, although interactive `add` usage is lower risk.
- **ollama** — Runs locally in JSON mode, avoiding quota and terms issues. Its lack of external dependency makes it a suitable default.

Authentication options include reused local CLI OAuth (`codex login` / `claude login`), an OpenRouter API key, and local Ollama. All pass through the same Provider interface.

**Recommended default:** Prefer `ollama`. Use `codex` or `claude` as optional accelerators when higher reasoning quality is needed. LLM calls are infrequent because they occur only during registration and diagnosis.

## 15. Distribution and Packaging

UpdateBar directly references steipete's **RepoBar** and **CodexBar**. Both are native macOS apps that ship a menu bar app and bundled CLI as one MIT-licensed artifact. UpdateBar adopts the same distribution structure.

### 15.1 Package Structure

- Use a **SwiftPM package**, not an Xcode project, as the single source of truth. Declare builds, dependencies, and targets in `Package.swift`.
- Expose the **menu bar app** and **CLI** as separate products in one package. Because a SwiftPM executable product does not create a signable `.app` bundle with Info.plist, resources, and icons, assemble the menu bar build output into an app bundle with a packaging script or `xcodebuild`, then sign and notarize it. The CLI is one executable and needs no assembly.
- Extract shared logic into **UpdateBarCore**, used by both app and CLI for domain models, version tracking, and authentication. Credential storage is platform-dependent, so abstract it behind a `CredentialStore` protocol: Keychain on macOS with `canImport(Security)`, and a file/environment fallback on Linux. Isolate Keychain, Sparkle, and other macOS-only dependencies with `#if os(macOS)` and keep Sparkle in the app target so the cross-platform CLI remains viable.

RepoBar's language split—Swift 95%, Shell 3%, TypeScript 1.5%—illustrates that this is a **pure native Swift app**. Node/pnpm is only a task runner. `package.json` scripts wrap workflows such as `swiftformat`, `swiftlint`, `build`, `test`, and `codesign`; **the app bundle contains no JavaScript**.

### 15.2 Homebrew Distribution

Operate the custom tap `youruser/homebrew-tap`.

- **App (macOS):** distribute as a cask with `brew install --cask youruser/tap/updatebar`.
- **CLI (Linux and others):** distribute as a formula.

Installing the cask installs **the app and CLI together** because the cask's `binary` stanza exposes the bundled CLI through a symlink in `/opt/homebrew/bin`. CodexBar, for example, links bundled `CodexBarCLI` as `/opt/homebrew/bin/codexbar`. UpdateBar similarly exposes `updatebar` on PATH.

### 15.3 Automatic Updates and Signing

- Provide in-app updates through **Sparkle** and publish new versions through `appcast.xml`.
- Use `version.env` as the **single source of truth** shared by the app, CLI, and appcast.
- Host build artifacts in **GitHub Releases**, referenced by the appcast.
- **Code signing and notarization are mandatory.** Automate signing, notarization, and stapling through a `codesign` script, entitlements, and GitHub Actions. Gatekeeper blocks unsigned builds from normal distribution.

### 15.4 Landing Page

Provide product information and download instructions through the static `updatebar.app` site.

## 16. Cost

- **Apple Developer Program: $99/year.** The fee is per account, with no limit on the number of apps signed and distributed under that account.
- Membership must be renewed annually.
- **Already signed and notarized builds continue to work after cancellation.** Developer ID certificates remain valid for five years from issuance, and secure timestamps preserve trust after certificate expiration or account cancellation.
- **New builds and updates cannot be signed or notarized after cancellation.** Continued distribution therefore requires ongoing membership.

## 17. macOS Runtime and Permission Constraints

For the menu bar app to run the CLI as a subprocess, it must be **non-sandboxed**. This requires direct Developer ID distribution through Homebrew and rules out the Mac App Store. App Sandbox prevents arbitrary execution of external binaries such as `git`, `codex`, `claude`, and `ollama`.

### 17.1 Three Practical Traps

1. **GUI PATH problem** — Apps launched from Finder or the Dock do not inherit shell PATH. Invoke external tools through absolute paths or a login shell such as `/bin/zsh -lc` so the user's PATH applies.
2. **File-access TCC prompts** — Reading protected locations such as Documents or Desktop prompts the user for Files and Folders access. Permission timing and UX must account for this.
3. **Gatekeeper/XProtect conflicts** — Modifying a CLI installed by someone else can trigger malware protection. CodexBar has encountered a case where macOS marked a user's `codex` CLI as *Malware Blocked* and moved it to Trash while the app attempted to manage it.

### 17.2 Design Recommendation

The menu bar app **must not invoke external tools such as `git` or `codex` directly**. It runs only the signed `updatebar` CLI distributed with the app. PATH resolution, external tool calls, and arbitrary binary execution remain isolated inside the CLI. This creates a clean trust boundary: the app trusts one signed child process and minimizes its Gatekeeper/XProtect conflict surface.

## 18. Reference Mapping (RepoBar → UpdateBar)

| RepoBar | UpdateBar |
|---------|-----------|
| Monitor GitHub repository status | Monitor **registered-item version status** |
| GraphQL/Apollo data layer | **Latest-version strategies + LLM provider** layer |
| RepoBarCore | **UpdateBarCore** |
| `repobar` CLI (`--json` / `--plain`) | `updatebar` CLI (`--json`) |
| Local projects and sync: folder scanning, branch/sync status, automatic fast-forward pull | **Item scanning + version tracking + sync strategies** |
| OAuth → Keychain | **OAuth/key → Keychain** for provider authentication |
| Brew cask + Sparkle + `version.env` | Same |
| AGENTS.md | Same |

**Conclusion:** The structure is almost a drop-in adaptation of RepoBar. Replace the data source (GitHub repository → version/package source) and data layer (GraphQL → latest strategies + LLM provider), while reusing packaging, distribution, authentication, and update infrastructure.

## 19. Constraints and Risks

| Risk / Constraint | Details | Mitigation |
|-------------------|---------|------------|
| **No sandbox → no App Store** | Arbitrary shell execution and user-tool management are incompatible with App Sandbox, preventing Mac App Store distribution | Use direct distribution with Developer ID signing, notarization, and Sparkle updates. |
| **Automated LLM-registration tests execute arbitrary shell commands** | Live-testing an AI-generated recipe's checks and updates creates a security risk | Run only read-only phases unattended: `check`, `latest`, and update dry-run. Require confirmation for real writes. Treat `requires_write` (default `true`) as a warning and apply stricter confirmation. |
| **Gatekeeper conflicts while managing user LLM CLIs** | Managed CLI binaries may be blocked because of signing or quarantine attributes | Document quarantine handling, verify trusted sources, and provide clear diagnostics. |
| **Dependency on subscription-based headless `claude -p`** | Credit consumption or terms changes can disable the helper feature | Keep provider abstraction and hedge with local Ollama and OpenRouter. Avoid dependence on one subscription. |
| **Accuracy of “latest” for non-semver items** | Commit hashes and opaque identifiers can make direction unclear | Separate semver, commit, and opaque strategies; expose uncertainty and allow user overrides. |
| **Signing/notarization operating cost** | Apple Developer Program costs $99/year and the pipeline needs maintenance | Automate CI and document release operations. |
| **Shared recipes execute arbitrary shell commands** | `check`, `latest.cmd`, and `update.cmd` from imported/community manifests can produce RCE; polling runs checks unattended | Isolate imported recipes as untrusted, require per-command approval and diff before first execution, and add provenance/signatures. See §22. |
| **Update integrity is not verified** | Fetching from Git/npm/HTTP without signatures, hashes, or pins permits MITM, upstream compromise, or typosquatting | Reject plaintext HTTP, support optional recipe-level hash/signature pins, and verify before execution. |
| **Recipe commands can access secrets** | Commands run with user privileges and may read or leak Keychain/environment provider tokens | Scrub provider secrets from child environments, block undeclared network access, and never log token-bearing commands/output. |

## 20. Open Questions

1. **v1 scope:** Release the CLI first or ship the menu bar at the same time? Recommendation: finish CLI core milestones 1–3 first, then add the menu bar.
   - Decision: Implement the CLI first, but design it with the menu bar in mind because the menu bar will follow immediately.
2. **Default LLM provider:** Force Ollama as the default or let users choose on first launch?
   - Decision: Launch initially with an OpenRouter API key. Also plan OAuth support for Codex or Claude by referencing OpenClaw, Hermes, and OpenCode. Keep the provider structure easy to change later.
3. **Recipe sharing:** Put a community registry or shared marketplace on the roadmap beyond export/import? This requires the §22 trust/signature model first.
   - Decision: The project is open source; recipes will likely be shared through GitHub and the landing page.
4. **Automatic update policy:** Notify only or automatically apply safe updates such as fast-forwards?
   - Decision: Show “Update ready” in the menu bar. Clicking it should update and then restart.
5. **Category presets:** Include built-in templates for skill, MCP, plugin, brew, npm, and Git?
   - Decision: Not now. Provide templates later through a landing page or guide.
6. **Multi-machine synchronization:** Include Git/cloud synchronization of the manifest in v1?
   - Decision: No multi-machine synchronization; use import/export first.
7. **Telemetry/privacy:** Should sending nothing be the default?
   - Decision: No telemetry.

## 21. Build Milestones (Roadmap)

Core principle: **Milestones 1–3 alone produce a useful version tracker that works without an LLM.** The core remains independent of LLMs, which serve only as an auxiliary registration/diagnosis layer.

1. **Manifest/state schemas + validation** — Deliver registry/state schemas using JSON Schema draft 2020-12 and a Swift validator in UpdateBarCore. Completion: correctly distinguish valid and invalid manifests. Do not adopt a JavaScript validator such as `ajv` because §15.1 excludes JS from the app bundle; it may be used only temporarily for prototyping.
2. **Deterministic core** — Deliver latest-version strategies for semver/commit/opaque and `check`, `list`, and `status --json`. Completion: determine outdated state without an LLM and stabilize JSON output.
3. **update / pin / sync** — Deliver item updates, version pinning, and cross-location reconciliation. Completion: registration → tracking → updating works entirely through the CLI.
4. **Provider interface + Ollama → `add`** — Deliver provider abstraction, Ollama integration, and a schema-enforced registration loop. Completion: AI-assisted recipes pass schema validation.
5. **Codex / Claude providers** — Deliver additional providers. Completion: switch providers through one interface.
6. **Swift menu bar ↔ status schema** — Deliver a SwiftPM two-product structure sharing the core. Completion: the “N updates” badge and one-click actions consume the status schema.
7. **diff / doctor (LLM assistance)** — Deliver change comparison and diagnosis/recovery commands. Completion: diagnose broken updates and provide a recovery path.
8. **Distribution pipeline** — Deliver a Brew tap with cask/formula, Sparkle/appcast, signing/notarization, and a landing page. Completion: signed and notarized builds are distributed and updated automatically.

> **Ordering requirement:** The recipe trust/sandbox model in §22 must land before milestone 4 introduces `add` and its first unattended execution, and before `import` is exposed. The community registry and multi-machine synchronization in §20 Q3/Q6 require the trust model first.

## 22. Security Model — Recipe Trust Boundary

UpdateBar's core mechanism is **executing shell commands from declarative recipes**. Commands come from (a) direct human input, (b) LLM inference, or (c) shared manifests obtained through `import` or a community registry. Sources (b) and (c) are **untrusted input**. Signing the CLI binary does not solve this problem because a signed CLI may execute unsigned arbitrary commands. The real trust boundary is **recipe provenance plus execution isolation**, not binary signing.

### 22.1 Threat Model

| Threat | Scenario | Core risk |
|--------|----------|-----------|
| **Import RCE** | Import a malicious manifest; `check` runs unattended during `status`/menu bar polling | Code executes on import even if the victim never runs `update`. |
| **Prompt injection → command** | AI registration reads a repository README or URL containing instructions to insert a malicious command | The LLM generates malicious `check`/`latest` commands that run during live testing. |
| **Missing integrity** | `update` fetches from Git/npm/HTTP without signatures or hashes | Plaintext-HTTP MITM, compromised upstream tags, or npm typosquatting. |
| **Secret theft** | A recipe command accesses the user's environment or Keychain | Provider OAuth or OpenRouter tokens leak. |
| **Abused doctor loop** | Failure output is returned to the LLM, automatically “fixed,” and rerun up to three times | An attacker crafts error text that induces a malicious correction command. |

### 22.2 Controls (Design Requirements)

1. **Isolate untrusted recipes** — Mark recipes from imports, registries, and AI as untrusted. Before the first execution of any command, including the first `check`, show the full command and require per-command human approval. Polling must not run it before approval. Default `config.toml [security].allow_import_exec=false`.
2. **Gate every command-bearing field** — `requires_write` covers only `update`; `check.cmd` and `latest.cmd` are also unattended execution surfaces and require the same trust level and approval. Mark recipes containing free-form commands as elevated trust.
3. **Sandbox execution** — Run live-test and periodic-check commands with undeclared network access blocked, writes blocked during tests, and time/resource limits. A dry run is not a security boundary because tools may ignore it; isolation is the enforcement mechanism.
4. **Update integrity** — Require HTTPS for `http`/`http_regex` sources with `require_https_source` and reject plaintext. Support optional per-recipe hash/signature pins and verify before execution. Show prominent UI warnings for `custom` and `http`.
5. **Secret scrubbing** — Remove provider tokens and Keychain handles from recipe-command child environments. Do not log commands or output that may contain tokens.
6. **Provenance/signatures** — Attach signature and source metadata to `export`, and display it on `import`. A community registry requires publisher identity and signatures; postpone the registry if those requirements are unmet.
7. **LLM output is only a proposal** — Never automatically execute Codex, Claude, or Ollama output. Apply controls 2–3 equally to compromised local models, arbitrary Ollama pulls, and prompt-injected hosted models. Explicitly reject the circular claim that automatic testing establishes trust—the test itself is execution.

### 22.3 Non-Controls (Current Limitations)

Complete shell sandboxing is nontrivial on macOS, especially for a non-sandboxed app with limited access to OS sandbox facilities. v1 reduces risk through **approval gates + environment scrubbing + network/write restrictions + integrity verification**, but describes the result honestly as “running human-approved commands in a controlled environment,” not “safely auto-executing untrusted recipes.”
