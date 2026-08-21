# Sidebar Update Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Dashboard sidebar's overflowing per-item update buttons with one width-safe summary control that opens Items.

**Architecture:** Keep `SidebarUpdateQueueModel` unchanged and simplify only the AppKit presentation. `DashboardSidebarViewController` emits a navigation-only callback, and `DashboardPanelController` maps it to `.items`.

**Tech Stack:** Swift 6, AppKit, Swift Package Manager, XCTest, Orca computer-use QA.

---

## File Structure

- Modify `Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift`: verify one summary control, width safety, visibility, accessibility, and callback behavior.
- Modify `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`: lock down Dashboard-to-Items wiring and removal of per-item footer controls.
- Modify `Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift`: render one summary control and emit `onOpenItems`.
- Modify `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`: navigate to `.items` from the footer callback.
- Modify `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`: require current sidebar documentation.
- Modify `docs/menu-bar.md`: describe the summary-only footer.

### Task 1: Render one width-safe update summary

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift`

- [ ] **Step 1: Write failing summary rendering tests**

Add a recursive button helper and these tests:

```swift
func testUpdateQueueRendersOneBoundedSummaryButton() throws {
    let controller = DashboardSidebarViewController()
    _ = controller.view
    controller.view.frame = NSRect(x: 0, y: 0, width: 150, height: 420)
    controller.apply(
        updateQueue: SidebarUpdateQueue(
            count: 12,
            items: [
                SidebarUpdateQueueItem(
                    id: "long",
                    title: "A Library Name That Must Never Control Sidebar Width",
                    versionChange: "123.456.789 → 987.654.321"
                )
            ],
            overflowCount: 11
        )
    )
    controller.view.layoutSubtreeIfNeeded()

    let button = try XCTUnwrap(
        findButtons(in: controller.view).first {
            $0.identifier?.rawValue == "sidebar-updates-summary"
        }
    )
    XCTAssertEqual(findButtons(in: controller.view).filter {
        $0.identifier?.rawValue == "sidebar-updates-summary"
    }.count, 1)
    XCTAssertEqual(button.attributedTitle.string, "Updates available\n12 items · Open Items")
    XCTAssertLessThanOrEqual(button.frame.maxX, try XCTUnwrap(button.superview).bounds.maxX)
    XCTAssertGreaterThanOrEqual(button.frame.minX, 0)
    XCTAssertEqual(button.accessibilityLabel(), "Open Items, 12 updates available")
    XCTAssertEqual(
        button.accessibilityHelp(),
        "Shows the Items section without starting an update"
    )
}

