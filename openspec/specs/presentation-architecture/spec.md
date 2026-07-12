# presentation-architecture Specification

## Purpose
Define responsibility boundaries between `UpdateBarCore`, the Swift CLI, the
Ink TUI, and the macOS Menu Bar so business rules remain centralized.
## Requirements
### Requirement: Core owns business logic
`UpdateBarCore` SHALL be the single source of truth for manifest, state, config, registry, check, update, approval, scan, init, version comparison, and command-execution business rules.

#### Scenario: Presentation layer requests update planning
- **WHEN** the Swift CLI, Ink TUI, or macOS Menu Bar needs to decide which items can update
- **THEN** the decision SHALL come from `UpdateBarCore` behavior rather than duplicated presentation-layer logic

#### Scenario: Business rule changes
- **WHEN** a trust, approval, version, or update rule changes
- **THEN** the change SHALL be made in `UpdateBarCore` and exposed through CLI/Menu Bar adapters

### Requirement: CLI remains automation interface
The Swift CLI SHALL remain the stable command parsing, scripting, CI, exit-code, JSON, and JSONL interface for external callers.

#### Scenario: Script invokes status
- **WHEN** a script runs `updatebar status --json`
- **THEN** stdout SHALL contain machine-readable JSON and the exit code SHALL retain documented automation meaning

#### Scenario: Human user invokes interactive presentation
- **WHEN** a user wants menus, keyboard navigation, progress bars, or log panes
- **THEN** the Ink TUI or macOS Menu Bar SHALL provide that presentation instead of adding UI-only business logic to `UpdateBarCore`

### Requirement: Presentation layers do not duplicate core rules
The Ink TUI and macOS Menu Bar SHALL NOT implement independent check, update, trust, approval, manifest, or state mutation rules.

#### Scenario: Ink TUI displays selectable updates
- **WHEN** the Ink TUI renders update choices
- **THEN** it SHALL use Swift CLI JSON/JSONL output derived from `UpdateBarCore`

#### Scenario: Menu Bar runs Check Now
- **WHEN** the macOS Menu Bar runs Check Now
- **THEN** it SHALL use `UpdateBarCore` directly or invoke the Swift CLI machine interface without duplicating check rules

### Requirement: Presentation boundaries are explicit
Each layer SHALL have a documented responsibility boundary: `UpdateBarCore` for business logic, Swift CLI for automation contracts, Ink TUI for terminal presentation, and macOS Menu Bar for native macOS presentation.

#### Scenario: New feature is added
- **WHEN** a feature touches business behavior and presentation behavior
- **THEN** business behavior SHALL be implemented in `UpdateBarCore` and presentation behavior SHALL be implemented in the relevant UI layer
