# Scan Count Card Labels Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the number-only Scan & Add summary badges with the approved left-aligned, two-line `Discovered`, `Enabled`, and `Disabled` cards while preserving their data flow and single-element accessibility behavior.

**Architecture:** Keep `DashboardPresentationModel.scanCounts(...)` and `ScanViewController.updateControls()` unchanged. Convert `ScanCountBadgeView` from one `NSTextField` into one accessible `NSView` containing an accessibility-hidden vertical stack with a title label and a numeric value label; constraints encode the approved 48-point height, 12-point horizontal inset, and 2-point internal gap.

**Tech Stack:** Swift 6, AppKit (`NSView`, `NSTextField`, `NSStackView`, Auto Layout), XCTest, existing UpdateBar packaging and menu-bar smoke scripts.

**Design reference:** `docs/superpowers/specs/2026-07-22-scan-count-card-labels-design.md`

---

### Task 1: Replace the obsolete single-field badge tests with the approved card contract

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/ScanCountAccessibilityTests.swift:8-110`
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift:218-240`
- Verify unchanged: `Sources/UpdateBarMenuBar/DashboardPresentationModel.swift:109-130`
- Verify unchanged: `Tests/UpdateBarMenuBarTests/DashboardPresentationModelTests.swift:80-96`

- [ ] **Step 1: Rewrite the loaded-view test around visible titles and leaf accessibility**

Replace `testLoadedScanViewExposesThreeDirectLeafCountBadges()` with:

```swift
func testLoadedScanViewExposesThreeLabeledLeafCountCards() throws {
    let controller = ScanViewController(
        service: CoreMenuBarService(),
        onChanged: {}
    )
    _ = controller.view
    controller.view.layoutSubtreeIfNeeded()

    let cards = descendants(of: ScanCountBadgeView.self, in: controller.view)
    XCTAssertEqual(cards.count, 3)
    XCTAssertTrue(cards.allSatisfy { $0.superview is NSStackView })
    XCTAssertEqual(
        cards.map { descendants(of: NSTextField.self, in: $0).map(\.stringValue) },
        [
            ["Discovered", "0"],
            ["Enabled", "0"],
            ["Disabled", "0"],
        ]
    )
    XCTAssertTrue(
        cards.allSatisfy {
            descendants(of: NSTextField.self, in: $0)
                .allSatisfy { !$0.isAccessibilityElement() }
        }
    )
    XCTAssertTrue(
        cards.allSatisfy {
            descendants(of: NSStackView.self, in: $0)
                .allSatisfy { !$0.isAccessibilityElement() }
        }
    )
    XCTAssertTrue(cards.allSatisfy { ($0.accessibilityChildren() ?? []).isEmpty })
    XCTAssertEqual(cards.filter { $0.isAccessibilityElement() }.count, 3)
    XCTAssertEqual(
        cards.compactMap { $0.accessibilityLabel() },
        ["Discovered", "Enabled", "Disabled"]
    )
    XCTAssertEqual(cards.compactMap { $0.accessibilityValue() }, ["0", "0", "0"])

    let expectedHelp = DashboardPresentationModel()
        .scanCounts(discovered: 0, enabled: 0, disabled: 0)
        .map(\.help)
    XCTAssertEqual(cards.compactMap { $0.accessibilityHelp() }, expectedHelp)
}
```

- [ ] **Step 2: Replace the update test with layout, styling, and state assertions**

Replace `testBadgeUpdateKeepsVisibleAndAccessibilityValuesCurrent()` with:

