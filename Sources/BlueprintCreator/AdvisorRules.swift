import Foundation

/// How urgently an administrator should look at a finding.
enum FindingSeverity: Int, Comparable, Sendable {
    case info = 0
    case review = 1
    case action = 2

    static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .info: return "FYI"
        case .review: return "Review"
        case .action: return "Needs action"
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .review: return "exclamationmark.circle"
        case .action: return "exclamationmark.triangle.fill"
        }
    }
}

enum AdvisorCategory: String, CaseIterable, Sendable {
    case unsupportedPayloadSkipped
    case customSettingsMCX
    case keptInProfileWrapper
    case emptyPayloadRemoved
    case payloadTypeRewritten
    case ddmRequiresNewOS
    case payloadRemovedMissingKey
    case domainUnwrapped
    case legacyPayloadReadOnly
    case takeoverNotSupported
    case takeoverNotRequested
    case takeoverSupported
    case conflictingDeployment
    case redactedCredentials
    case scopeNotCarriedOver
    case unrecognized

    /// Short phrase used as a retrieval query and as a list heading.
    var title: String {
        switch self {
        case .unsupportedPayloadSkipped: return "Payload not supported by blueprints"
        case .customSettingsMCX: return "Delivered as Custom Settings (MCX)"
        case .keptInProfileWrapper: return "Setting kept in the profile wrapper"
        case .emptyPayloadRemoved: return "Empty payload removed"
        case .payloadTypeRewritten: return "Payload type renamed"
        case .ddmRequiresNewOS: return "Needs macOS or iOS 26"
        case .payloadRemovedMissingKey: return "Payload removed: required key missing"
        case .domainUnwrapped: return "Custom Settings converted to a native component"
        case .legacyPayloadReadOnly: return "Legacy payload is API-only"
        case .takeoverNotSupported: return "Takeover not supported"
        case .takeoverNotRequested: return "Takeover not requested"
        case .takeoverSupported: return "Takeover supported"
        case .conflictingDeployment: return "Overlap with the Classic profile"
        case .redactedCredentials: return "Redacted credential values"
        case .scopeNotCarriedOver: return "Scope not carried over"
        case .unrecognized: return "Other message"
        }
    }
}

extension AdvisorCategory {
    /// What to look up in the jamf-cli documentation for this category. Nil means
    /// the documentation does not cover it, so no excerpt is shown.
    var retrievalQuery: String? {
        switch self {
        case .unsupportedPayloadSkipped:
            return "payload types disabled by blueprints skipped certificates VPN SSO web clips fonts include-unsupported"
        case .customSettingsMCX:
            return "payload type not accepted standalone delivered as Application and Custom Settings MCX"
        case .keptInProfileWrapper:
            return "no DDM equivalent kept in configuration-profile component legacy payload read-only Jamf Pro UI"
        case .emptyPayloadRemoved:
            return "payload removed empty no settings metadata stripping"
        case .payloadTypeRewritten:
            return "blueprints API only accepts canonical payload type spelling"
        case .ddmRequiresNewOS:
            return "native DDM component promoted payloads safari-settings macOS iOS 26"
        case .payloadRemovedMissingKey:
            return "DDM API requires key removed payload source profile did not include it validation"
        case .domainUnwrapped:
            return "Custom Settings MCX unwrapped inner preference domain DDM converter"
        case .legacyPayloadReadOnly:
            return "legacy payload components managed only through the blueprints API read-only"
        case .takeoverNotSupported:
            return "takeover not available when payload mirror installed profile installs alongside Classic profile"
        case .takeoverNotRequested:
            return "takeover opt-in --takeover keep the profile as installed convert default"
        case .takeoverSupported:
            return "takeover adopt copy of profile already installed on devices large fleet unscope warning"
        case .conflictingDeployment:
            return "deploying blueprint beside Classic profile conflicting settings unscope the Classic profile"
        case .scopeNotCarriedOver:
            return "scope handling device groups only carried over exclusions limitations individual computers"
        case .redactedCredentials, .unrecognized:
            return nil
        }
    }
}

extension AdvisorCategory {
    /// An excerpt is only shown if it mentions at least one of these (lower-case) terms.
    /// This keeps a loosely related passage from being presented as documentation.
    var requiredTerms: [String] {
        switch self {
        case .unsupportedPayloadSkipped: return ["disabled outright", "certificates"]
        case .customSettingsMCX: return ["custom settings"]
        case .keptInProfileWrapper: return ["legacy payload", "configuration-profile component"]
        case .emptyPayloadRemoved: return ["removed as empty"]
        case .payloadTypeRewritten: return ["canonical", "spelling"]
        case .ddmRequiresNewOS: return ["ios 26"]
        case .payloadRemovedMissingKey: return ["modulename", "required field", "required key"]
        case .domainUnwrapped: return ["unwrapped"]
        case .legacyPayloadReadOnly: return ["read-only", "legacy payload"]
        case .takeoverNotSupported, .takeoverNotRequested, .takeoverSupported: return ["takeover"]
        case .conflictingDeployment: return ["alongside", "beside", "conflict"]
        case .scopeNotCarriedOver: return ["scope"]
        case .redactedCredentials, .unrecognized: return []
        }
    }
}

