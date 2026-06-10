# UpdateBar CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a production-quality, distributable `updatebar` CLI that can register arbitrary update targets, check current/latest versions deterministically, update approved targets, import/export recipes, and use OpenRouter only for assisted `add`/diagnostics.

**Architecture:** SwiftPM is the single source of truth. `UpdateBarCore` owns models, storage, validation, version comparison, latest strategies, command execution policy, and provider interfaces. `UpdateBarCLI` is a thin argument-parsing layer over Core, with stable JSON/stdout/stderr/exit-code contracts designed for future macOS menu bar consumption.

**Tech Stack:** Swift 6.x, Swift Argument Parser, Foundation, FoundationNetworking on Linux, Security.framework Keychain on macOS, XCTest, GitHub Actions, Homebrew formula/cask packaging path.

---

## 0. Decisions Locked From PRD + User Answers

- v1 ships CLI first. The menu bar app is not implemented in this plan, but `status --json` is treated as a stable UI contract.
- `add` ships in v1 and uses OpenRouter API key auth only.
- Provider architecture must allow later `codex`, `claude`, OAuth, and local model providers without changing CLI commands.
- Default provider is `openrouter`.
- Default model is `google/gemini-3.5-flash`.
- API key storage:
  - macOS: Keychain through `CredentialStore`.
  - Linux: `OPENROUTER_API_KEY` env var by default, optional user-local file fallback only when explicitly enabled.
  - Config files never store API keys by default.
- Manual registration supports both wizard input and direct JSON import/edit/validate flow.
- Manifest is an object, not a top-level array:

```json
{
  "schema_version": 1,
  "items": [],
  "provenance": {}
}
```

- `sync` is out of v1. Users handle multi-machine/multi-folder workflows through `export` and `import`.
- No telemetry.
- v1 does not ship community recipe registry.

## 1. Release Definition

Release quality means:

- Fresh install creates no invalid state and does not require hand-edited files.
- All commands support deterministic `--json` output where documented.
- `status` never runs shell commands or network calls.
- `check` is the only state-refresh path.
- `update` never runs unapproved or disabled/pinned/untrusted commands.
- Imported and AI-generated recipes are untrusted until command-level approval.
- OpenRouter secrets never appear in `manifest.json`, `state.json`, logs, stdout, or stderr.
- Tests cover schema validation, version comparison, latest strategies, state transitions, CLI exit codes, trust gates, key storage fallback, and update execution.
- CI runs build, tests, formatting, lint-equivalent checks, Linux compile, and release artifact smoke tests.
- Homebrew formula install path works for CLI-only release.

## 2. Repository Layout

Create this structure:

```text
UpdateBar/
  Package.swift
  README.md
  LICENSE
  CHANGELOG.md
  version.env
  plan.md
  .gitignore
  .swift-format
  .github/
    workflows/
      ci.yml
      release.yml
  Sources/
    UpdateBarCLI/
      main.swift
      Commands/
        AddCommand.swift
        AuthCommand.swift
        CheckCommand.swift
        ConfigCommand.swift
        EditCommand.swift
        EnableDisableCommands.swift
        ExportImportCommands.swift
        ListCommand.swift
        PinCommand.swift
        RemoveCommand.swift
        StatusCommand.swift
        UpdateCommand.swift
        ValidateCommand.swift
      Output/
        Console.swift
        ExitCode.swift
    UpdateBarCore/
      Auth/
        CredentialStore.swift
        EnvironmentCredentialStore.swift
        FileCredentialStore.swift
        KeychainCredentialStore.swift
      Config/
        AppPaths.swift
        Config.swift
        ConfigStore.swift
        Duration.swift
      Execution/
        CommandApprovalStore.swift
        CommandExecutor.swift
        ExecutionPolicy.swift
        ShellCommand.swift
      Latest/
        BrewLatestStrategy.swift
        GitLatestStrategy.swift
        GitHubReleaseLatestStrategy.swift
        HTTPLatestStrategy.swift
        LatestStrategy.swift
        NPMRegistryLatestStrategy.swift
      Models/
        CheckResult.swift
        Manifest.swift
        Provenance.swift
        Recipe.swift
        State.swift
        StatusSnapshot.swift
      Providers/
        CompletionProvider.swift
        OpenRouterProvider.swift
        RecipePromptBuilder.swift
        SchemaConstrainedDecoder.swift
      Registry/
        ManifestStore.swift
        StateStore.swift
        RegistryService.swift
      Security/
        SecretRedactor.swift
        TrustPolicy.swift
        UntrustedRecipeGate.swift
      Update/
        UpdatePlanner.swift
        UpdateRunner.swift
      Validation/
        ManifestValidator.swift
        RecipeValidator.swift
        ValidationError.swift
      Versioning/
        VersionComparator.swift
        VersionParser.swift
    UpdateBarTestSupport/
      Fixtures.swift
      MockCommandExecutor.swift
      MockCredentialStore.swift
      MockHTTPClient.swift
  Tests/
    UpdateBarCoreTests/
      AuthTests.swift
      ConfigStoreTests.swift
      ExecutionPolicyTests.swift
      LatestStrategyTests.swift
      ManifestStoreTests.swift
      ManifestValidatorTests.swift
      ProviderTests.swift
      RegistryServiceTests.swift
      StateStoreTests.swift
      StatusSnapshotTests.swift
      UpdateRunnerTests.swift
      VersionComparatorTests.swift
    UpdateBarCLITests/
      AddCommandTests.swift
      AuthCommandTests.swift
      CheckCommandTests.swift
      ExportImportCommandTests.swift
      StatusCommandTests.swift
      UpdateCommandTests.swift
  Fixtures/
    manifests/
      valid-basic.json
      invalid-missing-required.json
      untrusted-import.json
    npm/
      claude-code-registry-response.json
    github/
      releases.json
  Scripts/
    build-release.sh
    install-local.sh
    smoke-test.sh
  Packaging/
    homebrew/
      updatebar.rb
```

