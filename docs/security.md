# Security

UpdateBar treats recipes as data until a command-bearing recipe is trusted.

## Trust

Imported recipes are saved with:

```json
{ "level": "untrusted", "approved_commands": {} }
```

`check` refuses unapproved `check.cmd` and `latest.cmd`. `update` refuses unapproved `update.cmd`.
Untrusted recipes must keep `approved_commands` empty.

Changing a command string or `update.cwd` changes its `sha256:<64 lowercase hex>`
fingerprint and invalidates the affected approval.

## Secrets

Recipe commands run with an allowlisted environment. Common provider and GitHub token values are removed from child process environments and redacted from captured errors.
Manifest validation rejects literal API keys and token values in recipe fields that are stored, exported, or used by execution:

- `id`, `name`, `category`, `path`, `pin`
- `source.ref`, `source.branch`
- `check.cmd`, `check.file`
- `latest.cmd`, `latest.pattern`
- `version_parse.regex`
- `update.cmd`, `update.cwd`

Recipes should reference environment variables instead of storing secret values.

## Command Boundaries

`status` does not execute shell commands or network calls. `import` validates and writes manifest data only. `check` is the state refresh path. `update` only runs approved update commands.

## Execution Boundary (Honest Statement)

Approved recipe commands are **not sandboxed**. The current guarantees are:

- approval-gated: a command runs only while its exact fingerprint is approved
- environment-allowlisted: child processes see only `PATH`, `HOME`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TMPDIR`, `USER`
- no login shell: commands run via `/bin/sh -c`; shell startup files are not sourced
- timeout-capped and output-capped
- secrets redacted from captured output and errors

An approved command can still read and write your files and use the network with your
user's privileges. Approve commands you have read and understood.
