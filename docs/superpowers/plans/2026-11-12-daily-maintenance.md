# Daily maintenance and clear approval status

The native menu remains in place. Replace the partial-approval half-circle with
an explicit pending-approval count and warning symbol. Preserve reviewed command
fingerprints and the existing approval actions.

Add a separate daily maintenance schedule, defaulting to check only at 09:00 in
the current local time zone. Settings offer Off, Check only, and Check and update
approved items, plus a time picker. Scheduling applies while UpdateBar is running;
the settings explain this and wake-up catch-up. The existing CLI LaunchAgent
continues to be a separate, opt-in, check-only facility.

1. Add config keys `schedule.mode` and `schedule.time` with strict validation and
   backwards-compatible defaults. Verify config round-trip and invalid values.
2. Add a deterministic daily scheduling policy and persist its last claimed run
   per UpdateBar home. Verify daily limits, restarts, busy deferral, sleep, DST,
   time changes, and disabled schedules.
3. Run a fresh check, then (only in the opted-in mode) use the existing approved
   update runner. Verify check-only, check failure, stop, and command approvals.
4. Wire the native app timer and settings; preserve external edits on Save.
   Verify settings load/save and the real rendered settings view.
5. Replace the ambiguous approval icon and verify existing actions stay bound to
   reviewed commands. Run focused tests, formatting, and the full quality gate.

No release or version bump is included in this change. Existing unrelated workflow
and TUI edits in this workspace must be preserved.
