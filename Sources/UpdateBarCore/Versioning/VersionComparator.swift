import Foundation

public enum VersionComparator {
    public enum VersionError: Error, Equatable {
        case invalidSemVer(String)
        case invalidCalVer(String)
    }

    public static func status(current: String, latest: String, scheme: VersionScheme) throws -> ItemStatus {
        switch scheme {
        case .semver:
            return try compareSemVer(current, latest) == .orderedAscending ? .outdated : .ok
        case .calver:
            return try compareCalVer(current, latest) == .orderedAscending ? .outdated : .ok
        case .commit:
            return current == latest ? .ok : .outdated
        case .opaque:
            return current == latest ? .ok : .differs
        }
    }

    public static func compareSemVer(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        let left = try SemVer(lhs)
        let right = try SemVer(rhs)
        return left.compare(to: right)
    }

    public static func compareCalVer(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
        let left = numericTokens(lhs)
        let right = numericTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            throw VersionError.invalidCalVer("\(lhs) / \(rhs)")
        }
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericTokens(_ version: String) -> [Int] {
        version.split { !$0.isNumber }.compactMap { Int($0) }
    }
}

private struct SemVer {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init(_ raw: String) throws {
        let buildParts = raw.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard let coreAndPrerelease = buildParts.first, !coreAndPrerelease.isEmpty else {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }
        if buildParts.count == 2, buildParts[1].isEmpty {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }

        let parts = coreAndPrerelease.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard !parts[0].isEmpty else {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }

        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard core.count == 3 else {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }
        let major = try Self.parseCoreIdentifier(core[0], raw: raw)
        let minor = try Self.parseCoreIdentifier(core[1], raw: raw)
        let patch = try Self.parseCoreIdentifier(core[2], raw: raw)

        self.major = major
        self.minor = minor
        self.patch = patch
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            try identifiers.forEach { try Self.validatePrereleaseIdentifier($0, raw: raw) }
            self.prerelease = identifiers
        } else {
            self.prerelease = []
        }
    }

    func compare(to other: SemVer) -> ComparisonResult {
        for (left, right) in [(major, other.major), (minor, other.minor), (patch, other.patch)] {
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }

        if prerelease.isEmpty && other.prerelease.isEmpty { return .orderedSame }
        if prerelease.isEmpty { return .orderedDescending }
        if other.prerelease.isEmpty { return .orderedAscending }

        for index in 0..<max(prerelease.count, other.prerelease.count) {
            guard index < prerelease.count else { return .orderedAscending }
            guard index < other.prerelease.count else { return .orderedDescending }
            let left = prerelease[index]
            let right = other.prerelease[index]
            if left == right { continue }
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (.some(leftValue), .some(rightValue)):
                if leftValue < rightValue { return .orderedAscending }
                if leftValue > rightValue { return .orderedDescending }
            case (.some, .none):
                return .orderedAscending
            case (.none, .some):
                return .orderedDescending
            case (.none, .none):
                return left < right ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func parseCoreIdentifier(_ value: String, raw: String) throws -> Int {
        guard isASCIIDigits(value), !(value.count > 1 && value.first == "0"), let parsed = Int(value) else {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }
        return parsed
    }

    private static func validatePrereleaseIdentifier(_ value: String, raw: String) throws {
        guard !value.isEmpty,
            value.unicodeScalars.allSatisfy({ scalar in
                ("0"..."9").contains(scalar) || ("A"..."Z").contains(scalar)
                    || ("a"..."z").contains(scalar) || scalar == "-"
            })
        else {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }
        if isASCIIDigits(value), value.count > 1, value.first == "0" {
            throw VersionComparator.VersionError.invalidSemVer(raw)
        }
    }

    private static func isASCIIDigits(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }
}
