import Foundation
import Security
import Darwin

private let cliVersion = "3.5.0"
private let settingsKey = "BlueprintCreator.Settings"
private let bundleIdentifier = "com.jawheelr.blueprintcreator"
private let keychainService = "com.jawheelr.blueprintcreator"
private let keychainAccount = "platform-api-client-secret"
private let appPath = "/Applications/Blueprint Conversion Utility.app"

enum CLIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

struct Settings: Decodable {
    var platformURL: String
    var platformClientID: String
    var environmentID: String
    var integrationExpirationDate: Date?
    var expiryWarningDays: Int

    enum CodingKeys: String, CodingKey {
        case platformURL, platformClientID, environmentID
        case integrationExpirationDate, expiryWarningDays
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        platformURL = try values.decodeIfPresent(String.self, forKey: .platformURL) ?? "https://us.api.jamfcloud.com"
        platformClientID = try values.decodeIfPresent(String.self, forKey: .platformClientID) ?? ""
        environmentID = try values.decodeIfPresent(String.self, forKey: .environmentID) ?? ""
        integrationExpirationDate = try values.decodeIfPresent(Date.self, forKey: .integrationExpirationDate)
        expiryWarningDays = try values.decodeIfPresent(Int.self, forKey: .expiryWarningDays) ?? 30
    }
}

struct StoredSecret: Decodable { let platformClientSecret: String }

struct PlatformSession {
    let settings: Settings
    let secret: String

