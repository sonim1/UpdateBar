## ADDED Requirements

### Requirement: Menu Bar is native macOS presentation
The macOS Menu Bar app SHALL provide a native status item and lightweight dashboard/background controller for UpdateBar.

#### Scenario: Menu Bar starts
- **WHEN** the Menu Bar app launches
- **THEN** it SHALL show a native macOS status item with a concise UpdateBar status

#### Scenario: User opens menu
- **WHEN** the user opens the Menu Bar menu
- **THEN** it SHALL show actions for Check Now, Refresh Status, Run Updates, Open TUI, Open Config, View Logs, and Quit when those actions are available

### Requirement: Menu Bar uses shared business logic
The macOS Menu Bar SHALL use `UpdateBarCore` directly for business behavior when practical and SHALL use the Swift CLI machine interface only as an MVP fallback.

#### Scenario: Direct core adapter is available
- **WHEN** Menu Bar needs status, check, update, config, or approval behavior
- **THEN** it SHALL call shared `UpdateBarCore` services rather than duplicate business rules

#### Scenario: CLI subprocess fallback is used
- **WHEN** Menu Bar uses the Swift CLI subprocess fallback
- **THEN** it SHALL consume documented JSON/JSONL contracts and SHALL NOT parse human output

### Requirement: Menu Bar can launch the Ink TUI
The macOS Menu Bar SHALL provide an Open TUI action that launches a terminal running the configured Ink TUI command.

#### Scenario: TUI command is available
- **WHEN** the user selects Open TUI
- **THEN** the Menu Bar SHALL open a terminal session with the TUI command and pass required environment such as binary path and UpdateBar home

#### Scenario: TUI command is unavailable
- **WHEN** the user selects Open TUI but no TUI command can be resolved
- **THEN** the Menu Bar SHALL show a clear unavailable/setup message

### Requirement: Menu Bar handles background operations visibly
The Menu Bar SHALL expose background check/update state, user-triggered operation state, and operation failures without blocking the macOS UI.

#### Scenario: Check Now is running
- **WHEN** the user starts Check Now
- **THEN** the Menu Bar SHALL show an in-progress state and keep the menu responsive

#### Scenario: Operation fails
- **WHEN** a check or update operation fails
- **THEN** the Menu Bar SHALL show a concise failure state and provide access to logs or details

### Requirement: Menu Bar packaging resolves bundled tools
The macOS app bundle SHALL resolve bundled or configured `updatebar` and TUI commands predictably.

#### Scenario: App bundle includes Swift CLI
- **WHEN** the Menu Bar app bundle includes an `updatebar` binary
- **THEN** Menu Bar subprocess fallback and Open TUI environment SHALL prefer that bundled binary unless the user configured an override

#### Scenario: Homebrew install launches Menu Bar
- **WHEN** UpdateBar is installed through Homebrew and Menu Bar is launched from that installation
- **THEN** Menu Bar SHALL resolve the Homebrew-provided CLI/TUI paths or show a clear configuration error
