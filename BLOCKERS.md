# Blockers

There are no repository or release blockers as of 2026-07-20.

TypeScript 7.0.2 was evaluated and is outside the official peer range of the
current `typescript-eslint` release (`>=4.8.4 <6.1.0`). UpdateBar therefore keeps
TypeScript 6.0.3 until the lint toolchain declares support; no force-install or
legacy peer override is used.

`Scripts/generate-appcast-test.sh` fails on a clean checkout of `main` (verified
against `3f69e02` with no working-tree changes): the keychain fixture stage exits
66 with `Missing or unsafe DMG: .../dist/UpdateBar-0.6.3-macos-arm64.dmg`. Both
CI jobs already route around it via `SKIP_SIGNED_APPCAST=1` (`a7ebfd7`,
`40e4f0d`), so local gate runs need the same skip until the fixture builds its
own DMG. This is unrelated to release credential wiring.

## Local menu verification — 2026-10-29

The earlier live-menu and usability checks were blocked by local disk exhaustion,
including `databaseFull` and `No space left on device` during packaging and Swift
index writes. On 2026-10-29, the data volume had 19 GiB available and verification
resumed without further cache cleanup.

`Scripts/quality-gate.sh` completed with exit 0 in one run, with no gate skips:
998 Swift tests, 152 TUI tests, formatting, CLI/script checks, final release-mode
app packaging, and menu bar launch smoke all passed. A separate launch smoke with
nine synthetic outdated recipes in an isolated `UPDATEBAR_HOME` also passed.
Independent code review approved the production changes with no blocking findings.

All 22 menu SF Symbols were available through AppKit on the local macOS system.
Native AppKit tests verify updates during actual menu tracking. Computer-use
access to the menu-bar-only QA app still timed out, so native menu screenshots
and theme verification remain unavailable; no visual approval is claimed.

Ignored build outputs and local tool state are intentionally retained. A
`git clean -ndX` preview includes Swift dependency checkouts, `.omo/`,
`.superpowers/`, `dist/`, and `tui/node_modules/`; deleting these is local
housekeeping and is not required to build, test, or release UpdateBar.

## Daily maintenance UI automation — 2026-11-12

The full quality gate passed without skips: 1,011 Swift tests, 152 TUI tests,
formatting, script/CLI checks, release-mode packaging, and menu bar launch smoke.
The packaged app was also launched against isolated approved fixture recipes:
check-only retained version 1.0.0 and check-and-update installed 2.0.0. Native
settings views were rendered and inspected in light mode and compact dark mode;
Save and Reload remain visible at a 420-point window height.

Packaged XCUITest click-through verification is inconclusive on this host.
With `CODE_SIGNING_ALLOWED=NO`, the generated runner fails signature verification
(`code has no resources but signature indicates they must be present`). A second
run using local ad-hoc signing passes signature verification, but the runner
still does not reach test execution. `DevToolsSecurity -status` reports developer
mode disabled; the remaining runner-start stall has not been conclusively
diagnosed. No system security setting was changed. The existing installed app
was left running; a separate bundle identifier was used for the QA copy.

Evidence, exact commands, screenshots, and runtime results are retained under
`.omo/evidence/daily-maintenance/`. The new packaged UI scenario must be rerun on
a host where the XCTest runner can start; it is not counted as a passing check.

On 2026-11-13, an isolated native settings window was also exposed through a
temporary XCTest fixture for Orca manual interaction. Orca reported Accessibility
and Screenshots permissions granted, but its app-state request failed with
`permission_denied`: the xctest process had a visible window but no accessible
AX window. No setting was changed, the temporary harness was removed, and this
attempt is not counted as UI click-through coverage. Packaged UI tests remain a
required macOS CI check before merging the release PR.

The isolated release worktree subsequently passed the full quality gate without
skips: 1,014 Swift tests and 152 TUI tests. The CLI aggregate JSON shape is
unchanged; schedule values use per-key config queries with a disabled fallback
for unsupported older CLIs. Independent code re-review approved the correction.
