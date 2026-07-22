# Menu Bar Status Icon Design

## Goal

Replace the generic circular-update SF Symbol and adjacent status text with one
compact UpdateBar-branded menu bar image that communicates current state without
changing width as status changes.

## Visual Structure

The left side uses a simplified monochrome version of the app icon: one solid
upward arrow with the shallow centered V-cut tail above a short horizontal bar.
The right side uses a separate outlined circle containing the status mark.

The complete image is rendered as an AppKit template image. macOS supplies the
foreground color for light, dark, active, and disabled menu bar appearances.
The app icon's green palette and Liquid Glass treatment are intentionally not
copied into the menu bar because those details do not remain legible at menu bar
size.

## Status Mapping

The circle replaces the existing visible `✓`, update-count, `!`, and `...`
button titles:

- Up to date: a bold checkmark (`✓`).
- Updates available: the exact count from `1` through `9`; counts of ten or
  more use `9+` so the badge retains a stable diameter.
- Approval required or error: a heavy exclamation mark (`!`) with visibly more
  weight than the current text treatment.
- Initial checking or an active check/update action: a centered ellipsis (`…`).

Approval-required and error states remain visually combined because the current
top-level status contract represents both as attention. The menu contents and
accessibility label continue to explain the specific reason.

## Rendering

The renderer creates one fixed-size transparent `NSImage` containing the brand
mark and badge. The arrow, V-tail, bar, and circle are drawn with `NSBezierPath`.
Badge characters use the system rounded font; the exclamation mark uses heavy
weight, other marks use bold weight, and `9+` uses a smaller size to fit.

The image is marked `isTemplate = true`. The status button uses image-only
presentation and receives a freshly rendered image only when its visual state
changes. No timer or animated frame loop is added; the ellipsis is the complete
running-state treatment.

## State And Accessibility

A small value type maps application state to one of `checking`, `upToDate`,
`updates(count:)`, or `attention`. The existing formatter remains responsible
for deciding whether updates or attention exist. Active actions and initial
refresh explicitly select `checking`; errors explicitly select `attention`.

Removing visible title text does not remove status information. Existing labels
such as `UpdateBar checking`, `UpdateBar 3 updates`, and `UpdateBar error` remain
on the status button for VoiceOver. Tooltips and menu content remain unchanged.

## Verification

- Unit tests cover mapping and badge text for checking, current, update counts
  `1`, `9`, and `10`, and attention.
- Renderer tests verify a fixed nonzero image size and template-image behavior.
- Source integration tests prove the button uses image-only presentation and no
  longer assigns the old visible status titles.
- Manual QA checks all four states on light and dark menu bars, including the
  heavy exclamation mark and legibility of `9+`.
- Existing menu, refresh-generation, action-coordinator, accessibility,
  packaging, signing, and smoke tests remain green.
