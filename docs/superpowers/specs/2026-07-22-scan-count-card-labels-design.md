# Scan Count Card Labels and Alignment Design

## Context

The Scan & Add dashboard currently renders three equal-width summary cards as
single `NSTextField` instances. Each card displays only a number in a fixed
30-point height. The presentation model already supplies the meanings
`Discovered`, `Enabled`, and `Disabled`, but those meanings are available only
through accessibility and tooltip text.

The number-only cards leave enough horizontal room for visible labels, and a
single text field does not provide reliable optical vertical alignment for the
current card shape. The replacement exposes each meaning directly and aligns all
numeric values consistently.

## Goals

- Show `Discovered`, `Enabled`, and `Disabled` inside their corresponding cards.
- Use the approved left-aligned, two-line metric-card layout.
- Give every numeric value the same baseline and tabular digit metrics.
- Preserve the existing equal-width three-card row and count calculations.
- Preserve one concise accessibility element per card without duplicate child
  announcements.
- Continue to update visible and accessibility values when scan state changes.

## Non-goals

- Do not change what discovered, enabled, or disabled means.
- Do not change scanning, candidate mutation, table contents, or Scan button
  behavior.
- Do not add icons, color-coded states, animation, localization infrastructure, or
  new presentation-model fields.
- Do not redesign other dashboard metric cards.

## Chosen Layout

Each `ScanCountBadgeView` becomes a 48-point-high card view containing two
non-editable text fields in a vertical stack:

- Label: 11-point system font with medium weight and `secondaryLabelColor`.
- Value: 17-point monospaced-digit system font with semibold weight and
  `labelColor`.
- Alignment: both fields left aligned.
- Horizontal inset: 12 points from the card's leading and trailing edges.
- Vertical relationship: label above value with 2 points of spacing; the pair is
  centered vertically inside the 48-point card.
- Background: retain `controlBackgroundColor` and a 6-point corner radius.

The three cards remain in the existing horizontal `NSStackView` with
`.fillEqually` distribution and 8 points of spacing.

## Component Structure

`ScanCountBadgeView` changes from an `NSTextField` subclass to an `NSView`
subclass. It owns:

- `titleLabel`, which displays `DashboardScanCountPresentation.accessibilityLabel`.
- `valueLabel`, which displays `DashboardScanCountPresentation.visibleValue`.
- One internal vertical `NSStackView` that applies the common alignment and spacing.

The view exposes no new public API. Its existing `apply(_:)` method remains the
single update entry point and updates the title, visible value, tooltip, and
accessibility attributes together.

## Data Flow

`ScanViewController.updateControls()` continues to call
`DashboardPresentationModel.scanCounts(discovered:enabled:disabled:)` and passes
the resulting three presentations to the existing cards. No count computation or
state priority changes.

`ScanCountBadgeView.apply(_:)` maps:

- `accessibilityLabel` to the visible title and container accessibility label.
- `visibleValue` to the visible numeric field and container accessibility value.
- `help` to the tooltip and container accessibility help.

## Accessibility

Each card remains one `.staticText` accessibility element. `titleLabel`,
`valueLabel`, and the internal stack are explicitly excluded from the accessibility
tree so VoiceOver does not announce the visible text twice. The spoken result
continues to pair the metric label with its current value and help text.

## Failure Behavior

This change introduces no new fallible operation. A count presentation always
contains a title and a visible integer string. Updates continue on the main actor
through the existing controller flow.

## Verification

- Add a failing view test that requires visible labels and separate numeric fields.
- Require the card to be 48 points high with 12-point horizontal insets, a 2-point
  vertical gap, and left-aligned text.
- Assert the label font, secondary color, numeric monospaced font, semibold weight,
  and primary color.
- Verify values with different widths, including `0`, `7`, and `32`, share the same
  left edge and layout constraints.
- Verify `apply(_:)` updates the visible value, visible label, tooltip, and container
  accessibility attributes.
- Verify each card is the only accessibility leaf and its child labels are not
  accessibility elements.
- Update source-contract tests that currently require a single `NSTextField` badge
  and forbid child value labels.
- Run the full quality gate, package the app, and run the menu bar smoke test.
- Install the verified local bundle with a recoverable backup and inspect the real
  Scan & Add dashboard in both light and dark appearance.

## Success Criteria

The installed Scan & Add dashboard shows three equal-width left-aligned cards with
visible `Discovered`, `Enabled`, and `Disabled` labels above consistently aligned
numeric values. The cards remain readable, accessible, and correctly updated for
single- and multi-digit counts.
