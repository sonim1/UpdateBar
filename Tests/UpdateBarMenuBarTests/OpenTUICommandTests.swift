import UpdateBarMenuBar
import XCTest

final class OpenTUICommandTests: XCTestCase {
    func testRunsBundledCLITUISubcommandInTerminal() {
        let command = OpenTUICommand(
            cliPath: "/Applications/UpdateBar.app/Contents/Resources/updatebar"
        )

        XCTAssertEqual(command.executablePath, "/usr/bin/osascript")
        let joined = command.arguments.joined(separator: " ")
        XCTAssertTrue(
            joined.contains(
                "exec '/Applications/UpdateBar.app/Contents/Resources/updatebar' tui"
            )
        )
        XCTAssertTrue(joined.contains("tell application \"Terminal\" to activate"))
    }

    func testTerminalCommandStaysSimple() {
        let command = OpenTUICommand(
            cliPath: "/Applications/UpdateBar.app/Contents/Resources/updatebar"
        )

        let joined = command.arguments.joined(separator: " ")
        XCTAssertFalse(joined.contains("export"))
        XCTAssertFalse(joined.contains("command -v"))
        XCTAssertFalse(joined.contains("if "))
        XCTAssertFalse(joined.contains("npm"))
    }

    func testShellQuotesCLIPathsWithSpaces() {
        let command = OpenTUICommand(cliPath: "/tmp/my tools/updatebar")

        let joined = command.arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("exec '/tmp/my tools/updatebar' tui"))
    }
}
