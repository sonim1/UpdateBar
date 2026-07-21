## ADDED Requirements

### Requirement: JSON stdout isolation
In JSON mode, the Swift CLI SHALL write only the command JSON payload to stdout.

#### Scenario: Command succeeds in JSON mode
- **WHEN** a caller runs a command with `--json`
- **THEN** stdout SHALL contain one valid JSON payload and no human-readable log lines

#### Scenario: Command emits diagnostics in JSON mode
- **WHEN** the command needs to emit warnings or human diagnostics
- **THEN** those diagnostics SHALL be written to stderr or represented as documented JSON fields/events

### Requirement: JSONL streaming event contract
Long-running machine-readable commands SHALL provide a JSONL streaming mode for progress, logs, item outcomes, cancellation, and final status.

#### Scenario: Update stream starts
- **WHEN** a caller runs a long-running command such as `update` with `--json-stream`
- **THEN** stdout SHALL emit newline-delimited JSON events with stable event fields

#### Scenario: Event envelope is emitted
- **WHEN** a JSONL event is emitted
- **THEN** the event SHALL include `type`, `operation`, `run_id`, and `timestamp`

#### Scenario: Item event is emitted
- **WHEN** a JSONL event refers to a manifest item
- **THEN** the event SHALL include `item_id` and SHALL identify the item outcome without requiring human-text parsing

### Requirement: Human logs are separated from machine output
The CLI SHALL keep human logs separate from machine-readable stdout contracts.

#### Scenario: JSONL mode captures command output
- **WHEN** a child command writes log output during `--json-stream`
- **THEN** the CLI SHALL emit logs as structured JSONL `log` events or write non-contract diagnostics to stderr

#### Scenario: Plain mode command runs
- **WHEN** a user runs a command without JSON or JSONL flags
- **THEN** the CLI SHALL treat stdout as human-readable output rather than a machine-readable contract

### Requirement: Exit codes remain stable
The CLI SHALL preserve documented exit-code meanings for success, validation/config/runtime failures, partial update failures, approval blocks, and outdated status.

#### Scenario: Machine caller receives partial failure
- **WHEN** an update command completes with one or more item failures
- **THEN** the CLI SHALL return the documented partial-failure exit code and include item-level error details in JSON or JSONL output

#### Scenario: Machine caller receives outdated status
- **WHEN** a status/check command detects outdated items
- **THEN** the CLI SHALL return the documented outdated exit code unless the caller passes the documented opt-out flag

### Requirement: Cancellation is observable
The CLI SHALL handle SIGINT/SIGTERM during long-running commands and expose cancellation as a machine-readable operation outcome when possible.

#### Scenario: Caller sends SIGINT during JSONL update
- **WHEN** the CLI receives SIGINT during `update --json-stream`
- **THEN** it SHALL stop scheduling new work, terminate owned child commands when needed, emit a cancellation event when possible, and return a non-success exit code

#### Scenario: Caller terminates process before final event
- **WHEN** the process is killed before it can emit a final event
- **THEN** callers SHALL be able to treat process termination as cancellation/failure without relying on partial human output

### Requirement: Binary path resolution is deterministic
Consumers that invoke `updatebar` as a subprocess SHALL resolve the Swift CLI binary through a documented deterministic order.

#### Scenario: Explicit binary override exists
- **WHEN** `UPDATEBAR_BIN` or configured binary path is present
- **THEN** presentation layers SHALL use that binary before searching `PATH`

#### Scenario: Packaged app includes a binary
- **WHEN** the TUI or Menu Bar is distributed with a bundled Swift CLI binary
- **THEN** the bundled binary path SHALL be preferred over development fallbacks