```swift
func testCardUsesApprovedLayoutAndUpdatesVisibleAndAccessibleContent() throws {
    let model = DashboardPresentationModel()
    let card = ScanCountBadgeView(
        frame: NSRect(x: 0, y: 0, width: 180, height: 48)
    )
    let stack = try XCTUnwrap(descendants(of: NSStackView.self, in: card).first)
    let fields = descendants(of: NSTextField.self, in: card)
    XCTAssertEqual(fields.count, 2)

    let titleLabel = fields[0]
    let valueLabel = fields[1]
    XCTAssertEqual(stack.orientation, .vertical)
    XCTAssertEqual(stack.alignment, .leading)
    XCTAssertEqual(stack.spacing, 2)
    XCTAssertEqual(titleLabel.alignment, .left)
    XCTAssertEqual(valueLabel.alignment, .left)
    XCTAssertEqual(titleLabel.font, .systemFont(ofSize: 11, weight: .medium))
    XCTAssertEqual(titleLabel.textColor, .secondaryLabelColor)
    XCTAssertEqual(
        valueLabel.font,
        .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
    )
    XCTAssertEqual(valueLabel.textColor, .labelColor)
    XCTAssertTrue(card.wantsLayer)
    XCTAssertEqual(card.layer?.cornerRadius, 6)
    XCTAssertEqual(card.layer?.backgroundColor, NSColor.controlBackgroundColor.cgColor)
    XCTAssertTrue(card.isAccessibilityElement())
    XCTAssertEqual(card.accessibilityRole(), .staticText)
    XCTAssertFalse(titleLabel.isAccessibilityElement())
    XCTAssertFalse(valueLabel.isAccessibilityElement())
    XCTAssertFalse(stack.isAccessibilityElement())
    XCTAssertTrue(
        card.constraints.contains {
            $0.firstAttribute == .height && $0.relation == .equal && $0.constant == 48
        }
    )
    XCTAssertTrue(
        card.constraints.contains {
            $0.firstItem === stack && $0.firstAttribute == .leading && $0.constant == 12
        }
    )
    XCTAssertTrue(
        card.constraints.contains {
            $0.firstItem === stack && $0.firstAttribute == .trailing && $0.constant == -12
        }
    )
    XCTAssertTrue(
        card.constraints.contains {
            $0.firstItem === stack && $0.firstAttribute == .centerY && $0.constant == 0
        }
    )

    let initial = try XCTUnwrap(
        model.scanCounts(discovered: 32, enabled: 1, disabled: 0).first
    )
    card.apply(initial)
    card.layoutSubtreeIfNeeded()

    XCTAssertEqual(titleLabel.stringValue, "Discovered")
    XCTAssertEqual(valueLabel.stringValue, "32")
    XCTAssertEqual(titleLabel.frame.minX, valueLabel.frame.minX, accuracy: 0.5)
    XCTAssertEqual(card.accessibilityLabel(), "Discovered")
    XCTAssertEqual(card.accessibilityValue(), "32")
    XCTAssertEqual(card.accessibilityHelp(), initial.help)
    XCTAssertEqual(card.toolTip, initial.help)

    let updated = try XCTUnwrap(
        model.scanCounts(discovered: 7, enabled: 1, disabled: 0).first
    )
    card.apply(updated)

    XCTAssertEqual(titleLabel.stringValue, "Discovered")
    XCTAssertEqual(valueLabel.stringValue, "7")
    XCTAssertEqual(card.accessibilityLabel(), "Discovered")
    XCTAssertEqual(card.accessibilityValue(), "7")
    XCTAssertEqual(card.accessibilityHelp(), updated.help)
    XCTAssertEqual(card.toolTip, updated.help)
}
```

If AppKit reports the leading/trailing constraints with the card as the first item, make the assertion accept the mathematically equivalent reversed relation. Do not weaken it to a source-string-only assertion.

- [ ] **Step 3: Update the source-hygiene contract to require the composite view**

Replace the obsolete badge assertions at lines 222-226 with:

```swift
XCTAssertTrue(scan.contains("final class ScanCountBadgeView: NSView"))
XCTAssertTrue(scan.contains("private let titleLabel"))
XCTAssertTrue(scan.contains("private let valueLabel"))
XCTAssertTrue(scan.contains("private let contentStack"))
XCTAssertTrue(scan.contains("addSubview(contentStack)"))
XCTAssertTrue(scan.contains("badge.apply(count)"))
XCTAssertTrue(scan.contains("setAccessibilityElement(true)"))
```

Keep the assertions at lines 238-240 that forbid hard-coded `Discovered`, `Enabled`, and `Disabled` construction in the controller. The visible titles must continue to come from `DashboardScanCountPresentation.accessibilityLabel`.

- [ ] **Step 4: Run the focused tests and confirm the intended RED state**

Run:

```bash
rtk test swift test --filter ScanCountAccessibilityTests
rtk test swift test --filter SourceHygieneTests/testDashboardSectionsUseCompactCopyWithAccessibleHelp
```

Expected: both focused commands fail because `ScanCountBadgeView` is still an `NSTextField`, has no two-field content stack, and violates the newly updated source contract. Record the failure reason before editing production code.

