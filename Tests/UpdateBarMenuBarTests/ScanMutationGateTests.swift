import UpdateBarMenuBar
import XCTest

final class ScanMutationGateTests: XCTestCase {
    func testBeginRetainsOptimisticPreviousAndTarget() {
        var gate = ScanMutationGate()

        let mutation = gate.begin(
            id: "brew.jq",
            previous: .untracked,
            target: .enabled
        )

        XCTAssertEqual(
            mutation,
            ScanRowMutation(id: "brew.jq", previous: .untracked, target: .enabled)
        )
        XCTAssertTrue(gate.hasPendingMutations)
        XCTAssertTrue(gate.isPending(id: "brew.jq"))
    }

    func testServiceIntentIsDerivedFromEveryPreviousState() {
        XCTAssertEqual(
            ScanRowMutation(id: "new", previous: .untracked, target: .enabled).serviceIntent,
            .register
        )
        XCTAssertEqual(
            ScanRowMutation(id: "on", previous: .enabled, target: .disabled).serviceIntent,
            .setEnabled(false)
        )
        XCTAssertEqual(
            ScanRowMutation(id: "off", previous: .disabled, target: .enabled).serviceIntent,
            .setEnabled(true)
        )
        XCTAssertNil(
            ScanRowMutation(
                id: "limited",
                previous: .unavailable("check-only"),
                target: .unavailable("check-only")
            ).serviceIntent
        )
    }

    func testDuplicateBeginForPendingIDIsRejectedWithoutReplacingMutation() {
        var gate = ScanMutationGate()
        let first = gate.begin(
            id: "brew.jq",
            previous: .untracked,
            target: .enabled
        )

        let duplicate = gate.begin(
            id: "brew.jq",
            previous: .enabled,
            target: .disabled
        )

        XCTAssertNil(duplicate)
        XCTAssertEqual(gate.finish(id: "brew.jq"), first)
    }

    func testDifferentIDsCanBePendingIndependently() {
        var gate = ScanMutationGate()

        let jq = gate.begin(id: "brew.jq", previous: .untracked, target: .enabled)
        let claude = gate.begin(id: "known.claude", previous: .disabled, target: .enabled)

        XCTAssertNotNil(jq)
        XCTAssertNotNil(claude)
        XCTAssertTrue(gate.hasPendingMutations)
        XCTAssertTrue(gate.isPending(id: "brew.jq"))
        XCTAssertTrue(gate.isPending(id: "known.claude"))
    }

    func testOutOfOrderFinishReturnsTheMatchingMutation() {
        var gate = ScanMutationGate()
        let first = gate.begin(id: "brew.jq", previous: .untracked, target: .enabled)
        let second = gate.begin(id: "known.claude", previous: .disabled, target: .enabled)

        XCTAssertEqual(gate.finish(id: "known.claude"), second)
        XCTAssertTrue(gate.isPending(id: "brew.jq"))
        XCTAssertFalse(gate.isPending(id: "known.claude"))
        XCTAssertEqual(gate.finish(id: "brew.jq"), first)
        XCTAssertFalse(gate.hasPendingMutations)
    }

    func testFinishRemovesAndReturnsMutationAndRepeatedFinishIsNil() {
        var gate = ScanMutationGate()
        let mutation = gate.begin(id: "brew.jq", previous: .enabled, target: .disabled)

        XCTAssertEqual(gate.finish(id: "brew.jq"), mutation)
        XCTAssertFalse(gate.hasPendingMutations)
        XCTAssertFalse(gate.isPending(id: "brew.jq"))
        XCTAssertNil(gate.finish(id: "brew.jq"))
    }
}
