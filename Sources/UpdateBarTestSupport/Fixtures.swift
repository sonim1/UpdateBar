import Foundation

public enum TestFixtures {
    public static func fixtureURL(_ components: String...) -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures")
        return components.reduce(root) { partial, component in
            partial.appendingPathComponent(component)
        }
    }
}
