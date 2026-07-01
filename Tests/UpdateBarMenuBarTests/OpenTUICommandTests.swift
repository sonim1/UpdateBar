import UpdateBarMenuBar
import XCTest

final class OpenTUICommandTests: XCTestCase {
    func testBuildsTerminalCommandWithUpdateBarEnvironment() {
        let command = OpenTUICommand(
            cliPath: "/Applications/UpdateBar.app/Contents/Resources/updatebar",
            tuiCommand: "updatebar-tui",
            updateBarHome: "/tmp/updatebar-home"
        )

        XCTAssertEqual(command.executablePath, "/usr/bin/osascript")
        let joined = command.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("UPDATEBAR_BIN"))
        XCTAssertTrue(joined.contains("/Applications/UpdateBar.app/Contents/Resources/updatebar"))
        XCTAssertTrue(joined.contains("UPDATEBAR_HOME"))
        XCTAssertTrue(joined.contains("/tmp/updatebar-home"))
        XCTAssertTrue(joined.contains("updatebar-tui"))
    }

    func testTerminalCommandExplainsMissingTUIBinary() {
        let command = OpenTUICommand(
            cliPath: "/Applications/UpdateBar.app/Contents/Resources/updatebar",
            tuiCommand: "updatebar-tui",
            updateBarHome: nil
        )

        let joined = command.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("command -v"))
        XCTAssertTrue(joined.contains("updatebar-tui not found on PATH"))
        XCTAssertTrue(joined.contains("npm link"))
    }
}
