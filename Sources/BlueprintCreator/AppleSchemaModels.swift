import Foundation

enum AppleSchemaFamily: String, CaseIterable, Identifiable {
    case all = "All"
    case profiles = "Configuration Profiles"
    case configurations = "Declarative Configurations"
    case assets = "Declarative Assets"
    case activations = "Declarative Activations"
    case management = "Declarative Management"
    case status = "Declarative Status"
    case commands = "MDM Commands"
    case other = "Other"

    var id: String { rawValue }

    func contains(_ family: String) -> Bool {
        switch self {
        case .all: return true
        case .profiles: return family == "mdm-profile"
        case .configurations: return family == "declarative-configuration"
        case .assets: return family == "declarative-asset"
        case .activations: return family == "declarative-activation"
        case .management: return family == "declarative-management"
        case .status: return family == "declarative-status"
        case .commands: return family == "mdm-command"
        case .other: return !["mdm-profile", "declarative-configuration", "declarative-asset", "declarative-activation", "declarative-management", "declarative-status", "mdm-command"].contains(family)
        }
    }
}

enum AppleSchemaLifecycleFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case current = "Current"
    case deprecated = "Deprecated"
    case removed = "Removed"
    var id: String { rawValue }
}

struct AppleSchemaCatalog: Decodable {
    let formatVersion: Int
    let generatedAt: String
    let objects: [AppleSchemaObject]
}

struct AppleSchemaObject: Decodable, Identifiable, Hashable {
    let id: String
    let family: String
    let identifier: String
    let title: String
    let description: String?
    let source: String
    let payload: JSONDocumentValue
    let keys: [AppleSchemaKey]

    var supportedOS: [String: JSONDocumentValue] {
        payload.objectValue?["supportedOS"]?.objectValue ?? [:]
    }

    var lifecycle: AppleSchemaLifecycle {
        AppleSchemaLifecycle.from(supportedOS: supportedOS)
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if [title, identifier, description ?? "", source, family].contains(where: { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(q) }) { return true }
        return keys.contains { $0.matches(query) }
    }
}

struct AppleSchemaKey: Decodable, Identifiable, Hashable {
    let key: String
    let path: [String]
    let pathString: String
    let wildcard: Bool
    let title: String?
    let description: String?
    let type: JSONDocumentValue?
    let presence: JSONDocumentValue?
    let defaultValue: JSONDocumentValue?
    let format: JSONDocumentValue?
    let values: JSONDocumentValue?
    let range: JSONDocumentValue?
    let repetition: JSONDocumentValue?
    let combinetype: JSONDocumentValue?
    let supportedOS: [String: JSONDocumentValue]?
    let recursiveReference: Bool?
    let children: [AppleSchemaKey]

    enum CodingKeys: String, CodingKey {
        case key, path, pathString, wildcard, title, description, type, presence, format, values, range, repetition, combinetype, supportedOS, recursiveReference, children
        case defaultValue = "default"
    }

    var id: String { pathString }
    var displayName: String { title?.isEmpty == false ? title! : key }
    var lifecycle: AppleSchemaLifecycle { AppleSchemaLifecycle.from(supportedOS: supportedOS ?? [:]) }

    func matches(_ query: String) -> Bool {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if [displayName, key, pathString, description ?? ""].contains(where: { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(q) }) { return true }
        return children.contains { $0.matches(query) }
    }
}

enum AppleSchemaLifecycle: String, Comparable, Hashable {
    case current = "Current"
    case deprecated = "Deprecated"
    case removed = "Removed"

    static func < (lhs: AppleSchemaLifecycle, rhs: AppleSchemaLifecycle) -> Bool {
        let order: [AppleSchemaLifecycle] = [.current, .deprecated, .removed]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    static func from(supportedOS: [String: JSONDocumentValue]) -> AppleSchemaLifecycle {
        var result: AppleSchemaLifecycle = .current
        for metadata in supportedOS.values {
            guard let values = metadata.objectValue else { continue }
            if let removed = values["removed"]?.stringValue, removed.lowercased() != "n/a" { result = max(result, .removed) }
            else if let deprecated = values["deprecated"]?.stringValue, deprecated.lowercased() != "n/a" { result = max(result, .deprecated) }
        }
        return result
    }
}

indirect enum JSONDocumentValue: Decodable, Hashable, CustomStringConvertible {
    case object([String: JSONDocumentValue])
    case array([JSONDocumentValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONDocumentValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONDocumentValue].self)) }
    }

    var objectValue: [String: JSONDocumentValue]? { if case .object(let value) = self { return value }; return nil }
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        default: return nil
        }
    }
    var description: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .array(let values): return values.map(\.description).joined(separator: ", ")
        case .object(let values): return values.keys.sorted().map { "\($0): \(values[$0]!.description)" }.joined(separator: ", ")
        }
    }
}
