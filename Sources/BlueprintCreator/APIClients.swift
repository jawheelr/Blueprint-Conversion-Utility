import Foundation

private struct OAuthToken: Decodable {
    let accessToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

enum HTTPClient {
    static func formBody(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")

        let body = values
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }

    static func validate(_ response: URLResponse, data: Data, operation: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AppFailure.message("\(operation) returned no HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "No response details"
            throw AppFailure.message("\(operation) failed with HTTP \(http.statusCode): \(detail.prefix(700))")
        }
    }
}

actor PlatformProfileClient {
    private let baseURL: URL
    private let clientID: String
    private let clientSecret: String
    private let environmentID: String
    private var accessToken = ""
    private var tokenExpiry = Date.distantPast

    init(
        url: String,
        clientID: String,
        clientSecret: String,
        environmentID: String
    ) throws {
        guard let value = URL(string: url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
              value.scheme == "https" else {
            throw AppFailure.message("Platform API URL must be a valid HTTPS URL.")
        }
        guard !environmentID.isEmpty else {
            throw AppFailure.message("Platform API requires a Platform Environment ID.")
        }
        baseURL = value
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.environmentID = environmentID
    }

    func test() async throws {
        _ = try await authenticate()
        _ = try await get("proclassic/mobiledeviceconfigurationprofiles")
        _ = try await get("proclassic/osxconfigurationprofiles")
    }

    func profiles(mobile: Bool) async throws -> [JamfProfile] {
        let path = mobile
            ? "proclassic/mobiledeviceconfigurationprofiles"
            : "proclassic/osxconfigurationprofiles"
        return try ProfileListParser().parse(try await get(path))
    }

    func profileDetail(_ profile: JamfProfile, mobile: Bool) async throws -> JamfProfile {
        let type = mobile
            ? "mobiledeviceconfigurationprofiles"
            : "osxconfigurationprofiles"
        let data = try await get("proclassic/\(type)/id/\(profile.id)")
        return try ProfileDetailParser().parse(data, base: profile)
    }

    func unscopeProfile(id: String, mobile: Bool) async throws {
        let resource = mobile
            ? "mobiledeviceconfigurationprofiles"
            : "osxconfigurationprofiles"
        let path = "proclassic/\(resource)/id/\(id)"
        let originalData = try await get(path)

        guard let originalXML = String(data: originalData, encoding: .utf8) else {
            throw AppFailure.message("Jamf Pro returned profile XML that was not UTF-8.")
        }
        guard let rootName = firstCapture(
            in: originalXML,
            pattern: #"(?s)^\s*(?:<\?xml[^>]*>\s*)?<([A-Za-z_][A-Za-z0-9_.:-]*)\b[^>]*>"#
        ) else {
            throw AppFailure.message("Unable to identify the profile XML root element.")
        }
        guard let scopeRange = firstRange(
            in: originalXML,
            pattern: #"(?s)<scope\b[^>]*>.*?</scope>"#
        ) else {
            throw AppFailure.message("The source profile response contains no <scope> element.")
        }

        let existingScope = String(originalXML[scopeRange])
        let modifiedScope = clearScope(existingScope, mobile: mobile)
        guard modifiedScope != existingScope else {
            throw AppFailure.message(
                "The source profile is already unscoped or has no recognized targets to remove."
            )
        }

        let partialXML = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<\(rootName)>\(modifiedScope)</\(rootName)>"
        let partial = try await putXML(path: path, xml: partialXML)
        if partial.success {
            try await verifyUnscoped(path: path, mobile: mobile, id: id)
            AppLogger.deployment.notice(
                "Source profile ID=\(id, privacy: .public) unscoped and verified with scope-only XML"
            )
            return
        }

        var fullXML = originalXML
        fullXML.replaceSubrange(scopeRange, with: modifiedScope)
        let full = try await putXML(path: path, xml: fullXML)
        if full.success {
            try await verifyUnscoped(path: path, mobile: mobile, id: id)
            AppLogger.deployment.notice(
                "Source profile ID=\(id, privacy: .public) unscoped and verified with full-profile XML"
            )
            return
        }

        throw AppFailure.message(
            "Jamf Pro could not unscope profile \(id).\n\n" +
            "Scope-only update: HTTP \(partial.status): \(partial.body)\n\n" +
            "Full-profile update: HTTP \(full.status): \(full.body)\n\n" +
            "The deployed blueprint is unchanged and the source profile remains scoped."
        )
    }

    private func verifyUnscoped(path: String, mobile: Bool, id: String) async throws {
        let data = try await get(path)
        guard let xml = String(data: data, encoding: .utf8),
              let range = firstRange(in: xml, pattern: #"(?s)<scope\b[^>]*>.*?</scope>"#) else {
            throw AppFailure.message("Platform profile update succeeded, but scope verification could not read the updated profile.")
        }
        let scope = String(xml[range])
        let active = inspectScope(scope, mobile: mobile)
        guard active.isEmpty else {
            let compact = scope.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppFailure.message("Read-back found active scope on profile \(id).\nActive scope indicators: \(active.joined(separator: ", "))\nScope XML: \(String(compact.prefix(1400)))")
        }
        AppLogger.deployment.notice("Platform profile read-back verified semantically empty scope for ID=\(id, privacy: .public)")
    }

    private func inspectScope(_ scopeXML: String, mobile: Bool) -> [String] {
        var findings: [String] = []
        let allTags = mobile ? ["all_mobile_devices", "all_jss_users"] : ["all_computers", "all_jss_users"]
        for tag in allTags {
            let escaped = NSRegularExpression.escapedPattern(for: tag)
            let pattern = "(?is)<\\s*\(escaped)\\b[^>]*>\\s*true\\s*</\\s*\(escaped)\\s*>"
            if scopeXML.range(of: pattern, options: .regularExpression) != nil { findings.append("\(tag)=true") }
        }
        let assignmentPatterns = [(#"(?is)<id\b[^>]*>\s*[^<\s][^<]*</id>"#, "assigned object ID"), (#"(?is)<name\b[^>]*>\s*[^<\s][^<]*</name>"#, "assigned object name")]
        for (pattern, label) in assignmentPatterns where scopeXML.range(of: pattern, options: .regularExpression) != nil { findings.append(label) }
        return findings
    }

    private func clearScope(_ scopeXML: String, mobile: Bool) -> String {
        var result = scopeXML
        let allTag = mobile ? "all_mobile_devices" : "all_computers"
        result = replaceElement(in: result, tag: allTag, body: "false")
        result = replaceElement(in: result, tag: "all_jss_users", body: "false")

        let targetContainers = mobile
            ? ["mobile_devices", "mobile_device_groups", "buildings", "departments", "jss_users", "jss_user_groups"]
            : ["computers", "computer_groups", "buildings", "departments", "jss_users", "jss_user_groups"]
        for tag in targetContainers {
            result = replaceElement(in: result, tag: tag, body: "")
        }

        // Clear limitation and exclusion targets as part of a true unscoping,
        // but only when those nodes already exist in the returned document.
        for tag in ["limitations", "exclusions"] {
            result = replaceElement(in: result, tag: tag, body: "")
        }
        return result
    }

    private func replaceElement(in xml: String, tag: String, body: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        let paired = "(?s)<\\s*\(escaped)\\b[^>]*>.*?</\\s*\(escaped)\\s*>"
        guard let regex = try? NSRegularExpression(pattern: paired) else { return xml }
        let range = NSRange(xml.startIndex..., in: xml)
        guard regex.firstMatch(in: xml, range: range) != nil else { return xml }
        return regex.stringByReplacingMatches(
            in: xml,
            range: range,
            withTemplate: "<\(tag)>\(body)</\(tag)>"
        )
    }

    private func firstRange(in text: String, pattern: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else { return nil }
        return Range(match.range, in: text)
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func putXML(
        path: String,
        xml: String
    ) async throws -> (success: Bool, status: Int, body: String) {
        let token = try await authenticate()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.httpBody = Data(xml.utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        applyScopeHeader(to: &request)
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? "No response details"
        return ((200...299).contains(status), status, String(body.prefix(700)))
    }

    private func authenticate() async throws -> String {
        if !accessToken.isEmpty && Date() < tokenExpiry { return accessToken }

        var request = URLRequest(url: baseURL.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTPClient.formBody([
            "grant_type": "client_credentials",
            "client_id": clientID,
            "client_secret": clientSecret
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPClient.validate(response, data: data, operation: "Platform API authentication")
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        accessToken = token.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval((token.expiresIn ?? 900) - 30))
        return accessToken
    }

    private func applyScopeHeader(to request: inout URLRequest) {
        request.setValue(environmentID, forHTTPHeaderField: "X-Environment-Id")
    }

    private func get(_ path: String) async throws -> Data {
        let token = try await authenticate()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        applyScopeHeader(to: &request)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPClient.validate(response, data: data, operation: "Platform profile request")
        return data
    }
}

actor PlatformClient {
    private let baseURL: URL
    private let clientID: String
    private let clientSecret: String
    private let environmentID: String
    private var accessToken = ""
    private var tokenExpiry = Date.distantPast

    init(url: String, clientID: String, clientSecret: String, environmentID: String) throws {
        guard let value = URL(string: url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
              value.scheme == "https" else {
            throw AppFailure.message("Platform API URL must be a valid HTTPS URL.")
        }
        guard !environmentID.isEmpty else {
            throw AppFailure.message("Platform API requires a Platform Environment ID.")
        }
        baseURL = value
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.environmentID = environmentID
    }

    func test() async throws {
        _ = try await authenticate()
    }

    struct DeviceGroupPage: Sendable {
        let groups: [DeviceGroup]
        let page: Int
        let pageSize: Int
        let totalCount: Int?
        let hasMore: Bool
    }

    func groups(page: Int = 0, pageSize: Int = 100) async throws -> DeviceGroupPage {
        let data = try await request(
            path: "device-groups/v1/device-groups",
            method: "GET",
            body: nil,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(pageSize))
            ]
        )
        let object = try JSONSerialization.jsonObject(with: data)
        let dictionary = object as? [String: Any]
        let records: [[String: Any]]
        if let dictionary {
            records = dictionary["results"] as? [[String: Any]]
                ?? dictionary["items"] as? [[String: Any]]
                ?? dictionary["data"] as? [[String: Any]]
                ?? []
        } else {
            records = object as? [[String: Any]] ?? []
        }

        let groups = records.compactMap(Self.deviceGroup(from:))
        let totalCount = Self.integerValue(
            dictionary?["totalCount"] ?? dictionary?["total"] ??
            (dictionary?["pagination"] as? [String: Any])?["totalCount"] ??
            (dictionary?["page"] as? [String: Any])?["totalElements"]
        )
        let loadedThrough = (page * pageSize) + records.count
        let hasMore = totalCount.map { loadedThrough < $0 } ?? (records.count == pageSize)
        return DeviceGroupPage(
            groups: groups,
            page: page,
            pageSize: pageSize,
            totalCount: totalCount,
            hasMore: hasMore
        )
    }

    private static func deviceGroup(from row: [String: Any]) -> DeviceGroup? {
        guard let rawID = row["id"] else { return nil }
        let id = String(describing: rawID)
        let name = row["name"] as? String ?? id
        let keys = [
            "deviceType", "deviceFamily", "platform", "type", "osType",
            "groupType", "memberType", "deviceGroupType", "objectType",
            "deviceCollectionType", "targetType"
        ]
        let metadata = keys.compactMap {
            row[$0].map { String(describing: $0).lowercased() }
        }.joined(separator: " ")
        let family: DeviceGroupFamily
        if metadata.contains("mobile") || metadata.contains("ios") ||
            metadata.contains("ipados") || metadata.contains("ipad") ||
            metadata.contains("iphone") || metadata.contains("tvos") {
            family = .mobile
        } else if metadata.contains("computer") ||
                    metadata.contains("macos") || metadata.contains("mac") {
            family = .computer
        } else {
            family = .unknown
        }
        return DeviceGroup(id: id, name: name, family: family)
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    func createBlueprint(_ data: Data) async throws -> String {
        let response = try await request(
            path: "blueprints/v1/blueprints",
            method: "POST",
            body: data
        )
        let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
        return String(describing: object?["id"] ?? object?["blueprintId"] ?? "Created")
    }

    func deployBlueprint(id: String) async throws {
        _ = try await request(
            path: "blueprints/v1/blueprints/\(id)/deploy",
            method: "POST",
            body: Data()
        )
    }

    func blueprintDeploymentState(id: String) async throws -> String? {
        let response = try await request(
            path: "blueprints/v1/blueprints/\(id)",
            method: "GET",
            body: nil
        )
        let object = try JSONSerialization.jsonObject(with: response)
        return deploymentState(in: object)
    }

    private func deploymentState(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            if let deployment = object["deploymentState"] as? [String: Any],
               let state = deployment["state"] as? String { return state }
            if let state = object["deploymentState"] as? String { return state }
            if let state = object["state"] as? String,
               ["DEPLOYED", "NOT_DEPLOYED", "DEPLOYMENT_PENDING", "DEPLOYMENT_FAILED", "FAILED", "ERROR"].contains(state.uppercased()) { return state }
            for child in object.values { if let state = deploymentState(in: child) { return state } }
        } else if let array = value as? [Any] {
            for child in array { if let state = deploymentState(in: child) { return state } }
        }
        return nil
    }

    private func authenticate() async throws -> String {
        if !accessToken.isEmpty && Date() < tokenExpiry { return accessToken }

        var request = URLRequest(url: baseURL.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTPClient.formBody([
            "grant_type": "client_credentials",
            "client_id": clientID,
            "client_secret": clientSecret
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPClient.validate(response, data: data, operation: "Platform API authentication")
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        accessToken = token.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval((token.expiresIn ?? 900) - 30))
        return accessToken
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        let token = try await authenticate()
        let endpoint = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw AppFailure.message("Unable to construct Platform API request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        request.setValue(environmentID, forHTTPHeaderField: "X-Environment-Id")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPClient.validate(response, data: data, operation: "Platform API request")
        return data
    }
}
