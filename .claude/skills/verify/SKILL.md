---
name: verify
description: Run UpdateBar's quality gate (build + XCTest + script-test twins + smokes) with toolchain triage. Use before claiming any change done.
---

# Verify (UpdateBar)

```bash
Scripts/quality-gate.sh      # the gate; same as CI
```

Env knobs: `SWIFT_BIN` (alternate toolchain), `SKIP_MENUBAR_SMOKE=1` (headless envs — say so in your report). The gate auto-sets `DEVELOPER_DIR` to `/Applications/Xcode.app` for XCTest.

## Triage

- `swift test`/XCTest "no such module XCTest" → DEVELOPER_DIR problem; use the gate (it handles it) or `docs/troubleshooting.md`.
- A script test (`X-test.sh`) failing → you changed `X.sh` behavior; update the twin with the change, never delete assertions to pass.
- Menubar smoke failing headless → skip WITH the env var and state it; that's an honest partial pass, not green.
- Quick loops: `swift build` + targeted `Scripts/<x>-test.sh` while iterating; completion still requires the full gate.

Completion = gate tail pasted + skips declared + changed binary exercised (`.build/debug/updatebar <cmd>`, exit code shown).
