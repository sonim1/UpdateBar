import ArgumentParser
import UpdateBarCore

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan installed local tools without modifying UpdateBar state."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Option(name: .long, help: .hidden)
    var detectors: String?

    @Option(name: .long, help: "Filter by category: ai-agent, package-manager, runtime-sdk, shell-utility, cloud-devops, library, codex-skill, or mcp-server.")
    var category: String?

    func run() throws {
        let categoryFilter = try parseCategoryFilter(category)
        let selectedDetectors = try parseDetectors(categoryFilter: categoryFilter)
        let service = ScanService()
        var report = try service.scan(detectors: selectedDetectors)
        if let category = categoryFilter {
            report.candidates = report.candidates.filter { $0.category == category }
        }

        if json {
            try printJSON(report)
        } else {
            printHuman(report)
        }
    }

    private func parseDetectors(categoryFilter: String?) throws -> [ScanDetector] {
        try parseScanDetectors(detectors, categoryFilter: categoryFilter)
    }

    private func printHuman(_ report: ScanReport) {
        print("Found \(report.candidates.count) candidate(s)")
        print("")
        let recommended = report.candidates.filter { $0.capability == .full }
        let needsReview = report.candidates.filter { $0.capability != .full }
        let nextIndex = printSection("Recommended", candidates: recommended, startIndex: 1)
        _ = printSection("Needs Review", candidates: needsReview, startIndex: nextIndex)
        printReviewOnlyNote(recommended: recommended, needsReview: needsReview)
        printNextStep(recommended)
        if !report.errors.isEmpty {
            print("")
            print("Errors")
            for error in report.errors {
                print("- \(error.detector.rawValue): \(error.message)")
            }
        }
    }

    private func printSection(
        _ title: String,
        candidates: [ScanCandidate],
        startIndex: Int
    ) -> Int {
        guard !candidates.isEmpty else { return startIndex }
        print(title)
        for (index, candidate) in candidates.enumerated() {
            let version = candidate.installedVersion.map { " \($0)" } ?? ""
            let name = "[\(startIndex + index)] \(candidate.name)\(version)"
            let fields = [
                name,
                candidate.id,
                candidate.category,
                candidate.detector.rawValue,
                candidate.capability.rawValue,
            ]
            let visibleFields = metadataSourceRef(for: candidate).map {
                fields + [$0]
            } ?? fields
            print(visibleFields.joined(separator: "\t"))
        }
        print("")
        return startIndex + candidates.count
    }

    private func printReviewOnlyNote(
        recommended: [ScanCandidate],
        needsReview: [ScanCandidate]
    ) {
        guard recommended.isEmpty, !needsReview.isEmpty else {
            return
        }
        print("Review-only candidates are not importable yet.")
        print("")
    }

    private func metadataSourceRef(for candidate: ScanCandidate) -> String? {
        guard candidate.capability != .full,
            let sourceRef = candidate.sourceRef,
            !sourceRef.isEmpty
        else {
            return nil
        }
        return sourceRef
    }

    private func printNextStep(_ candidates: [ScanCandidate]) {
        let ids = candidates.compactMap { candidate in
            candidate.recipe == nil ? nil : candidate.id
        }
        guard !ids.isEmpty else { return }
        print("Next")
        print("updatebar init")
        print("updatebar init --select \(ids.joined(separator: ","))")
        print("")
    }
}