func testEmptyUpdateQueueRendersNoSummaryButton() {
    let controller = DashboardSidebarViewController()
    _ = controller.view

    controller.apply(updateQueue: SidebarUpdateQueue(count: 0, items: [], overflowCount: 0))

    XCTAssertFalse(findButtons(in: controller.view).contains {
        $0.identifier?.rawValue == "sidebar-updates-summary"
    })
}
```

Use this helper:

```swift
private func findButtons(in view: NSView) -> [NSButton] {
    var result = view as? NSButton == nil ? [] : [view as! NSButton]
    for subview in view.subviews {
        result.append(contentsOf: findButtons(in: subview))
    }
    return result
}
```

- [ ] **Step 2: Write a failing callback test**

Replace the ID callback test with:

```swift
func testUpdateSummaryRoutesToItemsWithoutUpdating() throws {
    let controller = DashboardSidebarViewController()
    _ = controller.view
    var openCount = 0
    controller.onOpenItems = { openCount += 1 }
    controller.apply(
        updateQueue: SidebarUpdateQueue(
            count: 2,
            items: [SidebarUpdateQueueItem(id: "brew", title: "Homebrew", versionChange: "1 → 2")],
            overflowCount: 1
        )
    )
    let button = try XCTUnwrap(findButtons(in: controller.view).first {
        $0.identifier?.rawValue == "sidebar-updates-summary"
    })

    button.performClick(nil)

    XCTAssertEqual(openCount, 1)
}
```

- [ ] **Step 3: Run focused tests and verify RED**

Run: `rtk test swift test --filter DashboardSidebarViewControllerTests`

Expected: compilation fails because `onOpenItems` and `sidebar-updates-summary` do not exist.

- [ ] **Step 4: Implement the single summary control**

Replace `onUpdateSelected` with:

```swift
var onOpenItems: () -> Void = {}
```

After clearing arranged subviews and checking `updateQueue.isVisible`, create one button:

```swift
let button = NSButton(title: "", target: self, action: #selector(openItems))
button.identifier = NSUserInterfaceItemIdentifier("sidebar-updates-summary")
button.bezelStyle = .rounded
button.alignment = .left
button.image = NSImage(
    systemSymbolName: "arrow.down.circle.fill",
    accessibilityDescription: nil
)
button.imagePosition = .imageLeading
button.contentTintColor = .controlAccentColor
button.attributedTitle = summaryTitle(count: updateQueue.count)
button.setAccessibilityLabel("Open Items, \(updateQueue.count) updates available")
button.setAccessibilityHelp("Shows the Items section without starting an update")
button.translatesAutoresizingMaskIntoConstraints = false
queueContainer.addArrangedSubview(button)
NSLayoutConstraint.activate([
    button.widthAnchor.constraint(equalTo: queueContainer.widthAnchor, constant: -20),
    button.heightAnchor.constraint(equalToConstant: 48),
])
```

Build the title without item names:

```swift
private func summaryTitle(count: Int) -> NSAttributedString {
    let title = NSMutableAttributedString(
        string: "Updates available\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
    )
    title.append(NSAttributedString(
        string: "\(count) items · Open Items",
        attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    ))
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
    return title
}

@objc private func openItems() {
    onOpenItems()
}
```

Delete the header, per-item button loop, overflow label, `selectUpdate(id:)`, and ID-based selector.

- [ ] **Step 5: Run focused tests and build**

Run: `rtk test swift test --filter DashboardSidebarViewControllerTests`

Run: `rtk test swift build --target UpdateBarMenuBarApp`

Expected: tests and build exit 0.

- [ ] **Step 6: Commit**

```bash
rtk git add Sources/UpdateBarMenuBarApp/DashboardSidebarViewController.swift Tests/UpdateBarMenuBarTests/DashboardSidebarViewControllerTests.swift
rtk git commit -m "fix: contain sidebar update summary"
```

### Task 2: Route the summary to Items

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`
- Modify: `Sources/UpdateBarMenuBarApp/DashboardPanelController.swift`

- [ ] **Step 1: Write failing wiring contracts**

Update the existing Dashboard source contract:

```swift
XCTAssertTrue(sidebarSource.contains("var onOpenItems: () -> Void"))
XCTAssertFalse(sidebarSource.contains("onUpdateSelected"))
XCTAssertFalse(sidebarSource.contains("and \\(updateQueue.overflowCount) more"))
XCTAssertTrue(dashboardSource.contains("sidebarViewController.onOpenItems ="))
XCTAssertTrue(dashboardCompact.contains("self?.select(.items)"))
```

Remove the old assertion that forbids `onOpenItems`.

- [ ] **Step 2: Run the contract and verify RED**

Run: `rtk test swift test --filter SourceHygieneTests/testDashboardUsesOneSidebarWindowWithThreeEmbeddedSections`

Expected: Dashboard wiring assertions fail because the controller still uses the ID callback and selects Overview.

- [ ] **Step 3: Wire navigation to Items**

Replace the current callback:

```swift
sidebarViewController.onOpenItems = { [weak self] in
    self?.select(.items)
}
```

Do not call update service methods from this closure.

- [ ] **Step 4: Run focused tests and build**

Run: `rtk test swift test --filter SourceHygieneTests/testDashboardUsesOneSidebarWindowWithThreeEmbeddedSections`

Run: `rtk test swift build --target UpdateBarMenuBarApp`

Expected: tests and build exit 0.

- [ ] **Step 5: Commit**

```bash
rtk git add Sources/UpdateBarMenuBarApp/DashboardPanelController.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk git commit -m "fix: open Items from sidebar updates"
```

### Task 3: Document and verify the finished footer

**Files:**
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`
- Modify: `docs/menu-bar.md`

- [ ] **Step 1: Write a failing documentation assertion**

Add to the unified Dashboard documentation test:

```swift
XCTAssertTrue(normalizedDocs.contains("single update summary"))
XCTAssertTrue(normalizedDocs.contains("opens Items without starting an update"))
```

- [ ] **Step 2: Run the documentation test and verify RED**

Run: `rtk test swift test --filter DocumentationSnapshotTests/testMenuBarDocsDescribeCurrentNativeMenuAndUnifiedDashboardWindow`

Expected: the two new assertions fail.

- [ ] **Step 3: Replace stale sidebar documentation**

Use this wording:

```markdown
The sidebar footer shows a single update summary when updates are available. It stays within the sidebar width and opens Items without starting an update; individual names, versions, and update actions live in Items.
```

- [ ] **Step 4: Run automated verification**

Run: `rtk test swift test`

Run: `rtk test swift build --target UpdateBarMenuBarApp`

Run: `rtk test bash Scripts/app-icon-test.sh`

Run: `rtk git diff --check`

Expected: every command exits 0.

- [ ] **Step 5: Run visual QA**

Package and launch an isolated unsigned app. Open Dashboard at sidebar widths 150 and 190 points. Verify:

- exactly one footer summary appears for nonzero updates;
- no library name or version string appears in the sidebar;
- button bounds stay inside the footer at both widths;
- click selects Items and starts no update;
- zero updates hide the footer;
- accessibility tree exposes one `Open Items, N updates available` button.

- [ ] **Step 6: Commit**

```bash
rtk git add docs/menu-bar.md Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift
rtk git commit -m "docs: describe sidebar update summary"
```

- [ ] **Step 7: Final branch audit**

Run: `rtk git status --short --branch`

Run: `rtk git log --oneline --decorate -8`

Expected: clean feature branch with the plan and focused implementation commits.
