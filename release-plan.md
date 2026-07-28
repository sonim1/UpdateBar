# UpdateBar — Remaining Work Before Production Release

> Historical note (2026-07-12): This document is retained as the pre-v0.3.0 release audit record. For current operational guidance, prioritize `version.env`, `README.md`, `docs/release.md`, `.github/workflows/release.yml`, and `Packaging/homebrew/`.

Written: 2026-07-08. Baseline commit: `4642649` (main).
This document consolidates parallel audits across seven areas: release engineering, signing and distribution, product completeness, testing and quality, security, documentation and UX, and app/TUI polish.

## Current Status Summary

v0.2.0 has already been released publicly through a GitHub Release, the Homebrew formula `sonim1/tap/updatebar`, and an unsigned app cask. According to next-plan.md, all product milestones M0–M4 have been implemented and verified. Code quality, test coverage, and the honesty of the security documentation are all solid.

**However, in the current state the release pipeline cannot pass for the next tag (v0.3.0).** The distributed Linux binary does not run on machines without the Swift toolchain, and the first-launch instructions for the unsigned app (`Control-click → Open`) no longer work on macOS 15+. From a production-readiness perspective, the remaining work is not feature development but **repairing the release pipeline → signing/notarization → automating release operations → establishing a trust framework**.

| Area | Status | Key issue |
|---|---|---|
| Product features (CLI/core) | ✅ Complete | Documentation matches code; no phantom commands |
| Tests/CI | ✅ Strong | Only the release workflow is not connected to tests |
| Security model | ✅ Honest | Only supply-chain provenance and a reporting channel are missing |
| Release pipeline | 🔴 Blocked | The next tag cannot pass by design (two P0 issues) |
| App distribution (signing) | 🔴 Unresolved | Unsigned app plus invalid macOS 15+ launch instructions |
| Documentation/UX finish | 🟡 Moderate | Upgrade/uninstall docs, screenshots, and root cleanup |

---

## 0. Decisions Required First (Decisions, Not Tasks)

| ID | Decision | Impact |
|---|---|---|
| **Q-APPLE-1** | Whether to pay for the Apple Developer Program ($99/year) | All signed/notarized app distribution depends on this. **It is effectively mandatory for a production app** because macOS 15+ removed the Control-click bypass for unsigned apps, leaving only a deep System Settings workaround. |
| **Q-ARCH-1** | Whether to support Intel Macs (x86_64) | Both the current formula and cask hard-gate on arm64, but this is undocumented. Either build a universal binary or formally decide on Apple Silicon-only support and document it. |

---

## 1. P0 — Release Blockers (The Next Release Is Impossible Without These)

### 1.1 Break the Release-Pipeline Deadlock — Effort M

The strict Homebrew metadata validation at `release.yml:53-55` requires the cask SHA to match at tag time, but the app archive gets a different SHA on every build. `build-app-archive.sh:27` uses plain tar without normalizing mtime/owner; building the same bundle twice was verified to produce different SHAs. There is no way to know before tagging which SHA must be committed, so **the v0.3.0 tag fails regardless of the SHA entered**. This validation was added after v0.2.0 in commit `4642649` and has never passed a real release.

Choose one resolution:

- Apply the same mtime/owner normalization used at `build-release.sh:48-56` to `build-app-archive.sh`/`package-app.sh`, making the archive byte-reproducible.
- Move SHA equality out of strict tag-time validation and into a post-publish step, retaining only version/URL validation at tag time.

### 1.2 Statically Link the Linux Binary — Effort S

Inspection of the published `updatebar-0.2.0-linux-x86_64.tar.gz` ELF showed dynamic links to `libswiftCore.so`, `libFoundation.so`, and others, so **it cannot run on a typical Linux machine without the Swift toolchain**. The smoke test passed only because it ran on a build machine with the toolchain. Add `--static-swift-stdlib` to the Linux path at `Scripts/build-release.sh:26-28`.

### 1.3 Fix First-Launch Instructions for macOS 15+ — Effort S

README.md:20-21, docs/install.md, and the cask caveats all instruct users to use `Control-click → Open`, but macOS Sequoia (15) removed this bypass. Until signing is available, replace it with `System Settings → Privacy & Security → Open Anyway` and mention `--no-quarantine` if appropriate. The permanent solution is 1.4.

