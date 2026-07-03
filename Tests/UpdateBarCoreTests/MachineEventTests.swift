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

    func testMachineEventRejectsMismatchedEventAndTypeAliases() throws {
        let data = Data("""
        {
          "event": "started",
          "type": "finished",
          "operation": "check",
          "timestamp": "2026-06-30T00:00:00Z"
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(MachineEvent.self, from: data))
    }

    func testMachineEventRejectsUpdatePayloadForCheckOperation() throws {
        let data = Data("""
        {
          "event": "item_finished",
          "type": "item_finished",
          "operation": "check",
          "timestamp": "2026-06-30T00:00:00Z",
          "result": {
            "id": "tool",
            "name": "Tool",
            "outcome": "updated"
          }
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(MachineEvent.self, from: data))
    }

    func testMachineEventRejectsCheckPayloadForUpdateOperation() throws {
        let data = Data("""
        {
          "event": "item_finished",
          "type": "item_finished",
          "operation": "update",
          "timestamp": "2026-06-30T00:00:00Z",
          "check_result": {
            "id": "tool",
            "name": "Tool",
            "status": "ok"
          }
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(MachineEvent.self, from: data))
    }

    func testMachineEventRejectsNegativeUpdateSummaryCounts() throws {
        let data = Data("""
        {
          "event": "finished",
          "type": "finished",
          "operation": "update",
          "timestamp": "2026-06-30T00:00:00Z",
          "summary": {
            "total": 1,
            "updated": -1,
            "failed": 0,
            "skipped": 0,
            "skipped_untrusted": 0,
            "missing": 0,
            "cancelled": 0,
            "hard_failures": 0
          }
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(MachineEvent.self, from: data))
    }

    func testMachineEventRejectsNegativeCheckSummaryCounts() throws {
        let data = Data("""
        {
          "event": "finished",
          "type": "finished",
          "operation": "check",
          "timestamp": "2026-06-30T00:00:00Z",
          "check_summary": {
            "total": 1,
            "outdated": -1,
            "errors": 0,
            "untrusted": 0,
            "disabled": 0,
            "pinned": 0,
            "differs": 0
          }
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(MachineEvent.self, from: data))
    }
}
