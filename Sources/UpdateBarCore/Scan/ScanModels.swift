import Foundation

public struct ScanReport: Codable, Equatable {
    public var candidates: [ScanCandidate]
    public var errors: [ScanError]

    public init(candidates: [ScanCandidate], errors: [ScanError]) {
        self.candidates = candidates
        self.errors = errors
    }
}

public struct ScanCandidate: Codable, Equatable {
    public var id: String
    public var name: String
    public var detector: ScanDetector
    public var category: String
    public var capability: ScanCapability
    public var confidence: ScanConfidence
    public var installedVersion: String?
    public var sourceRef: String?
    public var recipe: Recipe?

    public init(
        id: String,
        name: String,
        detector: ScanDetector,
        category: String,
        capability: ScanCapability,
        confidence: ScanConfidence,
        installedVersion: String?,
        sourceRef: String?,
        recipe: Recipe?
    ) {
        self.id = id
        self.name = name
        self.detector = detector
        self.category = category
        self.capability = capability
        self.confidence = confidence
        self.installedVersion = installedVersion
        self.sourceRef = sourceRef
        self.recipe = recipe
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case detector
        case category
        case capability
        case confidence
        case installedVersion = "installed_version"
        case sourceRef = "source_ref"
        case recipe
    }
}

public enum ScanDetector: String, Codable, Equatable, CaseIterable {
    case brew
    case npmGlobal = "npm_global"
    case known
    case codexSkill = "codex_skill"
    case mcpConfig = "mcp_config"
}

public enum ScanCapability: String, Codable, Equatable {
    case full
    case checkOnly = "check-only"
    case metadataOnly = "metadata-only"
    case unsupported
}

public enum ScanConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
}

public struct ScanError: Codable, Equatable {
    public var detector: ScanDetector
    public var message: String

    public init(detector: ScanDetector, message: String) {
        self.detector = detector
        self.message = message
    }
}