### Task 2: Implement the two-line scan count card

**Files:**
- Modify: `Sources/UpdateBarMenuBarApp/ScanViewController.swift:32-65`
- Test: `Tests/UpdateBarMenuBarTests/ScanCountAccessibilityTests.swift`
- Test: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`

- [ ] **Step 1: Replace `ScanCountBadgeView` with the minimal composite implementation**

Use this implementation, adjusting only formatting required by SwiftFormat:

```swift
final class ScanCountBadgeView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "0")
    private let contentStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .left
        titleLabel.setAccessibilityElement(false)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .left
        valueLabel.setAccessibilityElement(false)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 2
        contentStack.setAccessibilityElement(false)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(valueLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(_ count: DashboardScanCountPresentation) {
        titleLabel.stringValue = count.accessibilityLabel
        valueLabel.stringValue = count.visibleValue
        toolTip = count.help
        setAccessibilityLabel(count.accessibilityLabel)
        setAccessibilityValue(count.visibleValue)
        setAccessibilityHelp(count.help)
    }
}
```

Do not change the three stored card properties, the existing `.fillEqually` count stack, the 8-point inter-card spacing, count calculations, or `DashboardPresentationModel`.

- [ ] **Step 2: Run the focused tests and reach GREEN**

Run:

```bash
rtk test swift test --filter ScanCountAccessibilityTests
rtk test swift test --filter SourceHygieneTests/testDashboardSectionsUseCompactCopyWithAccessibleHelp
rtk test swift test --filter DashboardPresentationModelTests/testScanCountsShowIntegersWhileHelpKeepsFullMeaning
```

Expected: all focused tests pass. If the constraint ownership assertion needs its equivalent reversed form, change only the test helper/assertion—not the approved geometry.

- [ ] **Step 3: Format only the touched Swift files and rerun focused tests**

Run:

```bash
rtk proxy swiftformat Sources/UpdateBarMenuBarApp/ScanViewController.swift Tests/UpdateBarMenuBarTests/ScanCountAccessibilityTests.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk test swift test --filter ScanCountAccessibilityTests
rtk test swift test --filter SourceHygieneTests/testDashboardSectionsUseCompactCopyWithAccessibleHelp
```

Expected: formatting exits 0 and both focused tests stay green.

- [ ] **Step 4: Review the surgical diff and commit the implementation**

Run:

```bash
rtk git diff --check
rtk git diff -- Sources/UpdateBarMenuBarApp/ScanViewController.swift Tests/UpdateBarMenuBarTests/ScanCountAccessibilityTests.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk git add Sources/UpdateBarMenuBarApp/ScanViewController.swift Tests/UpdateBarMenuBarTests/ScanCountAccessibilityTests.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk git commit -m "feat: label scan count cards"
```

Expected: every changed production line maps to the approved card composition, and the commit contains only the three listed files.

### Task 3: Run repository verification and package a signed local bundle

**Files:**
- Verify: entire repository
- Generate outside git: `dist/UpdateBar.app`

- [ ] **Step 1: Run the complete quality gate**

Run:

```bash
rtk test bash Scripts/quality-gate.sh
```

Expected: exit 0 with Swift tests, formatting/lint contracts, CLI checks, script tests, archive checks, and app packaging contracts green.

- [ ] **Step 2: Package and smoke-test the application**

Run:

```bash
rtk test env UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh
rtk test bash Scripts/menubar-smoke-test.sh dist/UpdateBar.app
```

Expected: both commands exit 0 and `dist/UpdateBar.app` launches through the existing smoke harness.

- [ ] **Step 3: Seal the local bundle with an inside-out ad-hoc signature**

Run:

```bash
rtk proxy codesign --force --sign - dist/UpdateBar.app/Contents/Resources/updatebar
rtk proxy codesign --force --sign - dist/UpdateBar.app/Contents/MacOS/UpdateBar
rtk proxy codesign --force --sign - dist/UpdateBar.app
rtk proxy codesign --verify --deep --strict --verbose=2 dist/UpdateBar.app
```

Expected: the app is valid on disk and satisfies its designated requirement.

### Task 4: Replace the installed app recoverably and inspect the real dashboard

**Files:**
- Install: `/Applications/UpdateBar.app`
- Preserve: `/Applications/UpdateBar.app.backup-0.5.0-pre-scan-count-labels`
- Capture outside git: `/tmp/updatebar-scan-count-labels-light.png`
- Capture outside git: `/tmp/updatebar-scan-count-labels-dark.png`

- [ ] **Step 1: Stage and verify the new app without overwriting existing paths**

Run:

```bash
rtk proxy test ! -e /Applications/UpdateBar.app.new
rtk proxy test ! -e /Applications/UpdateBar.app.backup-0.5.0-pre-scan-count-labels
rtk proxy cp -R dist/UpdateBar.app /Applications/UpdateBar.app.new
rtk proxy codesign --verify --deep --strict --verbose=2 /Applications/UpdateBar.app.new
```

Expected: the staged bundle passes strict verification and neither staging nor backup path existed beforehand.

- [ ] **Step 2: Stop UpdateBar and replace the bundle with rollback protection**

Run:

```bash
rtk proxy pkill -x UpdateBar || true
rtk proxy mv /Applications/UpdateBar.app /Applications/UpdateBar.app.backup-0.5.0-pre-scan-count-labels
if ! rtk proxy mv /Applications/UpdateBar.app.new /Applications/UpdateBar.app; then
  rtk proxy mv /Applications/UpdateBar.app.backup-0.5.0-pre-scan-count-labels /Applications/UpdateBar.app
  exit 1
