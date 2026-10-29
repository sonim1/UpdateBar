## ADDED Requirements

### Requirement: Live native status menu

The app SHALL preserve its native NSMenu and refresh visible rows while it is open.

#### Scenario: External state changes during menu tracking
- **WHEN** a monitored state file changes while the menu is open
- **THEN** the monitor SHALL continue polling and update the visible menu without reopening it
- **AND** unchanged rows and submenus SHALL keep their identity

### Requirement: Stable update rows

The menu SHALL sort recipe rows by name with ID as the tie breaker and retain the
original update rows until the active update action ends.

#### Scenario: Updates complete in a different order
- **WHEN** a refreshed snapshot removes completed recipes from its outdated set
- **THEN** the active menu SHALL keep those recipes in their original positions
- **AND** their icons and labels SHALL reflect queued, updating, successful, or failed progress

### Requirement: Recognizable menu actions

The menu SHALL show consistent SF Symbols for commands in enabled and disabled states.

#### Scenario: An action starts
- **WHEN** commands become temporarily disabled
- **THEN** their icons SHALL remain visible

### Requirement: Predictable active menu controls

The menu SHALL reuse its summary row during work, omit empty progress counters,
and show Stop After Current in Update All's position only for operations that
support cooperative stopping.

#### Scenario: Checking versions without an update plan
- **WHEN** a version check is running
- **THEN** the summary SHALL describe the active check without a zero-total counter
- **AND** the menu SHALL NOT present an idle summary or an unsupported stop action

#### Scenario: Following a large update batch
- **WHEN** more than six updates are displayed
- **THEN** remaining updates SHALL be reachable in a native overflow submenu
- **AND** their stable ordering, actions, and progress icons SHALL match the root rows
