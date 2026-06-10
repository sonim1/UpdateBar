# Changelog

## Unreleased

### Breaking

- Removed built-in AI recipe generation (`add --ai`) and the OpenRouter provider.
- Removed `auth` commands, provider credential stores, and the plaintext secret fallback.
- UpdateBar no longer generates recipes or commands itself. External agents author
  recipe JSON; UpdateBar validates, gates, and executes approved commands only.

### Added

- `guide agent` and recipe `template` commands for external-agent workflows.
- `validate` for manifest or single-recipe JSON.
- Per-command `approve` / `approvals` / `revoke`.
- `--exit-zero-on-outdated` on `check` and `status`.
- `manifest.lock` / `state.lock` cross-process file locks.

### Security

- Recipe child processes now receive an allowlisted environment
  (`PATH`, `HOME`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TMPDIR`, `USER`) instead of a denylist.
- Recipe commands run via `/bin/sh -c` with no login shell; shell startup files
  cannot re-inject secrets.

## 0.1.0

- Initial CLI: manifest validation, config, check/status/list/update,
  item management, import/export, manual add, edit.
- Smoke tests and release packaging scripts.