Responsibilities:

- `UpdateBarCLI`: Parse flags, call Core services, format output, map errors to exit codes.
- `UpdateBarCore`: All business logic. No CLI-specific printing.
- `UpdateBarTestSupport`: Shared mocks and fixtures. No production dependency on it.
- `Fixtures`: Deterministic test data.
- `Scripts`: Release and local smoke-test automation.
- `Packaging`: Homebrew formula source.

## 3. Command Surface For v1

Ship these commands:

```text
updatebar add --from <path|url> [--ai|--manual] [--provider openrouter] [--dry-run] [--json]
updatebar auth set openrouter [--api-key <key>]
updatebar auth status [--json]
updatebar auth remove openrouter
updatebar check [id...] [--json] [--force] [--exit-zero-on-outdated]
updatebar config get [key] [--json]
updatebar config set <key> <value>
updatebar edit <id>
updatebar enable <id>
updatebar disable <id>
updatebar export [file] [--json]
updatebar import <file> [--json]
updatebar list [--json]
updatebar pin <id> [version]
updatebar unpin <id>
updatebar remove <id> [--yes]
updatebar status [--json] [--refresh] [--exit-zero-on-outdated]
updatebar update [id...|--all] [--yes] [--json]
updatebar validate [file] [--json]
updatebar version [--json]
```

Defer these commands:

```text
updatebar sync
updatebar diff
updatebar doctor
```

Rationale:

- `sync` is explicitly out of v1.
- `diff` and `doctor` need more LLM prompt/security design. The provider interface is built now so they can be added without architecture churn.

## 4. Data Contracts

### 4.1 Manifest

Manifest file path:

```text
~/.updatebar/manifest.json
```

Manifest shape:

```json
{
  "schema_version": 1,
  "items": [
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
      "pin": null,
      "enabled": true,
      "notify": true,
      "trust": {
        "level": "trusted",
        "approved_commands": {}
      }
    }
  ],
  "provenance": {
    "created_by": "updatebar",
    "created_at": "2026-06-09T00:00:00Z",
    "updated_at": "2026-06-09T00:00:00Z"
  }
}
```

Validation rules:

- `schema_version` must equal `1`.
- `items[].id` must match `^[a-z0-9][a-z0-9._-]*$`.
- `items[].id` must be unique.
- `source.kind` is one of `git`, `npm`, `github_release`, `brew`, `http`, `custom`.
- `version_scheme` is one of `semver`, `commit`, `calver`, `opaque`.
- `check` is one of:
  - `{ "cmd": "<command>" }`
  - `{ "file": "<path>", "query": "<jq-or-regex>" }`
- `latest.strategy` is one of `git_tags`, `git_head`, `npm_registry`, `github_release`, `brew`, `http_regex`, `cmd`.
- `latest.cmd` is required only for `cmd`.
- `latest.pattern` is required only for `http_regex`.
- `version_parse` is one of `{ "regex": "..." }` or `{ "jq": "..." }`.
- `update.cmd` is required.
- `sync` is not part of v1 schema.
- `trust.level` is one of `trusted`, `untrusted`, `elevated`.

### 4.2 State

State file path:

```text
~/.updatebar/state.json
```

State shape:

```json
{
  "schema_version": 1,
  "generated_at": "2026-06-09T00:00:00Z",
  "items": {
    "claude-code": {
      "current": "1.4.2",
      "latest": "1.5.0",
      "status": "outdated",
      "last_checked": "2026-06-09T00:00:00Z",
      "error": null,
      "backoff_until": null
    }
  }
}
```

Status values:

```text
ok
outdated
differs
error
pinned
disabled
checking
untrusted
```

Priority:

```text
disabled > pinned > untrusted > error > checking > version comparison
```

### 4.3 Status JSON

`updatebar status --json` prints only JSON to stdout:

```json
{
  "generated_at": "2026-06-09T00:00:00Z",
  "summary": {
    "total": 1,
    "outdated": 1,
    "errors": 0
  },
  "items": [
    {
      "id": "claude-code",
      "name": "Claude Code",
      "category": "cli",
      "current": "1.4.2",
      "latest": "1.5.0",
      "status": "outdated",
      "pinned": false,
      "last_checked": "2026-06-09T00:00:00Z",
      "error": null
    }
  ]
}
```

Rules:

- `status` does not execute shell commands.
- `status` does not call network APIs.
- `status --refresh` marks stale items as `checking`, starts or requests background check if available, and returns immediately. If background execution is not installed yet, it prints a clear stderr note and exits successfully after marking state.

## 5. Exit Codes

Implement exactly:

```text
0  success
1  user/input/config error
2  partial item failure
10 outdated items exist for check/status
```

Rules:

- `--json` sends machine data to stdout only.
- Human messages and warnings go to stderr.
- `check` and `status` return `10` when outdated items exist unless `--exit-zero-on-outdated` is passed.
- `update` returns `0` only when every selected update succeeds.
- `update` returns `2` for partial failure.

## 6. Implementation Tasks

### Task 1: Initialize SwiftPM CLI Package

**Files:**

- Create: `Package.swift`
- Create: `.gitignore`
- Create: `.swift-format`
- Create: `version.env`
- Create: `Sources/UpdateBarCLI/main.swift`
- Create: `Sources/UpdateBarCore/Versioning/VersionComparator.swift`
- Create: `Tests/UpdateBarCoreTests/VersionComparatorTests.swift`

- [x] Create git repo if missing.

Run:

```bash
rtk git status
```

Expected if missing:

```text
Not a git repository
```

Then run:

```bash
rtk git init
```

- [x] Add SwiftPM package with products `updatebar`, `UpdateBarCore`, and `UpdateBarTestSupport`.

