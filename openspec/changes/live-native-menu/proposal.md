## Why

The native macOS status menu replaces its backing menu on every refresh, leaving
an open menu stale. The file monitor also stops during menu tracking. Update rows
follow incoming snapshot order and disappear as completed items leave the outdated
set, making progress difficult to follow.

## What Changes

- Keep the native NSMenu and update existing rows by stable identity.
- Run file monitoring during menu tracking and preserve the last snapshot during refresh.
- Sort recipe rows by name and ID, keeping the update list for the duration of an action.
- Add SF Symbols for commands and queued, updating, done, and failed states.

## Compatibility

Keep the existing native menu presentation, command approval boundary, CLI output,
dependencies, and packaging behavior.
