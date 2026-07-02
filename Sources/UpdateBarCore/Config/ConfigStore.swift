import Foundation

public struct ConfigStore {
    private let paths: AppPaths
    private let fileManager: FileManager

    public init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func load() throws -> Config {
        try ensureHome()
        if !fileManager.fileExists(atPath: paths.configFile.path) {
            let config = Config.default
            try save(config)
            return config
        }
        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        return try parse(text)
    }

    public func loadExistingOrDefault() throws -> Config {
        if !fileManager.fileExists(atPath: paths.configFile.path) {
            return .default
        }
        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        return try parse(text)
    }

    public func save(_ config: Config) throws {
        try ensureHome()
        try AtomicFileWriter.write(Data(render(config).utf8), to: paths.configFile, fileManager: fileManager)
    }

    public func renderForDisplay(_ config: Config) -> String {
        render(config)
    }

    private func parse(_ text: String) throws -> Config {
        var config = Config.default
        var section = ""
        for (lineIndex, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !section.isEmpty else {
                throw ConfigError.corruptConfig("line \(lineNumber): invalid line \(line)")
            }
            if section == "provider" {
                continue
            }
            let key = "\(section).\(parts[0])"
            if key == "refresh.concurrency"
                || key == "security.allow_import_exec"
                || key == "security.allow_plaintext_secret_file"
                || key == "notify.enabled"
            {
                continue
            }
            let value = unquote(parts[1])
            do {
                try config.set(key, value: value)
            } catch {
                throw ConfigError.corruptConfig("line \(lineNumber): \(error)")
            }
        }
        return config
    }

    private func render(_ config: Config) -> String {
        """
        [refresh]
        interval = "\(config.refresh.interval)"

        [security]
        require_https_source = \(config.security.requireHTTPSSource)

        """
    }

    private func unquote(_ value: String) -> String {
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func ensureHome() throws {
        try AppHomeDirectory.ensure(paths.homeDirectory, fileManager: fileManager)
    }
}
