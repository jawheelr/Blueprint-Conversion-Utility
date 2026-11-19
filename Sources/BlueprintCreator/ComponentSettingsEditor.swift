import SwiftUI

extension JSONDocumentValue {
    var arrayValue: [JSONDocumentValue]? { if case .array(let value) = self { return value }; return nil }
}

extension AppleSchemaKey {
    /// Apple's type tag without the angle brackets, for example "boolean" or "dictionary".
    var typeName: String {
        (type?.stringValue ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<>")).lowercased()
    }

    var enumChoices: [String] {
        (values?.arrayValue ?? []).compactMap { item in
            if let object = item.objectValue { return object["value"]?.stringValue }
            return item.stringValue
        }
    }

    var rangeText: String? {
        guard let range = range?.objectValue else { return nil }
        let low = range["min"]?.stringValue, high = range["max"]?.stringValue
        switch (low, high) {
        case let (low?, high?): return "Range \(low) to \(high)"
        case let (low?, nil): return "Minimum \(low)"
        case let (nil, high?): return "Maximum \(high)"
        default: return nil
        }
    }

    /// A starting value for a key being added.
    var starterValue: Any {
        switch typeName {
        case "boolean": return (defaultValue.flatMap { if case .bool(let v) = $0 { return v }; return nil }) ?? false
        case "integer": return NSNumber(value: 0)
        case "real": return NSNumber(value: 0.0)
        case "array": return [Any]()
        case "dictionary": return [String: Any]()
        default: return enumChoices.first ?? ""
        }
    }
}

/// Finds the Apple schema keys that describe a Jamf blueprint component.
enum ExplorerSchemaResolver {
    private static let metaKeys: Set<String> = ["version", "Included"]

    static func rootSchema(identifier: String, configuration: [String: Any], catalog: AppleSchemaCatalog?) -> [AppleSchemaKey]? {
        guard let catalog, identifier != "com.jamf.ddm-configuration-profile", identifier != "com.jamf.ddm.custom-declarations" else { return nil }
        let names = Set(configuration.keys).subtracting(metaKeys)
        guard !names.isEmpty else { return nil }
        var best: (score: Int, object: AppleSchemaObject)?
        for object in catalog.objects where object.family == "declarative-configuration" {
            let keys = Set(object.keys.map(\.key))
            let score = names.intersection(keys).count
            if score > (best?.score ?? 0) { best = (score, object) }
        }
        guard let best, Double(best.score) / Double(names.count) >= 0.5 else { return nil }
        return best.object.keys
    }

    /// Schema for an object nested inside a component, where the right definition depends on a sibling value.
    static func override(identifier: String, path: [JSONPathStep], configuration: Any, catalog: AppleSchemaCatalog?) -> [AppleSchemaKey]? {
        guard let catalog else { return nil }
        if identifier == "com.jamf.ddm-configuration-profile", path.count == 2,
           case .key("payloadContent") = path[0], case .index = path[1],
           let payload = JSONTree.value(in: configuration, at: path) as? [String: Any],
           let type = payload["payloadType"] as? String {
            return catalog.objects.first { $0.family == "mdm-profile" && $0.identifier == type }?.keys
        }
        if identifier == "com.jamf.ddm.custom-declarations", path.count == 3,
           case .key("declarations") = path[0], case .index = path[1], case .key("payload") = path[2],
           let declaration = JSONTree.value(in: configuration, at: Array(path.dropLast())) as? [String: Any],
           let type = declaration["type"] as? String {
            return catalog.objects.first { $0.family == "declarative-configuration" && $0.identifier == type }?.keys
        }
        return nil
    }
}

/// Edits one component's configuration: typed controls where Apple's schema is known, plus raw JSON.
struct ComponentSettingsEditor: View {
    @EnvironmentObject private var model: AppModel
    let step: Int
    let component: Int
    @State private var tab = 0
    @State private var rawText = ""
    @State private var rawError: String?

    private var basePath: [JSONPathStep] { [.key("steps"), .index(step), .key("components"), .index(component)] }
    private var configPath: [JSONPathStep] { basePath + [.key("configuration")] }
    private var identifier: String { (model.explorerValue(at: basePath + [.key("identifier")]) as? String) ?? "" }
    private var configuration: [String: Any] { (model.explorerValue(at: configPath) as? [String: Any]) ?? [:] }
    private var schema: [AppleSchemaKey]? {
        ExplorerSchemaResolver.rootSchema(identifier: identifier, configuration: configuration, catalog: model.explorerSchema)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(identifier.isEmpty ? "Component" : identifier).font(.title3.bold()).textSelection(.enabled)
                Spacer()
                Picker("", selection: $tab) { Text("Settings").tag(0); Text("Raw JSON").tag(1) }
                    .pickerStyle(.segmented).frame(width: 190).labelsHidden()
            }
            if tab == 0 {
                if schema == nil && identifier.hasPrefix("com.jamf.ddm.") && identifier != "com.jamf.ddm.custom-declarations" {
                    Label("No Apple schema matched this component, so values are shown without descriptions or choices.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    ConfigNodeView(identifier: identifier, path: configPath, relative: [], schema: schema, depth: 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextEditor(text: $rawText).font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 260).border(Color.secondary.opacity(0.3))
                    .onChange(of: rawText) { text in
                        if let value = JSONTree.parse(text) as? [String: Any] { rawError = nil; _ = value } else { rawError = "Not a valid JSON object." }
                    }
                HStack {
                    if let rawError { Label(rawError, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption) }
                    Spacer()
                    Button("Reset") { rawText = JSONTree.prettyString(configuration) }
                    Button("Apply JSON") {
                        if let value = JSONTree.parse(rawText) as? [String: Any] { model.explorerSet(value, at: configPath) }
                    }.disabled(rawError != nil)
                }
            }
        }
        .onAppear { rawText = JSONTree.prettyString(configuration) }
        .onChange(of: step) { _ in rawText = JSONTree.prettyString(configuration) }
        .onChange(of: component) { _ in rawText = JSONTree.prettyString(configuration) }
        .onChange(of: tab) { _ in rawText = JSONTree.prettyString(configuration) }
    }
}

/// One value in a configuration tree. Dictionaries and arrays recurse.
private struct ConfigNodeView: View {
    @EnvironmentObject private var model: AppModel
    let identifier: String
    let path: [JSONPathStep]
    let relative: [JSONPathStep]
    let schema: [AppleSchemaKey]?
    let depth: Int

