#if os(macOS)
    import AppKit
    import SwiftUI
    import XCTest

    @testable import UpdateBarMenuBarApp

    @MainActor
    final class AboutViewTests: XCTestCase {
        func testAboutViewRendersProvidedVersionAndBuild() throws {
            let baseline = renderedAboutView(version: "0.0.1", build: "1")

            XCTAssertNotEqual(baseline, renderedAboutView(version: "9.9.9", build: "1"))
            XCTAssertNotEqual(baseline, renderedAboutView(version: "0.0.1", build: "999"))
        }

        private func renderedAboutView(version: String, build: String) -> Data {
            _ = NSApplication.shared
            let view = AboutView(
                version: version,
                build: build,
                onSupport: {},
                onAcknowledgments: {}
            )
            .frame(width: 480, height: 360)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: 480, height: 360)
            return renderer.nsImage?.tiffRepresentation ?? Data()
        }
    }
#endif
