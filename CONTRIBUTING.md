# Contributing

Thanks for working on UpdateBar. Keep contributions small, testable, and
aligned with the existing CLI/core/menu bar boundaries.

## Ground Rules

- Preserve existing behavior unless the change explicitly states otherwise.
- Keep `UpdateBarCore` free of CLI-specific printing and UI concerns.
- Keep machine-readable stdout contracts stable; write human diagnostics to
  stderr.
- Do not add new product scope from drive-by cleanup. Use OpenSpec for larger
  behavior changes.
- Do not include private tokens, local user data, or live exploit details in
  issues, tests, or logs.

## Local Checks

Run the full gate before proposing release-sensitive changes:

```bash
Scripts/quality-gate.sh
```

For narrower changes, run the relevant subset first:

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test
npm --prefix tui run typecheck
npm --prefix tui run lint
npm --prefix tui run test
npm --prefix tui run build
```

Packaging or release metadata changes should also run:

```bash
bash Scripts/homebrew-packaging-test.sh
UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh
```

## Security Reports

Report suspected vulnerabilities privately through the process in
[.github/SECURITY.md](.github/SECURITY.md). Do not open public issues with
working exploit details or private data.
