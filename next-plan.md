# UpdateBar — Next Plan After Local Menu Bar MVP

Status as of 2026-07-01. Reviewed against commit `6b3bdcd` after the public
v0.2.0 release, Homebrew formula/cask publishing, and scan/init UX hardening.
Roadmap is now focused on post-release polish and the signed-app decision.

The current product stance:

```text
UpdateBar is a safe, scriptable CLI for tracking and updating user-approved recipes.
It does not generate recipes or commands itself.
External agents may author recipe JSON, but UpdateBar remains the validation, trust, and execution boundary.
```

Current implemented base:

- CLI and `UpdateBarCore`
- optional local macOS menu bar wrapper: `updatebar-menubar`, `UpdateBarMenuBar`,
  and `UpdateBarMenuBarApp`
- manifest/state/config stores with `manifest.lock` / `state.lock`
- manual add/import/export
- `guide agent`, `guide recipe`, recipe/manifest templates, JSON schema output
- `validate` for manifest or single recipe JSON, including stdin
- `import` from file or stdin
- per-command `approve` / `approvals` / `revoke`
- JSON output for mutating management commands
- JSON error envelope for parser/runtime failures when `--json` is present and
  no command payload has already been written
- `check` / `status` / `update`, with `--exit-zero-on-outdated` on `check` and `status`
- distinct update exit code `3` for approval-blocked updates
- env allowlist for recipe child processes (`PATH, HOME, LANG, LC_ALL, LC_CTYPE, TMPDIR, USER`)
- recipe commands run via `/bin/sh -c`, no login shell, no shell startup files
- opt-in macOS background check helper
- public `v0.2.0` release assets for Apple Silicon macOS and Linux x86_64 CLI
- unsigned Apple Silicon macOS app archive
- Homebrew formula `sonim1/tap/updatebar`
- Homebrew cask `sonim1/tap/updatebar-app` for the app only
- CI, CLI release packaging, archive-install smoke, app packaging smoke, and
  E2E edge-case checks

Removed from product: built-in OpenRouter add, provider auth, provider config,
plaintext secret fallback, credential stores.

---

## 1. Guardrails

These invariants must hold across every future milestone.

1. **No built-in AI recipe generation.** Agents author recipe files outside UpdateBar. UpdateBar validates and gates them.
2. **Untrusted by default.** Imported, templated, or agent-authored recipes land untrusted unless explicitly approved.
3. **Exact command fingerprints.** `check.cmd`, `latest.cmd`, and `update.cmd` run only when their current fingerprint is approved.
4. **Separated approval.** Prefer `approve` / `revoke` over `add --trust` for agent workflows.
5. **Status is read-only.** `status --json` remains the future UI contract and never runs shell or network.
6. **CLI is the single writer.** Future app/daemon surfaces mutate stores only by invoking the bundled CLI.
7. **Secrets stay out.** Recipe child processes get allowlisted env only. Captured output/errors are redacted.
8. **Validate-execute parity.** `validate` must never pass a recipe that `check`/`update` cannot execute (no "valid" recipes using unimplemented strategies).
9. **Non-interactive by contract.** Every mutating command must be runnable headless (`--yes` or no prompt); no `readLine()` path without an escape hatch.
10. **No telemetry.**

---

## 2. Sequencing

```text
M0  Finish CLI safety floor
        │
        ├── M1 Agent-facing CLI contract (the heart of the product)
        │
        ├── M2 Distribution hardening
        │
        └── M3 Background check helper
                │
                ▼
            M4 Local menu bar MVP
                │
                ▼
            M5 Signed/notarized app distribution (gated on explicit Apple-cost go/no-go)

Everything else: Not-Planned appendix (§9).
```

Execution status: **M0–M4 are implemented and published in v0.2.0.** Public CLI
release, Homebrew formula, and the unsigned app cask are live. Signed/notarized
app distribution stays behind the Apple Developer Program decision.

---

## 3. M0 — Finish CLI Safety Floor

Already done in current branch (audited, with evidence):

- removed built-in OpenRouter/provider/auth surface
- recipe commands via `/bin/sh -c`, no login shell (`CommandExecutor.swift:26`)
  — note: `edit` still launches the user's editor via `zsh -lc`; not a recipe path, acceptable