`Package.swift` package decisions:

- Swift tools version: 6.0 or current Xcode-supported version.
- Dependencies:
  - `swift-argument-parser`
- Platforms:
  - macOS 13+

- [x] Add minimal CLI entry.

First command:

```bash
rtk swift run updatebar version --json
```

Expected:

```json
{"version":"0.1.0"}
```

- [x] Add a first unit test for semantic version comparison.

Test cases:

```text
1.2.3 < 1.2.4
1.2.3 == 1.2.3
2.0.0 > 1.9.9
1.0.0-beta < 1.0.0
```

- [x] Run tests.

```bash
rtk swift test
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Package.swift .gitignore .swift-format version.env Sources Tests
rtk git commit -m "chore: initialize SwiftPM CLI"
```

### Task 2: Model Manifest, Recipe, State, And Status Types

**Files:**

- Create: `Sources/UpdateBarCore/Models/Manifest.swift`
- Create: `Sources/UpdateBarCore/Models/Recipe.swift`
- Create: `Sources/UpdateBarCore/Models/Provenance.swift`
- Create: `Sources/UpdateBarCore/Models/State.swift`
- Create: `Sources/UpdateBarCore/Models/StatusSnapshot.swift`
- Create: `Tests/UpdateBarCoreTests/ManifestStoreTests.swift`
- Create: `Tests/UpdateBarCoreTests/StatusSnapshotTests.swift`
- Create: `Fixtures/manifests/valid-basic.json`

- [x] Write decoding tests for the manifest object shape.

Cover:

- `schema_version`.
- `items`.
- `provenance`.
- `trust`.
- Missing `sync`.

- [x] Write status priority tests.

Expected priority:

```text
disabled > pinned > untrusted > error > checking > ok/outdated/differs
```

- [x] Implement `Codable`, `Equatable`, and focused helper methods.

Required helpers:

```text
Manifest.item(id:)
Manifest.replacing(item:)
Manifest.removing(id:)
Recipe.hasCommandFields
Recipe.commandFingerprints
StatusSnapshot.from(manifest:state:now:)
```

- [x] Run tests.

```bash
rtk swift test --filter Manifest
rtk swift test --filter StatusSnapshot
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Models Tests Fixtures
rtk git commit -m "feat: add manifest and status models"
```

### Task 3: Implement Manifest Validation

**Files:**

- Create: `Sources/UpdateBarCore/Validation/ManifestValidator.swift`
- Create: `Sources/UpdateBarCore/Validation/RecipeValidator.swift`
- Create: `Sources/UpdateBarCore/Validation/ValidationError.swift`
- Create: `Tests/UpdateBarCoreTests/ManifestValidatorTests.swift`
- Create: `Fixtures/manifests/invalid-missing-required.json`

- [x] Write validator tests before implementation.

Cases:

- Accept valid manifest.
- Reject unsupported `schema_version`.
- Reject duplicate `id`.
- Reject invalid `id`.
- Reject invalid `source.kind`.
- Reject invalid `version_scheme`.
- Reject `latest.strategy: "cmd"` without `cmd`.
- Reject `latest.strategy: "http_regex"` without `pattern`.
- Reject both `regex` and `jq` in `version_parse`.
- Reject `sync` when present.

- [x] Implement validators with precise error paths.

Error format:

```text
items[0].latest.cmd: required when latest.strategy is cmd
```

- [x] Add CLI `validate`.

Command behavior:

```bash
rtk swift run updatebar validate Fixtures/manifests/valid-basic.json --json
```

Expected stdout:

```json
{"valid":true,"errors":[]}
```

Invalid expected stdout:

```json
{"valid":false,"errors":["items[0].name: required"]}
```

- [x] Run tests.

```bash
rtk swift test --filter ManifestValidator
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Validation Sources/UpdateBarCLI/Commands/ValidateCommand.swift Tests Fixtures
rtk git commit -m "feat: validate manifests"
```

### Task 4: Add App Paths And Atomic Stores

**Files:**

- Create: `Sources/UpdateBarCore/Config/AppPaths.swift`
- Create: `Sources/UpdateBarCore/Registry/ManifestStore.swift`
- Create: `Sources/UpdateBarCore/Registry/StateStore.swift`
- Create: `Tests/UpdateBarCoreTests/ManifestStoreTests.swift`
- Create: `Tests/UpdateBarCoreTests/StateStoreTests.swift`

- [x] Write tests using a temporary home directory.

Cases:

- Empty store initializes manifest and state.
- Writes are atomic through temp file + rename.
- Corrupt manifest returns a clear error.
- Store never creates files outside configured `UPDATEBAR_HOME`.

- [x] Implement `AppPaths`.

Resolution order:

```text
UPDATEBAR_HOME
~/.updatebar
```

- [x] Implement atomic JSON read/write.

Rules:

- Pretty-print stable JSON.
- `manifest.json` permissions: `0600`.
- `state.json` permissions: `0600`.
- Use file lock or single-process lock to avoid concurrent writes in one process.

- [x] Run tests.

```bash
rtk swift test --filter Store
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Config Sources/UpdateBarCore/Registry Tests
rtk git commit -m "feat: add atomic manifest and state stores"
```

### Task 5: Implement Config Store

**Files:**

- Create: `Sources/UpdateBarCore/Config/Config.swift`
- Create: `Sources/UpdateBarCore/Config/ConfigStore.swift`
- Create: `Sources/UpdateBarCore/Config/Duration.swift`
- Create: `Tests/UpdateBarCoreTests/ConfigStoreTests.swift`
- Create: `Sources/UpdateBarCLI/Commands/ConfigCommand.swift`

- [x] Write config tests.

Defaults:

