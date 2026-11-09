import Foundation

struct ProfileParser {
    private let objectsByIdentifier: [String: [AppleSchemaObject]]

    init(catalog: AppleSchemaCatalog) {
        self.objectsByIdentifier = Dictionary(grouping: catalog.objects, by: \.identifier)
    }

    func parseMobileconfig(_ data: Data, profileID: String = "local", profileName: String? = nil) throws -> ProfileInspectorDocument {
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any] else {
            throw AppFailure.message("The mobileconfig root is not a property-list dictionary.")
        }
        let payloads: [[String: Any]]
        if let content = root["PayloadContent"] as? [[String: Any]] {
            payloads = content
        } else if root["PayloadType"] is String {
            payloads = [root]
        } else {
            throw AppFailure.message("The property list does not contain a profile payload or PayloadContent array.")
        }
        let resolvedName = profileName ?? (root["PayloadDisplayName"] as? String) ?? "Imported Configuration Profile"
        let profile = JamfProfile(id: profileID, name: resolvedName, payloads: payloads)
        return parse(profile)
    }

    func parse(_ profile: JamfProfile) -> ProfileInspectorDocument {
        var diagnostics: [ProfileParserDiagnostic] = []
        let payloads = profile.payloads.enumerated().map { index, payload in
            parsePayload(payload, index: index, diagnostics: &diagnostics)
        }
        if payloads.isEmpty {
            diagnostics.append(ProfileParserDiagnostic(
                id: "profile.\(profile.id).no-payloads",
                severity: .warning,
                path: "PayloadContent",
                message: "The selected profile did not contain readable PayloadContent entries."
            ))
        }
        return ProfileInspectorDocument(
            id: "profile.\(profile.id)",
            profileID: profile.id,
            profileName: profile.name,
            generatedAt: Date(),
            payloads: payloads,
            diagnostics: diagnostics
        )
    }

    private func parsePayload(
        _ payload: [String: Any],
        index: Int,
        diagnostics: inout [ProfileParserDiagnostic]
    ) -> ProfileInspectorPayload {
        let payloadType = payload["PayloadType"] as? String ?? "<missing PayloadType>"
        let schemaObject = preferredObject(for: payloadType)
        let displayName = (payload["PayloadDisplayName"] as? String) ?? schemaObject?.title ?? payloadType
        let payloadIdentifier = payload["PayloadIdentifier"] as? String
        let payloadUUID = payload["PayloadUUID"] as? String
        let rootPath = ["PayloadContent", String(index)]

        if schemaObject == nil {
            diagnostics.append(ProfileParserDiagnostic(
                id: "payload.\(index).unknown-type",
                severity: .warning,
                path: rootPath.joined(separator: "."),
                message: "No Apple profile schema matched PayloadType \(payloadType). The payload is preserved as unknown or vendor-defined content."
            ))
        }

        let nodes = payload.keys.sorted().map { key in
            parseNode(
                rawKey: key,
                value: ProfileValue.convert(payload[key]!),
                path: rootPath + [key],
                schemaCandidates: schemaObject?.keys ?? [],
                schemaObject: schemaObject,
                diagnostics: &diagnostics
            )
        }

        return ProfileInspectorPayload(
            id: payloadUUID ?? payloadIdentifier ?? "\(payloadType).\(index)",
            index: index,
            payloadType: payloadType,
            displayName: displayName,
            payloadIdentifier: payloadIdentifier,
            payloadUUID: payloadUUID,
            schemaObjectID: schemaObject?.id,
            schemaSource: schemaObject?.source,
            lifecycle: schemaObject?.lifecycle ?? .current,
            matchKind: schemaObject == nil ? .unknown : .exact,
            nodes: nodes
        )
    }

    private func parseNode(
        rawKey: String,
        value: ProfileValue,
        path: [String],
        schemaCandidates: [AppleSchemaKey],
        schemaObject: AppleSchemaObject?,
        diagnostics: inout [ProfileParserDiagnostic]
    ) -> ProfileInspectorNode {
        let exact = schemaCandidates.first { $0.key == rawKey }
        let wildcard = exact == nil ? schemaCandidates.first { $0.wildcard } : nil
        let schemaKey = exact ?? wildcard
        let matchKind: ProfileSchemaMatchKind = exact != nil ? .exact : wildcard != nil ? .wildcard : .unknown
        let displayName = schemaKey?.displayName ?? generatedTitle(from: rawKey)

        let children: [ProfileInspectorNode]
        switch value {
        case .dictionary(let dictionary):
            children = dictionary.keys.sorted().map { childKey in
                parseNode(
                    rawKey: childKey,
                    value: dictionary[childKey]!,
                    path: path + [childKey],
                    schemaCandidates: schemaKey?.children ?? [],
                    schemaObject: schemaObject,
                    diagnostics: &diagnostics
                )
            }
        case .array(let values):
            children = values.enumerated().map { index, childValue in
                let itemSchema = arrayItemCandidates(for: schemaKey, index: index)
                return parseNode(
                    rawKey: "[\(index)]",
                    value: childValue,
                    path: path + ["[\(index)]"],
                    schemaCandidates: itemSchema,
                    schemaObject: schemaObject,
                    diagnostics: &diagnostics
                )
            }
        default:
            children = []
        }

        if matchKind == .unknown && !isCommonPayloadKey(rawKey) {
            diagnostics.append(ProfileParserDiagnostic(
                id: "unknown.\(path.joined(separator: "."))",
                severity: .information,
                path: path.joined(separator: "."),
                message: "No exact or wildcard Apple schema key matched \(rawKey)."
            ))
        }

        let schema = ProfileSchemaMatch(
            kind: matchKind,
            objectID: schemaObject?.id,
            schemaPath: schemaKey?.pathString,
            title: schemaKey?.title,
            description: schemaKey?.description,
            source: schemaObject?.source,
            lifecycle: schemaKey?.lifecycle ?? schemaObject?.lifecycle ?? .current
        )

        return ProfileInspectorNode(
            id: path.joined(separator: "."),
            rawKey: rawKey,
            displayName: rawKey.hasPrefix("[") ? "Item \(rawKey.dropFirst().dropLast())" : displayName,
            path: path,
            value: value,
            schema: schema,
            children: children
        )
    }

    private func preferredObject(for identifier: String) -> AppleSchemaObject? {
        let candidates = objectsByIdentifier[identifier] ?? []
        return candidates.first { $0.family == "mdm-profile" } ?? candidates.first
    }

    private func arrayItemCandidates(for key: AppleSchemaKey?, index: Int) -> [AppleSchemaKey] {
        guard let key else { return [] }
        if key.children.count == 1 { return key.children }
        let indexKey = String(index)
        let direct = key.children.filter { $0.key == indexKey || $0.key == "[\(index)]" || $0.wildcard }
        return direct.isEmpty ? key.children : direct
    }

    private func isCommonPayloadKey(_ key: String) -> Bool {
        ["PayloadType", "PayloadVersion", "PayloadIdentifier", "PayloadUUID", "PayloadDisplayName", "PayloadDescription", "PayloadOrganization", "PayloadEnabled"].contains(key)
    }

    private func generatedTitle(from key: String) -> String {
        let withSpaces = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        return withSpaces.prefix(1).uppercased() + withSpaces.dropFirst()
    }
}