- env denylist replaced with allowlist (`CommandExecutor.swift:64`)
- `manifest.lock` / `state.lock` wrapping read-modify-write spans
- separated approval commands
- token redaction tests (`ExecutionPolicyTests.swift:84,91`)
- shell-startup non-reinjection test (`ExecutionPolicyTests.swift:51`)
- SemVer ambiguity rejection (`VersionComparatorTests.swift:12`)
- `--exit-zero-on-outdated` on `check` and `status`, documented and tested
- `docs/security.md` states "not sandboxed" with the real guarantee list (`docs/security.md:27`)
- CHANGELOG has an Unreleased CLI/menu-bar entry; move it under the tagged version
  during release finalization.
- README states the agent-facing stance and points to `guide agent`

Status after implementation pass:

1. **Execution sandbox decision (Q-SEC-1).**
   - Current guarantee: approval-gated, env-allowlisted, timeout-capped, output-capped, redacted.
   - Decision for CLI release: honest best-effort, not a filesystem/network sandbox.
   - `docs/security.md` states this clearly. A real sandbox is not in M0.

2. **Validate-execute parity (guardrail 8).**
   - Done: `version_parse.jq` is now rejected until runtime support exists.
  - `schema` advertises only `version_parse.regex`.
   - `check.file` docs now state regex-parsable content only.

3. **Concurrency stress tests.**
   - Done: process-level overlapping `check`, `status --refresh`, `approve`, `remove`
     against one `UPDATEBAR_HOME`.
   - Gate covered: no corrupt JSON, no lost unrelated item state.

4. **Approval semantics decision.**
   - Confirmed in code: approving any single field sets `trust.level = trusted`
     (`RegistryService.swift:192`); execution still requires per-field fingerprints.
   - Decision for CLI release: keep `trusted`; future UI must present per-field approval state
     from `approvals --json` instead of trusting the label alone.

Gate out of M0:

```text
swift test
Scripts/smoke-test.sh
release build
validate rejects every recipe the runtime cannot execute
concurrency stress test passes
docs/security.md states the real (non-)sandbox guarantee
```

---

## 4. M1 — Agent-Facing CLI Contract

Goal:

```text
An external coding agent, with no repo or web access, using only the installed
binary's guide/help/schema output, can author, validate, register, and manage
a working recipe end to end — programmatically.
```

This milestone is the heart of the product under the reset. Absorbs the old
"external-agent integrations" milestone.

Contract work (new — the machine-readable surface):

- **Done: `schema` command** emitting the recipe JSON Schema (`schema`):
  field rules, enums, executable `version_parse.regex` shape.
- **Done: stable JSON error envelope for top-level failures.** Parser/runtime failures
  with `--json` now return `{ok:false, code, errors}` when no command-specific JSON
  payload has already been written.
- **Done: granular exit code for approval block.** `update` returns `3` when blocked on approval
  without harder failures.
- **Done: `--yes` on `add --trust`.** The `--manual` wizard remains intentionally interactive.
- **Done: stdin for `validate` and `import`.** `add --from -` already existed.
- **Done: JSON output for mutators:** `approve`, `revoke`, `config set`, `enable`, `disable`,
  `pin`, `unpin`, `remove`.

Help/guide work:

- Done: expand `updatebar guide agent` into the primary agent interface: schema pointer,
  exit-code table, `--json` contract, duplicate/validation error recovery, template kinds.
- Done: compact `updatebar guide recipe`.
- Done: `validate --explain` with actionable errors.
- Done: `template recipe --id <id> --name <name> --source <ref>`; `template manifest --kind <kind>`.
- Done: `add --replace`.
- Done: shell completion docs for bash/zsh/fish using ArgumentParser's built-in generator.
- Examples for npm, brew, GitHub release, git tags, HTTP regex, custom command.
- Done: honest `check.file` docs (regex-parsable content only until more is implemented).

Positioning work:

- README already states the agent-facing stance (done in `1d6ef97`).
- Done: ship an agent-discovery doc (`llms.txt`) alongside the binary/release.

Testing:

- **Done: snapshot tests for `guide`/`--help` output and the exit-code table** — once guide is the
  canonical doc, drift silently misleads agents.

Contract stability: the JSON shapes and exit codes are free to change until the M1
gate passes; at that point the agent contract is frozen and versioned — later changes
require a documented contract version bump.

Non-goals: no built-in AI, no OAuth, no local LLM, no registry.

Gate:

