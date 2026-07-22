## 1. Scan state model
- [x] 1.1 Model untracked, enabled, disabled, and unavailable scan rows; unavailable means no complete recipe, a disabled checkbox, and no service call.
- [x] 1.2 Add per-row mutation gating and rollback tests.

## 2. Unified Dashboard
- [x] 2.1 Replace top tabs with native sidebar navigation.
- [x] 2.2 Embed Scan & Add and remove the standalone Scan panel.
  - Convert the existing `ScanPanelController` into reusable `ScanViewController`, reuse its table/scan behavior, then remove `NSPanel` ownership and the old source after embedding.
- [x] 2.3 Route all three native menu actions to one window.

## 3. Compact presentation
- [x] 3.1 Reduce persistent helper copy in Overview.
- [x] 3.2 Reduce persistent helper copy in Items.
- [x] 3.3 Add compact Scan counts, tooltips, and accessibility labels.

## 4. Verification
- [x] 4.1 Update source and documentation contracts.
- [x] 4.2 Run targeted tests and `rtk Scripts/quality-gate.sh`.
  - `rtk test swift test --filter ScanListModelTests` — expected pass; asserts stable untracked/enabled/disabled/unavailable mapping, including a disabled unavailable checkbox and zero service calls.
  - `rtk test swift test --filter ScanMutationGateTests` — expected pass; asserts per-ID independent-row behavior, duplicate-ID rejection, immediate target state with pending-row gating, successful target retention/refresh, and rollback on failure.
  - `rtk test swift test --filter ScanSessionGenerationGateTests` — expected pass; asserts a newer manual-scan token and window-close invalidation reject stale completions, while the current token is accepted.
  - `rtk test swift test --filter DashboardNavigationModelTests` — expected pass; asserts Dashboard/Manage Items/Scan & Add map to Overview/Items/Scan and changing the selected section creates no presentation state outside the model.
  - `rtk test swift test --filter DashboardPresentationModelTests` — expected pass; asserts compact visible values expose complete tooltip/accessibility strings for metrics, count badges, information, and refresh.
  - `rtk test swift test --filter CoreMenuBarServiceTests` — expected pass; asserts registration remains untrusted, disable preserves the same manifest recipe/approvals/state, and re-enable reuses that recipe.
  - `rtk test swift test --filter SourceHygieneTests` — expected pass as supplemental structural coverage only; asserts one window/sidebar, removed `NSPanel` and Add Selected, and actual UI binding to the accessibility text covered by `DashboardPresentationModelTests`.
  - `rtk test swift test --filter DocumentationSnapshotTests` — expected pass; covers the new OpenSpec wording and compatibility statements.
  - Manual AppKit pointer/AX QA — completed: pointer interaction and accessibility inspection verified Overview, Items, and Scan navigation, compact values and help surfaces, the active Scan spinner, and isolated immediate register → disable → re-enable behavior. This did not toggle or claim the global VoiceOver setting. Intentional failure/rollback induction was not performed for safety; automated rollback and redaction tests cover those paths.
  - `rtk swift build --product updatebar-menubar` — expected pass; covers app compilation after the controller refactor.
  - `rtk Scripts/quality-gate.sh` — expected pass; covers the full repository quality gate.
