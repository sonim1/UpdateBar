# Dashboard LLM Prompt Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native Dashboard `Templates` section with six safe, customizable English prompts and icon-only clipboard actions.

**Architecture:** A pure `UpdateBarMenuBar` presentation model owns template metadata and prompt generation. A focused AppKit view controller owns native layout, field updates, filtering, clipboard writes, and transient copy feedback. The existing Dashboard navigation and controller switch gain one section without adding CLI or service dependencies.

**Tech Stack:** Swift 6, AppKit, XCTest, Swift Package Manager

---

## File Map

- Create `Sources/UpdateBarMenuBar/PromptTemplateModel.swift`: categories, template definitions, fields, and pure prompt builders.
- Create `Tests/UpdateBarMenuBarTests/PromptTemplateModelTests.swift`: catalog, placeholder, substitution, and safety-contract tests.
- Create `Sources/UpdateBarMenuBarApp/TemplatesViewController.swift`: native cards, filter, preview, accessibility, and pasteboard behavior.
- Create `Tests/UpdateBarMenuBarTests/TemplatesViewControllerTests.swift`: rendering, filtering, copy, persistence, and accessibility tests.
- Modify `Sources/UpdateBarMenuBar/DashboardNavigationModel.swift`: add `.templates` in stable sidebar order.
- Modify `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`: own and display `TemplatesViewController`.
- Modify `Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift`: lock section order, title, symbol, and action mappings.
- Modify `docs/menu-bar.md`: document the new Dashboard section.
- Modify `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`: assert documentation includes Templates.

### Task 1: Pure Prompt Template Catalog

**Files:**
- Create: `Tests/UpdateBarMenuBarTests/PromptTemplateModelTests.swift`
- Create: `Sources/UpdateBarMenuBar/PromptTemplateModel.swift`

- [x] **Step 1: Write failing catalog and prompt-generation tests**

Add tests that assert:

```swift
XCTAssertEqual(PromptTemplateCatalog.templates.map(\.id), [
    .inspectCLI, .checkUpdates, .addItem, .reviewApprove,
    .updateApproved, .diagnose,
])
XCTAssertEqual(Set(PromptTemplateCatalog.templates.map(\.category)),
               Set(PromptTemplateCategory.allCases))
```

Add one focused test per builder:

```swift
let add = try XCTUnwrap(PromptTemplateCatalog.template(id: .addItem))
let generic = add.prompt(values: [:])
XCTAssertTrue(generic.contains("[ITEM_NAME]"))
XCTAssertTrue(generic.contains("[SOURCE]"))
XCTAssertTrue(generic.contains("wait for my explicit confirmation"))

let filled = add.prompt(values: [.itemName: " ripgrep ", .source: "BurntSushi/ripgrep"])
XCTAssertTrue(filled.contains("ripgrep"))
XCTAssertTrue(filled.contains("BurntSushi/ripgrep"))
XCTAssertFalse(filled.contains("[ITEM_NAME]"))
XCTAssertFalse(filled.contains("[SOURCE]"))
```

Assert whitespace uses placeholders, approval names `updatebar approvals` and exact fields, update never bypasses approval, and diagnosis starts read-only and requests secret redaction.

- [x] **Step 2: Verify RED**

Run:

```bash
rtk swift test --filter PromptTemplateModelTests
```

Expected: compilation fails because `PromptTemplateCatalog` and related types do not exist.

- [x] **Step 3: Implement the minimal pure model**

Create public enums and structs:

```swift
public enum PromptTemplateCategory: String, CaseIterable, Sendable {
    case discover, configure, operate
    public var title: String { rawValue.capitalized }
}

public enum PromptTemplateID: String, CaseIterable, Sendable {
    case inspectCLI, checkUpdates, addItem, reviewApprove, updateApproved, diagnose
}

public enum PromptTemplateFieldKey: String, Sendable {
    case focus, output, itemName, source, commandField, scope, symptom
}

public struct PromptTemplateField: Equatable, Sendable {
    public let key: PromptTemplateFieldKey
    public let label: String
    public let placeholder: String
}

public struct PromptTemplateDefinition: Equatable, Sendable {
    public let id: PromptTemplateID
    public let category: PromptTemplateCategory
    public let title: String
    public let systemImageName: String
    public let summary: String
    public let boundary: String
    public let fields: [PromptTemplateField]

    public func prompt(values: [PromptTemplateFieldKey: String]) -> String
}
```

Implement `PromptTemplateCatalog.templates` in the specified order and switch on `id` inside `prompt(values:)`. Trim values once and substitute the documented placeholders. Every mutating prompt must require exact-command preview, explicit confirmation, and post-action verification.

- [x] **Step 4: Verify GREEN**

Run:

```bash
rtk swift test --filter PromptTemplateModelTests
```

Expected: all prompt model tests pass.

- [x] **Step 5: Commit the model and tests**

```bash
rtk git add Sources/UpdateBarMenuBar/PromptTemplateModel.swift Tests/UpdateBarMenuBarTests/PromptTemplateModelTests.swift
rtk git commit -m "feat: add safe LLM prompt template catalog"
```

### Task 2: Native Templates Page

**Files:**
- Create: `Tests/UpdateBarMenuBarTests/TemplatesViewControllerTests.swift`
- Create: `Sources/UpdateBarMenuBarApp/TemplatesViewController.swift`

- [x] **Step 1: Write failing AppKit behavior tests**

Instantiate the controller with an injected pasteboard writer:

```swift
var copied: String?
let controller = TemplatesViewController { value in
    copied = value
    return true
}
_ = controller.view
```

Test six visible copy buttons, three category sections, `Copy prompt for <title>` accessibility labels, exact preview-to-copy equality, input substitution, whitespace placeholder behavior, and filter changes that preserve entered values.

