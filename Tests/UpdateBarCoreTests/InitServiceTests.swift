import XCTest
import UpdateBarCore

final class InitServiceTests: XCTestCase {
    func testInitServiceErrorDescriptionsRedactSecretLikeValues() {
        let secret = "sk-or-v1-secret-value"
        let error = InitServiceError.invalidSelection([
            "\(secret): not found",
            "tool: not importable (\(secret))"
        ])

        let message = String(describing: error)

        XCTAssertTrue(message.contains("[REDACTED]"))
        XCTAssertFalse(message.contains(secret))
    }
}
