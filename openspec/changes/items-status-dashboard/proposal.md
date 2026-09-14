# Status-first Items Dashboard

## Why
The Items table makes menu-bar update targets hard to locate and batch actions hard to discover. The user approved an interactive status-first prototype and requested native implementation, review, tests and release.

## Changes
Replace the Items table with Ready to update cards, separate command review and attention groups, and collapsed current/paused groups. Add explicit all/selected/visible update actions, search, per-item progress, stop-after-current and retry using the existing menu-bar action coordinator. Share eligibility and current approval identities with MenuBarPopoverModel; preserve enable/disable and all existing dashboard destinations.

## Boundaries
No auto-trust, command execution contract changes, new dependencies or CLI stdout changes. Approval is per exact displayed command and does not start updates. Test commands operate only within isolated fixtures. Native system colors and existing AppKit host remain.

## Acceptance
Every item appears once; only the same approved unpaused outdated targets as the menu bar can enter normal batch updates. Counts match actions; search never updates hidden targets; stale selection cannot run. Progress/stop/retry represent actual coordinator events. Builds, focused tests, full quality gate, native manual QA and independent review must pass before the authorized release.