```text
Agent self-sufficiency: external agent, no repo or web access, only the
installed binary — authors and registers a working recipe end to end,
recovering from at least one validation error programmatically.

Fresh UPDATEBAR_HOME
schema
template recipe --kind npm > recipe.json
validate recipe.json --json   (and via stdin)
add --from recipe.json --dry-run --json
add --from recipe.json
approvals <id> --json
approve <id> --field update.cmd --json
revoke <id> --field update.cmd --json
every failure above returns the documented error envelope
```

---

## 5. M2 — Distribution Hardening

Goal: make CLI distribution boring and honest before any app surface.

Work:

- Done: `version` reads generated `UpdateBarVersion.swift`, produced from `version.env`
  by `Scripts/generate-version-source.sh`; test asserts `version --json` matches `version.env`.
- CHANGELOG currently carries the CLI-only reset under `Unreleased`; move it under
  the tagged version during release finalization.
- Done locally: release URLs now target `sonim1/UpdateBar`; Homebrew tap target is
  `sonim1/homebrew-tap`.
- Done: published `v0.2.0` asset SHA matches the checked-in Homebrew formula SHA.
  For future releases, update the formula from the final uploaded `.sha256`;
  do not use a later local rebuild as the source of truth.
- Done: `Scripts/build-release.sh` normalizes archive metadata and uses `gzip -n`;
  binaries remain unstripped by default for Swift runtime compatibility.
- Done: clean source-copy release dry run passes with formula URL/SHA checks for
  `sonim1/UpdateBar`.
- Done: Homebrew formula style passes locally.
- Done: **archive-install smoke:** install the built archive into a temp bin and run
  `version --json`, `guide agent`, `template recipe --kind npm`.
  Implemented as `Scripts/archive-smoke-test.sh`.
- Done: **Linux CI lane** exists in `.github/workflows/ci.yml`.
- Done: Homebrew formula installs the CLI as `updatebar`.
- Done: Homebrew cask `updatebar-app` installs the unsigned app only. It must not
  link the bundled CLI or conflict with the formula; this is enforced by
  `Scripts/homebrew-packaging-test.sh`.
- Done: public CLI download claims match release assets: Apple Silicon macOS and
  Linux x86_64.
- Keep `version.env` as single source of truth.

Gate:

```text
swift build -c release
Scripts/build-release.sh
archive-install smoke passes
version --json == version.env
Linux CI lane green (or Linux claims removed)
Homebrew formula/cask packaging test passes
release docs match actual repo slug
CHANGELOG describes the actual product
```

---

## 6. M3 — Background Check Helper

Goal: fresh state without GUI.

Mechanism:

- Done: macOS per-user LaunchAgent plist runs the installed `updatebar check --exit-zero-on-outdated`
  by absolute path. (Flag already exists on `check` and `status` — this milestone consumes it,
  nothing to add.)
- Done: user-owned, never root, never LaunchDaemon.
- Done: **opt-in** via `updatebar background install --yes`: a daemon running `check` still executes approved
  `check.cmd`/`latest.cmd`; users must understand recipe command execution before enabling.
- Done: check-only. Never update. Never approve. Never import.

Behavior:

- honors TTL through `check`
- skips disabled/pinned/untrusted/unapproved items through existing check policy
- writes only `state.json`
- no notifications in CLI-only phase
- does not auto-run `launchctl`; it writes/removes/statuses the plist only

Gate:

```text
the shipped LaunchAgent plist invokes check only — never update/import/approve/remove [done]
daemon skips unapproved recipes [covered by check policy tests]
daemon keeps state fresh without corrupting state during manual CLI use [covered by store locks + concurrency tests]
```

---

## 7. M4 — Local Menu Bar MVP And Future Signed Distribution

The local unsigned MVP and public unsigned app cask are implemented. Public
signed/notarized app distribution still depends on an explicit go/no-go decision
on the Apple Developer Program cost ($99/yr). Decide before any signing or
notarization work starts.

App distribution:

- Apple Developer Program membership + Developer ID Application certificate (human prerequisites).
- Done locally: `Scripts/package-app.sh` assembles an unsigned `.app` (SwiftPM cannot emit one),
  `LSUIElement=true`, versions from `version.env`, the CLI bundled inside and invoked by absolute path.
- Done publicly: `updatebar-app` cask installs the unsigned app archive.
- Remaining for signed app distribution: sign inside-out with Developer ID after Apple go/no-go.
- Sign inside-out with Hardened Runtime + `--timestamp`; notarize via `notarytool`; staple.
- Keep the cask app-only. The CLI remains the `updatebar` formula, not a cask
  binary stanza.
