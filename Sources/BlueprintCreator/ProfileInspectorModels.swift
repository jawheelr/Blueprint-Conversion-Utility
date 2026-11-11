import Foundation

enum ProfileValue: Hashable, CustomStringConvertible {
    case dictionary([String: ProfileValue])
    case array([ProfileValue])
    case string(String)
    case integer(Int64)
    case real(Double)
    case boolean(Bool)
    case date(Date)
    case data(Data)
    case null
    case unsupported(String)

    static func convert(_ value: Any) -> ProfileValue {
        switch value {
        case let value as [String: Any]:
            return .dictionary(value.mapValues(ProfileValue.convert))
        case let value as [Any]:
            return .array(value.map(ProfileValue.convert))
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .boolean(value)
        case let value as Int:
            return .integer(Int64(value))
        case let value as Int8:
            return .integer(Int64(value))
        case let value as Int16:
            return .integer(Int64(value))
        case let value as Int32:
            return .integer(Int64(value))
        case let value as Int64:
            return .integer(value)
        case let value as UInt:
            return value <= UInt(Int64.max) ? .integer(Int64(value)) : .unsupported(String(value))
        case let value as Double:
            return .real(value)
        case let value as Float:
            return .real(Double(value))
        case let value as Date:
            return .date(value)
        case let value as Data:
            return .data(value)
        case _ as NSNull:
            return .null
        default:
            return .unsupported(String(describing: value))
        }
    }

    var description: String {
        switch self {
        case .dictionary(let value): return "Dictionary (\(value.count) keys)"
        case .array(let value): return "Array (\(value.count) items)"
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .date(let value): return ISO8601DateFormatter().string(from: value)
        case .data(let value): return "Data (\(value.count) bytes)"
        case .null: return "null"
        case .unsupported(let value): return value
        }
    }

    var typeName: String {
        switch self {
        case .dictionary: return "Dictionary"
        case .array: return "Array"
        case .string: return "String"
        case .integer: return "Integer"
        case .real: return "Real"
        case .boolean: return "Boolean"
        case .date: return "Date"
        case .data: return "Data"
        case .null: return "Null"
        case .unsupported: return "Unsupported"
        }
    }
}

enum ProfileSchemaMatchKind: String, Hashable {
    case exact = "Exact"
    case wildcard = "Wildcard"
    case payloadOnly = "Payload Only"
    case unknown = "Unknown"
}

struct ProfileSchemaMatch: Hashable {
    let kind: ProfileSchemaMatchKind
    let objectID: String?
    let schemaPath: String?
    let title: String?
    let description: String?
    let source: String?
    let lifecycle: AppleSchemaLifecycle
}

struct ProfileInspectorNode: Identifiable, Hashable {
    let id: String
    let rawKey: String
    let displayName: String
    let path: [String]
    let value: ProfileValue
    let schema: ProfileSchemaMatch
    let children: [ProfileInspectorNode]

    var pathString: String { path.joined(separator: ".") }
}

struct ProfileInspectorPayload: Identifiable, Hashable {
    let id: String
    let index: Int
    let payloadType: String
    let displayName: String
    let payloadIdentifier: String?
    let payloadUUID: String?
    let schemaObjectID: String?
    let schemaSource: String?
    let lifecycle: AppleSchemaLifecycle
    let matchKind: ProfileSchemaMatchKind
    let nodes: [ProfileInspectorNode]
}

struct ProfileInspectorDocument: Identifiable, Hashable {
    let id: String
    let profileID: String
    let profileName: String
    let generatedAt: Date
    let payloads: [ProfileInspectorPayload]
    let diagnostics: [ProfileParserDiagnostic]

    var payloadCount: Int { payloads.count }
    var settingCount: Int { payloads.reduce(0) { $0 + Self.count($1.nodes) } }
    var unknownSettingCount: Int { payloads.reduce(0) { $0 + Self.count($1.nodes, where: { $0.schema.kind == .unknown }) } }
    var wildcardMatchCount: Int { payloads.reduce(0) { $0 + Self.count($1.nodes, where: { $0.schema.kind == .wildcard }) } }

    private static func count(_ nodes: [ProfileInspectorNode], where predicate: (ProfileInspectorNode) -> Bool = { _ in true }) -> Int {
        nodes.reduce(0) { $0 + (predicate($1) ? 1 : 0) + count($1.children, where: predicate) }
    }
}

struct ProfileParserDiagnostic: Identifiable, Hashable {
    enum Severity: String, Hashable { case information, warning, error }
    let id: String
    let severity: Severity
    let path: String
    let message: String
}
