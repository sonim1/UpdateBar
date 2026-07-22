# Menu Bar Status Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generic menu bar symbol and adjacent status title with a fixed-width UpdateBar mark plus circular state badge.

**Architecture:** Add a tested status-icon value type and AppKit renderer to the existing `UpdateBarMenuBar` library so geometry and state mapping are isolated from the application delegate. The app delegate selects `checking`, `upToDate`, `updates(count:)`, or `attention`, caches the last rendered state, and keeps status detail in the accessibility label and menu rather than visible title text.

**Tech Stack:** Swift 6, AppKit (`NSImage`, `NSBezierPath`), SwiftPM, XCTest

---

## File Map

- Create `Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift`: status mapping, badge copy, and fixed-size AppKit template renderer.
- Create `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`: mapping, count cap, image sizing, and template behavior.
- Modify `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`: replace the SF Symbol and visible titles with rendered state images.
- Modify `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift`: enforce image-only integration and removal of legacy status titles.

### Task 1: Define menu bar status-icon state

**Files:**
- Create: `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`
- Create: `Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift`

- [ ] **Step 1: Write failing state-mapping tests**

Create `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`:

```swift
import AppKit
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

@MainActor
final class MenuBarStatusIconTests: XCTestCase {
    func testStateMapsCurrentUpdatesAndAttention() {
        XCTAssertEqual(makeState().statusIconState, .upToDate)
        XCTAssertEqual(makeState(outdated: 3).statusIconState, .updates(count: 3))
        XCTAssertEqual(makeState(attention: 1).statusIconState, .attention)
    }

    func testUpdatesTakeVisualPriorityOverAttention() {
        XCTAssertEqual(
            makeState(outdated: 2, attention: 1).statusIconState,
            .updates(count: 2)
        )
    }

    func testBadgeTextCapsCountsAtNinePlus() {
        XCTAssertEqual(MenuBarStatusIconState.checking.badgeText, "…")
        XCTAssertEqual(MenuBarStatusIconState.upToDate.badgeText, "✓")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 1).badgeText, "1")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 9).badgeText, "9")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 10).badgeText, "9+")
        XCTAssertEqual(MenuBarStatusIconState.attention.badgeText, "!")
    }

    private func makeState(outdated: Int = 0, attention: Int = 0) -> MenuBarState {
        MenuBarState(
            title: outdated > 0 ? "\(outdated) updates" : "Up to date",
            badgeValue: nil,
            outdatedItems: (0..<outdated).map { item(id: "old-\($0)", status: .outdated) },
            approvalItems: (0..<attention).map {
                item(id: "attention-\($0)", status: .untrusted)
            },
            errorItems: [],
            okItems: []
        )
    }

    private func item(id: String, status: ItemStatus) -> StatusItem {
        StatusItem(
            id: id,
            name: id,
            category: "cli",
            current: nil,
            latest: nil,
            status: status,
            pinned: false,
            lastChecked: nil,
            error: nil
        )
    }
}
```

- [ ] **Step 2: Run tests to verify RED**

```bash
rtk test swift test --filter MenuBarStatusIconTests
```

Expected: compilation fails because `MenuBarStatusIconState` and `statusIconState` do not exist.

- [ ] **Step 3: Implement minimal state and mapping**

Create `Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift` with the state unit first:

```swift
import AppKit

public enum MenuBarStatusIconState: Equatable, Sendable {
    case checking
    case upToDate
    case updates(count: Int)
    case attention

    public var badgeText: String {
        switch self {
        case .checking:
            "…"
        case .upToDate:
            "✓"
        case .updates(let count):
            count > 9 ? "9+" : "\(max(1, count))"
        case .attention:
            "!"
        }
    }
}

extension MenuBarState {
    public var statusIconState: MenuBarStatusIconState {
        if !outdatedItems.isEmpty {
            return .updates(count: outdatedItems.count)
        }
        if needsAttentionCount > 0 {
            return .attention
        }
        return .upToDate
    }
}
```

- [ ] **Step 4: Run state tests to verify GREEN**

```bash
rtk test swift test --filter MenuBarStatusIconTests
```