- **No Sparkle in the MVP.** App updates ship via cask. This removes the EdDSA
  key-custody problem entirely; revisit Sparkle only if direct-download demand appears.

Architecture (minimum honest version):

- One app target calling the bundled CLI. No premature `UpdateBarClient`/`UpdateBarUI`
  library split — extract libraries only when a second consumer exists.
- App reads `status --json` or pure read helpers only.
- Mutating/executing actions invoke the bundled CLI subprocess.
- App process never writes `manifest.json`, `state.json`, or config directly.

MVP UI:

- badge count for outdated items only
- separate "needs approval" indicator for untrusted/unapproved items (never counted as updates)
- list rows: name, current, latest, status
- actions: Check now · Update selected · Update all approved outdated ·
  Approve/revoke command fields · Reveal manifest · Preferences · Quit

UI decisions to settle inside this milestone (not standing open questions):

- partial-approval copy: surface `trusted`-with-per-field-gates honestly, or rename state (ties to M0 item 4)
- untrusted indicator: separate section recommended
- add-recipe GUI: deferred; `add` stays CLI-only at first

Defer: add-recipe GUI, registry browsing, sync, Sparkle.

Local gate:

```text
status display updates after state.json atomic replace [done]
outdated check exit code is treated as success-with-updates [done]
partial update exit 2 surfaces per-item errors [done]
untrusted items are never counted as "updates available" [done]
app package smoke launches the bundled CLI path without startup errors [done]
```

Signed distribution gate:

```text
clean-machine first launch passes Gatekeeper (signed + notarized + stapled)
brew install --cask sonim1/tap/updatebar-app works and does not conflict with
the CLI formula
```

---

## 8. Open Decisions

Only the ones that block actionable work:

- **Q-APPLE-1** (blocks signed/notarized app distribution): pay the $99/yr and ship
  a signed app, or keep the app unsigned for now.

Resolved/ratified: execution boundary is honest best-effort, not a sandbox (M0);
background helper is opt-in (M3); Homebrew tap/formula/cask are published (M2);
the cask is app-only and the formula owns the CLI.

---

## 9. Not Planned — Revisit Only on Real External Demand

Parked deliberately. Each has a written re-entry trigger; none carries design detail.

- **Recipe signing (Ed25519/TOFU)** — origin today is "the user's own agent"; approval
  fingerprints already gate execution. *Trigger: a second person wants to consume someone
  else's recipes.* Signing and registry live or die together.
- **Community registry** — platform-building with zero users. *Trigger: multiple external
  users publishing recipes and asking to share.* Until then `export`/`import` files suffice.
- **Multi-machine sync** — if ever: user-owned git repo, recipe definitions only, never state,
  never secrets, every machine re-approves fingerprints locally. *Trigger: real multi-machine pain
  that `export`/`import` can't cover.*
- **Local fan-out sync** — already expressible today as an approved `update.cmd`; needs a docs
  example, not product surface. *Trigger: a user hits an actual wall with the command approach.*
- **`doctor` / corrupt-store recovery** — `StoreError.corruptFile` exists but no repair path.
  *Trigger: first real corrupt-store report.* Until then, document manual recovery (delete
  `state.json`, re-run `check`).
- **`schema_version` migration policy** — currently hard-pinned to `1`. *Trigger: the first
  schema change; decide read-old-write-new before shipping it.*
- **Built-in AI / OAuth / local LLM providers** — removed by design. If ever revisited:
  model output stays an untrusted proposal, no auto-approval, no provider secrets in child env,
  redaction + allowlist + docs updated in the same PR.

---

## 10. Effort Summary

| Milestone | Scope | Effort | Depends on |
|---|---|---:|---|
| M0 | Finish CLI safety floor | M | current branch |
| M1 | Agent-facing CLI contract | M-L | M0 |
| M2 | Distribution hardening | S-M | M0 |
| M3 | Background check helper | S | M0, M2 |
| M4 | Local unsigned menu bar MVP | M | M1–M3 |
| M5 | Signed app + notarization | L | Q-APPLE-1 |

Next recommended work:

```text
1. Signed app: decide Apple Developer Program go/no-go, then implement Developer ID
   signing, notarization, stapling, and update the existing app-only cask to use
   the signed artifact.
2. Post-release polish: keep tightening CLI/TUI/Menu Bar UX from real usage and
   remove confusing surfaces before adding new commands.
```
