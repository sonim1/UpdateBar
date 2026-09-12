# Native architecture

Dashboard Items receives the same MenuBarPopoverModel snapshot as the menu popover after each status, approval, action and progress change. Its presentation model owns only status grouping, search, explicit selection and disclosures. ManageItemsViewController hosts native SwiftUI and invokes the existing MenuBarPopoverActions callbacks. CoreMenuBarService and MenuBarActionCoordinator remain the execution/approval boundary.

The old independent Items cache reload is removed so stale Dashboard status cannot overwrite current menu eligibility. Overview, Logs and Scan retain the generation-guarded Dashboard reload. Enable/disable retains ManageItemsMutationGate.

Visual contract: docs/items-dashboard/DESIGN.md. The approved HTML informs interaction and hierarchy; native controls/adaptive colors are retained rather than embedding HTML. The dashboard minimum remains760×420 and default opens1000×700.
