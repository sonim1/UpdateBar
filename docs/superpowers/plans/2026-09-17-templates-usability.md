# Templates Usability Implementation Plan

Goal: visible prompt previews and a compact, readable native Templates workflow.
Architecture: preserve catalog and controller; full-width category stacks with
one expanded editor, correctly sized NSTextView documents and labeled copy actions.
Tech stack: Swift6, AppKit, existing XCTest suite; no new dependency.

1. Reproduce blank preview with actual app and XCTest geometry.
   Capture frame/container bounds before and after width tracking correction.
2. Add regression tests in TemplatesViewControllerTests.swift for visible
   preview geometry, collapse/value persistence, filter scroll reset and copy text.
   Run `swift test --filter TemplatesViewControllerTests` and retain the red result.
3. Update TemplatesViewController.swift to replace two-column grids with
   vertical stacks, move filter below header, show one editor using disclosure,
   bind preview width to its clip view, and label copy feedback. Preserve IDs and
   catalog strings. Expand cards in geometry tests before inspecting hidden fields.
4. Run focused tests and manually use actual AppKit at both window sizes,
   all categories, six expanded prompts, both appearances and keyboard/copy flows.
   Add fresh screenshots and runtime evidence. Update docs/menu-bar.md and changelog.
5. Run full quality gate and independent source/runtime/visual reviews.
   Commit/push/merge within existing authorization, deploy app and verify installed
   version, then remove this task's worktree/branch and debug artifacts.

Execution evidence and completion state are retained under `.omo/evidence/templates-usability`.
