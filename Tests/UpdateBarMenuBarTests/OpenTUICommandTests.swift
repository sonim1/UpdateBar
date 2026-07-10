import Foundation
import UpdateBarMenuBar
import XCTest

final class OpenTUICommandTests: XCTestCase {
    private let cliPath = "/Applications/UpdateBar.app/Contents/Resources/updatebar"
    private let commandFileURL = URL(fileURLWithPath: "/tmp/UpdateBar/open-tui.command")

    func testCommandFileRunsCLITUISubcommand() {
        let command = OpenTUICommand(
            cliPath: cliPath,
            commandFileURL: commandFileURL,
            terminal: TUITerminal.fallback
        )

        XCTAssertTrue(command.commandFileContents.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(
            command.commandFileContents.contains(
                "exec '/Applications/UpdateBar.app/Contents/Resources/updatebar' tui"
            )
        )
        XCTAssertFalse(command.commandFileContents.contains("export"))
        XCTAssertFalse(command.commandFileContents.contains("command -v"))
        XCTAssertFalse(command.commandFileContents.contains("npm"))
    }

    func testShellQuotesCLIPathsWithSpaces() {
        let command = OpenTUICommand(
            cliPath: "/tmp/my tools/updatebar",
            commandFileURL: commandFileURL,
            terminal: TUITerminal.fallback
        )

        XCTAssertTrue(
            command.commandFileContents.contains("exec '/tmp/my tools/updatebar' tui")
        )
    }

    func testDocumentStyleTerminalOpensCommandFileByBundleID() {
        let command = OpenTUICommand(
            cliPath: cliPath,
            commandFileURL: commandFileURL,
            terminal: TUITerminal(
                id: "com.apple.Terminal",
                name: "Terminal",
                launchStyle: .openDocument
            )
        )

        XCTAssertEqual(command.executablePath, "/usr/bin/open")
        XCTAssertEqual(
            command.arguments,
            ["-b", "com.apple.Terminal", "/tmp/UpdateBar/open-tui.command"]
        )
    }

    func testArgumentStyleTerminalPassesCommandFileBehindFlags() {
        let command = OpenTUICommand(
            cliPath: cliPath,
            commandFileURL: commandFileURL,
            terminal: TUITerminal(
                id: "com.mitchellh.ghostty",
                name: "Ghostty",
                launchStyle: .openWithArgs(["-e"])
            )
        )

        XCTAssertEqual(command.executablePath, "/usr/bin/open")
        XCTAssertEqual(
            command.arguments,
            ["-nb", "com.mitchellh.ghostty", "--args", "-e", "/tmp/UpdateBar/open-tui.command"]
        )
    }

    func testKnownTerminalsHaveUniqueBundleIDsAndTerminalFallback() {
        let ids = TUITerminal.known.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(TUITerminal.fallback.id, "com.apple.Terminal")
        XCTAssertEqual(TUITerminal.known(id: "com.googlecode.iterm2")?.name, "iTerm")
        XCTAssertEqual(TUITerminal.known(id: "dev.warp.Warp-Stable")?.name, "Warp")
        XCTAssertEqual(TUITerminal.known(id: "com.raphaelamorim.rio")?.name, "Rio")
    }

    func testWarpLaunchesThroughLaunchConfigURI() throws {
        let command = OpenTUICommand(
            cliPath: cliPath,
            commandFileURL: commandFileURL,
            terminal: try XCTUnwrap(TUITerminal.known(id: "dev.warp.Warp-Stable")),
            homeDirectory: URL(fileURLWithPath: "/Users/tester")
        )

        let auxiliary = try XCTUnwrap(command.auxiliaryFile)
        XCTAssertEqual(
            auxiliary.url.path,
            "/Users/tester/.warp/launch_configurations/updatebar-tui.yaml"
        )
        XCTAssertTrue(auxiliary.contents.contains("name: UpdateBar TUI"))
        XCTAssertTrue(auxiliary.contents.contains("cwd: \"/Users/tester\""))
        XCTAssertTrue(
            auxiliary.contents.contains("exec: '/tmp/UpdateBar/open-tui.command'")
        )

        XCTAssertEqual(command.executablePath, "/usr/bin/open")
        XCTAssertEqual(
            command.arguments,
            ["warp://launch//Users/tester/.warp/launch_configurations/updatebar-tui.yaml"]
        )
    }

    func testNonWarpTerminalsNeedNoAuxiliaryFile() {
        for terminal in TUITerminal.known where terminal.id != "dev.warp.Warp-Stable" {
            let command = OpenTUICommand(
                cliPath: cliPath,
                commandFileURL: commandFileURL,
                terminal: terminal
            )
            XCTAssertNil(command.auxiliaryFile, terminal.name)
        }
    }
}
