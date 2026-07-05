import Foundation

public enum ShellQuote {
    public static func single(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
