# Sidebar Update Summary Design

## Goal

Replace the Dashboard sidebar's overflowing per-library update queue with one compact summary control that opens the Items section.

## Problem

The sidebar is constrained to 150–190 points. Its footer currently creates one rounded button per outdated item, gives each button a minimum width of 130 points, and lets the title keep its intrinsic width. Long names plus version transitions can therefore push beyond the sidebar bounds. The repeated bordered buttons also compete visually with primary navigation.

The Items section now owns row-level and multi-select update actions. Repeating individual update rows in the sidebar no longer provides a distinct workflow.

## Interface

When updates are available, the sidebar footer displays one full-width summary control:

- update system icon;
- primary text: `Updates available`;
- secondary text: `<count> items · Open Items`.

The control uses the sidebar's internal width after 10-point horizontal insets. It has one fixed-height, two-line label and never derives its width from library names or version strings. The footer contains no per-item buttons and no overflow label.

When the update count is zero, the footer remains hidden.

## Interaction

Clicking the summary control selects the Dashboard's Items section. It does not start an update, select an item, or open a second window.

The control remains visible while other Dashboard sections are selected. Its count updates from the existing `SidebarUpdateQueue` snapshot.

## Architecture

`SidebarUpdateQueueModel` remains unchanged. The presentation layer needs only its `count` and `isVisible` values, but retaining the model avoids unrelated data-flow changes.

`DashboardSidebarViewController` replaces `onUpdateSelected: (String) -> Void` with `onOpenItems: () -> Void`. `renderUpdateQueue()` creates one summary button and constrains it to the `queueContainer` width.

`DashboardPanelController` handles `onOpenItems` by selecting `.items`. The callback remains navigation-only; update execution stays inside the Items section and the existing action coordinator.

## Visual Rules

- The summary control is the only footer action.
- It uses a system update icon and native AppKit colors.
- Primary and secondary text fit within a 150-point sidebar without horizontal scrolling.
- Long item names and version changes never enter the sidebar layout.
- The control keeps a clear visual separation from the source-list navigation without appearing as a stack of primary buttons.

## Accessibility

The control exposes `Open Items, <count> updates available` as its accessibility label and `Shows the Items section without starting an update` as accessibility help.

It is reachable through normal keyboard traversal and exposes one action regardless of the number of outdated items.

## Testing

Tests verify:

- a zero-count queue hides the footer;
- a nonzero queue renders exactly one summary button;
- the summary button label contains the current count;
- clicking the summary emits one `onOpenItems` callback;
- the Dashboard callback selects `.items` without invoking update execution;
- the summary button is constrained to the footer width and has no minimum width that can exceed the sidebar;
- per-item queue buttons and the `and N more` label are absent;
- accessibility label and help match the navigation-only behavior;
- the full Swift suite and macOS app target build pass;
- manual QA at both 150-point and 190-point sidebar widths shows no clipping or horizontal overflow.

## Non-Goals

- Changing update eligibility or execution.
- Changing the Items table.
- Removing item data from `SidebarUpdateQueue`.
- Adding a popover, disclosure animation, or inline update action.
- Changing the overall Dashboard sidebar width.

## Success Criteria

- The footer never extends outside the sidebar.
- The sidebar shows one calm update summary instead of a library list.
- Clicking the summary always opens Items and never starts an update.
