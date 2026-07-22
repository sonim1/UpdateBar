# Compact Overlaid Menu Bar Status Icon Design

## Context

The current UpdateBar menu bar image places a 16-point brand mark and a 14-point
status circle side by side in a 34×18-point canvas. The state is readable, but the
status item consumes substantially more horizontal space than a normal compact
macOS menu bar icon.

The replacement should follow the visual relationship in compact system menu bar
icons: keep one primary symbol and attach a smaller status mark at its lower-right
corner. The status circle must remain visible without turning the item back into a
wide composite.

## Goals

- Reduce the rendered image from 34×18 points to 20×18 points.
- Preserve the existing up-arrow, shallow V-tail, and lower bar brand mark.
- Overlay one readable circular status badge at the lower-right corner.
- Preserve every existing status value: ellipsis, checkmark, counts 1 through 9,
  `9+`, and a heavy exclamation mark.
- Remain a single monochrome AppKit template image so macOS controls menu bar tint.
- Preserve existing state priority, accessibility labels, and status-item behavior.

## Non-goals

- Do not add color, glass effects, animation, or multiple views inside the status
  item.
- Do not change how UpdateBar computes checking, up-to-date, update-count, or
  attention states.
- Do not redesign the application icon or menu contents.

## Chosen Approach

Render the brand and status badge into one fixed-size `NSImage`. Before drawing the
badge, clear a circular area expanded by 1 point on every side. Then draw the badge
outline and text over that transparent knockout.

This approach keeps the status item image-only and compact while preventing the
arrow tail or lower bar from showing through the badge. It is preferred over a
direct overlay, which reduces text contrast, and over adding a separate AppKit badge
view, which would add layout, click-routing, and accessibility complexity.

## Rendering Geometry

- Canvas: 20×18 points.
- Brand mark: retain the current coordinates and 18-point visual height. Its right
  side may sit underneath the badge knockout.
- Badge circle: `NSRect(x: 7.5, y: 0.5, width: 12.5, height: 12.5)`, placing its
  outer bounds against the lower-right edge of the canvas.
- Knockout: the badge rectangle expanded by 1 point on every side and clipped by the
  canvas. It must create a visible gap between the brand and badge without erasing
  the badge after it is drawn.
- Badge stroke: 1.5 points.
- Badge text: centered optically with a 0.3-point upward adjustment. Single-character
  states use an 8.5-point bold font, attention uses heavy weight, and `9+` uses a
  6.25-point bold font.
- Output: `isTemplate = true`; the renderer draws in solid black and relies on macOS
  to tint the installed menu bar image.

The drawing order is brand mark, lower bar, transparent knockout, badge outline,
then badge text.

## State and Data Flow

`MenuBarState.statusIconState` and `MenuBarStatusIconState.badgeText` remain
unchanged. The app continues to request an image from
`MenuBarStatusIconRenderer`, cache the last rendered state, set the status button to
`.imageOnly`, and retain the current accessibility label.

Only renderer geometry and its layout-focused tests change.

## Failure Behavior and Accessibility

Rendering introduces no new recoverable failure path. If AppKit supplies a menu bar
tint, the single template image follows it as before. Error and approval states
continue to use the attention badge and their existing spoken accessibility labels;
visual overlap does not replace textual accessibility information.

## Verification

- Add a failing renderer test that requires an exact 20×18-point image.
- Add a layout-focused raster assertion proving the lower-right badge occupies the
  same compact canvas as the brand instead of a separate right-hand region.
- Keep badge-text, weight, state-priority, and source-contract tests green.
- Render all five representative states (`…`, `✓`, `1`, `9+`, `!`) at 2× and inspect
  spacing, knockout separation, centering, and stroke consistency.
- Run the full quality gate, package `dist/UpdateBar.app`, and run the menu bar smoke
  test.
- Replace the local `/Applications/UpdateBar.app` only after verification, preserve
  the previous installation as a backup, and confirm the installed process launches.

## Success Criteria

The installed menu bar item uses a 20×18-point template image, reads as the UpdateBar
brand with a lower-right circular status overlay, retains every status state, and is
materially narrower than the current 34×18-point side-by-side design.
