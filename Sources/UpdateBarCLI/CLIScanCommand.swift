import ArgumentParser
import UpdateBarCore

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan installed local tools without modifying UpdateBar state."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Option(
        name: .long,
        help: ArgumentHelp("Filter by category: \(ScanCategory.description)."),
        completion: .list(ScanCategory.completionValues)
    )
    var category: String?

    func run() throws {
        let categoryFilter = try ScanCategory.filterValue(for: category)
        let selectedDetectors = try ScanCategory.defaultDetectors(for: categoryFilter)
        let service = ScanService()
        let report = try service.scan(detectors: selectedDetectors).filtered(
            category: categoryFilter)

        if json {
            try printJSON(report)
        } else {
            printHuman(report, categoryFilter: categoryFilter)
        }
    }

    private func printHuman(_ report: ScanReport, categoryFilter: String?) {
        writeStdout("Found \(report.candidates.count) candidate(s)")
        writeStdout("")
        printEmptyResultHintIfNeeded(report, categoryFilter: categoryFilter)
        let recommended = report.candidates.filter { $0.capability == .full }
        let needsReview = report.candidates.filter { $0.capability != .full }
        let nextIndex = printSection("Recommended", candidates: recommended, startIndex: 1)
        printNextStep(recommended, categoryFilter: categoryFilter)
        if !recommended.isEmpty && !needsReview.isEmpty {
            writeStdout("")
        }
        _ = printSection("Needs Review", candidates: needsReview, startIndex: nextIndex)
        printReviewOnlyNote(
            recommended: recommended, needsReview: needsReview, categoryFilter: categoryFilter)
        if !report.errors.isEmpty {
            writeStderr("")
            writeStderr("Errors")
            for error in report.errors {
                writeStderr("- \(error.detector.rawValue): \(error.message)")
            }
        }
    }

    private func printEmptyResultHintIfNeeded(_ report: ScanReport, categoryFilter: String?) {
        guard report.candidates.isEmpty else { return }
        if let categoryFilter {
            writeStdout("No candidates found for category \(categoryFilter).")
            writeStdout("Try updatebar scan without --category.")
        } else {
            writeStdout("No candidates found. Check that supported tools are installed.")
        }
        writeStdout("")
    }

    private func printSection(
        _ title: String,
        candidates: [ScanCandidate],
        startIndex: Int
    ) -> Int {
        guard !candidates.isEmpty else { return startIndex }
        writeStdout(title)
        writeStdout(sectionHeader(for: candidates).joined(separator: "\t"))
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
            let visibleFields =
                metadataSourceRef(for: candidate).map {
                    fields + [$0]
                } ?? fields
            writeStdout(visibleFields.joined(separator: "\t"))
        }
        writeStdout("")
        return startIndex + candidates.count
    }

    private func sectionHeader(for candidates: [ScanCandidate]) -> [String] {
        var fields = ["ITEM", "ID", "CATEGORY", "SOURCE", "CAPABILITY"]
        if candidates.contains(where: { metadataSourceRef(for: $0) != nil }) {
            fields.append("REF")
        }
        return fields
    }

    private func printReviewOnlyNote(
        recommended: [ScanCandidate],
        needsReview: [ScanCandidate],
        categoryFilter: String?
    ) {
        guard recommended.isEmpty, !needsReview.isEmpty else {
            return
        }
        writeStdout("Review-only candidates are not importable yet.")
        if categoryFilter != nil {
            writeStdout("Run updatebar scan without --category to look for importable candidates.")
        }
        writeStdout("")
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

    private func printNextStep(_ candidates: [ScanCandidate], categoryFilter: String?) {
        let importable = candidates.filter { $0.recipe != nil }
        guard !importable.isEmpty else { return }
        let baseCommand =
            categoryFilter.map {
                "updatebar init --category \($0)"
            } ?? "updatebar init"
        var commands = [baseCommand]
        if importable.count >= 2 {
            let ids = importable.prefix(2).map(\.id).joined(separator: ",")
            commands.append("\(baseCommand) --select \(ids)")
        }
        commands.append("\(baseCommand) --select all")
        writeStdout("Scan is read-only. Use init to choose and register items.")
        printNextCommands(commands, leadingBlank: false)
    }
}