    private var value: Any? { model.explorerValue(at: path) }

    private var effectiveSchema: [AppleSchemaKey]? {
        guard let root = model.explorerDraft else { return schema }
        let componentRoot = Array(path.prefix(4 + 1))   // up to .configuration
        let configuration = JSONTree.value(in: root, at: componentRoot) ?? [:]
        return ExplorerSchemaResolver.override(identifier: identifier, path: relative, configuration: configuration, catalog: model.explorerSchema) ?? schema
    }

    var body: some View {
        if let dictionary = value as? [String: Any] {
            dictionaryView(dictionary)
        } else if let array = value as? [Any] {
            arrayView(array)
        }
    }

    private func dictionaryView(_ dictionary: [String: Any]) -> some View {
        let keys = effectiveSchema
        let missing = (keys ?? []).filter { !$0.wildcard && dictionary[$0.key] == nil }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(dictionary.keys.sorted(), id: \.self) { key in
                row(key: key, schemaKey: keys?.first { $0.key == key }, child: dictionary[key])
            }
            if !missing.isEmpty {
                Menu("Add setting") {
                    ForEach(missing) { key in
                        Button(key.displayName) { model.explorerSet(key.starterValue, at: path + [.key(key.key)]) }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(.leading, depth == 0 ? 0 : 14)
    }

    private func arrayView(_ array: [Any]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(array.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    Text("Item \(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    child(at: .index(index), value: array[index], schemaKey: nil)
                    Button { model.explorerRemove(at: path + [.index(index)]) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Item") {
                let sample = array.first
                model.explorerSet(array + [Self.blank(like: sample)], at: path)
            }.buttonStyle(.borderless)
        }
        .padding(.leading, depth == 0 ? 0 : 14)
    }

    private func row(key: String, schemaKey: AppleSchemaKey?, child value: Any?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(schemaKey?.displayName ?? key).font(.subheadline.bold())
                if schemaKey != nil, schemaKey?.displayName != key { Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                Spacer()
                Button { model.explorerRemove(at: path + [.key(key)]) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove this setting from the blueprint component")
            }
            if let value { child(at: .key(key), value: value, schemaKey: schemaKey) }
            if let description = schemaKey?.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if let range = schemaKey?.rangeText { Text(range).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder private func child(at step: JSONPathStep, value: Any, schemaKey: AppleSchemaKey?) -> some View {
        let childPath = path + [step]
        if value is [String: Any] || value is [Any] {
            ConfigNodeView(identifier: identifier, path: childPath, relative: relative + [step], schema: schemaKey?.children, depth: depth + 1)
        } else if JSONTree.isBool(value) {
            Toggle("", isOn: Binding(get: { (model.explorerValue(at: childPath) as? Bool) ?? false },
                                      set: { model.explorerSet($0, at: childPath) })).labelsHidden()
        } else if JSONTree.isNumber(value) {
            NumberField(path: childPath)
        } else if let text = value as? String {
            let choices = schemaKey?.enumChoices ?? []
            if !choices.isEmpty {
                Picker("", selection: Binding(get: { (model.explorerValue(at: childPath) as? String) ?? text },
                                              set: { model.explorerSet($0, at: childPath) })) {
                    ForEach(choices.contains(text) ? choices : [text] + choices, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().fixedSize()
            } else {
                TextField("", text: Binding(get: { (model.explorerValue(at: childPath) as? String) ?? text },
                                            set: { model.explorerSet($0, at: childPath) })).textFieldStyle(.roundedBorder)
            }
        } else {
            Text("null").foregroundStyle(.secondary)
        }
    }

    private static func blank(like sample: Any?) -> Any {
        switch sample {
        case is [String: Any]: return [String: Any]()
        case is [Any]: return [Any]()
        case let value? where JSONTree.isBool(value): return false
        case let value? where JSONTree.isNumber(value): return NSNumber(value: 0)
        default: return ""
        }
    }
}

/// Numeric text field that keeps whole numbers as integers and ignores text that is not a number.
private struct NumberField: View {
    @EnvironmentObject private var model: AppModel
    let path: [JSONPathStep]
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        TextField("", text: $text).textFieldStyle(.roundedBorder).frame(width: 140)
            .foregroundStyle(invalid ? .red : .primary)
            .onAppear { text = (model.explorerValue(at: path) as? NSNumber)?.stringValue ?? "" }
            .onChange(of: text) { newValue in
                if let number = JSONTree.number(from: newValue) { invalid = false; model.explorerSet(number, at: path) }
                else { invalid = true }
            }
    }
}