```toml
[provider]
default = "openrouter"
model = "google/gemini-3.5-flash"

[refresh]
interval = "6h"
concurrency = 8

[security]
allow_import_exec = false
require_https_source = true
allow_plaintext_secret_file = false

[notify]
enabled = true
```

- [x] Implement minimal TOML support.

Scope:

- Parse and write only the keys UpdateBar owns.
- Preserve no comments in v1.
- Reject unknown sections/keys in `config set`.

- [x] Implement commands.

Examples:

```bash
rtk swift run updatebar config get provider.default --json
rtk swift run updatebar config set refresh.interval 30m
```

- [x] Run tests.

```bash
rtk swift test --filter Config
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Config Sources/UpdateBarCLI/Commands/ConfigCommand.swift Tests
rtk git commit -m "feat: add config store"
```

### Task 6: Implement Credential Storage

**Files:**

- Create: `Sources/UpdateBarCore/Auth/CredentialStore.swift`
- Create: `Sources/UpdateBarCore/Auth/EnvironmentCredentialStore.swift`
- Create: `Sources/UpdateBarCore/Auth/FileCredentialStore.swift`
- Create: `Sources/UpdateBarCore/Auth/KeychainCredentialStore.swift`
- Create: `Sources/UpdateBarCLI/Commands/AuthCommand.swift`
- Create: `Tests/UpdateBarCoreTests/AuthTests.swift`
- Create: `Tests/UpdateBarCLITests/AuthCommandTests.swift`

- [x] Write credential tests.

Cases:

- `EnvironmentCredentialStore` reads `OPENROUTER_API_KEY`.
- `FileCredentialStore` is disabled unless config allows it.
- Secret values are redacted in descriptions.
- `auth status --json` never prints the key.

- [x] Implement `CredentialStore`.

Interface:

```swift
public protocol CredentialStore {
    func read(provider: String) throws -> String?
    func write(provider: String, secret: String) throws
    func delete(provider: String) throws
    func status(provider: String) throws -> CredentialStatus
}
```

- [x] Implement macOS Keychain.

Keychain item:

```text
service: app.updatebar.credentials
account: openrouter
```

Linux behavior:

- `read` checks `OPENROUTER_API_KEY`.
- `write` fails with an actionable message unless file fallback is explicitly enabled.

- [x] Implement `auth` commands.

Commands:

```bash
rtk swift run updatebar auth set openrouter
rtk swift run updatebar auth status --json
rtk swift run updatebar auth remove openrouter
```

Expected `status --json`:

```json
{"provider":"openrouter","available":true,"source":"keychain"}
```

- [x] Run tests.

```bash
rtk swift test --filter Auth
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Auth Sources/UpdateBarCLI/Commands/AuthCommand.swift Tests
rtk git commit -m "feat: store OpenRouter credentials"
```

### Task 7: Implement Version Parsing And Comparison

**Files:**

- Create: `Sources/UpdateBarCore/Versioning/VersionParser.swift`
- Modify: `Sources/UpdateBarCore/Versioning/VersionComparator.swift`
- Create: `Tests/UpdateBarCoreTests/VersionComparatorTests.swift`

- [x] Expand tests.

Cases:

- Semver normal versions.
- Semver prerelease.
- Calver numeric token comparison.
- Commit exact equality/difference.
- Opaque exact equality/difference.
- Regex extraction with one capture group.
- Regex with zero or two capture groups fails validation.

- [x] Implement comparison outputs.

Output:

```text
same
older
newer
differs
unknown
```

Mapping:

- `semver older` -> `outdated`.
- `calver older` -> `outdated`.
- `commit differs` -> `outdated`.
- `opaque differs` -> `differs`.

- [x] Run tests.

```bash
rtk swift test --filter Version
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Versioning Tests/UpdateBarCoreTests/VersionComparatorTests.swift
rtk git commit -m "feat: compare version schemes"
```

### Task 8: Implement Safe Command Execution

**Files:**

- Create: `Sources/UpdateBarCore/Execution/ShellCommand.swift`
- Create: `Sources/UpdateBarCore/Execution/CommandExecutor.swift`
- Create: `Sources/UpdateBarCore/Execution/ExecutionPolicy.swift`
- Create: `Sources/UpdateBarCore/Security/SecretRedactor.swift`
- Create: `Tests/UpdateBarCoreTests/ExecutionPolicyTests.swift`

- [x] Write tests.

Cases:

- Timeout kills process.
- Non-zero exit captures stderr.
- Provider secrets are removed from child env.
- Redactor masks `sk-or-v1-...`.
- `cwd` must exist.
- Command output size is capped.

- [x] Implement shell execution.

Rules:

- Use `/bin/zsh -lc` on macOS for user PATH compatibility.
- Use `/bin/sh -lc` on Linux.
- Default timeout: 60 seconds for check/latest cmd, no default for update without explicit confirmation path.
- Max captured stdout/stderr per stream: 128 KB.
- Strip env names:
  - `OPENROUTER_API_KEY`
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - `GOOGLE_API_KEY`
  - `GITHUB_TOKEN`
  - `GH_TOKEN`

- [x] Run tests.

```bash
rtk swift test --filter Execution
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Execution Sources/UpdateBarCore/Security Tests
rtk git commit -m "feat: execute commands with policy"
```

### Task 9: Implement Trust And Command Approval

**Files:**

- Create: `Sources/UpdateBarCore/Execution/CommandApprovalStore.swift`
- Create: `Sources/UpdateBarCore/Security/TrustPolicy.swift`
- Create: `Sources/UpdateBarCore/Security/UntrustedRecipeGate.swift`
- Create: `Tests/UpdateBarCoreTests/ExecutionPolicyTests.swift`

- [x] Write tests.

Cases:

- Imported recipe starts `untrusted`.
- AI recipe starts `untrusted`.
- Manual wizard recipe can become `trusted` after explicit approval.
- Any recipe with `latest.strategy: cmd` is `elevated`.
- Changed command invalidates previous approval.
- `check` refuses unapproved `check.cmd`.
- `update` refuses unapproved `update.cmd`.

