# Items Dashboard

## ADDED Requirements

### Requirement: Exclusive status groups
Items SHALL show every tracked tool once in Ready to update, Needs review, Needs attention, Up to date, or Paused. Ready SHALL match menu-bar eligibility. Current/paused groups SHALL be initially collapsed.

#### Scenario: Mixed status inventory
- **WHEN** approved outdated, unapproved, failed, current, pinned and disabled tools exist
- **THEN** only approved unpaused outdated tools appear as selectable Ready cards
- **AND** review, error and paused tools remain outside normal bulk updates

### Requirement: Explicit update target selection
Items SHALL offer Update all when no selection/search exists, Update selected for explicit selection, and Update visible when searching without selection. Targets SHALL be resolved against current eligibility.

#### Scenario: Eligibility changes after selection
- **WHEN** a selected tool changes version, approval, enabled or pinned state
- **THEN** stale selection SHALL not execute that tool

### Requirement: Shared real actions and progress
Items SHALL use existing menu actions and progress for checking, updating, stopping and retrying failed items. Exact command approval SHALL remain explicit per command; approval SHALL NOT start an update.

#### Scenario: Active batch
- **WHEN** updates are running
- **THEN** Items SHALL show queued/running/completed outcomes, disable conflicting mutations and allow Stop after current only when supported
- **AND** retry SHALL target only allowed failed items

### Requirement: Existing boundaries
The change SHALL preserve Core trust and CLI JSON/exit-code contracts, enable/disable, and other Dashboard destinations. No new product dependencies SHALL be introduced.
