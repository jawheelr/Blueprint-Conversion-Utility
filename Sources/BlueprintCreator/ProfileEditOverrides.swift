import Foundation

struct ProfileSettingOverride: Identifiable, Hashable {
    let id: String
    let profileID: String
    let payloadID: String
    let nodeID: String
    let displayName: String
    let rawKey: String
    let sourceValue: String
    var proposedValue: String
    let recommendation: SettingRecommendation
    let reason: String
    var decision: OverrideDecision
}

enum OverrideDecision: String, CaseIterable, Identifiable, Hashable {
    case apply = "Apply to Destination"
    case keepSource = "Keep Source Value"
    case reviewLater = "Review Later"
    var id: String { rawValue }
}