/// One thing the converter did, or one thing the administrator must still do.
struct AdvisorFinding: Identifiable, Hashable, Sendable {
    let category: AdvisorCategory
    /// The payload type, key or component the message is about (may be empty).
    let subject: String
    let severity: FindingSeverity
    let explanation: String
    let action: String
    /// The original tool message, kept so the panel can show exactly what jamf-cli said.
    let sourceLine: String

    var id: String { category.rawValue + "|" + subject }
}

/// Maps jamf-cli / profileconvert output and profile scope to plain-language findings.
///
/// Pure and deterministic: this is the source of truth for what was skipped or
/// changed. The optional on-device model only rephrases and prioritises these.
enum AdvisorRules {
    static func findings(
        from lines: [String],
        scope: ProfileScope? = nil,
        redactedFieldCount: Int = 0
    ) -> [AdvisorFinding] {
        var seen = Set<String>()
        var result: [AdvisorFinding] = []
        func add(_ finding: AdvisorFinding) {
            if seen.insert(finding.id).inserted { result.append(finding) }
        }
        for line in lines {
            if let finding = classify(line) { add(finding) }
        }
        if redactedFieldCount > 0 {
            add(AdvisorFinding(
                category: .redactedCredentials,
                subject: "\(redactedFieldCount)",
                severity: .action,
                explanation: "Jamf Pro hides stored passwords and secrets (Wi-Fi, VPN, accounts) when it returns a profile. \(redactedFieldCount) such field(s) came back as placeholder text, so the blueprint would carry the placeholder, not the real value.",
                action: "Re-enter these values in the blueprint before deploying, or keep the secret-bearing payload in the Classic profile.",
                sourceLine: "\(redactedFieldCount) redacted credential field(s)"
            ))
        }
        if let scope {
            for finding in scopeFindings(scope) { add(finding) }
        }
        return result.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.id < rhs.id
        }
    }

    static func scopeFindings(_ scope: ProfileScope) -> [AdvisorFinding] {
        var found: [AdvisorFinding] = []
        func make(_ subject: String, _ explanation: String, _ action: String) -> AdvisorFinding {
            AdvisorFinding(category: .scopeNotCarriedOver, subject: subject, severity: .action,
                           explanation: explanation, action: action, sourceLine: "Profile scope: \(scope.summary)")
        }
        if scope.allDevices {
            found.append(make("all devices",
                "The profile is scoped to all devices. Blueprints only target device groups, so this scope is not carried over.",
                "Choose a device group that contains the devices you want (a smart group with the right criteria works)."))
        }
        if scope.individualDeviceCount > 0 {
            found.append(make("individual devices",
                "\(scope.individualDeviceCount) individually scoped device(s) cannot be expressed in a blueprint.",
                "Put those devices in a static device group and target that group."))
        }
        if scope.otherTargetCount > 0 {
            found.append(make("buildings, departments or users",
                "\(scope.otherTargetCount) building, department or user target(s) have no blueprint equivalent.",
                "Recreate that targeting with a smart device group before deploying."))
        }
        if scope.limitationCount > 0 {
            found.append(make("limitations",
                "\(scope.limitationCount) scope limitation(s) cannot be carried over, so the blueprint could reach more devices than the profile did.",
                "Review the target group so it matches the limited audience before you deploy."))
        }
        if scope.exclusionCount > 0 {
            found.append(make("exclusions",
                "\(scope.exclusionCount) scope exclusion(s) exist. Excluded device groups carry over; other exclusion types do not.",
                "Confirm excluded devices are not in the target group before you deploy."))
        }
        return found
    }

    static func classify(_ rawLine: String) -> AdvisorFinding? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let lower = line.lowercased()
        if lower.hasPrefix("[dry-run] would create blueprint") { return nil }
        let quoted = quotedValues(in: line)

        func finding(_ category: AdvisorCategory, _ subject: String, _ severity: FindingSeverity,
                     _ explanation: String, _ action: String) -> AdvisorFinding {
            AdvisorFinding(category: category, subject: subject, severity: severity,
                           explanation: explanation, action: action, sourceLine: line)
        }

        if lower.contains("skipped payload type") {
            let type = quoted.first ?? "unknown"
            return finding(.unsupportedPayloadSkipped, type, .action,
                "Jamf blueprints cannot carry \(type) (certificates, VPN, SSO and similar payloads are disabled), so it was left out of the blueprint.",
                "Keep this payload in a Classic configuration profile, or deliver it another way. Do not unscope the source profile until you have.")
        }
        if lower.contains("is not a standalone blueprints payload") {
            let type = quoted.first ?? "unknown"
            return finding(.customSettingsMCX, type, .review,
                "\(type) is not one of the payload types blueprints accept on their own, so it is delivered as Application & Custom Settings (MCX), which still applies the settings.",
                "No change needed for the settings to apply. It also means this profile cannot be taken over in place.")
        }
        if lower.contains("kept in profile wrapper") {
            let key = quoted.first ?? "unknown"
            return finding(.keptInProfileWrapper, key, .info,
                "\(key) has no native Jamf DDM control, so it stays inside the configuration-profile component of the blueprint. It still applies, but it cannot be edited as a native setting in the Jamf Pro UI.",
                "No change needed unless you want a native control; check whether a newer jamf-cli adds a mapping.")
        }
        if lower.contains("removed empty payload") {
            let type = quoted.first ?? "unknown"
            return finding(.emptyPayloadRemoved, type, .info,
                "\(type) had no settings left after metadata was stripped, so it was dropped. Nothing was being managed by it.",
                "No change needed.")
        }
        if lower.contains("rewrote payload type") {
            let from = quoted.first ?? "unknown"
            let to = quoted.dropFirst().first ?? "unknown"
            return finding(.payloadTypeRewritten, "\(from) → \(to)", .info,
                "The blueprints API only accepts the canonical spelling, so \(from) was renamed to \(to).",
                "No change needed.")
        }
        if lower.contains("requires macos 26") || lower.contains("requires macos") && lower.contains("ios 26") {
            let component = line
                .replacingOccurrences(of: "Warning:", with: "")
                .split(separator: " ").first.map(String.init) ?? "component"
            return finding(.ddmRequiresNewOS, component, .review,
                "The \(component) DDM component only works on macOS 26 / iOS 26 or later. Older devices in the target group will ignore it.",
                "Check the OS versions in the target group, or keep the older profile for devices that cannot run it.")
        }
        if lower.hasPrefix("removed payload") || lower.contains("removed payload ") && lower.contains(" requires ") {
            let type = line.components(separatedBy: " ").dropFirst(2).first ?? "unknown"
            let key = value(after: "requires ", in: line) ?? "a required key"
            return finding(.payloadRemovedMissingKey, type, .action,
                "\(type) was removed because the Jamf DDM API requires \(key), and the source profile did not include it.",
                "Add the missing \(key) to the profile or create this setting directly in the blueprint, then convert again.")
        }
        if lower.contains("unwrapped") && lower.contains("custom settings") {
            let domain = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "unknown"
            return finding(.domainUnwrapped, domain, .info,
                "Settings for \(domain) were inside Custom Settings and have been converted so a native DDM component can manage them.",
                "No change needed; check the result in the blueprint editor.")
        }
        if lower.contains("can only be managed through the blueprints api") {
            return finding(.legacyPayloadReadOnly, "", .info,
                "Some payloads appear as read-only \"Legacy payload\" items in the Jamf Pro UI and can only be changed through the blueprints API.",
                "Plan to edit these through BCU or the API, not the Jamf Pro console.")
        }
        if lower.contains("takeover is not supported") || lower.contains("takeover not supported")
            || lower.contains("cannot take over") || lower.contains("(takeover not supported)") {
            return finding(.takeoverNotSupported, "", .action,
                "This profile cannot be adopted in place, so a blueprint would install beside the Classic profile and both would stay active.",
                "Convert instead, then plan the cutover: deploy to a small group, verify, and only then retire the Classic profile.")
        }
        if lower.contains("takeover was not requested") || lower.contains("takeover not requested")
            || lower.contains("(takeover not requested)") {
            return finding(.takeoverNotRequested, "", .info,
                "This run converted the profile without trying to take over the installed copy.",
                "Choose Preserve installed (takeover) if you want the blueprint to adopt the profile already on devices.")
        }
        if lower.contains("takeover supported") {
            return finding(.takeoverSupported, "", .info,
                "The blueprint can adopt the copy of the profile already installed on devices, so there is no reinstall gap.",
                "Try it on a small group first. Do not unscope the Classic profile on a large fleet while the blueprint is deployed.")
        }
        if lower.contains("previously deployed a configuration profile") {
            return finding(.conflictingDeployment, "", .review,
                "If the Classic profile is still on devices and the blueprint contains conflicting keys, behaviour can be unpredictable; for restrictions the most restrictive value wins.",
                "Deploy to a test group and compare, or scope the Classic profile out once the blueprint is verified.")
        }
        if lower.contains("redacted credential") {
            return nil // reported from the structured count, not from text
        }
        return nil
    }

    private static func quotedValues(in text: String) -> [String] {
        var values: [String] = []
        var current: String?
        for character in text {
            if character == "\"" {
                if let open = current { values.append(open); current = nil } else { current = "" }
            } else if current != nil {
                current?.append(character)
            }
        }
        return values
    }

    private static func value(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let rest = text[range.upperBound...]
        let word = rest.prefix { !$0.isWhitespace && $0 != "," && $0 != "." }
        return word.isEmpty ? nil : String(word)
    }
}
