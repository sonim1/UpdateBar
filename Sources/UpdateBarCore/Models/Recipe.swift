import Foundation

public struct Recipe: Codable, Equatable {
    public var id: String
    public var name: String
    public var category: String
    public var path: String?
    public var source: Source
    public var versionScheme: VersionScheme
    public var check: CheckSpec
    public var latest: LatestSpec
    public var versionParse: VersionParse
    public var update: UpdateSpec
    public var pin: String?
    public var enabled: Bool
    public var notify: Bool
    public var trust: Trust

    public init(
        id: String,
        name: String,
        category: String,
        path: String?,
        source: Source,
        versionScheme: VersionScheme,
        check: CheckSpec,
        latest: LatestSpec,
        versionParse: VersionParse,
        update: UpdateSpec,
        pin: String?,
        enabled: Bool,
        notify: Bool,
        trust: Trust
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.path = path
        self.source = source
        self.versionScheme = versionScheme
        self.check = check
        self.latest = latest
        self.versionParse = versionParse
        self.update = update
        self.pin = pin
        self.enabled = enabled
        self.notify = notify
        self.trust = trust
    }

    public var hasCommandFields: Bool {
        !commandFingerprints().isEmpty
    }

    public func commandTexts() -> [String: String] {
        var commands: [String: String] = [:]
        if case let .command(cmd) = check {
            commands["check.cmd"] = cmd
        }
        if latest.strategy == .cmd, let cmd = latest.cmd {
            commands["latest.cmd"] = cmd
        }
        commands["update.cmd"] = update.cmd
        return commands
    }

    public func commandWorkingDirectories() -> [String: String] {
        guard let cwd = update.cwd else { return [:] }
        return ["update.cmd": cwd]
    }

    public func commandFingerprints() -> [String: String] {
        var commands: [String: String] = [:]
        let checkMaterial = check.fingerprintMaterial()
        let latestMaterial = latest.fingerprintMaterial(source: source)
        if case let .command(cmd) = check {
            commands["check.cmd"] = Fingerprint.sha256("\(id)|check.cmd|\(cmd)|")
        }
        if latest.strategy == .cmd, let cmd = latest.cmd {
            commands["latest.cmd"] = Fingerprint.sha256("\(id)|latest.cmd|\(cmd)|")
        }
        let cwd = update.cwd ?? ""
        commands["update.cmd"] = Fingerprint.sha256(
            "\(id)|update.cmd|\(update.cmd)|\(cwd)|\(checkMaterial)|\(latestMaterial)"
        )
        return commands
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case path
        case source
        case versionScheme = "version_scheme"
        case check
        case latest
        case versionParse = "version_parse"
        case update
        case pin
        case enabled
        case notify
        case trust
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        source = try container.decode(Source.self, forKey: .source)
        versionScheme = try container.decode(VersionScheme.self, forKey: .versionScheme)
        check = try container.decode(CheckSpec.self, forKey: .check)
        latest = try container.decode(LatestSpec.self, forKey: .latest)
        versionParse = try container.decode(VersionParse.self, forKey: .versionParse)
        update = try container.decode(UpdateSpec.self, forKey: .update)
        pin = try container.decodeIfPresent(String.self, forKey: .pin)
        if container.contains(.enabled) {
            enabled = try container.decode(Bool.self, forKey: .enabled)
        } else {
            enabled = true
        }
        if container.contains(.notify) {
            notify = try container.decode(Bool.self, forKey: .notify)
        } else {
            notify = true
        }
        trust = try container.decode(Trust.self, forKey: .trust)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encode(source, forKey: .source)
        try container.encode(versionScheme, forKey: .versionScheme)
        try container.encode(check, forKey: .check)
        try container.encode(latest, forKey: .latest)
        try container.encode(versionParse, forKey: .versionParse)
        try container.encode(update, forKey: .update)
        try container.encodeIfPresent(pin, forKey: .pin)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(trust, forKey: .trust)
    }
}

public struct Source: Codable, Equatable {
    public var kind: SourceKind
    public var ref: String
    public var branch: String?

