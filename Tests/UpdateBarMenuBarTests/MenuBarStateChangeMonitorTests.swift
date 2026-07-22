import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarStateChangeMonitorTests: XCTestCase {
    func testDetectsAtomicCLIStateChangesOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-state-monitor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppPaths(homeDirectory: root)
        try Data("before".utf8).write(to: paths.stateFile, options: .atomic)
        var monitor = MenuBarStateChangeMonitor(paths: paths)

        XCTAssertFalse(monitor.poll())

        try Data("after-state".utf8).write(to: paths.stateFile, options: .atomic)

        XCTAssertTrue(monitor.poll())
        XCTAssertFalse(monitor.poll())

        try Data("manifest".utf8).write(to: paths.manifestFile, options: .atomic)

        XCTAssertTrue(monitor.poll())
        XCTAssertFalse(monitor.poll())
    }
}
