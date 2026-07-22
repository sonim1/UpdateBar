import Foundation
import UpdateBarMenuBar
import XCTest

final class MenuBarCommandEnvironmentTests: XCTestCase {
    func testAddsCommonInteractiveCLIPathsToRestrictedGUIPath() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        let environment = MenuBarCommandEnvironment.make(
            base: [
                "PATH": "/custom/bin:relative:/usr/bin",
                "HOME": home.path,
                "OPENROUTER_API_KEY": "sk-or-v1-secret-value",
            ],
            homeDirectory: home
        )

        XCTAssertEqual(
            environment["PATH"]?.split(separator: ":").map(String.init),
            [
                "/custom/bin",
                "/usr/bin",
                "/Users/example/.local/bin",
                "/Users/example/.volta/bin",
                "/Users/example/.asdf/shims",
                "/Users/example/.nodenv/shims",
                "/Users/example/.nvm/current/bin",
                "/Users/example/.local/share/fnm/aliases/default/bin",
                "/Users/example/.cargo/bin",
                "/Users/example/.bun/bin",
                "/Users/example/.local/share/mise/shims",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
            ]
        )
        XCTAssertNil(environment["OPENROUTER_API_KEY"])
    }
}