- [x] Implement command fingerprints.

Fingerprint input:

```text
recipe id + command field name + command string + cwd
```

Hash:

```text
SHA-256 hex
```

- [x] Store approvals in manifest item `trust.approved_commands`.

Example:

```json
{
  "check.cmd": "sha256:...",
  "update.cmd": "sha256:..."
}
```

- [x] Run tests.

```bash
rtk swift test --filter Trust
rtk swift test --filter ExecutionPolicy
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Execution Sources/UpdateBarCore/Security Tests
rtk git commit -m "feat: gate untrusted recipe commands"
```

### Task 10: Implement Latest Strategies

**Files:**

- Create: `Sources/UpdateBarCore/Latest/LatestStrategy.swift`
- Create: `Sources/UpdateBarCore/Latest/NPMRegistryLatestStrategy.swift`
- Create: `Sources/UpdateBarCore/Latest/GitLatestStrategy.swift`
- Create: `Sources/UpdateBarCore/Latest/GitHubReleaseLatestStrategy.swift`
- Create: `Sources/UpdateBarCore/Latest/BrewLatestStrategy.swift`
- Create: `Sources/UpdateBarCore/Latest/HTTPLatestStrategy.swift`
- Create: `Tests/UpdateBarCoreTests/LatestStrategyTests.swift`
- Create: `Fixtures/npm/claude-code-registry-response.json`
- Create: `Fixtures/github/releases.json`

- [x] Write strategy tests with mocked HTTP and command executor.

Cases:

- `npm_registry` reads `dist-tags.latest`.
- `git_head` compares remote head SHA.
- `git_tags` selects highest semver tag for semver items.
- `github_release` reads latest non-draft release.
- `brew` parses `brew info --json=v2`.
- `http_regex` extracts first capture.
- `cmd` uses command executor and version parser.

- [x] Implement per-strategy interfaces.

Interface:

```swift
public protocol LatestStrategy {
    func latest(for recipe: Recipe, context: LatestContext) async throws -> String
}
```

- [x] Implement HTTP client abstraction.

Avoid real network in unit tests.

- [x] Add optional GitHub token usage.

Source:

```text
GITHUB_TOKEN
GH_TOKEN
config provider.github_token only if later explicitly supported
```

Do not persist GitHub token in v1 config by default.

- [x] Run tests.

```bash
rtk swift test --filter LatestStrategy
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Latest Tests Fixtures
rtk git commit -m "feat: add latest version strategies"
```

### Task 11: Implement Check Flow

**Files:**

- Create: `Sources/UpdateBarCore/Models/CheckResult.swift`
- Create: `Sources/UpdateBarCore/Registry/RegistryService.swift`
- Create: `Sources/UpdateBarCLI/Commands/CheckCommand.swift`
- Create: `Tests/UpdateBarCoreTests/RegistryServiceTests.swift`
- Create: `Tests/UpdateBarCLITests/CheckCommandTests.swift`

- [x] Write tests.

Cases:

- `check` updates state for one item.
- `check` updates all enabled, trusted items.
- `check` skips disabled.
- `check` marks pinned as pinned.
- `check` returns item error without failing all items.
- `check` honors concurrency cap.
- `check` honors TTL unless `--force`.
- `check --json` stdout contains item results only.

- [x] Implement check pipeline.

Pipeline:

```text
load manifest
validate manifest
select items
apply trust/pin/enabled policy
run current check
run latest strategy
parse current/latest
compare
write state atomically
return CheckResult list
```

- [x] Implement CLI `check`.

Examples:

```bash
rtk swift run updatebar check --json
rtk swift run updatebar check claude-code --force --json
```

- [x] Verify exit code `10`.

Run fixture check where an item is outdated.

Expected:

```text
process exits 10 unless --exit-zero-on-outdated is set
```

- [x] Run tests.

```bash
rtk swift test --filter Check
rtk swift test --filter RegistryService
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Models Sources/UpdateBarCore/Registry Sources/UpdateBarCLI/Commands/CheckCommand.swift Tests
rtk git commit -m "feat: check registered items"
```

### Task 12: Implement Status And List

**Files:**

- Create: `Sources/UpdateBarCLI/Commands/StatusCommand.swift`
- Create: `Sources/UpdateBarCLI/Commands/ListCommand.swift`
- Create: `Tests/UpdateBarCLITests/StatusCommandTests.swift`

- [x] Write tests.

Cases:

- `status` reads state only.
- `status` does not call command executor.
- `status --refresh` marks items `checking`.
- `status --json` matches menu bar contract.
- `list --json` returns manifest items without state mutation.

- [x] Implement `status`.

Rules:

- No shell.
- No network.
- Stable item ordering by `name`, then `id`.

- [x] Implement `list`.

Human output columns:

```text
ID  NAME  CATEGORY  ENABLED  PINNED  TRUST
```

- [x] Run tests.

```bash
rtk swift test --filter Status
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCLI/Commands/StatusCommand.swift Sources/UpdateBarCLI/Commands/ListCommand.swift Tests
rtk git commit -m "feat: report status and list items"
```

### Task 13: Implement Update Flow

**Files:**

- Create: `Sources/UpdateBarCore/Update/UpdatePlanner.swift`
- Create: `Sources/UpdateBarCore/Update/UpdateRunner.swift`
- Create: `Sources/UpdateBarCLI/Commands/UpdateCommand.swift`
- Create: `Tests/UpdateBarCoreTests/UpdateRunnerTests.swift`
- Create: `Tests/UpdateBarCLITests/UpdateCommandTests.swift`

- [x] Write tests.

Cases:

