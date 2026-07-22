## ADDED Requirements

### Requirement: Dashboard uses one reusable native sidebar window

The Dashboard SHALL use one reusable native window with a left sidebar containing Overview, Items, and Scan & Add sections. The Dashboard, Manage Items, and Scan & Add menu actions SHALL open that window and select their matching sidebar section.

#### Scenario: Menu actions select sections

- **WHEN** the user selects Dashboard, Manage Items, or Scan & Add from the native menu
- **THEN** the reusable Dashboard window SHALL open and select Overview, Items, or Scan & Add respectively

### Requirement: Scan checkboxes control tracking immediately

Scan rows SHALL have stable untracked, enabled, disabled, and unavailable states. An unavailable candidate has no complete recipe; its checkbox SHALL be disabled and no service call SHALL be made. Other scan row checkboxes SHALL immediately control tracking state, while scanning SHALL occur only after an explicit user action.

#### Scenario: Selecting Scan does not scan

- **WHEN** the user selects the Scan & Add sidebar section
- **THEN** no scan SHALL start until the user explicitly activates the visible Scan button

#### Scenario: Untracked full candidate is checked

- **WHEN** the user checks an untracked full candidate row
- **THEN** the app SHALL call `registerScannedCandidates` for that one ID, mark it enabled, and keep the registration untrusted

#### Scenario: Enabled row is unchecked

- **WHEN** the user unchecks an enabled row
- **THEN** the app SHALL call `setEnabled(false)` and preserve its recipe, approvals, state, and history

#### Scenario: Disabled row is checked

- **WHEN** the user checks a disabled row
- **THEN** the app SHALL call `setEnabled(true)` for its existing recipe

#### Scenario: Unavailable candidate is shown

- **WHEN** a scan candidate has no complete recipe
- **THEN** the row SHALL be unavailable with a disabled checkbox and the app SHALL make no registration, enable, disable, or remove service call

### Requirement: Scan row mutations are deterministic and isolated

For each toggle, the app SHALL capture the previous and target state keyed by candidate ID, immediately reflect the target control state, disable only that pending row, and show row-local progress. A duplicate toggle for the same ID SHALL be rejected while pending, while unrelated rows SHALL remain interactive. The Scan button SHALL be disabled while any row mutation is pending.

#### Scenario: Row mutation is pending

- **WHEN** a user toggles a row
- **THEN** the app SHALL capture its previous and target state by candidate ID, show the target state immediately, disable only that row, and show row-local progress

#### Scenario: Duplicate toggle is attempted

- **WHEN** a second toggle is attempted for the same candidate ID before the first mutation completes
- **THEN** the duplicate toggle SHALL be rejected without a second service call

#### Scenario: Unrelated row remains interactive

- **WHEN** one candidate ID has a pending mutation
- **THEN** another candidate row SHALL remain interactive while the Scan button is disabled

#### Scenario: Row mutation succeeds

- **WHEN** a pending row mutation succeeds
- **THEN** the row SHALL keep its target state and the app SHALL trigger the shared Dashboard/menu refresh

#### Scenario: Scan mutation fails

- **WHEN** a checkbox mutation fails
- **THEN** the app SHALL restore the previous checkbox/state, show a redacted row-local warning, and present the native error

#### Scenario: Stale scan completion arrives

- **WHEN** a scan completion arrives with an older generation token than the current scan
- **THEN** the app SHALL reject the stale completion without replacing current scan rows

### Requirement: Dashboard helper copy remains discoverable

Dashboard helper copy SHALL be compact in the persistent layout while metrics, counts, and information remain fully meaningful through tooltips and accessibility labels; refresh controls SHALL expose their full meaning as well.

#### Scenario: Compact copy exposes full meaning

- **WHEN** a user views Overview, Items, or Scan & Add
- **THEN** compact labels SHALL provide equivalent full explanations through the corresponding tooltip and accessibility label
