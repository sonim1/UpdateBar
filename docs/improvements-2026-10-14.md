# Reliability and UX follow-up - 2026-10-14

This follow-up implements the highest-priority findings after the v0.6.31
cross-surface audit. It covers update correctness, useful persisted diagnostics,
first-use guidance, dependency CI and repeatable website delivery.

## Update success means an observed installation

Previously, an exit-zero updater could be reported as successful even when the
installed version stayed unchanged or its local check failed. History could
also substitute the intended latest version for an absent observed version.

The updater now rechecks the local installation after the command completes.
The observed version must meet the target selected before execution. It may
exceed a semantic/calendar target; an upstream release discovered during the
recheck does not move the goal. A local check failure, unchanged version or
downgrade fails verification. A successful local observation still verifies
the original target if the separate upstream lookup fails.

Update results and history retain the command exit code independently of
verification. New history records store observed `to`, planned `target` and a
redacted `error`. An absent observation stays absent. Error text is redacted
before retaining a 4,096-character prefix and truncation marker. Schema version 1
and older records remain readable. Existing records are preserved; their historical `to` values cannot
be retrospectively certified as observations.

Real CLI scenarios used isolated profiles and synthetic version files:

| Scenario | Observed result |
|---|---|
| Updater exits zero without changing 1.0.0 | CLI exit 2; failed verification; observed 1.0.0, target 1.1.0, command exit 0 |
| Updater writes installed version 1.1.0 | CLI exit 0; updated; observed and target 1.1.0 |
| Read both attempts through history | The failed attempt retains its explanation; only the successful attempt records 1.1.0 as observed |

The concurrency regression fixture now writes its own version files instead of
using a no-op command. It retains the original parallelism and exit assertions
and verifies both resulting installations.

## Native Dashboard and terminal behavior

Dashboard Logs combines search with tool, outcome and time filters. The table
separates observed transitions from planned targets. Selecting a failure opens
a selectable, scrollable detail pane and a full-detail copy action. A long
diagnostic initially pushed the table out of view during manual QA; the final
pane has a bounded height and keeps the list usable. Filtering clears the old
selection so a previous failure cannot appear under a new result set.

The empty Items page links directly to Scan & Add. Scan guidance distinguishes
an initial page from a completed scan with no discoveries. A real local scan
displayed 105 discovered tools without registering or approving them.

TUI View Logs now reads persisted history through `updatebar history --json`.
It shows the newest records first and labels transient command output as
Session output. Long history rows stay on one line with a hint for obtaining
full diagnostics through the CLI. Terminal control characters and secrets are
sanitized for display, while structured history remains intact. Manual QA also
found and fixed history consuming the `m` and `q` shortcuts.
History row identities also retain their append position, so multiple attempts
for the same tool within one second remain distinct when paging.

Status distinguishes the time a snapshot was generated from each tool's last
completed check. Cancellation is a separate notice rather than a failed
operation. Prompt input continues to accept literal `m` and `q` characters.

Native manual checks cover combined filters, empty results, keyboard filter and
row selection, long-detail scrolling, copying all 3,878 characters, and live
application appearance changes. The clipboard was preserved in memory and
restored afterwards. Desktop evidence uses the production Dashboard controllers
in an isolated GUI host; its startup wiring differs from the menu-bar app.
The packaged app launch and native menu contracts are covered by the quality
gate. VoiceOver spoken output and a true minimum-size window were not manually
certified. Completed-empty scan guidance is covered by controller tests.

The unused legacy popover implementation was removed. Shared item actions now
live in their own file, and the active Items hosting/search/selection tests
remain in place.

## CI, website delivery and dependency decisions

Dependency and fork PRs receive read-only platform tests, without release
version mutation or privileged tokens. Swift caches distinguish push, trusted
PR and untrusted PR namespaces; npm caching is disabled in this lane. Policy
failure still blocks the gate.

The landing workflow runs only after a main-branch push changes `docs/**`.
Serialized jobs read the current reviewed main branch at execution time,
preventing an older queued event from rolling production back. Actions and
Wrangler are pinned, GitHub permissions are read-only, and deployment records
the checked-out source SHA. HTTP postchecks require the home page, the exact
source marker and a real branded 404; the source contract checks all landing routes.

Automatic publication requires the repository's `CLOUDFLARE_ACCOUNT_ID`
variable and a `CLOUDFLARE_API_TOKEN` secret with account-scoped Pages Edit.
The code and runbook are ready; credential provisioning and a production run
must be verified separately before calling this workflow operational. Existing
broad local Wrangler OAuth credentials must not be copied into CI.

Compatible development updates include ESLint, typescript-eslint, tsx and Node
type declarations. Vitest 5 is deferred because it requires Node 22.12 or later
while the TUI supports Node 20. The setup-swift major upgrade is deferred to a
separate release-toolchain check.

## Measurement without inventing user counts

`Scripts/release-download-counts.sh` reports GitHub release-asset transfers.
At the 2026-10-14 snapshot, 34 releases and 238 uploaded assets totaled 303
transfers; 178 were installer archives/DMGs and 98 were macOS GUI distribution
assets. Counts include repeat downloads and automated verification. They exclude
source archives and R2/Sparkle transfers, and cannot establish unique users,
successful installations or active devices.

Cloudflare Web Analytics remains the website traffic source. Keep one injected
beacon, filter the production host, and use page/referral dimensions separately
from download totals. No native app or CLI telemetry was added. See
[website operations](site-operations.md) for the deployment and reporting runbook.

## Verification

The macOS quality gate completed successfully, including Swift format, shell
checks, CLI/installer/archive behavior, TUI and packaged app smoke checks.
The Swift suite has 984 passing tests; the final TUI suite has 152 across eight files.
Focused regressions were observed failing before their fixes and passing after.
The delivery contracts also exercise bot/fork policy, workflow restrictions,
HTTP responses and download arithmetic.

Real CLI and TUI PTY recordings, native screenshots/AX trees and before/after
diagnostics are retained locally under
`.omo/evidence/reliability-ux-20261014/`. TUI layout evidence renders the actual
recorded control sequences through xterm. Public PR and deployment outcomes
will be recorded after those external checks run.
