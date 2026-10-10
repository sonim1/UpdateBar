## ADDED Requirements

### Requirement: Approval matches the reviewed command

Menu Bar approvals SHALL carry the reviewed command fingerprint to RegistryService.
The current fingerprint comparison and approval write SHALL share the manifest
lock. Changed command text or working directory SHALL cause failure without an
approval write or command execution.

#### Scenario: A command changes while native confirmation is open

- **GIVEN** the confirmation shows command A
- **WHEN** a supported registry edit replaces it with command B before approval
- **THEN** approval fails and command B remains unapproved
- **AND** the user must review the new command before approving again

#### Scenario: A command changes after an adapter reads approvals

- **GIVEN** the service adapter reads command A with its reviewed fingerprint
- **WHEN** the registry replaces A before the approval write
- **THEN** the comparison under the manifest lock rejects approval

### Requirement: CLI automation can bind approval to review

The CLI SHALL accept optional `approve --expected-fingerprint <fingerprint>`.
A mismatch SHALL return exit code 1 with the existing `registry_error` JSON
envelope and leave the manifest unchanged. Omitting the option SHALL retain the
existing explicit approval behavior. Approval SHALL never execute a command.

#### Scenario: The reviewed command remains unchanged

- **WHEN** approval supplies the current fingerprint
- **THEN** only the requested command field is approved

#### Scenario: The reviewed working directory changes

- **WHEN** approval supplies a fingerprint from before a working-directory edit
- **THEN** approval fails without writing the manifest