Expected: all three state tests pass.

- [ ] **Step 5: Commit the state unit**

```bash
rtk git add Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift
rtk git commit -m "feat: model menu bar status icon states"
```

### Task 2: Render the branded template image

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift`

- [ ] **Step 1: Add failing renderer tests**

Add these tests to `MenuBarStatusIconTests`:

```swift
func testRendererCreatesFixedTemplateImageForEveryState() {
    let renderer = MenuBarStatusIconRenderer()
    let states: [MenuBarStatusIconState] = [
        .checking, .upToDate, .updates(count: 1), .updates(count: 10), .attention,
    ]

    for state in states {
        let image = renderer.image(for: state)
        XCTAssertEqual(image.size, MenuBarStatusIconRenderer.imageSize)
        XCTAssertTrue(image.isTemplate)
        XCTAssertFalse(image.representations.isEmpty)
    }
}

func testAttentionUsesHeavyBadgeWeight() {
    XCTAssertEqual(MenuBarStatusIconState.attention.badgeWeight, .heavy)
    XCTAssertEqual(MenuBarStatusIconState.upToDate.badgeWeight, .bold)
}
```

- [ ] **Step 2: Run renderer tests to verify RED**

```bash
rtk test swift test --filter MenuBarStatusIconTests
```

Expected: compilation fails because `MenuBarStatusIconRenderer` and `badgeWeight` do not exist.

- [ ] **Step 3: Implement the minimal AppKit renderer**

Append the following implementation to `MenuBarStatusIcon.swift`:

```swift
extension MenuBarStatusIconState {
    public var badgeWeight: NSFont.Weight {
        self == .attention ? .heavy : .bold
    }
}

@MainActor
public struct MenuBarStatusIconRenderer {
    public static let imageSize = NSSize(width: 34, height: 18)

    public init() {}

    public func image(for state: MenuBarStatusIconState) -> NSImage {
        let image = NSImage(size: Self.imageSize, flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor.black.setFill()
            NSColor.black.setStroke()
            drawBrandMark()
            drawBadge(for: state)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawBrandMark() {
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 8, y: 17))
        arrow.line(to: NSPoint(x: 15.5, y: 9.5))
        arrow.line(to: NSPoint(x: 11.5, y: 9.5))
        arrow.line(to: NSPoint(x: 11.5, y: 4.2))
        arrow.line(to: NSPoint(x: 8, y: 6))
        arrow.line(to: NSPoint(x: 4.5, y: 4.2))
        arrow.line(to: NSPoint(x: 4.5, y: 9.5))
        arrow.line(to: NSPoint(x: 0.5, y: 9.5))
        arrow.close()
        arrow.fill()

        let bar = NSBezierPath(roundedRect: NSRect(x: 2, y: 0.5, width: 12, height: 2), xRadius: 1, yRadius: 1)
        bar.fill()
    }

