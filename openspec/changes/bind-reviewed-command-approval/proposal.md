## Why

The native menu can approve a command replaced while its confirmation is open.
The reviewed-action adapter also has a gap between reading and saving approval.
Sparkle 2.9.4 lacks subsequent upstream installer security fixes.

## What Changes

- Carry the reviewed command status through native menu actions and compare its
  fingerprint under the same manifest lock used to save approval.
- Add an optional CLI `--expected-fingerprint` argument and forward it through
  both Menu Bar service adapters.
- Pin Sparkle 2.10.0 and its appcast tooling guard to the same upstream commit.

## Compatibility

Recipe schemas and JSON/JSONL payloads remain unchanged. An explicit CLI approval
without the new option still approves the current command. Approval never runs a
command. The app retains its macOS 13 minimum and existing update feed and key.
