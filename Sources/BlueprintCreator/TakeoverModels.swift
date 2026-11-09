import Foundation

enum BlueprintEditorMode: String, CaseIterable, Identifiable {
    case gui, json
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum ProfileWorkflowMode: String, CaseIterable, Identifiable {
    case takeover, standard
    var id: String { rawValue }
    var title: String { self == .takeover ? "Profile Takeover" : "Standard Conversion" }
}

enum ProfileImportMode: String, CaseIterable, Identifiable {
    case preserveInstalled, convert
    var id: String { rawValue }
    var title: String { self == .preserveInstalled ? "Preserve Installed Profile / Attempt Takeover" : "Convert to Native DDM Components" }
}

enum ImportScopeMode: String, CaseIterable, Identifiable {
    case preserveSource, overrideSelected
    var id: String { rawValue }
    var title: String { self == .preserveSource ? "Preserve Source Profile Scope" : "Override with Selected Platform Group" }
}

enum RecommendedProfileApproach: String, Sendable {
    case analyzing
    case takeover
    case convert
    case createForReview
    case unavailable
    case evaluationIncomplete

    var title: String {
        switch self {
        case .analyzing: return "Analyzing Configuration Profile"
        case .takeover: return "Take Over the Installed Profile"
        case .convert: return "Convert to a New Blueprint"
        case .createForReview: return "Create Blueprint for Review"
        case .unavailable: return "No Safe Import Path Found"
        case .evaluationIncomplete: return "Evaluation Incomplete"
        }
    }
}

enum TakeoverVerdict: String, Sendable {
    case notEvaluated, supported, unsupported, previewGenerated, failed, unknown
    var title: String {
        switch self {
        case .notEvaluated: return "Takeover Not Evaluated"
        case .supported: return "Takeover Supported"
        case .unsupported: return "Takeover Not Supported"
        case .previewGenerated: return "Preview Generated"
        case .failed: return "Takeover Analysis Failed"
        case .unknown: return "Takeover Verdict Unknown"
        }
    }
}

struct TakeoverCapabilities: Equatable, Sendable {
    var commandAvailable = false
    var supportsConvert = false
    var supportsComputerGroups = false
    var supportsMobileGroups = false
    var supportsSkipExclusions = false
    var supportsSkipLimitations = false
    var supportsStripDefaults = false
    var supportsIncludeUnsupported = false
    var supportsTakeoverOnly = false
    var supportsDeploy = false
}

enum DeploymentIntent: String, CaseIterable, Identifiable, Sendable {
    case createOnly
    case createAndDeploy
    case createDeployAndUnscope
    var id: String { rawValue }
    var title: String {
        switch self {
        case .createOnly: return "Create Only"
        case .createAndDeploy: return "Create and Deploy"
        case .createDeployAndUnscope: return "Create, Deploy, and Unscope"
        }
    }
    var requestsDeployment: Bool { self != .createOnly }
    var requestsUnscope: Bool { self == .createDeployAndUnscope }
}

enum DeploymentEligibility: Equatable, Sendable {
    case allowed
    case createOnly([String])
    case blocked([String])
    case reevaluationRequired([String])

    var canCreate: Bool {
        switch self { case .allowed, .createOnly: return true; case .blocked, .reevaluationRequired: return false }
    }
    var canDeploy: Bool { if case .allowed = self { return true }; return false }
    var reasons: [String] {
        switch self { case .allowed: return []; case .createOnly(let r), .blocked(let r), .reevaluationRequired(let r): return r }
    }
}


struct TakeoverImportResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let verdict: TakeoverVerdict
    let messages: [String]
    let droppedKeys: [String]
}


enum BlueprintRunStage: String, CaseIterable, Sendable {
    case idle
    case validatingAPI
    case preparing
    case downloadingProfile
    case resolvingScope
    case processingPayloads
    case evaluatingTakeover
    case generatingBlueprint
    case validatingJSON
    case awaitingDeployment
    case creatingBlueprint
    case completed
    case failed

    var title: String {
        switch self {
        case .idle: return "Ready"
        case .validatingAPI: return "Validating API credentials"
        case .preparing: return "Preparing operation"
        case .downloadingProfile: return "Downloading configuration profile"
        case .resolvingScope: return "Resolving profile scope"
        case .processingPayloads: return "Processing payloads"
        case .evaluatingTakeover: return "Evaluating takeover support"
        case .generatingBlueprint: return "Generating Blueprint"
        case .validatingJSON: return "Validating Blueprint JSON"
        case .awaitingDeployment: return "Waiting for deployment choice"
        case .creatingBlueprint: return "Creating Blueprint"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

enum TakeoverEvaluationState: Equatable {
    case notEvaluated
    case waiting
    case evaluating
    case supported
    case unsupported
    case failed(String)
}

struct BlueprintComponentOption: Identifiable, Equatable {
    let index: Int
    let identifier: String
    var included: Bool
    var id: Int { index }
}

enum BlueprintFieldKind: String, Equatable {
    case text
    case number
    case boolean
    case null
}

struct BlueprintEditableField: Identifiable, Equatable {
    let path: String
    let label: String
    let kind: BlueprintFieldKind
    var value: String
    var id: String { path }
}
