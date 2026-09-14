# UpdateBar Items dashboard

## Intent

Open Items and immediately see what can run. The approved HTML prototype is the interaction reference; the shipped screen uses SwiftUI inside the existing AppKit Dashboard. The Dashboard sidebar, existing menu-bar design system, and MenuBarPopoverModel remain authoritative.

Replace the seven-column table with vertical status groups. Provider categories stay quiet metadata. Ready cards support whole-list or selected updates; review and attention remain visible below them. Current and paused tools are collapsed initially. Each item belongs to exactly one section.

## Native visual system

Use system adaptive colors, system typography, SF Symbols, and native controls. Blue indicates action/selection, orange review, red attention, and green current status. Text and icons carry meaning independently of color. Monograms identify tools without external assets.

Keep the existing sidebar and window. The default content size is 1000×700 with a 760×420 minimum. Ready cards use an adaptive grid with a 310-point minimum column width. The fixed toolbar sits above one vertical content scroll area. The five status sections use an eager stack so filtering and changing section heights do not trigger lazy scroll-placement loops; the ready grid remains lazy. Compact rows contain non-ready items. Use 6/12/20/24-point layout spacing, 10-point card corners, tonal fills, and thin separators. Long names and commands wrap.

## Actions and state

- Ready to update: approved eligible tools, selectable cards, current → available version, and Details.
- Needs review: command approval or a pending post-approval check. Review opens exact command details.
- Needs attention: check failures or other unresolved status.
- Up to date: collapsed current tools.
- Paused: collapsed disabled or pinned tools; details retain tracking controls.

Selection starts empty and the primary action reads Update all with the eligible count. Selecting cards changes it to Update selected. Searching clears selection and scopes the unselected action to visible eligible results, labeled Update visible. Reconcile selection against current IDs, versions, and approval eligibility. Disable execution when busy, mutating tracking state, or without eligible targets.

The batch summary and individual phases use the existing action coordinator. Stop after current finishes in-flight work and leaves queued tools untouched. Retry failed uses the canonical retry set. The CLI-backed fallback shows indeterminate progress and omits unsupported stopping.

Command review shows the exact command and working directory with existing secret redaction. Acknowledgement is required before approval. Approval never starts an update; Check Now refreshes status separately. Identity changes invalidate acknowledgement. Tracking changes retain the existing mutation gate until the shared snapshot arrives.

## Integration and verification

Reuse MenuBarPopoverModel for eligibility, approvals, acknowledgement, progress, stop, and retry. Dashboard-local state is limited to search, explicit selection, details, and disclosure. Overview and other sections retain the existing cached snapshot/history refresh flow. No dependencies, Core trust semantics, or CLI JSON contracts change.

Native buttons and checkboxes expose descriptive accessibility labels. The detail sheet supports Escape; search has a clear action for empty results. Verify real native light/dark windows, minimum-size layout, keyboard input, search and selection, exact approval, update progress, stop, retry, errors, and tracking mutations using isolated fixture commands. No prototype reset controls, simulated backend, webview, or demo failure switches ship.
