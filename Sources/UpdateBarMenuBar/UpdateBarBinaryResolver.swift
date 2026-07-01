import Foundation

public struct UpdateBarBinaryResolution: Equatable, Sendable {
    public var path: String
    public var source: UpdateBarBinarySource

    public init(path: String, source: UpdateBarBinarySource) {
        self.path = path
        self.source = source
    }
}

public enum UpdateBarBinarySource: String, Equatable, Sendable {
    case updateBarBin = "UPDATEBAR_BIN"
    case configured = "configured"
    case bundled = "bundled"
    case path = "PATH"
    case developmentFallback = "development_fallback"
}

public enum UpdateBarBinaryResolverError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidPath(source: UpdateBarBinarySource, path: String)
    case notFound

    public var description: String {
        switch self {
        case .invalidPath(let source, let path):
            return "\(source.rawValue) path is not executable: \(path)"
        case .notFound:
            return "updatebar binary not found"
        }
    }
}

public struct UpdateBarBinaryResolver {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configuredPath: String? = nil,
        bundledDirectory: URL? = nil,
        developmentRoot: URL? = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        defaultPathEntries: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) throws -> UpdateBarBinaryResolution {
        if let resolution = try explicitPath(environment["UPDATEBAR_BIN"], source: .updateBarBin) {
            return resolution
        }
        if let resolution = try explicitPath(configuredPath, source: .configured) {
            return resolution
        }
        if let bundledDirectory,
            let path = executablePath(
                bundledDirectory.appendingPathComponent("updatebar", isDirectory: false).path)
        {
            return UpdateBarBinaryResolution(path: path, source: .bundled)
        }
        if let path = pathCandidate(environment: environment, defaultPathEntries: defaultPathEntries) {
            return UpdateBarBinaryResolution(path: path, source: .path)
        }
        if let developmentRoot, let path = developmentCandidate(root: developmentRoot) {
            return UpdateBarBinaryResolution(path: path, source: .developmentFallback)
        }
        throw UpdateBarBinaryResolverError.notFound
    }

    private func explicitPath(
        _ path: String?,
        source: UpdateBarBinarySource
    ) throws -> UpdateBarBinaryResolution? {
        guard let path, !path.isEmpty else { return nil }
        guard let executable = executablePath(path) else {
            throw UpdateBarBinaryResolverError.invalidPath(source: source, path: path)
        }
        return UpdateBarBinaryResolution(path: executable, source: source)
    }

    private func pathCandidate(
        environment: [String: String],
        defaultPathEntries: [String]
    ) -> String? {
        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init) + defaultPathEntries
        var seen: Set<String> = []
        for directory in pathEntries where seen.insert(directory).inserted {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent("updatebar", isDirectory: false)
                .path
            if let path = executablePath(candidate) {
                return path
            }
        }
        return nil
    }

    private func developmentCandidate(root: URL) -> String? {
        let candidates = [
            ".build/debug/updatebar",
            ".build/arm64-apple-macosx/debug/updatebar",
            ".build/x86_64-apple-macosx/debug/updatebar",
        ]
        for candidate in candidates {
            let path = root.appendingPathComponent(candidate, isDirectory: false).path
            if let executable = executablePath(path) {
                return executable
            }
        }
        return nil
    }

    private func executablePath(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard fileManager.isExecutableFile(atPath: url.path) else { return nil }
        return url.path
    }
}
