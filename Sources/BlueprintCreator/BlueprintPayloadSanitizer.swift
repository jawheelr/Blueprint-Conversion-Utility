import Foundation

struct PayloadSanitizationResult {
    let payloads: [[String: Any]]
    let warnings: [String]
}

enum BlueprintPayloadSanitizer {
    private static let maximumDepth = 64
    private static let redactedValues: Set<String> = [
        "<redacted>", "redacted", "********", "**********"
    ]
    private static let credentialFragments = ["password", "secret", "token", "credential"]

    static func sanitize(_ sourcePayloads: [[String: Any]]) throws -> PayloadSanitizationResult {
        guard !sourcePayloads.isEmpty else {
            throw AppFailure.message("The selected profile contains no readable payload content.")
        }
        var payloads: [[String: Any]] = []
        var warnings: [String] = []
        for (index, source) in sourcePayloads.enumerated() {
            let rawType = source["PayloadType"] ?? source["payloadType"]
            let type = rawType.map { String(describing: $0) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            guard !type.isEmpty, type.lowercased() != "unknown" else {
                throw AppFailure.message("Payload \(index + 1) has a blank or unknown payload type.")
            }
            var output: [String: Any] = ["payloadType": type]
            for (key, value) in source {
                if key == "PayloadType" || key == "payloadType" { continue }
                if isCredentialKey(key), let text = value as? String,
                   redactedValues.contains(text.lowercased()) {
                    warnings.append("\(type): redacted field '\(key)' was omitted.")
                    continue
                }
                let converted = try jsonSafeValue(
                    value, path: "payloadContent[\(index)].\(key)", depth: 0, visited: []
                )
                if key == "PayloadVersion" {
                    guard let version = converted as? Int64, version >= 1 else {
                        throw AppFailure.message(
                            "payloadContent[\(index)].PayloadVersion must be an integer of 1 or greater."
                        )
                    }
                }
                output[key] = converted
            }
            guard JSONSerialization.isValidJSONObject(output) else {
                throw AppFailure.message("Payload '\(type)' could not be converted to valid JSON.")
            }
            payloads.append(output)
        }
        return PayloadSanitizationResult(payloads: payloads, warnings: warnings)
    }

    static func validateBlueprint(
        _ object: [String: Any], requireDeviceGroup: Bool = true
    ) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AppFailure.message("The generated blueprint is not valid JSON.")
        }
        guard let name = object["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure.message("Blueprint name must not be blank.")
        }
        guard let scope = object["scope"] as? [String: Any],
              let groups = scope["deviceGroups"] as? [String] else {
            throw AppFailure.message("Blueprint scope.deviceGroups is missing.")
        }
        if requireDeviceGroup && groups.isEmpty {
            throw AppFailure.message("Select a Platform device group.")
        }
        guard let steps = object["steps"] as? [[String: Any]],
              let step = steps.first,
              let components = step["components"] as? [[String: Any]],
              let component = components.first,
              component["identifier"] as? String == "com.jamf.ddm-configuration-profile",
              let config = component["configuration"] as? [String: Any],
              let displayName = config["payloadDisplayName"] as? String,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let payloads = config["payloadContent"] as? [[String: Any]], !payloads.isEmpty else {
            throw AppFailure.message("The legacy profile component is incomplete.")
        }
        for (index, payload) in payloads.enumerated() {
            guard let type = payload["payloadType"] as? String,
                  !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  type.lowercased() != "unknown" else {
                throw AppFailure.message("payloadContent[\(index)].payloadType is blank or unknown.")
            }
        }
    }

    /// Checks the exact JSON that is about to be POSTed against the user's
    /// current selection. The text is editable, so nothing in it is trusted.
    static func validateSubmission(
        _ data: Data, expectedProfileID: String, expectedGroupID: String
    ) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppFailure.message("The blueprint JSON is not a valid JSON object.")
        }
        guard let name = object["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure.message("Blueprint name must not be blank.")
        }
        guard name.contains("Configuration Profile #\(expectedProfileID)") else {
            throw AppFailure.message(
                "The blueprint name no longer references the selected Configuration Profile (ID \(expectedProfileID)). Use Regenerate."
            )
        }
        guard let scope = object["scope"] as? [String: Any],
              let groups = scope["deviceGroups"] as? [String],
              groups == [expectedGroupID] else {
            throw AppFailure.message(
                "The blueprint's device group does not match the selected Platform group. Use Regenerate."
            )
        }
        guard let steps = object["steps"] as? [[String: Any]], !steps.isEmpty else {
            throw AppFailure.message("The blueprint has no steps.")
        }
        for step in steps {
            guard let components = step["components"] as? [[String: Any]], !components.isEmpty else {
                throw AppFailure.message("A blueprint step has no components.")
            }
            for component in components {
                guard let identifier = component["identifier"] as? String,
                      !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      component["configuration"] is [String: Any] else {
                    throw AppFailure.message("A blueprint component is missing its identifier or configuration.")
                }
            }
        }
    }

    /// Dotted key paths of credential-like fields whose value is a redaction
    /// placeholder; submitting these would deploy a broken credential.
    static func redactedCredentialFields(in payloads: [[String: Any]]) -> [String] {
        var found: [String] = []
        func walk(_ value: Any, path: String, credentialKey: Bool, depth: Int) {
            guard depth <= maximumDepth else { return }
            if let text = value as? String {
                if credentialKey, redactedValues.contains(text.lowercased()) { found.append(path) }
            } else if let dictionary = value as? [String: Any] {
                for (key, nested) in dictionary {
                    walk(nested, path: "\(path).\(key)", credentialKey: isCredentialKey(key), depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                for (index, nested) in array.enumerated() {
                    walk(nested, path: "\(path)[\(index)]", credentialKey: credentialKey, depth: depth + 1)
                }
            }
        }
        for (index, payload) in payloads.enumerated() {
            let type = (payload["PayloadType"] as? String) ?? "payload \(index + 1)"
            walk(payload, path: type, credentialKey: false, depth: 0)
        }
        return found.sorted()
    }

    private static func isCredentialKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return credentialFragments.contains { lower.contains($0) }
    }

    private static func normalizedNumber(_ number: NSNumber) -> Any {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        let encoding = String(cString: number.objCType)
        if encoding == "f" || encoding == "d" { return number.doubleValue }
        if ["Q", "L", "I", "S", "C"].contains(where: { encoding.hasPrefix($0) }) {
            return number.uint64Value
        }
        return number.int64Value
    }

    private static func jsonSafeValue(
        _ value: Any, path: String, depth: Int, visited: Set<ObjectIdentifier>
    ) throws -> Any {
        guard depth <= maximumDepth else {
            throw AppFailure.message("\(path) exceeds the maximum nesting depth.")
        }
        if value is NSNull { return NSNull() }
        if let value = value as? String { return value }
        if let number = value as? NSNumber { return normalizedNumber(number) }
        if let value = value as? Date { return ISO8601DateFormatter().string(from: value) }
        if let value = value as? Data { return value.base64EncodedString() }
        if let value = value as? URL { return value.absoluteString }
        if let dictionary = value as? NSDictionary {
            let id = ObjectIdentifier(dictionary)
            guard !visited.contains(id) else {
                throw AppFailure.message("\(path) contains a cyclic dictionary reference.")
            }
            var next = visited; next.insert(id)
            var result: [String: Any] = [:]
            for (rawKey, nested) in dictionary {
                guard let key = rawKey as? String else {
                    throw AppFailure.message("\(path) contains a non-string dictionary key.")
                }
                result[key] = try jsonSafeValue(
                    nested, path: "\(path).\(key)", depth: depth + 1, visited: next
                )
            }
            return result
        }
        if let array = value as? NSArray {
            let id = ObjectIdentifier(array)
            guard !visited.contains(id) else {
                throw AppFailure.message("\(path) contains a cyclic array reference.")
            }
            var next = visited; next.insert(id)
            return try array.enumerated().map { index, nested in
                try jsonSafeValue(
                    nested, path: "\(path)[\(index)]", depth: depth + 1, visited: next
                )
            }
        }
        throw AppFailure.message(
            "\(path) contains unsupported value type '\(String(describing: type(of: value)))'."
        )
    }
}
