# Menu Bar Logs and Icon Design

## Goal

Finish the menu-bar follow-up: leave unrelated menu rows usable while individual
updates run, remove TUI from the menu-bar surface, make update/check history
visible in the Dashboard, and ship the app icon without its baked black canvas.

## Decisions

- The merged per-item update implementation owns update progress. Update All
  schedules eligible items independently and the menu marks only each affected
  row as queued, updating, or done.
- `Open TUI` remains a CLI capability but is not exposed by the menu-bar app.
  Existing command support is retained; no TUI package or CLI behavior changes.
- Logs becomes a `Logs` Dashboard sidebar section. It presents the persisted
  `HistoryEvent` records in newest-first order. Update events show the item id,
  result, and version transition; check events show their outcome and outdated
  count. An empty history has an explicit empty state.
- The old `View Logs` action routes to the Dashboard Logs section for backwards
  compatibility, but it is removed from menu footer and error-recovery lists.
  It no longer opens Finder or the menu-bar diagnostic file.
- The replacement icon keeps the luminous upload-arrow visual, removes only the
  opaque black canvas around the rounded-square artwork, and is exported as a
  transparent PNG before rebuilding `UpdateBar.icns`.

## Validation

- Unit tests prove per-item action/menu presentation, TUI omission, Dashboard
  navigation, and log-row formatting including the empty state.
- The application builds and all Swift tests pass.
- The app-icon check verifies all ICNS representations; image inspection verifies
  transparent corners and no black outer padding.
- Packaging smoke tests verify the release app includes the rebuilt icon.
