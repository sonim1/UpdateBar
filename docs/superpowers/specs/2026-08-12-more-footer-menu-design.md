# More Footer Menu Design

## Goal

Reduce menu-bar clutter without removing any navigation action.

## Design

Keep `Dashboard`, `Check for Updates...`, and `Quit` as top-level footer items. Add one `More` submenu between Dashboard and Check for Updates. Move `Manage Items...`, `Scan & Add`, `Settings...`, and `About UpdateBar` into that submenu in the same order they have today.

Apply the same footer grouping to normal and error menus. Status, update, approval, error, and 30-day chart content remain unchanged.

## Verification

Model tests assert the exact top-level order and submenu actions for both normal and error menus. The full Swift test suite and formatting checks must pass.
