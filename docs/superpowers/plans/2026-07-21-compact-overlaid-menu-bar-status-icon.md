# Compact Overlaid Menu Bar Status Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 34-point side-by-side menu bar image with a 20×18-point template image whose circular state badge overlaps the UpdateBar brand at the lower-right.

**Architecture:** Keep `MenuBarStatusIconState` and the app's image-only status-button integration unchanged. Update only `MenuBarStatusIconRenderer`: draw the existing brand, clear an exact circular knockout, then draw a smaller badge and its state text inside the same compact canvas. Verify the geometry through real AppKit raster alpha samples before packaging and replacing the local app.

**Tech Stack:** Swift 6, AppKit (`NSImage`, `NSBezierPath`, `NSGraphicsContext`, `NSBitmapImageRep`), XCTest, existing shell packaging and smoke-test scripts

---

## File Map

- Modify `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`: lock the 20×18-point footprint and raster-check the brand, transparent knockout, and overlaid badge.
- Modify `Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift`: shrink the canvas, define the badge geometry, clear the overlap, and render smaller badge text.
- Temporarily modify `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift` during manual QA to export a 2× state contact sheet; remove the temporary method before the final test run.
- No app-state, accessibility, menu-routing, app-icon, or packaging source files change.

### Task 1: Lock the compact overlay contract with a failing raster test

**Files:**
- Modify: `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift:30-47`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`

- [ ] **Step 1: Add the compact canvas and raster assertions**

Add this test after `testRendererCreatesFixedTemplateImageForEveryState()`:

```swift
func testRendererOverlaysBadgeInsideCompactCanvas() throws {
    let image = MenuBarStatusIconRenderer().image(for: .attention)

    XCTAssertEqual(image.size, NSSize(width: 20, height: 18))
    XCTAssertGreaterThan(
        try alpha(in: image, at: NSPoint(x: 8, y: 16)),
        0.8,
        "The arrow head should remain opaque"
    )
    XCTAssertLessThan(
        try alpha(in: image, at: NSPoint(x: 11.5, y: 13)),
        0.1,
        "The badge knockout should clear the brand underneath"
    )
    XCTAssertGreaterThan(
        try alpha(in: image, at: NSPoint(x: 19, y: 6.75)),
        0.5,
        "The badge outline should reach the compact canvas edge"
    )
}
```

Add this helper before `makeState(outdated:attention:)`:

```swift
private func alpha(
    in image: NSImage,
    at point: NSPoint,
    scale: CGFloat = 4
) throws -> CGFloat {
    let pixelsWide = Int(image.size.width * scale)
    let pixelsHigh = Int(image.size.height * scale)
    let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    bitmap.size = image.size
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(origin: .zero, size: image.size))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let color = try XCTUnwrap(
        bitmap.colorAt(
            x: Int(point.x * scale),
            y: Int(point.y * scale)
        )
    )
    return color.alphaComponent
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
rtk test swift test --filter MenuBarStatusIconTests/testRendererOverlaysBadgeInsideCompactCanvas
```

Expected: FAIL because the current image is `34×18`, the brand remains opaque at the future knockout sample, and the badge sits in a separate right-hand region.

### Task 2: Render the brand and state badge in one 20-point canvas

**Files:**
- Modify: `Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift:41-100`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`

- [ ] **Step 1: Define the compact geometry and drawing order**

Replace the renderer's size declaration with:

```swift
public static let imageSize = NSSize(width: 20, height: 18)
private static let badgeRect = NSRect(x: 7.5, y: 0.5, width: 12.5, height: 12.5)
```

Change the image drawing handler to clear the overlap after drawing the brand and before drawing the badge:

```swift
public func image(for state: MenuBarStatusIconState) -> NSImage {
    let image = NSImage(size: Self.imageSize, flipped: false) { _ in
        NSGraphicsContext.current?.shouldAntialias = true
        NSColor.black.setFill()
        NSColor.black.setStroke()
        drawBrandMark()
        clearBadgeBackdrop()
        drawBadge(for: state)
        return true
    }
    image.isTemplate = true
    return image
}
```

- [ ] **Step 2: Implement the transparent knockout**

Add this method between `drawBrandMark()` and `drawBadge(for:)`:

```swift
private func clearBadgeBackdrop() {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.compositingOperation = .clear
    NSBezierPath(
        ovalIn: Self.badgeRect.insetBy(dx: -1, dy: -1)
    ).fill()
    NSGraphicsContext.restoreGraphicsState()
}
```

