import XCTest

@testable import UpdateBarCore

final class UpdateLaneTests: XCTestCase {
    func testUsesFirstCommandToken() {
        XCTAssertEqual(UpdateLane.key(forCommand: "brew upgrade ripgrep"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "npm"), "npm")
    }

    func testStripsDirectoryAndLowercases() {
        XCTAssertEqual(UpdateLane.key(forCommand: "/opt/homebrew/bin/brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "/usr/local/bin/NPM install -g y"), "npm")
    }

    func testSkipsWrapperCommands() {
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -u kendrick brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "env brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "nohup nice cargo install-update -a"), "cargo")
    }

    func testSkipsLeadingEnvironmentAssignments() {
        XCTAssertEqual(UpdateLane.key(forCommand: "FOO=1 npm install -g y"), "npm")
        XCTAssertEqual(UpdateLane.key(forCommand: "A=1 B=2 env brew upgrade x"), "brew")
    }

    func testTreatsNonAssignmentEqualsAsCommand() {
        XCTAssertEqual(UpdateLane.key(forCommand: "9bad=x brew upgrade"), "9bad=x")
    }

    func testReturnsNilWhenNothingUsableRemains() {
        XCTAssertNil(UpdateLane.key(forCommand: ""))
        XCTAssertNil(UpdateLane.key(forCommand: "   "))
        XCTAssertNil(UpdateLane.key(forCommand: "sudo env"))
        XCTAssertNil(UpdateLane.key(forCommand: "FOO=1"))
    }

    func testBooleanWrapperFlagsDoNotSwallowTheToolName() {
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -n brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -E brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "env -i brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo --non-interactive brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -S brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "env -S brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "nice -n 10 brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "exec -a foo brew upgrade x"), "brew")
    }

    func testValueTakingWrapperFlagsSkipTheirArgument() {
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -u kendrick brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -u kendrick -n brew upgrade x"), "brew")
    }

    func testAmbiguousWrapperSyntaxUsesTheGlobalBarrierLane() {
        XCTAssertEqual(
            UpdateLane.key(forCommand: "sudo --user kendrick brew upgrade x"),
            UpdateLane.globalBarrierKey
        )
        XCTAssertEqual(
            UpdateLane.key(forCommand: "env --split-string 'brew upgrade x'"),
            UpdateLane.globalBarrierKey
        )
    }
}
