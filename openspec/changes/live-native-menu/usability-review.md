# Native menu usability review

Reviewed from the perspective of a Mac developer checking and following several
approved tool updates. Preserve the standard NSMenu, readable labels, template
SF Symbols, system selection, and native keyboard navigation.

| Finding | User impact | Improvement | Evidence |
| --- | --- | --- | --- |
| Starting work inserted an extra progress header, stop row, and separator above the existing summary. | Check, refresh, and navigation moved three positions during work. | Reuse the summary row and place Stop After Current in Update All's slot. | `testMenuCommandsStayInPlaceWhenAnUpdateStartsOrStops` |
| Check and approval work displayed `(0/0)` alongside an idle status. | Work appeared broken or already complete. | Show one active summary and only show a counter when a nonempty update plan exists. | `testCheckingDoesNotShowAnEmptyCounterOrContradictoryIdleSummary` |
| Only six update/error rows were reachable; overflow was disabled text. | A running seventh or later update could not be inspected. | Keep the root concise with native More Updates/More Errors submenus in stable name order. | `testOverflowKeepsRunningUpdatesReachableWithoutReorderingTheList`, `testBuildsCompactMenuWithReachableOverflowSubmenus` |
| Stop After Current was offered for checks and the CLI adapter, which do not consume the cooperative update stop signal. | The control promised behavior unavailable for that operation. | Pass the actual stop capability from the app and retain the disabled Update All row when unsupported. | Check-mode assertions and app capability routing |

Existing native tests also verify in-place updates during actual menu tracking,
unchanged submenu/history view identity, and current action payloads after refresh.
The focused model/native/source checks passed: 58 tests, zero failures.
Independent code review approved the production changes; the brittle new
source-text pins identified in review were removed in favor of the existing
behavioral coverage.

Final verification on 2026-10-29: `Scripts/quality-gate.sh` completed with exit 0
and no skips after disk space became available. It passed 998 Swift tests,
152 TUI tests, formatting, CLI/script checks, release-mode app packaging, and
menu bar launch smoke. The final `dist/UpdateBar.app` also passed a separate
launch smoke with nine synthetic outdated recipes in an isolated
`UPDATEBAR_HOME`. AppKit successfully loaded all 22 SF Symbols used by the menu
on the local macOS system.

Visual limitation: computer-use access to the menu-bar-only QA app timed out.
No native menu screenshot, theme, or pixel-level approval is claimed. These
findings are supported by source, menu structure assertions, icon availability,
and real AppKit tracking tests.