- [x] **Step 2: Verify RED**

Run:

```bash
rtk swift test --filter TemplatesViewControllerTests
```

Expected: compilation fails because `TemplatesViewController` does not exist.

- [x] **Step 3: Implement native view controller and card view**

Use only native AppKit controls:

```swift
final class TemplatesViewController: NSViewController {
    typealias PasteboardWriter = (String) -> Bool

    init(writeToPasteboard: @escaping PasteboardWriter = TemplatesViewController.copy)
}
```

Build a header, `NSSegmentedControl`, and scroll view containing three category stack views. Each category uses a two-column `NSGridView`; the existing Dashboard minimum width keeps cards readable. Each card owns up to two labeled `NSTextField`s, a non-editable selectable `NSTextView`, boundary label, and icon-only `NSButton` using `doc.on.doc`.

Keep card instances alive in a dictionary. Filtering hides category containers instead of recreating cards, preserving input. Field actions rebuild only that card preview. Copy writes the current preview, then briefly shows `checkmark`; failure shows `exclamationmark.triangle` and updates the accessibility label.

- [x] **Step 4: Verify GREEN and build the app target**

Run:

```bash
rtk swift test --filter TemplatesViewControllerTests
rtk swift build --product updatebar-menubar
```

Expected: tests pass and app target builds.

- [x] **Step 5: Commit the native page**

```bash
rtk git add Sources/UpdateBarMenuBarApp/TemplatesViewController.swift Tests/UpdateBarMenuBarTests/TemplatesViewControllerTests.swift
rtk git commit -m "feat: add native Dashboard templates page"
```

### Task 3: Dashboard Navigation Integration

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift`
- Modify: `Sources/UpdateBarMenuBar/DashboardNavigationModel.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`

- [x] **Step 1: Update navigation tests first**

Require this stable order:

```swift
XCTAssertEqual(DashboardSection.allCases, [
    .overview, .items, .scan, .templates, .logs, .settings, .about,
])
XCTAssertEqual(DashboardSection.allCases.map(\.title), [
    "Overview", "Items", "Scan & Add", "Templates", "Logs", "Settings", "About",
])
```

Require `DashboardSection.templates.systemImageName == "doc.on.doc"`. Existing `MenuBarMenuAction` mappings must remain unchanged.

- [x] **Step 2: Verify RED**

Run:

```bash
rtk swift test --filter DashboardNavigationModelTests
```

Expected: compilation fails because `.templates` does not exist.

- [x] **Step 3: Add the section and controller wiring**

Add `.templates` between `.scan` and `.logs`, then update title and symbol switches. Add one retained `TemplatesViewController` property to `DashboardPanelController` and return it in `controller(for:)`. Do not add menu actions, reload calls, or service dependencies.

- [x] **Step 4: Verify GREEN**

Run:

```bash
rtk swift test --filter DashboardNavigationModelTests
rtk swift test --filter DashboardSidebarViewControllerTests
```

Expected: navigation and sidebar tests pass with seven sections.

- [x] **Step 5: Commit navigation integration**

```bash
rtk git add Sources/UpdateBarMenuBar/DashboardNavigationModel.swift Sources/UpdateBarMenuBarApp/DashboardPanelController.swift Tests/UpdateBarMenuBarTests/DashboardNavigationModelTests.swift
rtk git commit -m "feat: expose templates in Dashboard navigation"
```

### Task 4: Documentation and Full Verification

**Files:**
- Modify: `docs/menu-bar.md`
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`

- [x] **Step 1: Write the failing documentation assertion**

Extend the Dashboard documentation snapshot test to require `Templates`, all three category names, and language explaining that templates copy prompts but do not execute commands.

- [x] **Step 2: Verify RED**

Run:

```bash
rtk swift test --filter DocumentationSnapshotTests/testMenuBarDocsDescribeCurrentNativeMenuAndUnifiedDashboardWindow
```

Expected: failure because the current menu-bar documentation does not mention Templates.

- [x] **Step 3: Update Dashboard documentation**

Document the sidebar placement, six built-in English prompts, card-specific fields, copy icon, confirmation boundaries, and the fact that the page performs no CLI or LLM action.

- [x] **Step 4: Verify documentation and formatting**

Run:

```bash
rtk swift test --filter DocumentationSnapshotTests/testMenuBarDocsDescribeCurrentNativeMenuAndUnifiedDashboardWindow
rtk xcrun swift-format lint --strict --recursive Sources Tests Package.swift
```

Expected: documentation test and Swift formatting lint pass.

- [x] **Step 5: Run fresh full verification**

Run:

```bash
rtk swift test
rtk swift build -c release --product updatebar-menubar
rtk git diff --check
```

Expected: all tests pass, release app builds, and diff check is clean.

- [x] **Step 6: Commit documentation**

```bash
rtk git add docs/menu-bar.md Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift docs/superpowers/plans/2026-08-23-dashboard-llm-prompt-templates.md
rtk git commit -m "docs: document Dashboard prompt templates"
```

- [x] **Step 7: Perform native visual QA**

Launch the built app against an isolated temporary UpdateBar home, open Dashboard → Templates, and verify source-list placement, card layout, category filtering, field updates, keyboard focus, copy icon feedback, tooltip, and VoiceOver labels. Record screenshots for pre-landing evidence without committing generated QA artifacts.

- [x] **Step 8: Complete pre-landing review and hand off to ship/deploy workflows**

Run the required code review workflow, resolve all critical and important findings, then run `/ship`. After the PR passes CI, run `/land-and-deploy`, merge it, monitor the release workflow, and verify the published signed macOS release or deployment artifact according to the repository release configuration.
