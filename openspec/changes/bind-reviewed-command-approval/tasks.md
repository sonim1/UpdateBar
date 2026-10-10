## Implementation

- [x] Reproduce stale review and adapter read/write races with real CLI regressions.
- [x] Compare and save under the manifest lock; preserve manual CLI compatibility.
- [x] Carry reviewed command status through native menu actions and both adapters.
- [x] Update Sparkle and the appcast pin guard together.

## Verification

- [x] Run Scripts/quality-gate.sh without skips.
- [x] Exercise untrusted registration, refused execution, approval and execution.
- [x] Exercise native stale confirmation and unchanged approval in a fixture home.
- [x] Verify the packaged SDK version and signed appcast tooling guard.