### 1.4 Complete the Signing/Notarization Pipeline (If Q-APPLE-1 = Go) — Effort L

The signing path in `Scripts/package-app.sh` is implemented but has been tested **only with mock codesign/xcrun stubs**; it has no end-to-end run with a real Developer ID certificate. release.yml contains no signing wiring and references zero secrets. Remaining work:

- Issue a certificate, store the .p12 in CI secrets, and add a temporary-keychain import step.
- Configure App Store Connect API key secrets for `xcrun notarytool store-credentials`.
- Wire `UPDATEBAR_SIGN_APP=1`, `UPDATEBAR_NOTARIZE_APP=1`, and identity/profile environment variables into the macOS release job.
- Add real post-signing verification: `codesign --verify --strict`, `spctl --assess`, and `xcrun stapler validate`. Current grep results show zero instances, so otherwise the first real run would happen on release day.
- Update the cask to use the signed artifact and remove the Gatekeeper instructions.
- Document secret names, certificate renewal, and other operational procedures in docs/release.md.

---

## 2. P1 — Strongly Recommended Before Production Release

### Release Operations

| Task | Effort | Rationale |
|---|---|---|
| Cut v0.3.0: bump version.env, roll CHANGELOG Unreleased to 0.3.0, tag, and update tap SHAs | M | Unreleased fixes and behavior changes, including removal of the hidden add wizard, have accumulated on main. Proceed after P0 1.1/1.2. |
| Automate Homebrew tap synchronization from release.yml to the tap repository using PR/push and uploaded `.sha256` files | M | Two files are currently copied manually and SHAs typed by hand. One typo breaks `brew install` for every user. |
| Automatically attach GitHub release notes from the CHANGELOG section through `body_path` or `generate_release_notes` | S | `gh release view v0.2.0` reports an empty body. A blank public release description makes the project look abandoned. |
| Enforce CHANGELOG rollover: fail tagged builds without a `## <version>` section | S | Tagging the current state would produce a “no changes” release. |
| Add a pre-release test gate in release.yml using `swift test` or a required successful CI run | S | A tag push currently publishes even a commit with failing tests. |
| Add post-deployment verification against the live release with `install-release.sh` and `brew install` jobs | M | All current checks target local pre-upload artifacts; no one verifies the assets users actually receive. |
| Document rollback/yank procedures: deleting a release, reverting the tap, and fix-forward criteria | S | `install-release.sh` defaults to latest, immediately exposing all users to a bad release. There is no rollback/yank documentation. |
| Add a `workflow_dispatch` dry-run mode to release.yml that builds and verifies everything and prints SHAs without publishing | S | Four of the last five release runs failed, causing repeated tag deletion and repushing. A rehearsal path is needed. |

### Trust and Security Framework

| Task | Effort | Rationale |
|---|---|---|
| Add build attestations with `actions/attest-build-provenance` or cosign | M | The `.sha256` is served from the same release as the artifact, proving transport integrity but not provenance. Supply-chain trust is especially important for a command-execution tool. |
| Add a vulnerability-reporting channel in `.github/SECURITY.md` and enable GitHub private reporting | S | A threat-model document exists, but there is no reporting path, so vulnerabilities would arrive as public issues. |
| Add continuous dependency vulnerability monitoring in `.github/dependabot.yml` for npm/tui, GitHub Actions, and Swift | S | CI runs `npm ci --no-audit`. There are no findings today, but future Ink/React advisories would be invisible. |

### User-Facing Finish

| Task | Effort | Rationale |
|---|---|---|
| Document upgrades: `brew upgrade`, cask upgrades, rerunning curl, and the fact that there is no in-app updater because cask-based updates are intentional | S | An update-tracking tool does not document how to update itself. |
| Clearly state Apple Silicon-only scope, including the hard-coded `ARCH=arm64` section in install.md | S | Intel users currently discover the limitation through a 404. |
| Document product uninstall: formula/cask removal and the `UPDATEBAR_HOME` data location/cleanup | S | Only `background uninstall` is documented; product removal is not. |
| Add screenshots/demo GIFs for the menu bar app and TUI to README | S | There are no visuals; a menu bar product is represented only by text. |
| Create and bundle an app icon | M | There is no `.icns` and no icon wiring in `package-app.sh`; a production app cannot ship with the default icon. |
| Add `.github` community files: issue templates and CONTRIBUTING.md | S | `.github/` currently contains only workflows. |