- Update selected item.
- Update all outdated items.
- Skip pinned.
- Skip disabled.
- Skip untrusted/unapproved commands.
- Require confirmation unless `--yes`.
- On success, run `check` for updated item.
- Partial failure exits `2`.
- Redact secrets from output.

- [x] Implement update planning.

Planner outputs:

```text
will_update
skipped_pinned
skipped_disabled
skipped_untrusted
skipped_not_outdated
missing
```

- [x] Implement update execution.

Rules:

- Use approved `update.cmd`.
- Use recipe `update.cwd` if set.
- Human confirmation prints full command.
- `--json` includes command fingerprint, not command output unless safe and redacted.

- [x] Run tests.

```bash
rtk swift test --filter Update
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Update Sources/UpdateBarCLI/Commands/UpdateCommand.swift Tests
rtk git commit -m "feat: update approved items"
```

### Task 14: Implement Pin, Enable, Disable, Remove

**Files:**

- Create: `Sources/UpdateBarCLI/Commands/PinCommand.swift`
- Create: `Sources/UpdateBarCLI/Commands/EnableDisableCommands.swift`
- Create: `Sources/UpdateBarCLI/Commands/RemoveCommand.swift`
- Modify: `Sources/UpdateBarCore/Registry/RegistryService.swift`
- Create: `Tests/UpdateBarCLITests/UpdateCommandTests.swift`

- [x] Write tests.

Cases:

- `pin <id> <version>` sets pin.
- `pin <id>` pins current state version.
- `unpin <id>` clears pin.
- `disable <id>` sets enabled false.
- `enable <id>` sets enabled true.
- `remove <id>` requires confirmation unless `--yes`.
- State is removed when manifest item is removed.

- [x] Implement commands.

Expected examples:

```bash
rtk swift run updatebar pin claude-code 1.4.2
rtk swift run updatebar disable claude-code
rtk swift run updatebar remove claude-code --yes
```

- [x] Run tests.

```bash
rtk swift test --filter Pin
rtk swift test --filter Remove
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCLI/Commands Sources/UpdateBarCore/Registry Tests
rtk git commit -m "feat: manage registered items"
```

### Task 15: Implement Import And Export

**Files:**

- Create: `Sources/UpdateBarCLI/Commands/ExportImportCommands.swift`
- Create: `Tests/UpdateBarCLITests/ExportImportCommandTests.swift`
- Create: `Fixtures/manifests/untrusted-import.json`

- [x] Write tests.

Cases:

- `export` writes manifest object.
- `import` validates file before merge.
- Imported items become `untrusted`.
- Duplicate id requires explicit replace flag.
- Import never executes commands.
- Import rejects unsupported schema version.

- [x] Implement export.

Commands:

```bash
rtk swift run updatebar export exported.json
rtk swift run updatebar export --json
```

- [x] Implement import.

Default behavior:

- Merge new ids.
- Reject duplicate ids with clear message.
- Mark all imported command-bearing recipes as `untrusted`.

- [x] Run tests.

```bash
rtk swift test --filter ExportImport
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCLI/Commands/ExportImportCommands.swift Tests Fixtures
rtk git commit -m "feat: import and export manifests"
```

### Task 16: Implement Manual Add Wizard And JSON Add

**Files:**

- Create: `Sources/UpdateBarCLI/Commands/AddCommand.swift`
- Modify: `Sources/UpdateBarCore/Registry/RegistryService.swift`
- Create: `Tests/UpdateBarCLITests/AddCommandTests.swift`

- [x] Write tests.

Cases:

- `add --manual --json recipe.json` validates and adds recipe.
- Added JSON recipe is untrusted unless `--trust` is explicitly passed and commands are approved.
- Wizard creates a valid recipe.
- Duplicate id fails.
- `--dry-run` prints recipe but does not write manifest.

- [x] Implement JSON add.

Command:

```bash
rtk swift run updatebar add --manual --json Fixtures/manifests/valid-basic.json --dry-run
```

Behavior:

- Accept either a full manifest object with one item or a single recipe object.
- Print validation result.

- [x] Implement wizard add.

Prompt fields:

```text
id
name
category
path
source.kind
source.ref
source.branch
version_scheme
check.cmd or check.file/query
latest.strategy
version_parse.regex or version_parse.jq
update.cmd
update.cwd
notify
```

- [x] Implement command approval prompt.

Show:

```text
check.cmd: <command>
latest.cmd: <command if present>
update.cmd: <command>
```

Require exact `yes`.

- [x] Run tests.

```bash
rtk swift test --filter AddCommand
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCLI/Commands/AddCommand.swift Sources/UpdateBarCore/Registry Tests
rtk git commit -m "feat: add recipes manually"
```

### Task 17: Implement OpenRouter Provider For AI Add

**Files:**

- Create: `Sources/UpdateBarCore/Providers/CompletionProvider.swift`
- Create: `Sources/UpdateBarCore/Providers/OpenRouterProvider.swift`
- Create: `Sources/UpdateBarCore/Providers/RecipePromptBuilder.swift`
- Create: `Sources/UpdateBarCore/Providers/SchemaConstrainedDecoder.swift`
- Modify: `Sources/UpdateBarCLI/Commands/AddCommand.swift`
- Create: `Tests/UpdateBarCoreTests/ProviderTests.swift`
- Create: `Tests/UpdateBarCLITests/AddCommandTests.swift`

- [x] Write provider tests with mocked HTTP.

Cases:

- Sends model `google/gemini-3.5-flash`.
- Sends API key as `Authorization: Bearer`.
- Requests JSON-only response.
- Retries schema-invalid response up to 3 times.
- Never logs API key.
- AI-created recipe is untrusted.

- [x] Implement provider interface.

Interface:

```swift
public protocol CompletionProvider {
    var name: String { get }
    func complete<T: Decodable>(
        prompt: String,
        schemaName: String,
        type: T.Type
    ) async throws -> T
}
```

