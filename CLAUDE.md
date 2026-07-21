# UpdateBar — Agent Operating Manual

Safe, scriptable macOS CLI (+ menu bar app) for tracking and updating user-approved "recipes" (tools, CLIs, packages). Core promise: **UpdateBar never auto-trusts commands** — it is the validation, trust, and execution boundary. Swift 6, SwiftPM, distributed via Homebrew tap + signed/notarized releases.

This is an operating manual. Follow it literally; `CONTRIBUTING.md` ground rules apply to you.

## Ground Truth (verified)

- **Targets (Package.swift, macOS 13+):** `UpdateBarCLI` (product `updatebar`), `UpdateBarMenuBarApp` (product `updatebar-menubar`), `UpdateBarMenuBar`, **`UpdateBarCore` (library — must stay free of CLI printing and UI concerns)**, `UpdateBarTestSupport`, `Tests/`. Dependency: swift-argument-parser only.
- **The gate:** `Scripts/quality-gate.sh` — same as CI. Handles `DEVELOPER_DIR` for XCTest (prefers `/Applications/Xcode.app`), exports `UPDATEBAR_TEST_BIN`, honors `SWIFT_BIN` and `SKIP_MENUBAR_SMOKE`. Direct `swift test` failing → troubleshooting documented in `docs/troubleshooting.md`.
- **Scripts (~30 in `Scripts/`), each with a `-test.sh` twin:** packaging (`build-app-archive`, `package-app`, `build-release`), verification (`verify-archive-checksum`, `verify-homebrew-metadata`), changelog (`extract-changelog-section`), smokes (cli/menubar/tui/install/e2e-edgecases), `install-local.sh`, `install-release.sh`. Script tests are part of the gate.
- **Contracts (CONTRIBUTING.md):** machine-readable stdout STABLE; human diagnostics → stderr; preserve behavior unless the change says otherwise; larger behavior changes go through **OpenSpec** (`openspec/`); no private tokens/user data/live exploit details in issues, tests, or logs.
- **Release machinery:** `.github/workflows/release.yml` + `ci.yml`; `CHANGELOG.md` sections extracted by script; published asset SHAs recorded in-repo (see "Record published v0.4.0 asset SHAs"); `version.env`; Homebrew formula (`updatebar`) + cask (`updatebar-app`) on `sonim1/tap`; signed + notarized from v0.3.0.
- **Planning artifacts at root:** `PRD.md` (52K), `plan.md`, `current-plan.md`, `next-plan.md`, `release-plan.md`, `current-architecture.md`, `BLOCKERS.md`, `SECURITY_BLOCKERS.md`, `llms.txt`. `.swift-format` config present. Tests keep writes inside test home dirs ("Keep test history writes inside test home directories").

## Commands

```bash
Scripts/quality-gate.sh            # THE gate (build + tests + script tests + smokes)
swift build                        # quick compile check
swift build -c release --product updatebar
Scripts/install-local.sh           # local install (UPDATEBAR_INSTALL_PREFIX to relocate)
Scripts/smoke-test.sh | cli-smoke-test.sh | menubar-smoke-test.sh | tui-smoke-test.sh
updatebar guide agent              # the agent-facing recipe workflow
```

## Conventions

Kendrick's (observed — keep):
- Plain imperative commit subjects here (this repo predates his conventional-commit era: "Fix singular menu attention copy", "Release 0.4.0") — match the repo's existing style.
- Small, testable changes along the CLI/core/menu-bar boundaries; scripts always ship with `-test.sh` twins.
- OpenSpec for behavior-sized changes; plan docs at root track direction.
- Security posture: trust boundary is the product; `SECURITY_BLOCKERS.md` items are owner-only.

Added (follow these too):
- New CLI output: decide stream deliberately — payload/stdout (stable contract), diagnostics/stderr; changing existing stdout shapes is a breaking change requiring approval.
- Core logic → `UpdateBarCore` with tests; CLI target only parses args and formats; menu bar consumes Core the same way.
- Tests never write outside their sandboxed test home (established convention).
- `.swift-format` governs formatting — run it rather than hand-styling.

## Named Failure Modes

1. **Trust Boundary Erosion** — auto-trusting recipes, widening what runs without explicit user approval, "convenience" defaults that execute commands. *Rule: nothing executes without prior explicit trust; changes to trust/validation logic → ask first, always.*
2. **Stdout Contract Break** — new fields/format changes in machine-readable output, or diagnostics leaking to stdout. *Rule: stdout shapes are stable API; additive changes need approval, breaking changes are release decisions.*
3. **Core Contamination** — `print()`/UI concerns inside `UpdateBarCore`. *Rule: Core stays pure (CONTRIBUTING); presentation lives in CLI/menu-bar targets.*
4. **Gate Skipping** — `swift build` alone before "done" when the gate runs script tests + smokes too. *Rule: `Scripts/quality-gate.sh` is the completion gate; XCTest env issues → docs/troubleshooting.md, not skipped tests.*
5. **Script-Without-Twin** — adding/changing a Script without updating its `-test.sh`. *Rule: twins move together.*
6. **Test-Home Escape** — tests touching the real `~/`. *Rule: writes stay in test home dirs like existing tests.*
7. **Release Freelancing** — hand-running publish steps outside `release.yml`/release scripts. *Rule: release skill; published-asset SHA records must stay accurate.*
8. **Confident Green Claim** — *Rule: fresh quality-gate output pasted.*

## Quality Bars (checkable)

Any change:
- [ ] `Scripts/quality-gate.sh` → 0 (paste tail; note `SKIP_MENUBAR_SMOKE` if used and why)
- [ ] `git diff --stat` only task files; no new dependencies without approval

Core/CLI change: additionally
- [ ] New logic in `UpdateBarCore` + tests; CLI stdout diff reviewed against the stable-contract rule
- [ ] Changed command exercised via built binary (`.build/debug/updatebar …`), output + exit code pasted

Script change: additionally
- [ ] `-test.sh` twin updated; both run clean; `bash -n` passes

Behavior-sized change:
- [ ] OpenSpec entry in `openspec/` per its config, or explicit Kendrick waiver noted

## Escalation Rules (exact)

1. **Ask before:** trust/validation semantics; stdout contract changes; new dependencies; signing/notarization/tap/release actions; `SECURITY_BLOCKERS.md` items; version bumps.
2. **Document + continue:** pre-existing failures (stash-proof) → `BLOCKERS.md`, continue.
3. **Stop + report:** same error after 2 distinct attempts; XCTest/toolchain env unfixable via troubleshooting doc → report env details.
4. **Never:** commit/push unless asked; auto-trust anything; put tokens/user data/exploit details in tests or logs.

## Skills

- `verify` — the quality gate + env triage
- `release` — CHANGELOG/tag/asset-SHA release procedure
- `recipe-trust` — working on recipe schema/validation without eroding the trust boundary
