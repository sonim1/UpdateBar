# UpdateBar Settings And About Sidebar Design

## Goal

Keep the information-rich native menu-bar menu, while making the windowed UI
match SwitchTab's readable visual language. The existing Dashboard remains the
home for UpdateBar statistics. A reusable sidebar window adds Settings and
About destinations, and uses spare sidebar space for a compact update queue.

## Success Criteria

- One reusable UpdateBar window has an icon-and-title sidebar for `Overview`,
  `Manage Items`, `Scan & Add`, `Settings`, and `About`.
- Existing Overview, Manage Items, and Scan & Add behavior remains unchanged.
- Settings uses a clear content header, readiness state, grouped rows, and an
  Updates section for the UpdateBar app's own Sparkle checks.
- About is clean and product-focused: icon, name, version, description,
  support, and acknowledgments; it contains no usage statistics.
- Statistics remain in Overview and are not duplicated in About.
- The sidebar bottom contains an `Updates available` card with a count and a
  bounded list of outdated tracked items.
- Selecting an item in that card routes to Overview's actionable update list.
- The native menu remains information-rich and does not become a thin launcher.

## Scope

### In Scope

- Dashboard sidebar destinations and routing.
- Settings window content and visual treatment.
- About window content and actions.
- Sidebar update-queue presentation and Overview routing.
- Menu labels/actions required to reach Settings and About.
- Unit, source-contract, and manual QA coverage for the new routes.

### Out Of Scope

- Replacing the native menu-bar menu with a popover or custom menu.
- Moving Overview statistics into Settings or About.
- Adding release notes, download progress, or a custom update installer UI.
- Changing Sparkle's update presentation or signing behavior.
- Changing CLI output, manifest format, update policy, or approval semantics.
- Redesigning the existing Overview, Manage Items, or Scan & Add workflows
  beyond the shared sidebar integration.

## Information Architecture

`DashboardPanelController` remains the single reusable window owner. Its
`DashboardSidebarViewController` owns five stable sections:

1. `Overview` — existing metrics and update history.
2. `Manage Items` — existing item management table.
3. `Scan & Add` — existing manual scan flow.
4. `Settings` — UpdateBar configuration and Sparkle settings.
5. `About` — product information and support actions.

The sidebar uses the existing source-list pattern with SF Symbols, visible
titles, selected state, keyboard selection, and accessibility labels. The
content container swaps one child view controller without creating another
window. Opening any menu route selects the requested section in the same
window; closing the last titled window returns the app to accessory activation.

The existing menu-bar menu keeps its status, update, approval, error, and
installed-item sections. Its footer routes `Settings` and `About` to the
corresponding sidebar sections. The menu's item-level update actions continue
to execute immediately in the menu.

## Sidebar Update Queue

The sidebar is split vertically: navigation occupies the upper region and an
update summary occupies the lower region. The queue is derived from the latest
`MenuBarState.outdatedItems` already used to build the menu.

- Header: `Updates available` and the current count.
- Rows: at most three items, showing the redacted item name and current → latest
  versions.
- Overflow: `and N more` when more than three items are outdated.
- Empty state: the card is omitted when no updates are available.
- Click: selects `Overview`; Overview presents its existing actionable update
  section. The queue does not run an update directly, avoiding a second action
  path.
- Accessibility: the card exposes its count, each row exposes its version
  change, and the overflow exposes the hidden count.

The queue updates whenever the menu-bar state refreshes. It is presentation
only and does not add a new service call or persistence field.

## Settings Screen

Settings uses a native SwiftUI-hosted content controller inside the shared
window. The layout follows SwitchTab's compact header and grouped-row language:

- Header: UpdateBar icon/name, one-line description, and a green/yellow
  readiness pill based on current service/config state.
- `General` group: refresh interval, HTTPS-source requirement, and existing
  configuration controls with native controls and concise help text.
- `Updates` group: current app version, `Check for Updates…` action, and the
  existing automatic-check preference when Sparkle is available.
- Save/reload behavior preserves the existing Config service and redacted error
  presentation.

The app's own update action calls the existing Sparkle updater. It must not be
confused with item updates shown in Overview or the sidebar queue.

## About Screen

About uses a separate SwiftUI-hosted content controller styled after SwitchTab's
clean About panel:

- Large UpdateBar application icon.
- Product name, version, and optional build line.
- Short description emphasizing local update tracking.
- Support button opening the configured support URL.
- Acknowledgments button showing the existing dependency attribution copy.

No usage metrics, update counts, charts, or item lists appear in About. Those
belong exclusively to Overview.

## Data Flow And Errors

1. The app refreshes `latestState` as it does today.
2. `rebuildMenu()` passes the same state to the menu model and dashboard
   presentation, including the sidebar queue.
3. Selecting a sidebar row swaps the child controller on the main actor.
4. Settings loads/saves through `MenuBarServicing.loadConfig` and
   `saveConfig`; failures stay in the Settings content area and are redacted.
5. About content is generated from the app bundle and static product metadata;
missing optional values are omitted rather than shown as empty labels.
6. Queue navigation only changes selection. If Overview cannot reload, the
   existing dashboard error queue presents the redacted error.

No new background polling, persistence, or service protocol is required.

## Accessibility And Visual Rules

- Every sidebar row has an icon, visible title, selected state, and VoiceOver
  label.
- Icon-only controls have native tooltips and accessibility labels.
- Readiness pills and update counts expose text equivalents, not color alone.
- Grouped settings rows use consistent spacing, rounded containers, and native
  controls; no essential information is encoded only by color.
- About's dark or neutral presentation must preserve readable contrast and
  support Dynamic Type where the host view supports it.

## Verification

### Unit And Contract Tests

- Sidebar section cases include Settings and About and preserve existing route
  ordering.
- Menu actions route Settings and About into the shared Dashboard window.
- Queue presentation caps visible items at three, reports overflow, redacts
  names, omits the empty card, and routes a selected row to Overview.
- Settings content exposes the existing config controls and Sparkle update
  action without changing service calls.
- About content exposes version/description/support/acknowledgments and no
  statistics fields.
- Source contracts prove the native menu remains the primary menu-bar surface.

### Manual QA

- Open Settings and About from the menu, switch between all five sidebar rows,
  and confirm one window is reused.
- Confirm the sidebar queue appears only when updates exist and routes to
  Overview without executing an update.
- Change and save a setting, reload it, and verify the existing config values.
- Trigger Sparkle's app update check from Settings.
- Verify About at normal and larger text sizes, including support and
  acknowledgments actions.
- Close the window and confirm the app returns to menu-bar-only activation.

### Completion Gate

- Run targeted menu-bar tests and source-contract tests.
- Run `Scripts/quality-gate.sh`.
- Review the final diff for only sidebar/settings/about task changes.
