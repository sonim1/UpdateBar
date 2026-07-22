import UpdateBarMenuBar
import XCTest

final class ScanSessionGenerationGateTests: XCTestCase {
    func testCurrentManualScanTokenIsAccepted() {
        var gate = ScanSessionGenerationGate()

        let token = gate.beginManualScan()

        XCTAssertTrue(gate.acceptsCurrentScan(token))
    }

    func testNewerManualScanRejectsEarlierCompletionAndAcceptsNewCompletion() {
        var gate = ScanSessionGenerationGate()
        let first = gate.beginManualScan()

        let second = gate.beginManualScan()

        XCTAssertFalse(gate.acceptsCurrentScan(first))
        XCTAssertTrue(gate.acceptsCurrentScan(second))
    }

    func testWindowCloseInvalidationRejectsCurrentCompletionToken() {
        var gate = ScanSessionGenerationGate()
        let token = gate.beginManualScan()

        gate.invalidateForWindowClose()

        XCTAssertFalse(gate.acceptsCurrentScan(token))
    }
}