fi
```

Expected: the previous installation remains recoverable under the backup path; a failed second move restores it automatically.

- [ ] **Step 3: Verify and launch the installed app**

Run:

```bash
rtk proxy codesign --verify --deep --strict --verbose=2 /Applications/UpdateBar.app
rtk test bash Scripts/menubar-smoke-test.sh /Applications/UpdateBar.app
rtk proxy open /Applications/UpdateBar.app
for attempt in {1..10}; do
  if rtk proxy pgrep -x UpdateBar >/dev/null; then break; fi
  rtk proxy sleep 1
done
rtk proxy pgrep -x UpdateBar
rtk proxy ps ax -o pid=,command= | rtk proxy rg '/Applications/UpdateBar\.app/Contents/MacOS/UpdateBar'
```

Expected: signature and smoke checks pass, and the live process runs from `/Applications/UpdateBar.app`.

- [ ] **Step 4: Capture and inspect the real Scan & Add dashboard in light appearance**

Open Dashboard → Scan & Add in the installed app and capture `/tmp/updatebar-scan-count-labels-light.png`. Confirm:

- `Discovered`, `Enabled`, and `Disabled` appear above their corresponding values.
- all three title/value pairs are left aligned with equal internal leading insets;
- single- and multi-digit values share the same left edge and use tabular digits;
- all cards remain equal width and visually centered as a row;
- the 48-point card height does not collide with the table or controls.

Expected: the screenshot matches approved option C. If any criterion fails, retain the screenshot as evidence and return to Task 1 or 2 instead of declaring completion.

- [ ] **Step 5: Capture and inspect the same dashboard in dark appearance**

Switch macOS appearance to dark, reopen the same dashboard state, and capture `/tmp/updatebar-scan-count-labels-dark.png`. Confirm the title uses the secondary label color, the value uses the primary label color, and the retained control-background card remains readable without custom hard-coded colors. Restore the user's original appearance afterward.

Expected: both screenshots show native readable contrast and identical geometry.

### Task 5: Verify the branch and hand off integration

**Files:**
- Verify: branch history and worktree state

- [ ] **Step 1: Run completion verification before making any success claim**

Use `superpowers:verification-before-completion`, then run its selected current checks. At minimum repeat:

```bash
rtk test swift test --filter ScanCountAccessibilityTests
rtk git diff --check
rtk git status --short
```

Expected: tests and whitespace checks pass; only intentional non-source artifacts, if any, remain outside git.

- [ ] **Step 2: Confirm branch scope**

Run:

```bash
rtk git log --oneline main..HEAD
rtk git diff main...HEAD --stat
```

Expected: the branch contains the plan plus the focused card implementation/test commit, without changes to `DashboardPresentationModel`, scanning behavior, packaging scripts, or unrelated dashboard sections.

- [ ] **Step 3: Invoke the branch-finishing workflow**

Use `superpowers:finishing-a-development-branch`, repeat its required verification, determine the current base branch, and present its four integration options. Do not merge, push, or discard without the user's explicit selection.
