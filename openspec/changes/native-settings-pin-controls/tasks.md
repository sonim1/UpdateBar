## Implementation

- [x] Reproduce configuration loss before the fix.
- [x] Merge edited fields and expose bounded concurrency.
- [x] Add Core/CLI pin adapters and native controls.
- [x] Preserve mutation gating, failure recovery and selection reconciliation.
- [x] Reproduce and resolve stale paused status after resume.

## Verification

- [x] Run relevant XCTest suites, including real CLI/Core state round trips.
- [x] Run Scripts/quality-gate.sh without skips.
- [x] Exercise Preferences Save and pin/unpin in a running native app using an isolated fixture home.
- [x] Record native QA and regression evidence for final review.
