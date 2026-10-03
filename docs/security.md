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
The `updatebar tui` launcher, the Ink TUI's Swift CLI subprocess, and the Menu Bar CLI subprocess also use allowlisted environments and do not forward provider token environment variables.
Presentation subprocesses also receive only absolute `PATH` entries.
GitHub release-check tokens (`GITHUB_TOKEN` and `GH_TOKEN`) may pass through TUI and Menu Bar layers to the Swift CLI, but recipe command subprocesses still do not receive them.
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

- approval-gated: commands require approval of their exact fingerprints. Updates recheck
  the recipe's existence, enabled and pin state, command/cwd fingerprint, and approval
  under the manifest lock immediately before starting the process
- environment-allowlisted: child processes see only `PATH`, `HOME`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TMPDIR`, `USER`; relative entries are removed so recipe commands receive only absolute `PATH` entries
- no login shell: commands run via `/bin/sh -c`; shell startup files are not sourced
- timeout-capped and output-capped: timeout or cancellation sends escalating signals to the
  isolated process group owned by that launch, including descendants that remain in the group
- secrets redacted from captured output and errors

Revoking an update approval after launch blocks later launches; it does not terminate
an already running command.

The CLI treats `SIGINT` as cooperative cancellation and `SIGTERM` as a request to
terminate active command groups immediately. This lets an outer supervisor's escalation
reach the inner command groups before the CLI itself is killed.

An approved command can still read and write your files and use the network with your
user's privileges. It can also deliberately leave its original process group, which is outside
the descendant-cleanup guarantee. Approve commands you have read and understood.
