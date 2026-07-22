# Agent-Friendly Command Field Editing Design

## Goal

Let people and external AI agents safely correct a registered recipe's command
fields without making `check` interactive. Support `check.cmd`, `latest.cmd`, and
`update.cmd`, preserve explicit per-field approval, and provide stable
non-interactive input and JSON output for automation.

UpdateBar continues to own validation, persistence, and approval invalidation.
External agents may author command text, but editing a command never approves or
executes it.

## Existing Behavior

`updatebar edit <id>` opens the entire recipe JSON in `$VISUAL` or `$EDITOR`.
It validates the edited recipe and invalidates approvals whose fingerprints no
longer match. The command is currently hidden from top-level help and has no
field-specific, stdin, or JSON mode.

Agent-authored additions already use a suitable non-interactive flow:
`template` or an external agent produces JSON, `validate` checks it, and
`add --from <file|-> --json` stores it as untrusted. This design leaves that flow
unchanged and gives edits an equivalent automation-friendly path.

## CLI Interface

Keep whole-recipe editing unchanged:

```bash
updatebar edit <id>
```

Add field-specific editor mode for people:

```bash
updatebar edit <id> --field check.cmd
updatebar edit <id> --field latest.cmd
updatebar edit <id> --field update.cmd
```

The temporary editor document contains only the exact command text. UpdateBar
removes one editor-added final `LF` or `CRLF` before validation while preserving
internal newlines and all other command content.

Add file and stdin input for agents and scripts:

```bash
updatebar edit <id> --field check.cmd --from command.txt --json
updatebar edit <id> --field update.cmd --from - --json
```

`--from` requires `--field`; whole-recipe non-interactive replacement remains
available through the existing validated import/add mechanisms rather than
adding a second manifest replacement path. `--field` accepts exactly
`check.cmd`, `latest.cmd`, or `update.cmd`. It fails if the selected recipe does
not contain that command field, such as `latest.cmd` on a built-in latest
strategy.

Expose both `add` and `edit` in top-level CLI help so an agent inspecting
`updatebar --help` can discover the supported authoring paths. Update the agent
guide to show the non-interactive edit flow.

## Mutation And Trust Behavior

Field editing follows the same validation and locked persistence path as
whole-recipe editing:

1. Load the registered recipe and resolve the selected command field.
2. Read new text from the editor, a file, or standard input.
3. Reject empty or whitespace-only commands and invalid UTF-8.
4. Replace only the selected command field in a copy of the recipe.
5. Validate the complete recipe and containing manifest.
6. Recompute fingerprints and retain only approvals that still match.
7. Acquire the manifest lock, confirm the item still exists, and save.

Editing never automatically approves a field. Existing fingerprint dependency
behavior remains authoritative: changing `check.cmd` or `latest.cmd` can also
invalidate `update.cmd` approval because the update fingerprint binds the check
and latest configuration.

If the new command is byte-for-byte equivalent after final-line-ending
normalization, report an unchanged result and do not rewrite the manifest.

## Human And JSON Output

Successful human field editing prints the affected id and field, followed by
the explicit review step:

```text
edited brew.foo check.cmd

Next
updatebar approvals brew.foo
```

`--json` is accepted for field edits only when `--from` is also present. This
keeps editor output away from the machine-readable stdout contract. It writes
one stable object to stdout with:

- `ok`: `true`
- `id`: the redacted recipe id
- `field`: the edited field
- `changed`: whether persisted content changed
- `item`: the complete redacted stored recipe

Errors never contaminate stdout in JSON mode. Whole-recipe and field-specific
editor modes retain their existing human-oriented terminal behavior.

## Check And Approval Guidance

`check` remains deterministic and non-interactive. When a recipe cannot be
checked because required command approvals are missing, human output keeps the
existing `approvals` next step and adds field-edit commands only for command
fields required by checking:

```text
Next
updatebar approvals brew.foo
updatebar edit brew.foo --field check.cmd
```

If a `cmd` latest strategy is also blocked, include `latest.cmd`. Do not suggest
editing `update.cmd` from `check`, because it is not executed by checking.

`approvals <id>` continues to display exact redacted command text and produce
explicit `approve` commands. For each unapproved field, its human next-step
section also provides the corresponding `edit <id> --field <field>` command.
This makes all three supported fields discoverable at the point where users
review them without adding prompts or automatic approval.

Machine-readable `check` and `approvals --json` contracts remain unchanged.

## Agent Workflow

An external agent can discover, modify, review, approve, and test without a TTY:

```bash
updatebar approvals brew.foo --json
updatebar edit brew.foo --field check.cmd --from command.txt --json
updatebar approvals brew.foo --json
updatebar approve brew.foo --field check.cmd --json
updatebar check brew.foo --json
```

The separation is intentional: the agent can propose and store a command, but
approval is a distinct explicit action. Callers that require human trust review
can stop after the second `approvals --json` call.

For additions, the existing `guide agent`, `schema`, `template`, `validate`, and
`add --from` flow remains the recommended path.

## Error Handling

- Unknown fields fail with the existing command-field-not-found vocabulary.
- A valid field absent from the recipe reports that the recipe has no such
  command field.
- `--from` without `--field`, `--json` without `--field --from`, unreadable
  files, invalid UTF-8, empty commands, failed editors, and validation failures
  produce no mutation.
- JSON-requested failures use the existing CLI error envelope and stdout/stderr
  discipline.
- Literal-secret validation and secret redaction remain mandatory for every
  input and output path.

## Verification

- CLI tests cover editor, file, and stdin edits for `check.cmd`, `latest.cmd`,
  and `update.cmd`.
- Tests prove missing fields, invalid option combinations, invalid UTF-8, empty
  input, editor failure, and validation failure leave the manifest unchanged.
- Tests prove unchanged input does not rewrite state.
- Approval tests prove the edited field is invalidated and unrelated approvals
  remain, including the existing update-fingerprint dependency behavior.
- Output tests prove human next steps, stable redacted JSON, and clean JSON
  stdout.
- Check tests prove only check-required edit commands are suggested.
- Approvals tests prove every unapproved command field receives an edit command.
- Help and agent-guide snapshot tests prove `add` and `edit` are discoverable and
  document the non-interactive edit path.
- The focused CLI test suites and the repository quality gate pass.

## Non-Goals

- No interactive prompt inside `check`, `approvals`, or `approve`.
- No automatic command generation, approval, or execution.
- No `--value` option that requires callers to encode complex shell text in an
  argument.
- No editing of non-command recipe fields through `--field`.
- No change to trust policy, command fingerprints, scan recipe templates, or
  machine-readable check/approval schemas.
