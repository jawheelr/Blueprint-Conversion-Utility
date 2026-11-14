import Foundation

/// Attributes the Visual activation editor offers. Each one maps to a declarative
/// status item that exists in Apple's device-management schema, or to Jamf's own
/// group-membership property. Anything else is written in the Text editor.
enum ActivationAttribute: String, CaseIterable, Identifiable, Sendable {
    case osFamily, osVersion, osBuild
    case modelFamily, modelIdentifier, modelName, modelNumber
    case serialNumber, udid, batteryHealth
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .osFamily: return "Operating system"
        case .osVersion: return "Operating system version"
        case .osBuild: return "Operating system build"
        case .modelFamily: return "Device family"
        case .modelIdentifier: return "Model identifier"
        case .modelName: return "Model name"
        case .modelNumber: return "Model number"
        case .serialNumber: return "Serial number"
        case .udid: return "UDID"
        case .batteryHealth: return "Battery health"
        case .group: return "Device group"
        }
    }

    /// Status item key path; nil for group membership.
    var keyPath: String? {
        switch self {
        case .osFamily: return "device.operating-system.family"
        case .osVersion: return "device.operating-system.version"
        case .osBuild: return "device.operating-system.build-version"
        case .modelFamily: return "device.model.family"
        case .modelIdentifier: return "device.model.identifier"
        case .modelName: return "device.model.marketing-name"
        case .modelNumber: return "device.model.number"
        case .serialNumber: return "device.identifier.serial-number"
        case .udid: return "device.identifier.udid"
        case .batteryHealth: return "device.power.battery-health"
        case .group: return nil
        }
    }

    /// Version and build strings can be compared with <, >, <= and >=.
    var allowsOrdering: Bool { self == .osVersion || self == .osBuild }

    /// Fixed value choices, when Apple documents them.
    var choices: [String] {
        switch self {
        case .osFamily: return ["macOS", "iOS", "iPadOS", "tvOS", "watchOS", "visionOS"]
        case .modelFamily: return ["Mac", "iPhone", "iPad", "AppleTV", "Watch", "RealityDevice"]
        case .batteryHealth: return ["normal", "service-recommended", "non-genuine", "unknown", "unsupported"]
        default: return []
        }
    }

    static func attribute(forKeyPath key: String) -> ActivationAttribute? {
        allCases.first { $0.keyPath == key }
    }

    var operators: [ActivationOperator] {
        if self == .group { return [.memberOf, .notMemberOf] }
        var list: [ActivationOperator] = [.equals, .notEquals]
        if !choices.isEmpty { return list }
        list += [.contains, .notContains, .beginsWith, .notBeginsWith, .endsWith, .notEndsWith, .like, .matches]
        if allowsOrdering { list += [.greater, .greaterOrEqual, .less, .lessOrEqual] }
        return list
    }
}

enum ActivationOperator: String, CaseIterable, Identifiable, Sendable {
    case equals, notEquals
    case contains, notContains
    case beginsWith, notBeginsWith
    case endsWith, notEndsWith
    case like, matches
    case greater, greaterOrEqual, less, lessOrEqual
    case memberOf, notMemberOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .beginsWith: return "starts with"
        case .notBeginsWith: return "does not start with"
        case .endsWith: return "ends with"
        case .notEndsWith: return "does not end with"
        case .like: return "is like"
        case .matches: return "matches"
        case .greater: return "is greater than"
        case .greaterOrEqual: return "is at least"
        case .less: return "is less than"
        case .lessOrEqual: return "is at most"
        case .memberOf: return "is a member of"
        case .notMemberOf: return "is not a member of"
        }
    }

    /// Predicate token and whether the whole term is wrapped in NOT ( ... ).
    var token: (op: String, negated: Bool) {
        switch self {
        case .equals: return ("==", false)
        case .notEquals: return ("!=", false)
        case .contains: return ("CONTAINS", false)
        case .notContains: return ("CONTAINS", true)
        case .beginsWith: return ("BEGINSWITH", false)
        case .notBeginsWith: return ("BEGINSWITH", true)
        case .endsWith: return ("ENDSWITH", false)
        case .notEndsWith: return ("ENDSWITH", true)
        case .like: return ("LIKE", false)
        case .matches: return ("MATCHES", false)
        case .greater: return (">", false)
        case .greaterOrEqual: return (">=", false)
        case .less: return ("<", false)
        case .lessOrEqual: return ("<=", false)
        case .memberOf, .notMemberOf: return ("IN", false)
        }
    }

    static func from(token: String, negated: Bool) -> ActivationOperator? {
        allCases.first { $0 != .memberOf && $0 != .notMemberOf && $0.token.op == token && $0.token.negated == negated }
    }
}

struct ActivationConditionRow: Identifiable, Equatable, Sendable {
    var id = UUID()
    var attribute: ActivationAttribute = .osFamily
    var op: ActivationOperator = .equals
    /// Text value, or a Platform group ID for group rows.
    var value: String = ""
}

enum ActivationMatch: String, Sendable { case all, any
    var joiner: String { self == .all ? " AND " : " OR " }
}

/// Builds and parses Apple declarative predicates, the format of a Blueprint step's
/// `activationPredicate`. Parsing is deliberately strict: anything it cannot read back
/// exactly is reported as nil so callers keep the original text instead of rewriting it.
enum ActivationPredicate {
    static let groupProperty = "@property(jamf.device.groups)"
    static let maxLength = 10_000

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    static func term(for row: ActivationConditionRow) -> String? {
        let value = row.value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if row.attribute == .group {
            let quantifier = row.op == .notMemberOf ? "NONE" : "ANY"
            return "\(quantifier) \(groupProperty) IN {\(quote(value))}"
        }
        guard let key = row.attribute.keyPath else { return nil }
        let token = row.op.token
        let core = "@status(\(key)) \(token.op) \(quote(value))"
        return token.negated ? "NOT (\(core))" : core
    }

