# Native menu bar implementation

Approved 2026-09-09. Implemented and reviewed on `sonim1/menubar-popover` before integration into `main`.

Implementation assumptions: macOS 13+, English to match the existing app, native AppKit popover with SwiftUI content, existing Dashboard and Core services. No new dependencies, CLI output changes, or trust-policy changes. Release metadata is prepared separately during main integration using the repository's existing version workflow.

## Execution plan

1. **Completed:** Implement persistent popover presentation, selection, inline command review, progress/results and native controller. Twenty targeted model/controller tests pass; app target links.
2. **Completed:** Wire the status button, secondary menu, refresh/action lifecycle, exact displayed-command freshness checks and failed-only retry into the app. Integration spec and code review pass. New service regression tests are included in the full gate below.
3. **Completed:** Formatting and `Scripts/quality-gate.sh` pass. The unsigned app passed native interaction scenarios with isolated test profiles. Independent design/function and visual/CJK reviewers both returned PASS with no blocking findings on the complete final capture packet.

## Interface and behavior

- Width 392pt, maximum height 560pt, constrained to the anchor screen. Header and footer remain fixed; only the body scrolls. A stable hosting controller/store survives close and refresh.
- New eligible items start selected; deselection survives unchanged snapshots. Disabled, pinned and unapproved items cannot enter the normal update selection.
- Checking leaves the previous list visible. The last checked label uses item timestamps, never the time a cached snapshot was loaded.
- Commands are reviewed field by field with exact command and cwd, explicit acknowledgment and approval. Snapshot changes reset acknowledgment; app re-reads the field before approving. Approval never triggers update.
- Progress is completed/total plus queued/running/succeeded/failed states. Closing or Escape never cancels work. Stop drains every active command before starting no more work.
- Last update results persist. Retry rechecks status using the existing service, then passes only the failed IDs to the existing update planner. UI explicitly names the recheck; no changes to the planner's eligibility rules.
- CLI adapter has no per-item events or stop support: show indeterminate activity without claiming a result count or offering an unsupported Stop action.
- Left click opens popover. Right click and More open existing secondary NSMenu. Dashboard routes, Sparkle and Quit remain available.

## Native design contract

System font (13pt body, 11pt secondary, 17pt section heading), system semantic colors, SF Symbols, 16pt horizontal inset, 8/12/16pt spacing, restrained separators, standard focus rings and controls. Accent is the system accent color; status includes text and symbols. Command text is selectable monospaced text and wraps within the panel. No decorative gradients, fake progress/ETA, or animation dependence. Honor reduced motion for popover animation.

## Evidence

Baseline: 207 menu-bar tests passed on original HEAD `a4b7b0e6bb88686c149642d7fe08e571ba3b2195`. Existing captured-variable warning in SettingsViewController.swift is outside this change.

Final full quality gate: **902 Swift tests and 137 TUI tests passed**, with strict formatting, script contracts, builds and CLI/menu-bar/package/install/TUI smoke checks. Log: `.omo/evidence/native-popover/quality-gate-verified.log`, exit 0. The unsigned development app is `dist/UpdateBar.app`; packaging also passed.

Native evidence: `.omo/evidence/native-popover/review-packet.json` enumerates **44 final PNGs and 3 closed-popover snapshots**. All captures are newer than the final product edit. The packaged app covered 43 states, including selection/scroll retention, check, two concurrent updates, stop/drain, partial failure, failed-only retry, approval freshness, Dashboard routes, first run, 30 items, long CJK names, CLI adapter, error/recovery, and actual Tab/Space interactions. Four supplementary Aqua captures use the same compiled controller/view in an inactive native popover. Detailed evidence and boundaries: `.omo/evidence/native-popover/NATIVE-QA.md`.

Actual update execution receipt: Node/Python/SwiftFormat/ripgrep ran once each; failed jq ran twice; deselected UV and the approval sample never ran. Keyboard Navigation was temporarily enabled for the Tab/Space check and restored to its original value. The user's installed app was not replaced or terminated.

Native QA resolved hosting auto-size growth beyond 560pt, incorrect detail scroll position, dimmed row text, duplicated accessibility identifiers, approval readiness, unsupported CLI stopping, and conflicting success/error copy. A full spoken VoiceOver session and physical multi-monitor positioning were not exercised; accessibility roles, labels, enabled states, focus, Escape, Tab/Space and screen-size calculations were checked.

Final build identity: HEAD `a4b7b0e6bb88686c149642d7fe08e571ba3b2195` plus the uncommitted file hashes in `.omo/evidence/native-popover/source-manifest.json`. App binary SHA256: `a154d137a76ee76a8af61803e6818dccf3867af13afaed3dc38d5b5dfc6b4659`. This is a development package with a test Sparkle key, not a signed release.

Independent final reviews: `.omo/evidence/native-popover/final-integrity-review.md` and `final-visual-review.md`, both **PASS**, no blocking findings. Both reviewers opened all 44 final PNGs and independently checked source/image hashes, execution/keyboard receipts and closure snapshots. Nonblocking maintenance notes concern the large SwiftUI view and existing source-string test convention; no unrelated refactor was added.

Integration review found and resolved the nonthrowing check-error retry case: the retry helper reads the refreshed status and reports an unsuccessful precheck before dispatching updates, retaining the previous failed results. Command freshness validation is a best-effort UI reread; the existing service does not expose an atomic expected-fingerprint approval operation.
