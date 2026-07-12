# ink-tui Specification

## Purpose
Define the Ink/React terminal UI as a presentation layer over the Swift
`updatebar` CLI and its documented JSON/JSONL contracts.
## Requirements
### Requirement: Ink TUI uses Swift CLI subprocesses
The Ink/React TUI SHALL use the Swift `updatebar` CLI subprocess and documented JSON/JSONL contracts to read state and run actions.

#### Scenario: TUI loads status
- **WHEN** the TUI starts or refreshes status
- **THEN** it SHALL invoke `updatebar status --json` or an equivalent documented machine command

#### Scenario: TUI runs update
- **WHEN** the user starts an update from the TUI
- **THEN** the TUI SHALL invoke the Swift CLI with a machine-readable contract such as `update --json-stream`

### Requirement: Ink TUI does not mutate UpdateBar files directly
The Ink TUI SHALL NOT directly read or write `manifest.json`, `state.json`, config files, approval stores, or command log files for business behavior.

#### Scenario: User selects recipes or updates
- **WHEN** the user selects items in the TUI
- **THEN** the TUI SHALL pass selected ids to the Swift CLI or render data returned by the Swift CLI

#### Scenario: User changes config
- **WHEN** the user changes configuration through the TUI
- **THEN** the TUI SHALL call documented Swift CLI config commands rather than writing config files directly

### Requirement: TUI provides interactive terminal presentation
The Ink TUI SHALL provide menu navigation, status screens, selection controls, progress display, log display, and keyboard navigation.

#### Scenario: User navigates main menu
- **WHEN** the user opens the TUI
- **THEN** the TUI SHALL show navigable actions for status, check, update, logs, configuration, and exit

#### Scenario: Long-running operation emits events
- **WHEN** the Swift CLI emits JSONL progress events
- **THEN** the TUI SHALL render progress, current item, logs, and final status without parsing human output

### Requirement: TUI cancellation propagates to CLI
The Ink TUI SHALL propagate user cancellation to the active Swift CLI child process.

#### Scenario: User presses cancel during update
- **WHEN** the user cancels an active update in the TUI
- **THEN** the TUI SHALL send SIGINT to the active CLI process and display the resulting cancellation or failure state

#### Scenario: Child process does not exit after cancellation
- **WHEN** the child process does not exit within the configured grace period
- **THEN** the TUI SHALL send a stronger termination signal and display that the operation was terminated

### Requirement: TUI handles machine contract failures
The Ink TUI SHALL show recoverable errors when the Swift CLI binary is missing, returns invalid JSON/JSONL, exits with a known failure code, or emits a documented error payload.

#### Scenario: Binary is missing
- **WHEN** the TUI cannot resolve an `updatebar` binary
- **THEN** it SHALL show a clear setup error and SHALL NOT attempt direct file mutation

#### Scenario: JSON parse fails
- **WHEN** the TUI receives invalid JSON or JSONL from the subprocess
- **THEN** it SHALL show a machine-contract error and include enough diagnostic context for troubleshooting
