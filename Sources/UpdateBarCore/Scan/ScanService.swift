import Foundation

public struct ScanService {
    public static let brewListCommand =
        [
            "if command -v brew >/dev/null 2>&1; then",
            "leaves=$(brew leaves --installed-on-request 2>&1);",
            "status=$?;",
            "if [ $status -ne 0 ]; then",
            "fallback=$(brew leaves 2>&1);",
            "fallback_status=$?;",
            "if [ $fallback_status -ne 0 ]; then",
            "printf \"%s\\n%s\\n\" \"$leaves\" \"$fallback\" >&2;",
            "exit $fallback_status;",
            "fi;",
            "leaves=$fallback;",
            "fi;",
            "if [ -n \"$leaves\" ]; then brew list --formula --versions $leaves; fi;",
            "fi",
        ].joined(separator: " ")
    public static let npmGlobalListCommand =
        "if command -v npm >/dev/null 2>&1; then npm ls -g --depth=0 --json; fi"
    public static let knownToolsCommand =
        #"for tool in rtk gstack gh claude codex node swift brew npm; do if command -v "$tool" >/dev/null 2>&1; then version=$("$tool" --version 2>/dev/null | head -n 1 || true); printf "%s\t%s\n" "$tool" "$version"; fi; done"#

    private let commandRunner: CommandRunning
    private let homeDirectory: URL

    public init(
        commandRunner: CommandRunning = CommandExecutor(),
        homeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.commandRunner = commandRunner
        self.homeDirectory = homeDirectory ?? Self.defaultHomeDirectory(environment: environment)
    }

    public func scan(detectors: [ScanDetector] = ScanDetector.allCases) throws -> ScanReport {
        var candidates: [ScanCandidate] = []
        var errors: [ScanError] = []

        for detector in detectors {
            do {
                candidates.append(contentsOf: try scan(detector: detector))
            } catch {
                let message = SecretRedactor.redact(String(describing: error))
                errors.append(ScanError(detector: detector, message: message))
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
        case .codexSkill:
            return try codexSkillCandidates()
        case .mcpConfig:
            return try mcpConfigCandidates()
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

    private func codexSkillCandidates() throws -> [ScanCandidate] {
        try [
            ".codex/skills",
            ".agents/skills",
        ].flatMap { root in
            try codexSkillCandidates(in: homeDirectory.appendingPathComponent(root), root: root)
        }
    }

    private func codexSkillCandidates(in directory: URL, root: String) throws -> [ScanCandidate] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return []
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                FileManager.default.fileExists(
                    atPath: url.appendingPathComponent("SKILL.md").path
                )
            else {
                return nil
            }
            let name = url.lastPathComponent
            return ScanCandidate(
                id: "codex_skill.\(idComponent(name))",
                name: name,
                detector: .codexSkill,
                category: "codex-skill",
                capability: .metadataOnly,
                confidence: .high,
                installedVersion: nil,
                sourceRef: "~/\(root)/\(name)",
                recipe: nil
            )
        }
    }

    private func mcpConfigCandidates() throws -> [ScanCandidate] {
        try Self.mcpConfigSources.flatMap { source in
            let url = homeRelativeURL(source.path)
            switch source.kind {
            case .json:
                return try mcpConfigCandidatesFromJSON(url: url, displayPath: source.path)
            case .codexTOML:
                return try mcpConfigCandidatesFromCodexTOML(url: url, displayPath: source.path)
            }
        }
    }

    private func mcpConfigCandidatesFromJSON(
        url: URL,
        displayPath: String
    ) throws -> [ScanCandidate] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let servers = object["mcpServers"] as? [String: Any]
                ?? object["mcp_servers"] as? [String: Any]
        else {
            return []
        }

        return servers.compactMap { name, value in
            let server = value as? [String: Any]
            return mcpConfigCandidate(
                name: name,
                command: server?["command"] as? String,
                displayPath: displayPath
            )
        }
    }

