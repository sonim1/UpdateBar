import UpdateBarMenuBar
import XCTest

final class MenuBarRefreshGenerationGateTests: XCTestCase {
    func testRejectsFirstTokenAfterSecondBeginsToProtectNewerSuccess() {
        var gate = MenuBarRefreshGenerationGate()
        let first = gate.begin()

        _ = gate.begin()

        XCTAssertFalse(gate.isCurrent(first))
    }

    func testAcceptsSecondTokenSoNewestErrorCanApply() {
        var gate = MenuBarRefreshGenerationGate()
        _ = gate.begin()

        let second = gate.begin()

        XCTAssertTrue(gate.isCurrent(second))
    }

    func testInvalidateRejectsInFlightRefreshBeforeActionWorkBegins() {
        var gate = MenuBarRefreshGenerationGate()
        let refresh = gate.begin()

        gate.invalidate()

        XCTAssertFalse(gate.isCurrent(refresh))
        let nextRefresh = gate.begin()
        XCTAssertTrue(gate.isCurrent(nextRefresh))
    }
}
