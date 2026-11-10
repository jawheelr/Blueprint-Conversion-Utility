import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Where the wording of a piece of advice came from.
enum AdvisorSource: Sendable, Equatable {
    case onDeviceAI
    case builtIn(reason: String)

    var label: String {
        switch self {
        case .onDeviceAI: return "Summary written by Apple's on-device model. Details come from built-in rules and jamf-cli documentation."
        case .builtIn(let reason): return "Built-in guidance. \(reason)"
        }
    }
}

struct AdvisorItem: Identifiable, Hashable, Sendable {
    let finding: AdvisorFinding
    /// Best-matching jamf-cli documentation excerpt, if the corpus is bundled.
    let passage: AdvisorPassage?
    var id: String { finding.id }
}

struct AdvisorAdvice: Sendable, Equatable {
    var headline: String
    var topChanges: [String]
    var risks: [String]
    var items: [AdvisorItem]
    var source: AdvisorSource
    var corpusVersion: String?

    static func == (lhs: AdvisorAdvice, rhs: AdvisorAdvice) -> Bool {
        lhs.headline == rhs.headline && lhs.topChanges == rhs.topChanges && lhs.risks == rhs.risks
            && lhs.items.map(\.id) == rhs.items.map(\.id) && lhs.source == rhs.source
    }
}

/// Builds read-only advice. It never calls create, deploy or unscope, and it
/// only sees structured, redacted findings: never raw payloads, tool output or secrets.
enum AdvisorService {
    static func advise(findings: [AdvisorFinding]) async -> AdvisorAdvice {
        let index = AdvisorIndex.shared
        var items: [AdvisorItem] = []
        for finding in findings {
            var passage: AdvisorPassage?
            if let query = finding.category.retrievalQuery {
                passage = await index.retrieve(query: query, limit: 1, requiredTerms: finding.category.requiredTerms).first
            }
            items.append(AdvisorItem(finding: finding, passage: passage))
        }
        let version = await index.versionLabel
        var advice = builtIn(items: items, reason: "Apple Intelligence is not used on this Mac.", corpusVersion: version)
        guard !items.isEmpty else { return advice }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch AdvisorModel.availability() {
            case .available:
                let overall = await index.retrieve(
                    query: Set(items.compactMap { $0.finding.category.retrievalQuery }).sorted().joined(separator: ". "),
                    limit: 3
                )
                do {
                    let summary = try await AdvisorModel.summarize(items: items, reference: overall)
                    advice.headline = summary.headline
                    advice.topChanges = summary.topChanges
                    advice.risks = summary.risks
                    advice.source = .onDeviceAI
                    AppLogger.ai.notice("Advisor summary generated on device findings=\(items.count)")
                } catch {
                    advice.source = .builtIn(reason: "The on-device model could not produce a summary this time.")
                    AppLogger.ai.error("Advisor on-device summary failed: \(error.localizedDescription, privacy: .private)")
                }
            case .unavailable(let reason):
                advice.source = .builtIn(reason: reason)
                AppLogger.ai.notice("Advisor on-device model unavailable")
            }
        } else {
            advice.source = .builtIn(reason: "On-device AI needs macOS 26 or later.")
        }
        #else
        advice.source = .builtIn(reason: "This build does not include on-device AI support.")
        #endif
        return advice
    }

    static func builtIn(items: [AdvisorItem], reason: String, corpusVersion: String?) -> AdvisorAdvice {
        let actions = items.filter { $0.finding.severity == .action }
        let reviews = items.filter { $0.finding.severity == .review }
        let headline: String
        if items.isEmpty {
            headline = "Nothing to change was reported for this profile."
        } else if actions.isEmpty {
            headline = "No blocking changes. \(reviews.count) item(s) are worth a quick review."
        } else {
            headline = "\(actions.count) item(s) need your attention before you deploy."
        }
        var seen = Set<String>()
        let topChanges = actions.map { $0.finding.action }.filter { seen.insert($0).inserted }.prefix(5)
        let risks = reviews.map { "\($0.finding.subject.isEmpty ? $0.finding.category.title : $0.finding.subject): \($0.finding.explanation)" }.prefix(4)
        return AdvisorAdvice(
            headline: headline,
            topChanges: Array(topChanges),
            risks: Array(risks),
            items: items,
            source: .builtIn(reason: reason),
            corpusVersion: corpusVersion
        )
    }
}

#if canImport(FoundationModels)
struct AdvisorModelSummary: Sendable {
    var headline: String
    var topChanges: [String]
    var risks: [String]

    /// Parses the fixed line format requested in `AdvisorModel.instructions`.
    /// Returns nil when no headline was produced, so callers fall back to built-in text.
    static func parse(_ text: String) -> AdvisorModelSummary? {
        var headline = ""
        var changes: [String] = []
        var risks: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            func payload(_ prefix: String) -> String? {
                guard line.uppercased().hasPrefix(prefix) else { return nil }
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: ": -*").union(.whitespaces))
                return value.isEmpty ? nil : String(value.prefix(300))
            }
            if let value = payload("HEADLINE") { headline = value }
            else if let value = payload("CHANGE") { changes.append(value) }
            else if let value = payload("REVIEW") { risks.append(value) }
        }
        guard !headline.isEmpty else { return nil }
        return AdvisorModelSummary(headline: headline, topChanges: Array(changes.prefix(5)), risks: Array(risks.prefix(4)))
    }
}

@available(macOS 26.0, *)
enum AdvisorModel {
    enum Availability { case available; case unavailable(String) }

    static func availability() -> Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to add an AI-written summary.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device model is still downloading.")
        case .unavailable:
            return .unavailable("The on-device model is unavailable.")
        }
    }

    private static let instructions = """
    You help a Jamf administrator who is converting a Jamf Pro configuration profile into a Jamf Platform Blueprint. \
    Use only the findings and reference text you are given. Do not invent settings, payload types, menu names or steps. \
    Never recommend deploying, unscoping or deleting anything; only describe what to check or change first. \
    If something is not covered by the findings or reference, leave it out. Write short, plain sentences. \
    Answer in exactly this line format and nothing else: one line "HEADLINE: <one sentence, at most 30 words>", \
    then up to 5 lines "CHANGE: <one short imperative sentence>" for things that must change, most urgent first, \
    then up to 4 lines "REVIEW: <one short sentence>" for non-blocking things worth checking.
    """

    static func summarize(items: [AdvisorItem], reference: [AdvisorPassage]) async throws -> AdvisorModelSummary {
        var prompt = "Findings:\n"
        for (number, item) in items.prefix(12).enumerated() {
            let finding = item.finding
            let subject = finding.subject.isEmpty ? "" : " (\(finding.subject))"
            prompt += "\(number + 1). [\(finding.severity.label)] \(finding.category.title)\(subject): \(finding.explanation) Suggested action: \(finding.action)\n"
        }
        if !reference.isEmpty {
            prompt += "\nReference from jamf-cli documentation:\n"
            for passage in reference {
                prompt += "- \(passage.heading): \(String(passage.text.prefix(400)))\n"
            }
        }
        prompt += "\nSummarize what needs to change."
        let session = LanguageModelSession(instructions: instructions)
        let capped = String(prompt.prefix(5000))
        let text = try await withTimeout(seconds: 20) {
            try await session.respond(to: capped).content
        }
        guard let summary = AdvisorModelSummary.parse(text) else {
            throw AppFailure.message("The on-device model returned an unexpected format.")
        }
        return summary
    }

    private static func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AppFailure.message("The on-device model took too long.")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AppFailure.message("No result.") }
            return first
        }
    }
}
#endif
