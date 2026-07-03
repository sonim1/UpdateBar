import Foundation
import UpdateBarCore
import XCTest

final class MachineEventTests: XCTestCase {
    func testMachineEventEncodesEventAndTypeAliases() throws {
        let event = MachineEvent(
            event: .itemStarted,
            operation: .update,
            timestamp: Date(timeIntervalSince1970: 1_800),
            runId: "run-1",
            itemId: "brew.gh",
            message: "GitHub CLI"
        )

        let data = try JSONEncoder.updateBar.encode(event)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["event"] as? String, "item_started")
        XCTAssertEqual(payload["type"] as? String, "item_started")
        XCTAssertEqual(payload["operation"] as? String, "update")
        XCTAssertEqual(payload["run_id"] as? String, "run-1")
        XCTAssertEqual(payload["item_id"] as? String, "brew.gh")
    }

    func testMachineEventDecodesLegacyTypeOnlyPayloads() throws {
        let data = Data("""
        {
          "type": "finished",
          "operation": "check",
          "timestamp": "2026-06-30T00:00:00Z"
        }
        """.utf8)

        let event = try JSONDecoder.updateBar.decode(MachineEvent.self, from: data)

        XCTAssertEqual(event.event, .finished)
        XCTAssertEqual(event.operation, .check)
    }
}
