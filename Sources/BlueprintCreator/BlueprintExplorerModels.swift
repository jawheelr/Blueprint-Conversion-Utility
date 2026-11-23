import Foundation

/// One row in the Blueprints Explorer list (the list endpoint has no steps or scope).
struct ExplorerBlueprintSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let updated: String
    let state: String

    init?(json: [String: Any]) {
        guard let rawID = json["id"], Validators.isSafeIdentifier(String(describing: rawID)) else { return nil }
        id = String(describing: rawID)
        name = (json["name"] as? String) ?? "Untitled"
        description = (json["description"] as? String) ?? ""
        updated = (json["updated"] as? String) ?? ""
        state = Self.deploymentState(in: json)
    }

    static func deploymentState(in json: [String: Any]) -> String {
        if let object = json["deploymentState"] as? [String: Any], let state = object["state"] as? String { return state }
        if let state = json["deploymentState"] as? String { return state }
        return "UNKNOWN"
    }

    var stateTitle: String {
        switch state.uppercased() {
        case "DEPLOYED": return "Deployed"
        case "NOT_DEPLOYED": return "Not deployed"
        case "OUT_OF_DATE": return "Out of date"
        default: return "Unknown"
        }
    }
}

/// Which part of a blueprint the Explorer's editor pane shows.
enum ExplorerSelection: Hashable {
    case details
    case scope
    case step(Int)
    case component(Int, Int)
}

/// A step in a JSON path: a dictionary key or an array index.
enum JSONPathStep: Hashable {
    case key(String)
    case index(Int)
}

/// Value-in, value-out editing of parsed JSON (`JSONSerialization` output). Integers,
/// booleans and doubles keep their type, and every edit returns a new tree.
enum JSONTree {
    static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func isNumber(_ value: Any) -> Bool { value is NSNumber && !isBool(value) }

    static func value(in root: Any, at path: [JSONPathStep]) -> Any? {
        var current: Any = root
        for step in path {
            switch step {
            case .key(let key):
                guard let dictionary = current as? [String: Any], let next = dictionary[key] else { return nil }
                current = next
            case .index(let index):
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return current
    }

    /// Sets (or inserts, for a dictionary key) a value. Returns nil when the path does not exist.
    static func setting(_ value: Any, in root: Any, at path: [JSONPathStep]) -> Any? {
        guard let first = path.first else { return value }
        let rest = Array(path.dropFirst())
        switch first {
        case .key(let key):
            guard var dictionary = root as? [String: Any] else { return nil }
            if rest.isEmpty { dictionary[key] = value; return dictionary }
            guard let child = dictionary[key], let updated = setting(value, in: child, at: rest) else { return nil }
            dictionary[key] = updated
            return dictionary
        case .index(let index):
            guard var array = root as? [Any], array.indices.contains(index) else { return nil }
            if rest.isEmpty { array[index] = value; return array }
            guard let updated = setting(value, in: array[index], at: rest) else { return nil }
            array[index] = updated
            return array
        }
    }

    static func removing(in root: Any, at path: [JSONPathStep]) -> Any? {
        guard let first = path.first else { return nil }
        let rest = Array(path.dropFirst())
        switch first {
        case .key(let key):
            guard var dictionary = root as? [String: Any] else { return nil }
            if rest.isEmpty { dictionary.removeValue(forKey: key); return dictionary }
            guard let child = dictionary[key], let updated = removing(in: child, at: rest) else { return nil }
            dictionary[key] = updated
            return dictionary
        case .index(let index):
            guard var array = root as? [Any], array.indices.contains(index) else { return nil }
            if rest.isEmpty { array.remove(at: index); return array }
            guard let updated = removing(in: array[index], at: rest) else { return nil }
            array[index] = updated
            return array
        }
    }

    /// Parses numeric text, keeping whole numbers as integers.
    static func number(from text: String) -> NSNumber? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let integer = Int64(trimmed) { return NSNumber(value: integer) }
        if let double = Double(trimmed), double.isFinite { return NSNumber(value: double) }
        return nil
    }

    static func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    static func prettyString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func parse(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Human-readable list of paths whose values differ between two trees.
    static func changedPaths(from old: Any, to new: Any, prefix: String = "") -> [String] {
        if let a = old as? [String: Any], let b = new as? [String: Any] {
            var paths: [String] = []
            for key in Set(a.keys).union(b.keys).sorted() {
                let child = prefix.isEmpty ? key : "\(prefix).\(key)"
                switch (a[key], b[key]) {
                case (nil, .some): paths.append("\(child) (added)")
                case (.some, nil): paths.append("\(child) (removed)")
                case (.some(let x), .some(let y)): paths += changedPaths(from: x, to: y, prefix: child)
                default: break
                }
            }
            return paths
        }
        if let a = old as? [Any], let b = new as? [Any] {
            if a.count != b.count { return ["\(prefix) (\(a.count) to \(b.count) items)"] }
            return zip(a, b).enumerated().flatMap { changedPaths(from: $1.0, to: $1.1, prefix: "\(prefix)[\($0)]") }
        }
        return equal(old, new) ? [] : [prefix]
    }

    static func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSObject, let y = b as? NSObject { return x.isEqual(y) }
        return false
    }
}
