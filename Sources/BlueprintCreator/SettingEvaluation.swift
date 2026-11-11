import Foundation

enum SettingRecommendation: String, CaseIterable, Hashable {
    case keep = "Keep"
    case convert = "Convert"
    case edit = "Edit Before Conversion"
    case replace = "Replace"
    case remove = "Remove"
    case legacy = "Preserve as Legacy"
    case review = "Review"
    case metadata = "Metadata"
    var priority: Int { [.metadata, .keep, .convert, .legacy, .review, .edit, .replace, .remove].firstIndex(of: self) ?? 0 }
}

enum RecommendationTiming: String, Hashable {
    case before = "Before Blueprint creation"
    case during = "During BCU review"
    case after = "After Blueprint creation"
    case never = "Do not edit"
}

enum RecommendationConfidence: String, Hashable { case high = "High", medium = "Medium", low = "Low" }

struct SettingEvaluation: Hashable {
    let recommendation: SettingRecommendation
    let timing: RecommendationTiming
    let confidence: RecommendationConfidence
    let reason: String
    let migrationBehavior: String
    let proposedValue: String?
    let evidence: [String]
}

struct PayloadEvaluation: Hashable {
    let recommendation: SettingRecommendation
    let summary: String
    let primaryFinding: String?
}

enum SettingEvaluationService {
    private static let metadata: Set<String> = ["PayloadType", "PayloadVersion", "PayloadIdentifier", "PayloadUUID", "PayloadDisplayName", "PayloadDescription", "PayloadOrganization", "PayloadEnabled"]

    static func evaluate(_ node: ProfileInspectorNode, payload: ProfileInspectorPayload) -> SettingEvaluation {
        if metadata.contains(node.rawKey) {
            return result(.metadata, .never, .high, "This field describes or identifies the payload instead of configuring device behavior.", "Preserve metadata. Do not independently change identifiers or UUIDs because references may depend on them.", nil, ["Common profile metadata key"])
        }
        if node.schema.lifecycle == .removed {
            return result(.remove, .before, .high, "Apple marks this setting as removed.", "Do not carry the setting forward unless a supported replacement is identified for the target platform.", nil, ["Apple lifecycle: Removed"])
        }
        if node.schema.lifecycle == .deprecated {
            return result(.replace, .during, .high, "Apple marks this setting as deprecated.", "Review the modern declarative or payload-specific replacement before deployment.", nil, ["Apple lifecycle: Deprecated"])
        }
        if node.schema.kind == .unknown {
            return result(.review, .during, .medium, "No exact or wildcard Apple schema definition matched this property.", "Preserve it as unknown or vendor-defined content and confirm destination support.", nil, ["Schema match: Unknown", node.pathString])
        }
        if node.schema.kind == .wildcard {
            return result(.legacy, .during, .medium, "Apple permits this key through an ANY wildcard but does not define its vendor-specific semantics.", "Preserve as managed or vendor preference content unless an explicit migration rule exists.", nil, ["Apple ANY wildcard match"])
        }
        let key = node.rawKey.lowercased()
        if key == "encryptiontype", case .string(let value) = node.value, value.lowercased() == "none" {
            return result(.edit, .before, .high, "This Wi-Fi payload specifies no encryption. Confirm that the network is intentionally open.", "Keep None only for an intentionally open network; otherwise select the network's actual encryption and authentication mode.", "Confirm the required Wi-Fi encryption type", ["Configured value: None", payload.payloadType])
        }
        if key.contains("password") || key.contains("secret") {
            return result(.review, .before, .medium, "Credential material requires explicit migration handling.", "Confirm whether the destination expects an asset, encrypted credential, or user-supplied value.", nil, ["Credential-like key", node.value.typeName])
        }
        if key.contains("uuid") || key == "identifier" || key.hasSuffix("identifier") {
            return result(.keep, .never, .high, "This identifier can participate in references.", "Preserve it unless BCU rewrites all related references as one operation.", nil, ["Identifier/reference field"])
        }
        if node.children.isEmpty {
            return result(.keep, .never, .high, "The configured value matches a current Apple schema property and has no lifecycle conflict.", "Preserve without semantic change unless jamf-cli reports a destination-specific transformation.", node.value.description, ["Exact Apple schema match", "Lifecycle: Current"])
        }
        return result(.convert, .during, .medium, "This structured setting contains schema-recognized configured children.", "Convert the children together while preserving dictionary or array relationships.", nil, ["Structured configured value", "Children: \(node.children.count)"])
    }

    static func evaluate(_ payload: ProfileInspectorPayload) -> PayloadEvaluation {
        let values = flatten(payload.nodes).map { evaluate($0, payload: payload) }
        let counts = Dictionary(grouping: values, by: \.recommendation).mapValues(\.count)
        let primary = values.max { $0.recommendation.priority < $1.recommendation.priority }
        let summary = SettingRecommendation.allCases.compactMap { action in counts[action].map { "\($0) \(action.rawValue.lowercased())" } }.joined(separator: ", ")
        return PayloadEvaluation(recommendation: primary?.recommendation ?? .keep, summary: summary, primaryFinding: primary?.reason)
    }

    private static func flatten(_ nodes: [ProfileInspectorNode]) -> [ProfileInspectorNode] { nodes.flatMap { [$0] + flatten($0.children) } }
    private static func result(_ recommendation: SettingRecommendation, _ timing: RecommendationTiming, _ confidence: RecommendationConfidence, _ reason: String, _ behavior: String, _ proposed: String?, _ evidence: [String]) -> SettingEvaluation {
        SettingEvaluation(recommendation: recommendation, timing: timing, confidence: confidence, reason: reason, migrationBehavior: behavior, proposedValue: proposed, evidence: evidence)
    }
}