    func token() async throws -> String {
        guard let url = URL(string: settings.platformURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/token") else {
            throw CLIError.message("Invalid Platform API URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            "grant_type": "client_credentials",
            "client_id": settings.platformClientID,
            "client_secret": secret
        ]
        request.httpBody = fields.map { key, value in
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = String(data: data, encoding: .utf8) ?? "No response"
            throw CLIError.message("Platform authentication failed (HTTP \(code)): \(detail.prefix(400))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String else {
            throw CLIError.message("Platform token response was invalid.")
        }
        return token
    }

    func get(_ path: String, accept: String = "application/json") async throws -> Data {
        let token = try await token()
        guard let base = URL(string: settings.platformURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw CLIError.message("Invalid Platform API URL.")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(settings.environmentID, forHTTPHeaderField: "X-Environment-Id")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = String(data: data, encoding: .utf8) ?? "No response"
            throw CLIError.message("Platform request failed (HTTP \(code)): \(detail.prefix(500))")
        }
        return data
    }
}

enum OutputMode { case text, json }

@main
struct BCUCLI {
    static func main() async {
        do {
            let code = try await run(Array(CommandLine.arguments.dropFirst()))
            exit(Int32(code))
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run(_ args: [String]) async throws -> Int {
        guard let first = args.first else { printHelp(); return 0 }
        let mode: OutputMode
        if let outputIndex = args.firstIndex(of: "--output"),
           args.indices.contains(outputIndex + 1),
           args[outputIndex + 1] == "json" {
            mode = .json
        } else {
            mode = .text
        }
        switch first {
        case "help", "--help", "-h": printHelp(); return 0
        case "version": return version(mode)
        case "connection": return try await connection(Array(args.dropFirst()), mode)
        case "credentials": return try credentials(Array(args.dropFirst()), mode)
        case "profiles": return try await profiles(Array(args.dropFirst()), mode)
        case "groups": return try await groups(Array(args.dropFirst()), mode)
        case "logs": return try logs(Array(args.dropFirst()))
        case "app": return try await app(Array(args.dropFirst()), mode)
        default: throw CLIError.message("Unknown command '\(first)'. Run 'bcu help'.")
        }
    }

    static func version(_ mode: OutputMode) -> Int {
        if mode == .json { printJSON(["name": "Blueprint Conversion Utility CLI", "version": cliVersion, "bundleIdentifier": bundleIdentifier]) }
        else { print("Blueprint Conversion Utility CLI \(cliVersion)\nBundle identifier: \(bundleIdentifier)") }
        return 0
    }

    static func connection(_ args: [String], _ mode: OutputMode) async throws -> Int {
        let settings = try loadSettings()
        switch args.first ?? "status" {
        case "status":
            let configured = readSecret() != nil
            if mode == .json { printJSON(["platformURL": settings.platformURL, "clientID": settings.platformClientID, "environmentID": settings.environmentID, "clientSecretConfigured": configured]) }
            else {
                print("Platform API URL: \(settings.platformURL)")
                print("Client ID: \(settings.platformClientID)")
                print("Platform Environment ID: \(settings.environmentID)")
                print("Client Secret: \(configured ? "Configured in macOS Keychain" : "Not configured")")
            }
            return configured ? 0 : 3
        case "test":
            let session = try makeSession(settings)
            _ = try await session.token()
            _ = try await session.get("proclassic/osxconfigurationprofiles", accept: "application/xml")
            _ = try await session.get("proclassic/mobiledeviceconfigurationprofiles", accept: "application/xml")
            _ = try await session.get("device-groups/v1/device-groups")
            if mode == .json { printJSON(["authentication": "passed", "computerProfiles": "passed", "mobileProfiles": "passed", "deviceGroups": "passed"]) }
            else { print("Authentication: Passed\nComputer profiles: Passed\nMobile profiles: Passed\nDevice groups: Passed\n\nPlatform API connection passed.") }
            return 0
        default: throw CLIError.message("Usage: bcu connection [status|test]")
        }
    }

    static func credentials(_ args: [String], _ mode: OutputMode) throws -> Int {
        let settings = try loadSettings()
        guard (args.first ?? "status") == "status" else { throw CLIError.message("Usage: bcu credentials status") }
        guard let expiration = settings.integrationExpirationDate else {
            if mode == .json { printJSON(["status": "notConfigured", "warningDays": settings.expiryWarningDays]) }
            else { print("Status: Expiration date not configured") }
            return 3
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: expiration)).day ?? 0
        let status = days < 0 ? "expired" : (days <= settings.expiryWarningDays ? "expiringSoon" : "valid")
        if mode == .json { printJSON(["status": status, "expiration": ISO8601DateFormatter().string(from: expiration), "daysRemaining": days, "warningDays": settings.expiryWarningDays]) }
        else { print("Status: \(status)\nExpiration: \(DateFormatter.localizedString(from: expiration, dateStyle: .medium, timeStyle: .none))\nDays remaining: \(days)\nWarning threshold: \(settings.expiryWarningDays) days") }
        return status == "valid" ? 0 : (status == "expiringSoon" ? 11 : 12)
    }

    static func profiles(_ args: [String], _ mode: OutputMode) async throws -> Int {
        guard (args.first ?? "") == "list" else { throw CLIError.message("Usage: bcu profiles list --type computer|mobile [--output json]") }
        let type = value(after: "--type", in: args) ?? "computer"
        guard ["computer", "mobile"].contains(type) else { throw CLIError.message("--type must be computer or mobile") }
        let settings = try loadSettings(); let session = try makeSession(settings)
        let resource = type == "mobile" ? "mobiledeviceconfigurationprofiles" : "osxconfigurationprofiles"
        let data = try await session.get("proclassic/\(resource)", accept: "application/xml")
        let xml = String(data: data, encoding: .utf8) ?? ""
        let records = parseProfileList(xml)
        if mode == .json { printJSON(["type": type, "profiles": records]) }
        else { for record in records { print("\(record["id"] ?? "")\t\(record["name"] ?? "")") } }
        return 0
    }

    static func groups(_ args: [String], _ mode: OutputMode) async throws -> Int {
        guard (args.first ?? "") == "list" else { throw CLIError.message("Usage: bcu groups list --type computer|mobile [--output json]") }
        let requested = value(after: "--type", in: args) ?? "computer"
        guard ["computer", "mobile"].contains(requested) else { throw CLIError.message("--type must be computer or mobile") }
        let settings = try loadSettings(); let session = try makeSession(settings)
        let data = try await session.get("device-groups/v1/device-groups")
        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]] = (object as? [String: Any])?["results"] as? [[String: Any]] ?? (object as? [String: Any])?["items"] as? [[String: Any]] ?? (object as? [[String: Any]]) ?? []
        let filtered = rows.compactMap { row -> [String: String]? in
            let metadata = ["deviceType", "deviceFamily", "platform", "type", "groupType", "memberType"].compactMap { row[$0].map { String(describing: $0).lowercased() } }.joined(separator: " ")
            let family = metadata.contains("mobile") || metadata.contains("ios") || metadata.contains("ipad") || metadata.contains("iphone") || metadata.contains("tvos") ? "mobile" : (metadata.contains("computer") || metadata.contains("macos") || metadata.contains("mac") ? "computer" : "unknown")
            guard family == requested else { return nil }
            return ["id": String(describing: row["id"] ?? ""), "name": row["name"] as? String ?? "", "family": family]
        }
        if mode == .json { printJSON(["type": requested, "groups": filtered]) }
        else { for row in filtered { print("\(row["id"] ?? "")\t\(row["name"] ?? "")") } }
        return 0
    }

    static func logs(_ args: [String]) throws -> Int {
        let action = args.first ?? "show"
        guard ["show", "stream"].contains(action) else { throw CLIError.message("Usage: bcu logs show [--last 1h] [--category Category] | bcu logs stream") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        var predicate = "subsystem == \"com.jawheelr.blueprintcreator\""
        if let category = value(after: "--category", in: args) { predicate += " AND category == \"\(category)\"" }
        process.arguments = action == "stream" ? ["stream", "--style", "compact", "--predicate", predicate] : ["show", "--style", "compact", "--last", value(after: "--last", in: args) ?? "1h", "--predicate", predicate]
        process.standardOutput = FileHandle.standardOutput; process.standardError = FileHandle.standardError
        try process.run(); process.waitUntilExit(); return Int(process.terminationStatus)
    }

    static func app(_ args: [String], _ mode: OutputMode) async throws -> Int {
        switch args.first ?? "open" {
        case "open":
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = [appPath]; try process.run(); process.waitUntilExit(); return Int(process.terminationStatus)
        case "check-for-updates":
            let current = cliVersion
            let latestURL = URL(string: "https://github.com/jawheelr/Blueprint-Conversion-Utility/releases/latest")!
            let (_, response) = try await URLSession.shared.data(from: latestURL)
            guard let final = response.url, let index = final.pathComponents.firstIndex(of: "tag"), final.pathComponents.indices.contains(index + 1) else { throw CLIError.message("No published latest release was returned.") }
            let tag = final.pathComponents[index + 1]; let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let available = latest.compare(current, options: .numeric) == .orderedDescending
            if mode == .json { printJSON(["installedVersion": current, "latestVersion": latest, "updateAvailable": available, "releaseURL": final.absoluteString]) }
            else { print("Installed version: \(current)\nLatest version: \(latest)\nUpdate available: \(available ? "Yes" : "No")\nRelease URL: \(final.absoluteString)") }
            return available ? 14 : 0
        default: throw CLIError.message("Usage: bcu app [open|check-for-updates]")
        }
    }

    static func loadSettings() throws -> Settings {
        guard let defaults = UserDefaults(suiteName: bundleIdentifier), let data = defaults.data(forKey: settingsKey) else { throw CLIError.message("Application settings are not configured. Open Blueprint Conversion Utility > Connections.") }
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    static func readSecret() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let secret = try? JSONDecoder().decode(StoredSecret.self, from: data) else { return nil }
        return secret.platformClientSecret
    }

    static func makeSession(_ settings: Settings) throws -> PlatformSession {
        guard !settings.platformClientID.isEmpty, !settings.environmentID.isEmpty, let secret = readSecret(), !secret.isEmpty else { throw CLIError.message("Platform configuration is incomplete. Configure and test Connections in the app.") }
        return PlatformSession(settings: settings, secret: secret)
    }

    static func value(after flag: String, in args: [String]) -> String? { guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }; return args[index + 1] }
    static func parseProfileList(_ xml: String) -> [[String: String]] {
        let pattern = #"(?s)<(?:os_x_configuration_profile|configuration_profile|mobile_device_configuration_profile)\b[^>]*>.*?<id>([^<]+)</id>.*?<name>([^<]+)</name>.*?</(?:os_x_configuration_profile|configuration_profile|mobile_device_configuration_profile)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: xml), let nameRange = Range(match.range(at: 2), in: xml) else { return nil }
            return ["id": String(xml[idRange]), "name": String(xml[nameRange]).replacingOccurrences(of: "&amp;", with: "&")]
        }
    }
    static func printJSON(_ object: Any) { if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) } }
    static func printHelp() {
        print("""
        Blueprint Conversion Utility CLI \(cliVersion)

        Usage: bcu <command> [options]

          version [--output json]
          connection status|test [--output json]
          credentials status [--output json]
          profiles list --type computer|mobile [--output json]
          groups list --type computer|mobile [--output json]
          logs show [--last 1h] [--category Category]
          logs stream [--category Category]
          app open
          app check-for-updates [--output json]
        """)
    }
}