This makes the brand-to-badge separation part of the image alpha channel, so template tinting remains controlled by macOS.

- [ ] **Step 3: Resize the badge outline and text**

Replace `drawBadge(for:)` with:

```swift
private func drawBadge(for state: MenuBarStatusIconState) {
    let circle = NSBezierPath(ovalIn: Self.badgeRect.insetBy(dx: 0.75, dy: 0.75))
    circle.lineWidth = 1.5
    circle.stroke()

    let text = state.badgeText as NSString
    let fontSize: CGFloat = text.length > 1 ? 6.25 : 8.5
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: state.badgeWeight),
        .foregroundColor: NSColor.black,
    ]
    let size = text.size(withAttributes: attributes)
    let origin = NSPoint(
        x: Self.badgeRect.midX - size.width / 2,
        y: Self.badgeRect.midY - size.height / 2 + 0.3
    )
    text.draw(at: origin, withAttributes: attributes)
}
```

- [ ] **Step 4: Run the renderer tests and verify GREEN**

Run:

```bash
rtk test swift test --filter MenuBarStatusIconTests
```

Expected: PASS. The new raster test confirms the arrow remains, the overlap is transparent, and the badge outline is visible at the lower-right edge. Existing badge text, state priority, template-image, and heavy-attention assertions remain green.

- [ ] **Step 5: Run the source integration contracts**

Run:

```bash
rtk test swift test --filter SourceHygieneTests/testMenuBarStatusItemUsesImageOnlyBrandedStatusStates
rtk test swift test --filter MenuBarStatusFormatterTests
rtk git diff --check
```

Expected: all commands exit 0. The app still uses `statusIconState`, `.imageOnly`, and the existing accessibility labels.

- [ ] **Step 6: Commit the compact overlay implementation**

Run:

```bash
rtk git add Sources/UpdateBarMenuBar/MenuBarStatusIcon.swift Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift
rtk git commit -m "fix: compact the menu bar status icon"
```

Expected: one commit containing only the renderer and its tests.

### Task 3: Inspect every badge state at 2× without retaining preview code

**Files:**
- Temporarily modify: `Tests/UpdateBarMenuBarTests/MenuBarStatusIconTests.swift`
- Create artifact outside git: `/Users/kendrick/.codex/visualizations/2026/07/21/compact-overlaid-menu-bar-statuses@2x.png`

- [ ] **Step 1: Add a temporary opt-in preview exporter**

Add this method before `alpha(in:at:scale:)`:

```swift
func testWriteCompactVisualPreviewWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["UPDATEBAR_ICON_PREVIEW_PATH"]
    else { throw XCTSkip("Visual preview not requested") }

    let states: [MenuBarStatusIconState] = [
        .checking, .upToDate, .updates(count: 1), .updates(count: 10), .attention,
    ]
    let pointSize = NSSize(
        width: MenuBarStatusIconRenderer.imageSize.width * CGFloat(states.count),
        height: MenuBarStatusIconRenderer.imageSize.height
    )
    let bitmap = try XCTUnwrap(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pointSize.width * 2),
            pixelsHigh: Int(pointSize.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    bitmap.size = pointSize
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: pointSize)).fill()
    let renderer = MenuBarStatusIconRenderer()
    for (index, state) in states.enumerated() {
        renderer.image(for: state).draw(
            in: NSRect(
                x: CGFloat(index) * MenuBarStatusIconRenderer.imageSize.width,
                y: 0,
                width: MenuBarStatusIconRenderer.imageSize.width,
                height: MenuBarStatusIconRenderer.imageSize.height
            )
        )
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: outputURL)
}
```

- [ ] **Step 2: Export and inspect the representative states**

Run:

```bash
rtk test env UPDATEBAR_ICON_PREVIEW_PATH=/Users/kendrick/.codex/visualizations/2026/07/21/compact-overlaid-menu-bar-statuses@2x.png swift test --filter MenuBarStatusIconTests/testWriteCompactVisualPreviewWhenRequested
```

Expected: PASS and a 200×36-pixel PNG containing `…`, `✓`, `1`, `9+`, and `!`. Inspect the PNG with `view_image` at original detail. Confirm that each cell is 20 points wide, the circular badge reads as a lower-right overlay, the transparent gap separates it from the arrow and bar, and no glyph is clipped.

- [ ] **Step 3: Remove the temporary exporter and re-run focused tests**

