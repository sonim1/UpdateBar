# Repo Maintenance Audit

Last updated: 2026-07-20.

This note records the current cleanup pass for documentation, security,
dependencies, CI, and local repository hygiene. It is evidence-oriented: prefer
the listed files and commands over older planning notes.

## Current Authorities

- Product overview and install paths: `README.md`, `docs/install.md`
- Security model: `docs/security.md`
- Architecture: `docs/architecture.md`, `current-architecture.md`
- Release process: `docs/release.md`, `.github/workflows/release.yml`,
  `Packaging/homebrew/`
- Historical planning context: `current-plan.md`, `next-plan.md`,
  `release-plan.md`

## Documentation Cleanup

- Release and install examples now use the current `0.5.0` release line.
- `docs/release.md` reflects the current CLI/app/TUI release metadata and
  includes a rollback/yank procedure.
- Historical root planning docs are marked as historical so they are not
  mistaken for current operating state.
- The completed Ink TUI/Menu Bar OpenSpec change was archived with
  `openspec archive`, and its requirements now live under `openspec/specs/`.
- `CONTRIBUTING.md` and a bug report issue template now document expected
  maintenance checks and safe public reporting hygiene.

## Security Review

- High-signal current-file and git-history searches found no reportable leaked
  credentials outside test fixtures/placeholders.
- `gitleaks` was not installed locally, so pattern scanning used `rg` and
  `git log -p` searches instead.
- GitHub Actions are SHA-pinned and use narrow permissions.
- `.github/CODEOWNERS` now covers workflow, script, and Homebrew packaging
  paths, but GitHub branch protection must enforce CODEOWNERS review before this
  becomes a hard control. See `SECURITY_BLOCKERS.md`.

## Dependency Review

- `npm --prefix tui audit --package-lock-only --audit-level=moderate` reported
  `0 vulnerabilities`.
- Safe TUI patch/minor devDependency updates were applied:
  `@types/node`, `eslint`, `tsx`, `typescript-eslint`, and `vitest`.
- TypeScript 7.0.2 is intentionally deferred because the current
  `typescript-eslint` peer range is `<6.1.0`; TypeScript 6.0.3 remains the newest
  supported compiler line for this TUI toolchain.
- Swift dependency inspection showed `swift-argument-parser` at `1.8.2`, which
  matches the latest tag observed from the upstream repository.

## Local Hygiene

- Current checkout has one worktree on `main`, no stashes, and active cleanup
  changes.
- Ignored build outputs and local tool state are present, including `.build/`,
  `dist/`, `tui/node_modules/`, `tui/dist/`, `.omo/`, and `.superpowers/`.
- `git clean -ndX` was used only as a preview. These paths are intentionally
  retained because cleanup is local housekeeping, not a release requirement.

## Verification Commands

Run the standard verification set after maintenance changes:

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test
npm --prefix tui run typecheck
npm --prefix tui run lint
npm --prefix tui run test
npm --prefix tui run build
bash Scripts/homebrew-packaging-test.sh
bash Scripts/quality-gate-contract-test.sh
UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh
bash Scripts/quality-gate.sh
```