---

## 3. P2 — May Be Done After Release

**Release-pipeline improvements**

- Decide whether to add macOS x86_64/universal and Linux arm64 artifacts as a follow-up to Q-ARCH-1.
- Build Linux releases in the same `swift:6.0` container used by CI. The test and release environments currently differ, and the glibc floor is unnecessarily high.
- Add `fail_on_unmatched_files: true` to `action-gh-release` and consider manual promotion after creating a draft.
- Run `brew style`/`brew audit` in CI; only custom grep-based checks currently exist.
- Make shellcheck mandatory in CI. It is not installed in the Linux container, so the current step silently skips it.

**Quality**

- Add a TUI↔CLI JSONL contract end-to-end test that spawns the real binaries; both sides currently use fixtures only.
- Add menu bar interaction-level tests; only a launch smoke test exists.
- Measure coverage with `--enable-code-coverage` and Vitest coverage.
- Replace the XCTSkip fallback in DocumentationSnapshotTests with XCTFail for supported shells.

**Product policy**

- Decide on a TUI distribution channel: npm publication, formula resources, or bundling. Otherwise, downgrade the wording to “source checkout only.” It is currently unpublished with `private: true`, but README and the menu bar advertise it.
- Add menu bar launch-at-login through SMAppService. The update tracker currently does not return after a reboot.
- Notify users when background checks find outdated items. There are currently zero uses of UNUserNotification, so users who do not open the menu bar see nothing.
- Add an `updatebar doctor`/troubleshooting pointer to `StoreError.corruptFile` messages.
- Document `status --refresh` and `--exit-zero-on-outdated` in docs/cli.md. They are hidden but part of the contract.
- Version the agent JSON contract. next-plan M1 promised it would be “frozen and versioned,” but it has no version marker.
- Actually include llms.txt in release archives/assets. next-plan marks this done, but it is not included.
- Document the `schema_version` compatibility contract in one paragraph, including how old binaries handle new schemas. state.json currently does not validate schemaVersion.

**Repository hygiene**

- Mark superseded material in PRD.md. Removed designs such as `add --ai`, sync, and mandatory Sparkle still mislead new contributors and agents.
- Move or archive root planning documents: PRD.md, plan.md, current-plan.md, next-plan.md, plan-required.md, and current-architecture.md.
- Delete stale branches: three codex/* branches are patch-equivalent to main, while work/updatebar-cli is 224 files behind. Remove the empty `Sources/UpdateBarCore/Auth` and `Providers` directories.

---

## 4. Recommended Execution Order

```text
R1  Repair the pipeline (P0 1.1 + 1.2 + 1.3)                ~several days
     └─ Rehearse with a release.yml dry run
R2  Cut v0.3.0 and publish the accumulated Unreleased work
     └─ Add release notes, CHANGELOG gate, and test gate at the same time
R3  Decide Q-APPLE-1 → if go, build signing/notarization pipeline (P0 1.4) ~1–2 weeks
     └─ v0.4.0 = signed, notarized, stapled app release and production declaration
R4  Operational automation + trust framework (tap automation, post-release
     verification, rollback docs, provenance, SECURITY.md, Dependabot)
R5  User-facing finish (icon, screenshots, upgrade/uninstall docs)
Then work through the P2 backlog
```

If a production release means “a typical user can install with brew, the app launches without warnings, problems have a reporting path, and a bad release can be rolled back,” then **completion of R1–R4 is the line**.

---

## Appendix: Audit Methods and Limitations

- Agents directly inspected code, workflows, and live release assets across five audit areas: release engineering, signing/distribution, product completeness, testing, and security. This included parsing the Linux binary ELF, comparing SHAs from two app archive builds, and checking `gh release view` results.
- The documentation/UX and app/TUI audits were interrupted by session limits, so the main task performed those checks directly. The absence of icons, notifications, launch-at-login, community files, screenshots, and uninstall documentation was confirmed with grep/find.
- Most adversarial cross-verification was not run for the same reason. Each item is based on file-and-line evidence supplied by an auditor; verify that evidence once before starting the corresponding work.
