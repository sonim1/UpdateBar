## ADDED Requirements

### Requirement: Preferences preserve unrelated values

The native Preferences screen SHALL merge fields edited by the user into the configuration loaded when Save runs. Validation failure SHALL leave the configuration unchanged. Preferences SHALL expose update concurrency using the existing 1–8 range and reload canonical saved values after success.

#### Scenario: Save does not reset configured concurrency

- **GIVEN** the CLI configures concurrency to 8
- **WHEN** the user changes only refresh interval in Preferences and saves
- **THEN** concurrency remains 8

#### Scenario: CLI changes after opening Preferences

- **GIVEN** Preferences has loaded and the CLI changes unedited fields
- **WHEN** the user saves another edited field
- **THEN** the unedited CLI values are retained and shown in the saved form

### Requirement: Native pin controls share existing state

Items details SHALL provide pin/unpin independently of tracking enable/disable. Pinning SHALL require an available current version; clearing an existing pin SHALL remain available without that version. Mutations SHALL use the existing Core or CLI service adapter without changing approvals or executing recipe commands.

#### Scenario: Pin removes an item from update selection

- **WHEN** the user pins a selected item
- **THEN** actions remain blocked until a matching canonical snapshot arrives
- **AND** the pinned item is removed from update selection

#### Scenario: Mutation failure

- **WHEN** pin persistence fails
- **THEN** pending state is cleared, the original state remains visible, and the error is reported

#### Scenario: Unpin after a pinned check

- **GIVEN** a previous check stored a pinned result
- **WHEN** the item is unpinned
- **THEN** native and CLI status stop reporting it as pinned and indicate a check is needed
- **AND** no command executes automatically

#### Scenario: Disabled item remains disabled after unpinning

- **WHEN** the user clears a pin on a disabled item
- **THEN** the item remains disabled and its command approvals remain unchanged