- [x] Implement OpenRouter chat completion call.

Endpoint:

```text
https://openrouter.ai/api/v1/chat/completions
```

Request model:

```text
google/gemini-3.5-flash
```

- [x] Build recipe prompt.

Prompt must instruct:

- Return only JSON.
- Do not include shell commands that delete files, exfiltrate secrets, mutate unrelated files, or use network destinations unrelated to source.
- Prefer deterministic package manager or VCS commands.
- Mark uncertain fields conservatively.

- [x] Implement `add --ai`.

Flow:

```text
read --from path or URL
build context
call OpenRouter
decode recipe
validate recipe
show all commands
require approval
save as untrusted until approved fingerprints are stored
```

- [x] Run tests.

```bash
rtk swift test --filter Provider
rtk swift test --filter AddCommand
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCore/Providers Sources/UpdateBarCLI/Commands/AddCommand.swift Tests
rtk git commit -m "feat: add OpenRouter assisted registration"
```

### Task 18: Implement Edit Flow

**Files:**

- Create: `Sources/UpdateBarCLI/Commands/EditCommand.swift`
- Modify: `Sources/UpdateBarCore/Registry/RegistryService.swift`
- Create: `Tests/UpdateBarCLITests/EditCommandTests.swift`

- [x] Write tests.

Cases:

- `edit <id>` opens `$EDITOR`.
- Edited recipe is validated before save.
- Command changes invalidate affected approvals.
- Invalid edit leaves original manifest unchanged.

- [x] Implement edit command.

Rules:

- Use `$VISUAL`, then `$EDITOR`, then platform fallback.
- Write temp JSON recipe.
- Validate after editor exits.
- Save atomically through `ManifestStore`.

- [x] Run tests.

```bash
rtk swift test --filter EditCommand
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources/UpdateBarCLI/Commands/EditCommand.swift Sources/UpdateBarCore/Registry Tests
rtk git commit -m "feat: edit recipes safely"
```

### Task 19: CLI Output Polish And Error Taxonomy

**Files:**

- Create: `Sources/UpdateBarCLI/Output/Console.swift`
- Create: `Sources/UpdateBarCLI/Output/ExitCode.swift`
- Modify: all command files.
- Create: `Tests/UpdateBarCLITests/*`

- [x] Write CLI output tests.

Cases:

- JSON stdout is valid JSON.
- stderr contains human messages.
- No secrets in stdout/stderr.
- Missing manifest prints actionable setup hint.
- Missing API key prints `updatebar auth set openrouter`.
- Invalid args return exit `1`.

- [x] Implement unified errors.

Categories:

```text
usage
config
validation
credential
trust
execution
network
partialFailure
outdated
```

- [x] Add `--verbose` for debug-safe extra context.

Verbose still redacts secrets.

- [x] Run full tests.

```bash
rtk swift test
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Sources Tests
rtk git commit -m "feat: standardize CLI output and errors"
```

### Task 20: Smoke Tests

**Files:**

- Create: `Scripts/smoke-test.sh`
- Create: `Scripts/install-local.sh`
- Create: `Fixtures/manifests/valid-basic.json`

- [x] Create smoke test script.

Smoke flow:

```bash
#!/usr/bin/env bash
set -euo pipefail

TMP_HOME="$(mktemp -d)"
export UPDATEBAR_HOME="$TMP_HOME"

swift run updatebar version --json
swift run updatebar validate Fixtures/manifests/valid-basic.json --json
swift run updatebar import Fixtures/manifests/valid-basic.json --json
swift run updatebar list --json
swift run updatebar status --json --exit-zero-on-outdated
swift run updatebar auth status --json
```

- [x] Run smoke test.

```bash
rtk bash Scripts/smoke-test.sh
```

Expected: pass.

- [x] Commit.

```bash
rtk git add Scripts Fixtures
rtk git commit -m "test: add CLI smoke test"
```

### Task 21: Documentation

**Files:**

- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `LICENSE`
- Create: `docs/cli.md`
- Create: `docs/manifest.md`
- Create: `docs/security.md`
- Create: `docs/release.md`

- [x] Write README.

Must include:

- What UpdateBar is.
- Install from source.
- Quick start:
  - `updatebar auth set openrouter`
  - `updatebar add --manual`
  - `updatebar check`
  - `updatebar status --json`
  - `updatebar update --all`
- No telemetry.
- v1 scope exclusions.

- [x] Write CLI docs.

For every command:

- Purpose.
- Options.
- Example.
- JSON output when supported.
- Exit-code behavior.

- [x] Write manifest docs.

Include full schema example and trust model.

- [x] Write security docs.

Include:

- Untrusted recipes.
- Command approval.
- Keychain/env secret storage.
- Secret redaction.
- `status` vs `check`.

- [x] Run docs check.

```bash
rtk grep "TO[D]O|TB[D]|PLACEHOLDER" README.md docs
```

Expected: no matches.

- [x] Commit.

```bash
rtk git add README.md CHANGELOG.md LICENSE docs
rtk git commit -m "docs: document UpdateBar CLI"
```

### Task 22: CI

**Files:**

- Create: `.github/workflows/ci.yml`

- [x] Add CI jobs.

Jobs:

- macOS Swift build and test.
- Linux Swift build and test.
- Smoke test.
- Formatting check.

Commands:

```bash
swift build
swift test
bash Scripts/smoke-test.sh
swift-format lint --recursive Sources Tests
```

- [x] Add dependency caching for SwiftPM.

- [x] Verify locally where possible.

```bash
rtk swift build
rtk swift test
rtk bash Scripts/smoke-test.sh
```

Expected: pass.

- [x] Commit.

```bash
rtk git add .github/workflows/ci.yml
rtk git commit -m "ci: add build and test workflow"
```