    /// Joins rows. With "match all", every "is not a member" row is folded into a
    /// single NONE over the whole set, which is the form jamf-cli writes for exclusions.
    static func build(rows: [ActivationConditionRow], match: ActivationMatch) -> String {
        var terms: [String] = []
        var excluded: [String] = []
        for row in rows {
            if match == .all, row.attribute == .group, row.op == .notMemberOf {
                let id = row.value.trimmingCharacters(in: .whitespaces)
                if !id.isEmpty, !excluded.contains(id) { excluded.append(id) }
                continue
            }
            if let text = term(for: row) { terms.append(text) }
        }
        if !excluded.isEmpty {
            terms.append("NONE \(groupProperty) IN {\(excluded.map(quote).joined(separator: ", "))}")
        }
        return terms.joined(separator: match.joiner)
    }

    struct Parsed: Equatable, Sendable {
        var rows: [ActivationConditionRow]
        var match: ActivationMatch
    }

    /// Returns nil when the text uses anything the Visual editor cannot represent.
    static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(rows: [], match: .all) }
        let andParts = splitTopLevel(trimmed, joiner: " AND ")
        let orParts = splitTopLevel(trimmed, joiner: " OR ")
        let match: ActivationMatch
        let parts: [String]
        switch (andParts.count > 1, orParts.count > 1) {
        case (true, true): return nil
        case (true, false): match = .all; parts = andParts
        case (false, true): match = .any; parts = orParts
        case (false, false): match = .all; parts = [trimmed]
        }
        var rows: [ActivationConditionRow] = []
        for part in parts {
            guard let parsed = parseTerm(part.trimmingCharacters(in: .whitespaces), match: match) else { return nil }
            rows += parsed
        }
        let result = Parsed(rows: rows, match: match)
        // Only accept it when rebuilding reproduces the same predicate.
        return build(rows: rows, match: match) == trimmed ? result : nil
    }

    private static func parseTerm(_ text: String, match: ActivationMatch) -> [ActivationConditionRow]? {
        if let groups = parseGroupTerm(text, match: match) { return groups }
        var body = text
        var negated = false
        if body.hasPrefix("NOT (") && body.hasSuffix(")") {
            negated = true
            body = String(body.dropFirst(5).dropLast())
        }
        let prefix = "@status("
        guard body.hasPrefix(prefix), let close = body.firstIndex(of: ")") else { return nil }
        let key = String(body[body.index(body.startIndex, offsetBy: prefix.count)..<close])
        guard let attribute = ActivationAttribute.attribute(forKeyPath: key) else { return nil }
        let rest = body[body.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard let space = rest.firstIndex(of: " ") else { return nil }
        let token = String(rest[..<space])
        let valueText = rest[rest.index(after: space)...].trimmingCharacters(in: .whitespaces)
        guard let value = unquote(valueText),
              let op = ActivationOperator.from(token: token, negated: negated),
              attribute.operators.contains(op) else { return nil }
        return [ActivationConditionRow(attribute: attribute, op: op, value: value)]
    }

    private static func parseGroupTerm(_ text: String, match: ActivationMatch) -> [ActivationConditionRow]? {
        for (word, op) in [("ANY", ActivationOperator.memberOf), ("NONE", ActivationOperator.notMemberOf)] {
            let prefix = "\(word) \(groupProperty) IN {"
            guard text.hasPrefix(prefix), text.hasSuffix("}") else { continue }
            let inner = String(text.dropFirst(prefix.count).dropLast())
            let ids = splitTopLevel(inner, joiner: ", ").compactMap(unquote)
            guard !ids.isEmpty, ids.count == splitTopLevel(inner, joiner: ", ").count else { return nil }
            // A NONE over several IDs becomes one row per ID under "match all".
            // ANY over several IDs cannot be expressed as separate rows.
            if op == .memberOf && ids.count > 1 { return nil }
            if op == .notMemberOf && ids.count > 1 && match != .all { return nil }
            return ids.map { ActivationConditionRow(attribute: .group, op: op, value: $0) }
        }
        return nil
    }

    private static func unquote(_ text: String) -> String? {
        guard text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") else { return nil }
        let inner = String(text.dropFirst().dropLast())
        var result = ""
        var escaped = false
        for character in inner {
            if escaped { result.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "'" { return nil }
            else { result.append(character) }
        }
        return escaped ? nil : result
    }

    /// Splits on `joiner` only outside quotes, parentheses and braces.
    static func splitTopLevel(_ text: String, joiner: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        var escaped = false
        let characters = Array(text)
        let joinerChars = Array(joiner)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuote {
                current.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "'" { inQuote = false }
                index += 1
                continue
            }
            if character == "'" { inQuote = true; current.append(character); index += 1; continue }
            if character == "(" || character == "{" { depth += 1 }
            if character == ")" || character == "}" { depth -= 1 }
            if depth == 0, index + joinerChars.count <= characters.count,
               Array(characters[index..<(index + joinerChars.count)]) == joinerChars {
                parts.append(current)
                current = ""
                index += joinerChars.count
                continue
            }
            current.append(character)
            index += 1
        }
        parts.append(current)
        return parts
    }
}
