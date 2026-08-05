## Verification

- [ ] `Scripts/quality-gate.sh` exits 0
- [ ] `swift test` passes across UpdateBarCoreTests, UpdateBarCLITests, and
      UpdateBarMenuBarTests
- [ ] `updatebar update --jobs 9` is rejected; `--jobs 2` is accepted
- [ ] `updatebar config get --json` reports `update.max_concurrent`
