import Foundation

public struct ScanService {
    public static let brewListCommand =
        [
            "if command -v brew >/dev/null 2>&1; then",
            "leaves=$(brew leaves --installed-on-request 2>/dev/null || brew leaves 2>/dev/null || true);",
            "if [ -n \"$leaves\" ]; then brew list --formula --versions $leaves; fi;",
            "fi",
        ].joined(separator: " ")
    public static let npmGlobalListCommand =
        "if command -v npm >/dev/null 2>&1; then npm ls -g --depth=0 --json; fi"
    public static let knownToolsCommand =
        #"for tool in rtk gstack gh claude codex node swift brew npm; do if command -v "$tool" >/dev/null 2>&1; then version=$("$tool" --version 2>/dev/null | head -n 1 || true); printf "%s\t%s\n" "$tool" "$version"; fi; done"#

    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandExecutor()) {
        self.commandRunner = commandRunner
    }

    public func scan(detectors: [ScanDetector] = ScanDetector.allCases) throws -> ScanReport {
        var candidates: [ScanCandidate] = []
        var errors: [ScanError] = []

        for detector in detectors {
            do {
                candidates.append(contentsOf: try scan(detector: detector))
            } catch {
                errors.append(ScanError(detector: detector, message: String(describing: error)))
            }
        }

        return ScanReport(candidates: dedupe(candidates).sorted(by: sortCandidates), errors: errors)
    }

    private func scan(detector: ScanDetector) throws -> [ScanCandidate] {
        switch detector {
        case .brew:
            return try brewCandidates()
        case .npmGlobal:
            return try npmGlobalCandidates()
        case .known:
            return try knownCandidates()
        }
    }

    private func brewCandidates() throws -> [ScanCandidate] {
        let output = try run(Self.brewListCommand)
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.first else { return nil }
            let version = parts.dropFirst().first
            let recipe = Recipe(
                id: "brew.\(idComponent(name))",
                name: name,
                category: category(for: name, detector: .brew),
                path: nil,
                source: Source(kind: .brew, ref: name, branch: nil),
                versionScheme: .calver,
                check: .command("brew list --versions \(ShellQuote.single(name))"),
                latest: LatestSpec(strategy: .brew, cmd: nil, pattern: nil),
                versionParse: .regex("([0-9][0-9A-Za-z._+-]*)"),
                update: UpdateSpec(cmd: "brew upgrade \(ShellQuote.single(name))", cwd: nil),
                pin: nil,
                enabled: true,
                trust: Trust(level: .untrusted, approvedCommands: [:])
            )
            return ScanCandidate(
                id: recipe.id,
                name: name,
                detector: .brew,
                category: recipe.category,
                capability: .full,
                confidence: .high,
                installedVersion: version,
                sourceRef: name,
                recipe: recipe
            )
        }
    }

    private func npmGlobalCandidates() throws -> [ScanCandidate] {
        let output = try run(Self.npmGlobalListCommand)
        guard let data = output.data(using: .utf8), !data.isEmpty else { return [] }
        let decoded = try JSONDecoder().decode(NPMGlobalList.self, from: data)
        return decoded.dependencies.map { package, info in
            let id = "npm.\(idComponent(package))"
            let category = category(for: package, detector: .npmGlobal)
            let recipe = Recipe(
                id: id,
                name: package,
                category: category,
                path: nil,
                source: Source(kind: .npm, ref: package, branch: nil),
                versionScheme: .semver,
                check: .command("npm ls -g --depth=0 \(ShellQuote.single(package)) --json"),
                latest: LatestSpec(strategy: .npmRegistry, cmd: nil, pattern: nil),
                versionParse: .regex(#""version"\s*:\s*"([^"]+)""#),
                update: UpdateSpec(
                    cmd: "npm install -g \(ShellQuote.single(package))@latest", cwd: nil),
                pin: nil,
                enabled: true,
                trust: Trust(level: .untrusted, approvedCommands: [:])
            )
            return ScanCandidate(
                id: id,
                name: package,
                detector: .npmGlobal,
                category: category,
                capability: .full,
                confidence: .high,
                installedVersion: info.version,
                sourceRef: package,
                recipe: recipe
            )
        }
    }

    private func knownCandidates() throws -> [ScanCandidate] {
        try run(Self.knownToolsCommand)
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.split(
                    separator: "\t", maxSplits: 1, omittingEmptySubsequences: false
                )
                .map(String.init)
                guard let name = parts.first, !name.isEmpty else { return nil }
                let versionLine = parts.count > 1 ? parts[1] : nil
                return ScanCandidate(
                    id: "known.\(idComponent(name))",
                    name: name,
                    detector: .known,
                    category: category(for: name, detector: .known),
                    capability: .checkOnly,
                    confidence: .medium,
                    installedVersion: extractVersion(from: versionLine),
                    sourceRef: name,
                    recipe: nil
                )
            }
    }

    private func run(_ command: String) throws -> String {
        let result = try commandRunner.run(
            ShellCommand(command: command, cwd: nil),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024 * 1024)
        )
        guard result.exitCode == 0 else {
            throw ScanServiceError.commandFailed(
                command: command, exitCode: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
    }

    private func dedupe(_ candidates: [ScanCandidate]) -> [ScanCandidate] {
        let managerOwnedNames = Set(
            candidates
                .filter { $0.detector != .known && $0.capability == .full }
                .map { $0.name.lowercased() }
        )
        var seenIDs = Set<String>()
        return candidates.filter { candidate in
            guard seenIDs.insert(candidate.id).inserted else {
                return false
            }
            return !(candidate.detector == .known
                && managerOwnedNames.contains(candidate.name.lowercased()))
        }
    }

    private func sortCandidates(_ lhs: ScanCandidate, _ rhs: ScanCandidate) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        if lhs.detector != rhs.detector {
            return lhs.detector.rawValue < rhs.detector.rawValue
        }
        return lhs.name < rhs.name
    }

    private func idComponent(_ value: String) -> String {
        let cleaned =
            value
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "/", with: ".")
            .unicodeScalars
            .map { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_"
                    || scalar == "-"
                    ? String(scalar)
                    : "-"
            }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return cleaned.isEmpty ? "tool" : cleaned
    }

    private func category(for name: String, detector: ScanDetector) -> String {
        let normalized = name.lowercased()
        let leafName = normalized.split(separator: "/").last.map(String.init) ?? normalized
        let simpleName = leafName.split(separator: "@").first.map(String.init) ?? leafName
        let isScopedPackage = detector == .npmGlobal && normalized.hasPrefix("@")

        if [
            "claude", "claude-code", "codex", "rtk", "gstack", "aider", "opencode",
            "gemini", "gemini-cli", "agent-browser",
        ].contains(simpleName) || normalized == "@anthropic-ai/claude-code" {
            return "ai-agent"
        }
        if isScopedPackage {
            return "library"
        }
        if [
            "brew", "npm", "pnpm", "yarn", "bun", "pipx", "uv", "cargo", "rustup",
            "corepack",
        ].contains(simpleName) {
            return "package-manager"
        }
        if [
            "node", "nodejs", "python", "python3", "ruby", "go", "golang", "rust", "swift",
            "java",
        ].contains(simpleName) {
            return "runtime-sdk"
        }
        if [
            "gh", "aws", "gcloud", "vercel", "wrangler", "flyctl", "kubectl", "docker", "terraform",
            "cloudflared", "supabase",
        ].contains(simpleName) {
            return "cloud-devops"
        }
        if ["jq", "ripgrep", "rg", "fd", "fzf", "bat", "eza", "zoxide", "starship", "tmux"]
            .contains(simpleName)
        {
            return "shell-utility"
        }
        if detector == .npmGlobal {
            return "library"
        }
        return "shell-utility"
    }

    private func extractVersion(from line: String?) -> String? {
        guard let line else { return nil }
        let pattern = #"[0-9]+(?:\.[0-9A-Za-z_-]+)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
            let range = Range(match.range, in: line)
        else {
            return nil
        }
        return String(line[range])
    }

    private struct NPMGlobalList: Decodable {
        var dependencies: [String: Package]

        struct Package: Decodable {
            var version: String?
        }
    }
}

public enum ScanServiceError: Error, CustomStringConvertible {
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .commandFailed(let command, let exitCode, let stderr):
            return "\(command): exited \(exitCode): \(stderr)"
        }
    }
}