Remove only `testWriteCompactVisualPreviewWhenRequested()` from the test file, leaving the permanent raster helper and assertions intact.

Run:

```bash
rtk test swift test --filter MenuBarStatusIconTests
rtk git diff --check
rtk git status --short
```

Expected: PASS, no whitespace errors, and no uncommitted source changes. The PNG remains outside the repository as QA evidence.

### Task 4: Run the full gate and package the compact app

**Files:**
- Verify: entire repository
- Generate outside git: `dist/UpdateBar.app`

- [ ] **Step 1: Run the full quality gate**

Run:

```bash
rtk test bash Scripts/quality-gate.sh
```

Expected: exit 0 with the Swift tests, script contracts, CLI checks, TUI checks, archive checks, and app packaging contracts green.

- [ ] **Step 2: Package and smoke-test the app bundle**

Run:

```bash
rtk test env UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh
rtk test bash Scripts/menubar-smoke-test.sh dist/UpdateBar.app
```

Expected: both commands exit 0 and `dist/UpdateBar.app` launches through the existing menu bar smoke harness.

- [ ] **Step 3: Apply a valid local ad-hoc signature inside-out**

The local packaging path leaves only Swift's linker signature unless release signing is requested. Seal the local bundle before installation:

```bash
rtk proxy codesign --force --sign - dist/UpdateBar.app/Contents/Resources/updatebar
rtk proxy codesign --force --sign - dist/UpdateBar.app/Contents/MacOS/UpdateBar
rtk proxy codesign --force --sign - dist/UpdateBar.app
rtk proxy codesign --verify --deep --strict --verbose=2 dist/UpdateBar.app
```

Expected: `dist/UpdateBar.app: valid on disk` and `satisfies its Designated Requirement`.

### Task 5: Replace the local installation and verify the real menu bar item

**Files:**
- Install: `/Applications/UpdateBar.app`
- Preserve: `/Applications/UpdateBar.app.backup-0.5.0-pre-compact-overlay`

- [ ] **Step 1: Stage the verified app without overwriting anything**

Run:

```bash
rtk proxy test ! -e /Applications/UpdateBar.app.new
rtk proxy test ! -e /Applications/UpdateBar.app.backup-0.5.0-pre-compact-overlay
rtk proxy cp -R dist/UpdateBar.app /Applications/UpdateBar.app.new
rtk proxy codesign --verify --deep --strict --verbose=2 /Applications/UpdateBar.app.new
```

Expected: the `.new` bundle passes strict signature verification and neither staging nor backup path existed beforehand.

- [ ] **Step 2: Stop UpdateBar and atomically replace the bundle**

Run:

```bash
rtk proxy pkill -x UpdateBar || true
rtk proxy mv /Applications/UpdateBar.app /Applications/UpdateBar.app.backup-0.5.0-pre-compact-overlay
if ! rtk proxy mv /Applications/UpdateBar.app.new /Applications/UpdateBar.app; then
  rtk proxy mv /Applications/UpdateBar.app.backup-0.5.0-pre-compact-overlay /Applications/UpdateBar.app
  exit 1
fi
```

Expected: the previous installation is recoverable at the backup path and the new bundle occupies `/Applications/UpdateBar.app`. If the second move fails, the command restores the previous app.

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

Expected: signature and smoke checks pass, and the final process listing points to `/Applications/UpdateBar.app/Contents/MacOS/UpdateBar`.

- [ ] **Step 4: Inspect the real menu bar width**

Inspect the running status item on the macOS menu bar. Confirm the brand and circular badge overlap like the approved B mockup, the item is visibly narrower than the previous 34-point composite, and the active state's glyph is readable. If visual inspection contradicts the approved 20×18-point design, do not declare completion; record the screenshot and return to the renderer geometry test.

### Task 6: Finish the development branch

**Files:**
- Verify: branch history and worktree state

- [ ] **Step 1: Confirm the branch contains only intended commits and no uncommitted files**

Run:

```bash
rtk git status --short
rtk git log --oneline main..HEAD
rtk git diff main...HEAD --stat
```

Expected: clean status; the plan and compact renderer commits are present; the approved design commit is an ancestor of the branch; and the feature diff contains only this plan, renderer, and renderer tests.

- [ ] **Step 2: Invoke the branch-finishing workflow**

Use `superpowers:finishing-a-development-branch`, re-run its required verification, determine the current base branch, and present its four integration options. Do not merge, push, or discard without the user's explicit selection.
