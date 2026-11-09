import Foundation

struct AppSettings: Codable, Equatable {
    var platformURL = "https://us.api.jamfcloud.com"
    var platformClientID = ""
    var environmentID = ""
    var integrationExpirationDate: Date?
    var expiryWarningDays = 30

    enum CodingKeys: String, CodingKey {
        case platformURL, platformClientID, environmentID
        case integrationExpirationDate, expiryWarningDays
    }

    init() { }

    /// True when the configured host looks like a Jamf-operated endpoint.
    var hostIsKnownJamf: Bool {
        guard let host = URLComponents(string: platformURL)?.host?.lowercased() else { return false }
        return ["jamfcloud.com", "jamf.com"].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        platformURL = try values.decodeIfPresent(String.self, forKey: .platformURL)
            ?? "https://us.api.jamfcloud.com"
        platformClientID = try values.decodeIfPresent(String.self, forKey: .platformClientID) ?? ""
        environmentID = try values.decodeIfPresent(String.self, forKey: .environmentID) ?? ""
        integrationExpirationDate = try values.decodeIfPresent(
            Date.self,
            forKey: .integrationExpirationDate
        )
        expiryWarningDays = try values.decodeIfPresent(
            Int.self,
            forKey: .expiryWarningDays
        ) ?? 30
    }
}

enum PlatformCredentialHealth: Equatable {
    case notConfigured
    case valid(daysRemaining: Int, expirationDate: Date)
    case expiringSoon(daysRemaining: Int, expirationDate: Date)
    case expired(daysExpired: Int, expirationDate: Date)
    case authenticationFailed
}

enum PlatformCredentialEvaluator {
    static func evaluate(
        expirationDate: Date?,
        warningDays: Int,
        authenticationPassed: Bool,
        authenticationFailed: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlatformCredentialHealth {
        if authenticationFailed { return .authenticationFailed }
        guard let expirationDate else { return .notConfigured }
        let today = calendar.startOfDay(for: now)
        let expiration = calendar.startOfDay(for: expirationDate)
        guard let days = calendar.dateComponents([.day], from: today, to: expiration).day else {
            return .notConfigured
        }
        if days < 0 {
            return .expired(daysExpired: abs(days), expirationDate: expiration)
        }
        if days <= max(1, warningDays) {
            return .expiringSoon(daysRemaining: days, expirationDate: expiration)
        }
        if authenticationPassed {
            return .valid(daysRemaining: days, expirationDate: expiration)
        }
        return .notConfigured
    }
}

struct ProfileScope: Hashable {
    var allDevices = false
    var groupNames: [String] = []
    var individualDeviceCount = 0
    var limitationCount = 0
    var exclusionCount = 0
    /// Buildings, departments, users, user groups and network segments.
    var otherTargetCount = 0

    var summary: String {
        var parts: [String] = []
        if allDevices { parts.append("all devices") }
        if !groupNames.isEmpty { parts.append("\(groupNames.count) group(s)") }
        if individualDeviceCount > 0 { parts.append("\(individualDeviceCount) individual device(s)") }
        if otherTargetCount > 0 { parts.append("\(otherTargetCount) building/department/user target(s)") }
        if limitationCount > 0 { parts.append("\(limitationCount) limitation(s)") }
        if exclusionCount > 0 { parts.append("\(exclusionCount) exclusion(s)") }
        return parts.isEmpty ? "Unscoped" : parts.joined(separator: ", ")
    }
}

struct JamfProfile: Identifiable, Hashable {
    let id: String
    let name: String
    var description = ""
    var payloads: [[String: Any]] = []
    var scope = ProfileScope()

    static func == (lhs: JamfProfile, rhs: JamfProfile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum DeviceGroupFamily: String, Hashable { case computer, mobile, unknown }
struct DeviceGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let family: DeviceGroupFamily
}

enum DeploymentChoice: String, Identifiable {
    case createOnly
    case createAndDistribute
    case createDistributeAndUnscope
    var id: String { rawValue }
}

struct OperationResult: Identifiable {
    let id = UUID()
    let title: String
    let details: String
}

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return "Unknown error"
    }
}
