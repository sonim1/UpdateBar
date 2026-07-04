import Foundation
import XCTest

final class SourceHygieneTests: XCTestCase {
    func testMenuBarAppDelegateAvoidsImplicitlyUnwrappedStoredProperties() throws {
        let sourceURL = URL(fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("NSStatusItem!"))
        XCTAssertFalse(source.contains("MenuBarServicing)!"))
    }

    func testMenuBarResolvedCLIPathDebugLogsAreRedacted() throws {
        let sourceURL = URL(fileURLWithPath: "Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("updatebar: \\(resolution.path)"))
        XCTAssertTrue(source.contains("SecretRedactor.redact(resolution.path)"))
    }
}
