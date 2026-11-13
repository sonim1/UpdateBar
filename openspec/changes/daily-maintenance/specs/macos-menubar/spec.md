## ADDED Requirements

### Requirement: Daily recipe maintenance
The menu bar app SHALL default to checking recipes once daily at 09:00 local time.
Settings SHALL allow disabling the schedule, checking only, or checking and then
updating approved outdated items, and SHALL allow choosing a daily local time.
The app SHALL explain that it must remain running for scheduled work to execute.

Configuration SHALL persist `schedule.mode` and `schedule.time` independently of
the cache lifetime. The CLI adapter SHALL read and save those keys through the
existing per-key JSON config commands, preserving the aggregate JSON shape.

#### Scenario: Sleep or busy app
- WHEN a scheduled time passes while the app is asleep or performing another action
- THEN it runs once after waking or becoming idle, without replaying every missed day
- AND it does not start a second scheduled run on the same local calendar day

#### Scenario: Explicit update opt-in
- WHEN the user selects check and update
- THEN the app performs a fresh check before the existing approved update operation
- AND a recipe whose fresh check fails is excluded from updates
- AND a failure of the check operation, cancellation, or stop prevents starting the update phase
- AND no command approval is created or bypassed

### Requirement: Clear pending command approval
Items requiring command approval SHALL use a warning symbol and explicit pending
approval text instead of a half-filled circle. Approval actions SHALL retain their
reviewed command fingerprints.
