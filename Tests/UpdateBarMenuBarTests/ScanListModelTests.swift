import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class ScanListModelTests: XCTestCase {
    func testMarksRegisteredCandidatesAndBlocksReimport() throws {
        let report = try decodeReport(
            """
            {"candidates":[
              {"id":"brew.jq","name":"jq","category":"shell-utility","detector":"brew",
               "capability":"full","confidence":"high","source_ref":"jq",
               "installed_version":"1.7.1",
               "recipe":{"category":"shell-utility","check":{"cmd":"brew list --versions jq"},
                 "id":"brew.jq","latest":{"cmd":"brew info jq","strategy":"cmd"},
                 "name":"jq","source":{"kind":"brew","ref":"jq"},
                 "update":{"cmd":"brew upgrade jq"},
                 "version_parse":{"regex":"([0-9]+\\\\.[0-9]+\\\\.[0-9]+)"},
                 "version_scheme":"semver","enabled":true,"trust":{"level":"untrusted","approved_commands":{}}}},
              {"id":"known.claude","name":"claude","category":"ai-agent","detector":"known",
               "capability":"check-only","confidence":"medium","source_ref":"claude"}
            ],"errors":[]}
            """
        )

        let rows = ScanListModel().rows(from: report, registeredIDs: ["brew.jq"])

        XCTAssertEqual(rows.map(\.isRegistered), [true, false])
        XCTAssertEqual(rows.map(\.isImportable), [false, false])
        XCTAssertEqual(rows.map(\.stateLabel), ["registered", "check-only"])
    }

    func testUnregisteredFullCandidateIsImportable() throws {
        let report = try decodeReport(
            """
            {"candidates":[
              {"id":"brew.jq","name":"jq","category":"shell-utility","detector":"brew",
               "capability":"full","confidence":"high","source_ref":"jq",
               "recipe":{"category":"shell-utility","check":{"cmd":"brew list --versions jq"},
                 "id":"brew.jq","latest":{"cmd":"brew info jq","strategy":"cmd"},
                 "name":"jq","source":{"kind":"brew","ref":"jq"},
                 "update":{"cmd":"brew upgrade jq"},
                 "version_parse":{"regex":"([0-9]+\\\\.[0-9]+\\\\.[0-9]+)"},
                 "version_scheme":"semver","enabled":true,"trust":{"level":"untrusted","approved_commands":{}}}}
            ],"errors":[]}
            """
        )

        let rows = ScanListModel().rows(from: report, registeredIDs: [])

        XCTAssertEqual(rows.map(\.isImportable), [true])
        XCTAssertEqual(rows.map(\.stateLabel), ["importable"])
    }

    private func decodeReport(_ json: String) throws -> ScanReport {
        try JSONDecoder.updateBar.decode(ScanReport.self, from: Data(json.utf8))
    }
}