    private func drawBadge(for state: MenuBarStatusIconState) {
        let circleRect = NSRect(x: 20, y: 2, width: 14, height: 14)
        let circle = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.8, dy: 0.8))
        circle.lineWidth = 1.6
        circle.stroke()

        let text = state.badgeText as NSString
        let fontSize: CGFloat = text.length > 1 ? 7 : 9.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: state.badgeWeight),
            .foregroundColor: NSColor.black,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: circleRect.midX - size.width / 2,
            y: circleRect.midY - size.height / 2 + 0.4
        )
        text.draw(at: origin, withAttributes: attributes)
    }
}
```

- [ ] **Step 4: Run renderer tests to verify GREEN**

```bash
rtk test swift test --filter MenuBarStatusIconTests
```

Expected: all five tests pass.

- [ ] **Step 5: Commit the renderer unit**

```bash
rtk git add Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift
rtk git commit -m "feat: render branded menu bar status icons"
```

### Task 3: Connect status transitions to image-only presentation

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift:34-43`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift:20-25,56-76,358-365,438-451,517-537`

- [ ] **Step 1: Replace the legacy source contract with failing integration assertions**

Replace `testMenuBarStatusItemDoesNotShowBrandFallback` with:

```swift
func testMenuBarStatusItemUsesImageOnlyBrandedStatusStates() throws {
    let sourceURL = URL(
        fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertTrue(source.contains("statusButton.imagePosition = .imageOnly"))
    XCTAssertTrue(source.contains("setStatusIcon(.checking"))
    XCTAssertTrue(source.contains("latestState.statusIconState"))
    XCTAssertTrue(source.contains("setStatusIcon(.attention"))
    XCTAssertFalse(source.contains("arrow.triangle.2.circlepath"))
    XCTAssertFalse(source.contains(#"statusButton.title = "...""#))
    XCTAssertFalse(source.contains(#"latestState.badgeValue ?? "✓""#))
}
```

- [ ] **Step 2: Run the source contract to verify RED**

```bash
rtk test swift test --filter SourceHygieneTests/testMenuBarStatusItemUsesImageOnlyBrandedStatusStates
```

Expected: FAIL because the app still uses the SF Symbol and visible title text.

- [ ] **Step 3: Implement image-only state integration**

Add stored renderer state near the existing formatter:

```swift
private let statusIconRenderer = MenuBarStatusIconRenderer()
private var renderedStatusIconState: MenuBarStatusIconState?
```

Replace the initial title and SF Symbol block with:

```swift
statusButton.title = ""
statusButton.toolTip = "UpdateBar"
statusButton.setAccessibilityIdentifier("updatebar-status-button")
statusButton.imagePosition = .imageOnly
setStatusIcon(.checking, accessibilityLabel: "UpdateBar checking")
```

Replace refresh, active-action, current-state, and error title calls with:

```swift
setStatusIcon(.checking, accessibilityLabel: "UpdateBar checking")
setStatusIcon(.checking, accessibilityLabel: "UpdateBar running \(activeAction.title)")
setStatusIcon(
    latestState.statusIconState,
    accessibilityLabel: accessibilityLabel(for: latestState)
)
setStatusIcon(.attention, accessibilityLabel: "UpdateBar error")
```

Replace `setTitle` with:

```swift
private func setStatusIcon(
    _ state: MenuBarStatusIconState,
    accessibilityLabel: String
) {
    guard let button = statusItem?.button else { return }
    if renderedStatusIconState != state {
        button.image = statusIconRenderer.image(for: state)
        renderedStatusIconState = state
    }
    button.title = ""
    button.imagePosition = .imageOnly
    button.setAccessibilityLabel(accessibilityLabel)
}
```

- [ ] **Step 4: Run focused integration and status tests**

```bash
rtk test swift test --filter SourceHygieneTests/testMenuBarStatusItemUsesImageOnlyBrandedStatusStates
rtk test swift test --filter MenuBarStatusIconTests
rtk test swift test --filter MenuBarStatusFormatterTests
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit app integration**

```bash
rtk git add Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift Tests/UpdateBarMenuBarTests/SourceHygieneTests.swift
rtk git commit -m "feat: show state badges in the menu bar icon"
```

### Task 4: Full verification and manual QA

**Files:**
- Verify only; no planned source changes.

- [ ] **Step 1: Run the full automated gate**

```bash
rtk test bash Scripts/quality-gate.sh
rtk git diff --check
```

Expected: quality gate exits 0; diff check emits no output.

- [ ] **Step 2: Package and launch the menu bar app**

```bash
rtk test env UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh
rtk test bash Scripts/menubar-smoke-test.sh dist/UpdateBar.app
```

Expected: package command prints `dist/UpdateBar.app`; smoke test exits 0.

- [ ] **Step 3: Capture state-image previews from tests or a focused preview harness**

Render `checking`, `upToDate`, `updates(count: 1)`, `updates(count: 10)`, and
`attention` at 2x scale and inspect them against both light and dark backgrounds.
Confirm the V-tail and bar remain distinct, the circle diameter stays fixed,
`9+` fits, and the exclamation mark is visibly heavier than the other marks.

- [ ] **Step 4: Review final branch state**

```bash
rtk git status --short
rtk git log --oneline -5
```

Expected: clean worktree with the plan commit followed by three focused implementation commits.
