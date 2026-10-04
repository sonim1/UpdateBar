#if os(macOS)
    import AppKit
    import Combine
    import UpdateBarCore
    import UpdateBarMenuBar
    import XCTest

    @testable import UpdateBarMenuBarApp

    @MainActor
    final class SettingsViewControllerTests: XCTestCase {
        func testSavingRefreshPreservesConfiguredConcurrency() async throws {
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            var initial = Config.default
            initial.update.maxConcurrent = 8
            try ConfigStore(paths: paths).save(initial)
            let saved = expectation(description: "settings saved")
            let controller = SettingsViewController(
                service: CoreMenuBarService(paths: paths), onSaved: { saved.fulfill() },
                onCheckForUpdates: {}
            )
            await load(controller)

            controller.model.refreshInterval = "1h"
            controller.model.onSave()
            await fulfillment(of: [saved], timeout: 2)

            let config = try ConfigStore(paths: paths).load()
            XCTAssertEqual(config.refresh.interval, Duration(hours: 1))
            XCTAssertEqual(config.update.maxConcurrent, 8)
        }

        func testUneditedFieldsPreserveChangesMadeAfterPreferencesLoad() async throws {
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            try ConfigStore(paths: paths).save(.default)
            let saved = expectation(description: "settings saved")
            let controller = SettingsViewController(
                service: CoreMenuBarService(paths: paths), onSaved: { saved.fulfill() },
                onCheckForUpdates: {}
            )
            await load(controller)
            var external = Config.default
            external.update.maxConcurrent = 8
            external.security.requireHTTPSSource = false
            try ConfigStore(paths: paths).save(external)

            controller.model.refreshInterval = "30m"
            controller.model.onSave()
            await fulfillment(of: [saved], timeout: 2)

            let config = try ConfigStore(paths: paths).load()
            XCTAssertEqual(config.refresh.interval, Duration(minutes: 30))
            XCTAssertEqual(config.update.maxConcurrent, 8)
            XCTAssertFalse(config.security.requireHTTPSSource)
            XCTAssertEqual(controller.model.maxConcurrent, 8)
            XCTAssertFalse(controller.model.requireHTTPS)
        }

        func testExplicitConcurrencyEditIsPersisted() async throws {
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            try ConfigStore(paths: paths).save(.default)
            let saved = expectation(description: "settings saved")
            let controller = SettingsViewController(
                service: CoreMenuBarService(paths: paths), onSaved: { saved.fulfill() },
                onCheckForUpdates: {}
            )
            await load(controller)

            controller.model.maxConcurrent = 8
            controller.model.onSave()
            await fulfillment(of: [saved], timeout: 2)

            XCTAssertEqual(try ConfigStore(paths: paths).load().update.maxConcurrent, 8)
            XCTAssertEqual(controller.model.maxConcurrent, 8)
        }

        func testInvalidEditsLeaveConfigurationUnchanged() async throws {
            _ = NSApplication.shared
            for (refresh, concurrency) in [("invalid", 7), ("30m", 9)] {
                let paths = temporaryPaths()
                defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
                try ConfigStore(paths: paths).save(.default)
                var didSave = false
                let controller = SettingsViewController(
                    service: CoreMenuBarService(paths: paths), onSaved: { didSave = true },
                    onCheckForUpdates: {}
                )
                await load(controller)
                let finished = expectation(description: "invalid save finished")
                let observation = controller.model.$isRunning.dropFirst()
                    .filter { !$0 }.first().sink { _ in finished.fulfill() }

                controller.model.refreshInterval = refresh
                controller.model.maxConcurrent = concurrency
                controller.model.requireHTTPS = false
                controller.model.onSave()
                await fulfillment(of: [finished], timeout: 2)
                observation.cancel()

                XCTAssertEqual(try ConfigStore(paths: paths).load(), .default)
                XCTAssertFalse(didSave)
            }
        }

        private func load(_ controller: SettingsViewController) async {
            let loaded = expectation(description: "settings loaded")
            let observation = controller.model.$isRunning.dropFirst()
                .filter { !$0 }.first().sink { _ in loaded.fulfill() }
            controller.prepare()
            await fulfillment(of: [loaded], timeout: 2)
            observation.cancel()
        }

        private func temporaryPaths() -> AppPaths {
            AppPaths(
                homeDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("updatebar-settings-tests-\(UUID().uuidString)")
            )
        }
    }
#endif
