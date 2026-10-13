#if os(macOS)
    import AppKit
    import Combine
    import UpdateBarCore
    import UpdateBarMenuBar
    import XCTest

    @testable import UpdateBarMenuBarApp

    @MainActor
    final class SettingsViewControllerTests: XCTestCase {
        func testEnteringSettingsLoadsPersistedConfiguration() async throws {
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            var config = Config.default
            config.refresh.interval = Duration(hours: 24)
            config.update.maxConcurrent = 1
            try ConfigStore(paths: paths).save(config)
            let controller = SettingsViewController(
                service: CoreMenuBarService(paths: paths), onSaved: {},
                onCheckForUpdates: {}
            )

            await load(controller)

            XCTAssertEqual(controller.model.refreshInterval, config.refresh.interval.description)
            XCTAssertEqual(controller.model.maxConcurrent, 1)
        }

        func testReenteringSettingsReloadsExternalChanges() async throws {
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            try ConfigStore(paths: paths).save(.default)
            let controller = SettingsViewController(
                service: CoreMenuBarService(paths: paths), onSaved: {},
                onCheckForUpdates: {}
            )
            await load(controller)
            controller.viewDidDisappear()
            var config = Config.default
            config.refresh.interval = Duration(minutes: 30)
            config.update.maxConcurrent = 1
            try ConfigStore(paths: paths).save(config)

            await load(controller)

            XCTAssertEqual(controller.model.refreshInterval, "30m")
            XCTAssertEqual(controller.model.maxConcurrent, 1)
        }

        func testOpeningAlreadyVisibleSettingsReloadsExternalChanges() async throws {
            _ = NSApplication.shared
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            try ConfigStore(paths: paths).save(.default)
            let now = Date()
            try ManifestStore(paths: paths).save(
                Manifest(
                    schemaVersion: 1, items: [],
                    provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
                )
            )
            let dashboard = DashboardPanelController(
                service: CoreMenuBarService(paths: paths), onItemsChanged: {},
                itemActions: MenuBarPopoverActions(
                    check: {}, update: { _ in }, retry: { _ in },
                    setApproval: { _, _, _ in }, stop: {}, dashboard: { _ in }, more: {}
                ),
                onCheckForUpdates: {}
            )
            defer { dashboard.close() }
            dashboard.showWindowAndReload(selecting: .settings)
            let root = try XCTUnwrap(dashboard.window?.contentViewController)
            let settings = try XCTUnwrap(settingsController(in: root))
            await load(settings)
            var external = Config.default
            external.refresh.interval = Duration(hours: 12)
            try ConfigStore(paths: paths).save(external)
            let reloaded = expectation(description: "visible settings reloaded")
            let observation = settings.model.$isRunning.dropFirst()
                .filter { !$0 }.first().sink { _ in reloaded.fulfill() }

            dashboard.showWindowAndReload(selecting: .settings)
            await fulfillment(of: [reloaded], timeout: 2)
            observation.cancel()

            XCTAssertEqual(settings.model.refreshInterval, "12h")
        }

        func testReenteringSettingsPreservesUnsavedEdits() async throws {
            let paths = temporaryPaths()
            defer { try? FileManager.default.removeItem(at: paths.homeDirectory) }
            try ConfigStore(paths: paths).save(.default)
            let controller = SettingsViewController(
                service: CoreMenuBarService(paths: paths), onSaved: {},
                onCheckForUpdates: {}
            )
            await load(controller)
            controller.model.refreshInterval = "1h"
            controller.model.requireHTTPS = false
            controller.viewDidDisappear()

            controller.viewWillAppear()

            XCTAssertFalse(controller.model.isRunning)
            XCTAssertEqual(controller.model.refreshInterval, "1h")
            XCTAssertFalse(controller.model.requireHTTPS)
            XCTAssertEqual(try ConfigStore(paths: paths).load(), .default)
        }

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
            _ = controller.view
            let loaded = expectation(description: "settings loaded on appearance")
            let observation = controller.model.$isRunning.dropFirst()
                .filter { !$0 }.first().sink { _ in loaded.fulfill() }
            controller.viewWillAppear()
            await fulfillment(of: [loaded], timeout: 2)
            observation.cancel()
        }

        private func temporaryPaths() -> AppPaths {
            AppPaths(
                homeDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("updatebar-settings-tests-\(UUID().uuidString)")
            )
        }

        private func settingsController(in root: NSViewController) -> SettingsViewController? {
            if let settings = root as? SettingsViewController { return settings }
            return root.children.compactMap { settingsController(in: $0) }.first
        }
    }
#endif