### Task 23: Release Build And Homebrew Formula

**Files:**

- Create: `Scripts/build-release.sh`
- Create: `Packaging/homebrew/updatebar.rb`
- Create: `.github/workflows/release.yml`
- Modify: `version.env`
- Modify: `docs/release.md`

- [x] Implement release build script.

Script behavior:

```bash
swift build -c release --product updatebar
install_name_tool check on macOS if needed
codesign ad-hoc for local smoke if Developer ID not present
archive binary as updatebar-macos-arm64.tar.gz or updatebar-linux-x86_64.tar.gz
```

- [x] Add formula.

Formula must:

- Download GitHub release tarball.
- Install `bin/updatebar`.
- Run `updatebar version --json` in test block.

- [x] Add release workflow.

Trigger:

```text
tag v*
```

Outputs:

- macOS arm64 CLI archive.
- Linux x86_64 CLI archive.
- Checksums.

- [x] Run local release build.

```bash
rtk bash Scripts/build-release.sh
```

Expected:

```text
dist/updatebar-<platform>.tar.gz
```

- [x] Commit.

```bash
rtk git add Scripts/build-release.sh Packaging/homebrew/updatebar.rb .github/workflows/release.yml docs/release.md version.env
rtk git commit -m "build: add release packaging"
```

### Task 24: Production Hardening Pass

**Files:**

- Modify: focused files found by review.

- [x] Run full verification.

```bash
rtk swift build -c release
rtk swift test
rtk bash Scripts/smoke-test.sh
rtk grep "OPENROUTER_API_KEY" Sources Tests README.md docs
```

Expected:

- Build passes.
- Tests pass.
- Smoke passes.
- `OPENROUTER_API_KEY` appears only in docs/tests where intended, never in logged fixture output.

- [x] Manual CLI dogfood with temp home.

```bash
export UPDATEBAR_HOME="$(mktemp -d)"
rtk swift run updatebar version --json
rtk swift run updatebar auth status --json
rtk swift run updatebar add --manual --dry-run
rtk swift run updatebar import Fixtures/manifests/valid-basic.json --json
rtk swift run updatebar list
rtk swift run updatebar status --json --exit-zero-on-outdated
```

Expected:

- No crash.
- No invalid JSON.
- Clear error if auth missing.
- `status` returns immediately.

- [x] Review against PRD.

Coverage checklist:

- CLI-first core: implemented.
- Menu bar contract: `status --json` implemented.
- Deterministic runtime: implemented.
- OpenRouter `add`: implemented.
- OAuth/local LLM extension points: provider interface exists.
- Import/export: implemented.
- Sync: intentionally absent.
- Telemetry: absent.
- Security gate: implemented.

- [x] Commit fixes.

```bash
rtk git add .
rtk git commit -m "chore: harden CLI release"
```

## 7. Test Matrix

Run before release:

```bash
rtk swift build
rtk swift build -c release
rtk swift test
rtk bash Scripts/smoke-test.sh
```

Manual command matrix with `UPDATEBAR_HOME="$(mktemp -d)"`:

```bash
rtk swift run updatebar version --json
rtk swift run updatebar validate Fixtures/manifests/valid-basic.json --json
rtk swift run updatebar import Fixtures/manifests/valid-basic.json --json
rtk swift run updatebar list
rtk swift run updatebar list --json
rtk swift run updatebar status --json --exit-zero-on-outdated
rtk swift run updatebar check --json --exit-zero-on-outdated
rtk swift run updatebar pin claude-code 1.4.2
rtk swift run updatebar unpin claude-code
rtk swift run updatebar disable claude-code
rtk swift run updatebar enable claude-code
rtk swift run updatebar export exported.json
rtk swift run updatebar remove claude-code --yes
```

OpenRouter manual test with real key:

```bash
rtk swift run updatebar auth set openrouter
rtk swift run updatebar auth status --json
rtk swift run updatebar add --from https://github.com/example/example --ai --dry-run --json
```

Expected:

- Key is not printed.
- Recipe is valid or validation errors are actionable.
- No generated command executes without approval.

## 8. Security Acceptance Criteria

- `status` cannot trigger RCE because it reads only state.
- `import` cannot trigger RCE because it only validates and writes untrusted manifest items.
- `add --ai` cannot trigger RCE because generated commands require explicit approval before any live test.
- `check` cannot run untrusted commands.
- `update` cannot run untrusted commands.
- Command approval is invalidated by command string or cwd change.
- Provider secrets are scrubbed from child process env.
- API keys are redacted in all errors and logs.
- `manifest.json`, `state.json`, and optional local secret files are `0600`.
- Plain HTTP sources are rejected when `security.require_https_source = true`.

## 9. Release Gate

Release only when all are true:

- `rtk swift test` passes on macOS.
- CI passes on macOS and Linux.
- `Scripts/smoke-test.sh` passes from a clean temp `UPDATEBAR_HOME`.
- `updatebar status --json` output matches documented schema.
- `updatebar check --json` returns exit `10` for outdated fixture and `0` with `--exit-zero-on-outdated`.
- `updatebar update` refuses untrusted recipes.
- OpenRouter API key never appears in captured output.
- Homebrew formula test passes.
- README quick start works on a clean machine.
- CHANGELOG has version entry matching `version.env`.

## 10. Deferred Work

Explicitly not part of this CLI release:

- macOS menu bar app.
- Sparkle appcast for menu bar app.
- `sync`.
- Community recipe registry.
- Recipe signing.
- Full OS-level sandbox for recipe commands.
- `codex`/`claude` OAuth providers.
- Local Ollama provider.
- `diff`.
- `doctor`.

Keep architecture ready for these by preserving:

- `CompletionProvider`.
- `CredentialStore`.
- `LatestStrategy`.
- `CommandExecutor`.
- `TrustPolicy`.
- Stable `status --json`.