    public init(kind: SourceKind, ref: String, branch: String?) {
        self.kind = kind
        self.ref = ref
        self.branch = branch
    }
}

public enum SourceKind: String, Codable, Equatable {
    case git
    case npm
    case githubRelease = "github_release"
    case brew
    case http
    case custom
}

public enum VersionScheme: String, Codable, Equatable {
    case semver
    case commit
    case calver
    case opaque
}

public enum CheckSpec: Codable, Equatable {
    case command(String)
    case file(path: String)

    enum CodingKeys: String, CodingKey {
        case cmd
        case file
        case query
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let cmd = try container.decodeIfPresent(String.self, forKey: .cmd) {
            self = .command(cmd)
            return
        }
        if container.contains(.query) {
            throw DecodingError.dataCorruptedError(
                forKey: .query,
                in: container,
                debugDescription: "check.query is unsupported"
            )
        }
        let file = try container.decode(String.self, forKey: .file)
        self = .file(path: file)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .command(cmd):
            try container.encode(cmd, forKey: .cmd)
        case let .file(path):
            try container.encode(path, forKey: .file)
        }
    }

    fileprivate func fingerprintMaterial() -> String {
        switch self {
        case let .command(cmd):
            return "cmd|\(cmd)"
        case let .file(path):
            return "file|\(path)"
        }
    }
}

public struct LatestSpec: Codable, Equatable {
    public var strategy: LatestStrategyKind
    public var cmd: String?
    public var pattern: String?

    public init(strategy: LatestStrategyKind, cmd: String?, pattern: String?) {
        self.strategy = strategy
        self.cmd = cmd
        self.pattern = pattern
    }

    fileprivate func fingerprintMaterial(source: Source) -> String {
        [
            "strategy=\(strategy.rawValue)",
            "source.kind=\(source.kind.rawValue)",
            "source.ref=\(source.ref)",
            "source.branch=\(source.branch ?? "")",
            "cmd=\(cmd ?? "")",
            "pattern=\(pattern ?? "")",
        ].joined(separator: "|")
    }
}

public enum LatestStrategyKind: String, Codable, Equatable {
    case gitTags = "git_tags"
    case gitHead = "git_head"
    case npmRegistry = "npm_registry"
    case githubRelease = "github_release"
    case brew
    case httpRegex = "http_regex"
    case cmd
}

public enum VersionParse: Codable, Equatable {
    case regex(String)
    case jq(String)

    enum CodingKeys: String, CodingKey {
        case regex
        case jq
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let regex = try container.decodeIfPresent(String.self, forKey: .regex) {
            self = .regex(regex)
            return
        }
        self = .jq(try container.decode(String.self, forKey: .jq))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .regex(regex):
            try container.encode(regex, forKey: .regex)
        case let .jq(jq):
            try container.encode(jq, forKey: .jq)
        }
    }
}

public struct UpdateSpec: Codable, Equatable {
    public var cmd: String
    public var requiresWrite: Bool
    public var cwd: String?

    public init(cmd: String, requiresWrite: Bool = true, cwd: String?) {
        self.cmd = cmd
        self.requiresWrite = requiresWrite
        self.cwd = cwd
    }

    enum CodingKeys: String, CodingKey {
        case cmd
        case requiresWrite = "requires_write"
        case cwd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cmd = try container.decode(String.self, forKey: .cmd)
        if container.contains(.requiresWrite) {
            requiresWrite = try container.decode(Bool.self, forKey: .requiresWrite)
        } else {
            requiresWrite = true
        }
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cmd, forKey: .cmd)
        try container.encode(requiresWrite, forKey: .requiresWrite)
        try container.encodeIfPresent(cwd, forKey: .cwd)
    }
}

public struct Trust: Codable, Equatable {
    public var level: TrustLevel
    public var approvedCommands: [String: String]

    public init(level: TrustLevel, approvedCommands: [String: String]) {
        self.level = level
        self.approvedCommands = approvedCommands
    }

    enum CodingKeys: String, CodingKey {
        case level
        case approvedCommands = "approved_commands"
    }
}

public enum TrustLevel: String, Codable, Equatable {
    case trusted
    case untrusted
    case elevated
}
