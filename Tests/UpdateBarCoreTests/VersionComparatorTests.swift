import XCTest
import UpdateBarCore

final class VersionComparatorTests: XCTestCase {
    func testComparesSemanticVersions() throws {
        XCTAssertEqual(try VersionComparator.compareSemVer("1.2.3", "1.2.4"), .orderedAscending)
        XCTAssertEqual(try VersionComparator.compareSemVer("1.2.3", "1.2.3"), .orderedSame)
        XCTAssertEqual(try VersionComparator.compareSemVer("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(try VersionComparator.compareSemVer("1.0.0-beta", "1.0.0"), .orderedAscending)
    }

    func testRejectsInvalidSemanticVersionsThatWouldCompareAmbiguously() {
        XCTAssertThrowsError(try VersionComparator.compareSemVer("01.2.3", "1.2.3"))
        XCTAssertThrowsError(try VersionComparator.compareSemVer("1.2.3-01", "1.2.3-1"))
        XCTAssertThrowsError(try VersionComparator.compareSemVer("1.2.3-alpha..1", "1.2.3-alpha.1"))
    }

    func testComparesVersionSchemesToItemStatus() throws {
        XCTAssertEqual(
            try VersionComparator.status(current: "1.2.3", latest: "1.2.4", scheme: .semver),
            .outdated
        )
        XCTAssertEqual(
            try VersionComparator.status(current: "2026.06", latest: "2026.07", scheme: .calver),
            .outdated
        )
        XCTAssertEqual(
            try VersionComparator.status(current: "abc123", latest: "def456", scheme: .commit),
            .outdated
        )
        XCTAssertEqual(
            try VersionComparator.status(current: "abc", latest: "def", scheme: .opaque),
            .differs
        )
        XCTAssertEqual(
            try VersionComparator.status(current: "same", latest: "same", scheme: .opaque),
            .ok
        )
    }

    func testExtractsVersionsWithRegex() throws {
        XCTAssertEqual(
            try VersionParser.extract(from: "claude 1.2.3", using: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)")),
            "1.2.3"
        )
        XCTAssertThrowsError(
            try VersionParser.extract(from: "claude 1.2.3", using: .regex("([0-9]+)\\.([0-9]+)"))
        )
        XCTAssertThrowsError(
            try VersionParser.extract(from: "claude 1.2.3", using: .regex("version: ([0-9]+)"))
        )
    }
}