    private func mcpConfigCandidatesFromCodexTOML(
        url: URL,
        displayPath: String
    ) throws -> [ScanCandidate] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        var names = Set<String>()
        var commands: [String: String] = [:]
        var currentName: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentName = mcpServerName(fromTOMLSection: String(line.dropFirst().dropLast()))
                if let currentName {
                    names.insert(currentName)
                }
                continue
            }
            guard let currentName else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == "command" else { continue }
            commands[currentName] = unquoteTOMLValue(parts[1])
        }

        return names.compactMap { name in
            mcpConfigCandidate(name: name, command: commands[name], displayPath: displayPath)
        }
    }

    private func mcpConfigCandidate(
        name: String,
        command: String?,
        displayPath: String
    ) -> ScanCandidate? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }
        let command = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScanCandidate(
            id: "mcp_config.\(idComponent(name))",
            name: name,
            detector: .mcpConfig,
            category: "mcp-server",
            capability: .metadataOnly,
            confidence: .medium,
            installedVersion: nil,
            sourceRef: command?.isEmpty == false ? command : "~/\(displayPath)#\(name)",
            recipe: nil
        )
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
        let managerOwnedNames =
            candidates
                .filter { $0.detector != .known && $0.capability == .full }
                .reduce(into: Set<String>()) { names, candidate in
                    names.formUnion(managerOwnedKnownToolNames(for: candidate))
                }
        var seenIDs = Set<String>()
        return candidates.filter { candidate in
            guard seenIDs.insert(candidate.id).inserted else {
                return false
            }
            return !(candidate.detector == .known
                && managerOwnedNames.contains(candidate.name.lowercased()))
        }
    }

    private func managerOwnedKnownToolNames(for candidate: ScanCandidate) -> Set<String> {
        var names = Set([candidate.name.lowercased()])
        if candidate.detector == .brew, let versionlessName = versionlessBrewName(candidate.name) {
            names.insert(versionlessName)
        }
        if candidate.detector == .npmGlobal,
            candidate.category == "ai-agent",
            let packageLeafName = scopedPackageLeafName(candidate.name)
        {
            names.insert(packageLeafName)
        }
        if candidate.detector == .npmGlobal {
            names.formUnion(scopedPackageCommandAliases(candidate.name))
        }
        return names
    }

    private func versionlessBrewName(_ name: String) -> String? {
        let normalized = name.lowercased()
        guard let suffixStart = normalized.firstIndex(of: "@") else { return nil }
        let versionlessName = normalized[..<suffixStart]
        return versionlessName.isEmpty ? nil : String(versionlessName)
    }

    private func scopedPackageLeafName(_ name: String) -> String? {
        let normalized = name.lowercased()
        guard normalized.hasPrefix("@"),
            let slashIndex = normalized.firstIndex(of: "/")
        else {
            return nil
        }
        let leafName = normalized[normalized.index(after: slashIndex)...]
        return leafName.isEmpty ? nil : String(leafName)
    }

    private func scopedPackageCommandAliases(_ name: String) -> Set<String> {
        switch name.lowercased() {
        case "@anthropic-ai/claude-code":
            return ["claude"]
        default:
            return []
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

    private func homeRelativeURL(_ relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(homeDirectory) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func mcpServerName(fromTOMLSection section: String) -> String? {
        let prefix = "mcp_servers."
        guard section.hasPrefix(prefix) else {
            return nil
        }
        let rawName = String(section.dropFirst(prefix.count))
        if rawName.contains(".") && !rawName.hasPrefix("\"") && !rawName.hasPrefix("'") {
            return nil
        }
        let name = unquoteTOMLValue(rawName)
        return name.isEmpty ? nil : name
    }

    private func unquoteTOMLValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
            (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
                || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
        {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func defaultHomeDirectory(environment: [String: String]) -> URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    private static let mcpConfigSources: [MCPConfigSource] = [
        MCPConfigSource(path: ".cursor/mcp.json", kind: .json),
        MCPConfigSource(path: ".claude.json", kind: .json),
        MCPConfigSource(
            path: "Library/Application Support/Claude/claude_desktop_config.json",
            kind: .json
        ),
        MCPConfigSource(path: ".codex/config.toml", kind: .codexTOML),
    ]

    private struct MCPConfigSource {
        var path: String
        var kind: MCPConfigKind
    }

    private enum MCPConfigKind {
        case json
        case codexTOML
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
        case .commandFailed(_, let exitCode, let stderr):
            let detail = Self.normalizedStderr(stderr)
            guard !detail.isEmpty else {
                return "exited \(exitCode)"
            }
            return "exited \(exitCode): \(detail)"
        }
    }

    private static func normalizedStderr(_ stderr: String) -> String {
        var seen = Set<String>()
        let normalized = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: "\n")
        return SecretRedactor.redact(normalized)
    }
}
