import Foundation
import NaturalLanguage

/// A short excerpt from jamf-cli's own documentation, with where it came from.
struct AdvisorPassage: Codable, Hashable, Identifiable, Sendable {
    let id: String
    /// Human-readable origin, e.g. "jamf-cli 1.36.0 · import-profile --help".
    let source: String
    let heading: String
    let text: String
}

struct AdvisorCorpus: Codable, Sendable {
    let version: String
    let passages: [AdvisorPassage]
}

/// Retrieval over the corpus that `bcu build-advisor-index` bundles into the app.
///
/// Nothing is fetched at runtime. Ranking combines Apple's on-device sentence
/// embedding (NaturalLanguage) with keyword overlap, so it still works if the
/// embedding model is unavailable.
actor AdvisorIndex {
    static let shared = AdvisorIndex()

    private var corpus: AdvisorCorpus?
    private var vectors: [String: [Double]] = [:]
    private var documentFrequency: [String: Int] = [:]
    private var tokenized: [String: Set<String>] = [:]
    private var loaded = false
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    var versionLabel: String? { corpus?.version }
    var isAvailable: Bool { !(corpus?.passages.isEmpty ?? true) }

    /// Test and tooling hook: use an explicit corpus instead of the bundled one.
    func load(_ explicit: AdvisorCorpus) {
        install(explicit)
    }

    func retrieve(query: String, limit: Int = 3, minimumScore: Double = 0.3, requiredTerms: [String] = []) -> [AdvisorPassage] {
        loadBundledIfNeeded()
        guard let corpus, !corpus.passages.isEmpty, limit > 0 else { return [] }
        let queryTokens = Self.tokens(in: query)
        guard !queryTokens.isEmpty else { return [] }
        let queryVector = embedding?.vector(for: String(query.prefix(600)))

        var keywordScores: [String: Double] = [:]
        let documentCount = Double(corpus.passages.count)
        for passage in corpus.passages {
            let words = tokenized[passage.id] ?? []
            var score = 0.0
            for token in queryTokens where words.contains(token) {
                let df = Double(documentFrequency[token] ?? 1)
                score += log(1 + documentCount / df)
            }
            keywordScores[passage.id] = score
        }
        let maxKeyword = keywordScores.values.max() ?? 0

        var scored: [(AdvisorPassage, Double)] = []
        for passage in corpus.passages {
            if !requiredTerms.isEmpty {
                let haystack = (passage.heading + " " + passage.text).lowercased()
                guard requiredTerms.contains(where: { haystack.contains($0) }) else { continue }
            }
            let keyword = maxKeyword > 0 ? (keywordScores[passage.id] ?? 0) / maxKeyword : 0
            var semantic = 0.0
            if let queryVector, let vector = vector(for: passage) {
                semantic = max(0, Self.cosine(queryVector, vector))
            }
            let score = queryVector == nil ? keyword : (0.6 * semantic + 0.4 * keyword)
            if score >= minimumScore { scored.append((passage, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    // MARK: - Loading

    private func loadBundledIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Advisor"),
              let url = urls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AdvisorCorpus.self, from: data) else {
            AppLogger.ai.notice("Advisor corpus not found in the app bundle; guidance will use built-in rules only")
            return
        }
        install(decoded)
        AppLogger.ai.notice("Advisor corpus loaded passages=\(decoded.passages.count)")
    }

    private func install(_ value: AdvisorCorpus) {
        loaded = true
        corpus = value
        vectors = [:]
        documentFrequency = [:]
        tokenized = [:]
        for passage in value.passages {
            let words = Self.tokens(in: passage.heading + " " + passage.text)
            tokenized[passage.id] = words
            for word in words { documentFrequency[word, default: 0] += 1 }
        }
    }

    private func vector(for passage: AdvisorPassage) -> [Double]? {
        if let cached = vectors[passage.id] { return cached }
        guard let embedding,
              let computed = embedding.vector(for: String((passage.heading + ". " + passage.text).prefix(600))) else { return nil }
        vectors[passage.id] = computed
        return computed
    }

    // MARK: - Math

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "is", "it", "for", "on", "as", "be", "by",
        "with", "that", "this", "are", "was", "not", "can", "if", "so", "at", "from", "which", "when"
    ]

    static func tokens(in text: String) -> Set<String> {
        var result = Set<String>()
        var word = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber || character == "." || character == "-" || character == "_" {
                word.append(character)
            } else {
                if word.count > 2 { result.insert(word) }
                word = ""
            }
        }
        if word.count > 2 { result.insert(word) }
        return result.subtracting(stopWords)
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        let denominator = (na.squareRoot() * nb.squareRoot())
        return denominator == 0 ? 0 : dot / denominator
    }
}
