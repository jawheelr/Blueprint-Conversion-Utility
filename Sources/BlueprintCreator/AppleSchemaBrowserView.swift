import SwiftUI
import AppKit

struct AppleSchemaBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: AppleSchemaCatalog?
    @State private var summary: AppleSchemaSummary?
    @State private var loadError: String?
    @State private var search = ""
    @State private var family: AppleSchemaFamily = .all
    @State private var lifecycle: AppleSchemaLifecycleFilter = .all
    @State private var selectedObjectID: String?
    @State private var selectedKeyPath: String?
    @State private var expandedSchemaPaths: Set<String> = []

    private var objects: [AppleSchemaObject] {
        guard let catalog else { return [] }
        return catalog.objects.filter { object in
            family.contains(object.family) && lifecycleMatches(object.lifecycle) && object.matches(search)
        }
    }

    private var selectedObject: AppleSchemaObject? {
        guard let catalog, let selectedObjectID else { return nil }
        return catalog.objects.first { $0.id == selectedObjectID }
    }

    private var selectedKey: AppleSchemaKey? {
        guard let selectedObject, let selectedKeyPath else { return nil }
        return find(path: selectedKeyPath, in: selectedObject.keys)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let loadError {
                placeholder("Unable to Load Apple Schema", icon: "exclamationmark.triangle.fill", detail: loadError)
            } else if catalog == nil {
                ProgressView("Loading Apple Device Management schema...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                browser
            }
            Divider()
            footer
        }
        .frame(minWidth: 1180, minHeight: 760)
        .task { loadCatalog() }
        .onChange(of: family) { _ in normalizeSelection() }
        .onChange(of: lifecycle) { _ in normalizeSelection() }
        .onChange(of: search) { value in
            normalizeSelection()
            if !value.isEmpty { expandSchemaSearchMatches() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Schema Browser").font(.largeTitle.bold())
                    Text("Browse Apple Device Management profiles and declarative schemas with nested keys, lifecycle metadata, and source definitions.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let summary {
                    HStack(spacing: 14) {
                        statistic("Objects", summary.objectCount)
                        statistic("Keys", summary.keyCount)
                        statistic("Wildcards", summary.wildcardCount)
                    }
                }
            }
            HStack {
                TextField("Search titles, identifiers, raw keys, descriptions, or paths", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("Family", selection: $family) {
                    ForEach(AppleSchemaFamily.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 240)
                Picker("Lifecycle", selection: $lifecycle) {
                    ForEach(AppleSchemaLifecycleFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 160)
                Button("Expand All") { expandAllSchema() }
                Button("Collapse All") { expandedSchemaPaths.removeAll() }
                Button("Expand Configured") { expandVisibleSchema() }
            }
        }
        .padding(18)
    }

    private var browser: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Schema Objects").font(.headline)
                    Spacer()
                    Text("\(objects.count)").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
                Divider()
                List(objects, selection: $selectedObjectID) { object in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(object.title).lineLimit(1)
                            Spacer()
                            LifecycleBadge(value: object.lifecycle)
                        }
                        Text(object.identifier).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        Text(familyTitle(object.family)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(object.id)
                    .padding(.vertical, 3)
                }
            }
            .frame(minWidth: 300, idealWidth: 340)

            if let object = selectedObject {
                objectBrowser(object)
            } else {
                placeholder("Select a Schema Object", icon: "list.bullet.rectangle", detail: "Choose a profile, declaration, asset, activation, status, or command from the list.")
                    .frame(minWidth: 720)
            }
        }
    }

    private func objectBrowser(_ object: AppleSchemaObject) -> some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(object.title).font(.title.bold())
                            LifecycleBadge(value: object.lifecycle)
                        }
                        Text(object.identifier).font(.body.monospaced()).textSelection(.enabled)
                        Text(object.description ?? "Apple does not provide a description for this schema object.")
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Divider()
                    if object.keys.isEmpty {
                        placeholder("No Schema Keys", icon: "curlybraces", detail: "This Apple schema object does not expose payloadkeys.")
                    } else {
                        ForEach(object.keys) { key in
                            SchemaKeyDisclosure(key: key, selectedPath: $selectedKeyPath, expandedPaths: $expandedSchemaPaths, search: search)
                        }
                    }
                }
                .padding(18)
            }
            .frame(minWidth: 500, idealWidth: 620)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selectedKey {
                        keyDetails(selectedKey, object: object)
                    } else {
                        objectDetails(object)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 420, idealWidth: 500)
        }
    }

    private func objectDetails(_ object: AppleSchemaObject) -> some View {
        Group {
            Text("Object Details").font(.title2.bold())
            detail("Identifier", object.identifier)
            detail("Family", familyTitle(object.family))
            detail("Lifecycle", object.lifecycle.rawValue)
            detail("Source YAML", object.source)
            supportedOSDetails(object.supportedOS)
            Button("Copy Identifier") { copy(object.identifier) }
        }
    }

    private func keyDetails(_ key: AppleSchemaKey, object: AppleSchemaObject) -> some View {
        Group {
            HStack { Text(key.displayName).font(.title2.bold()); LifecycleBadge(value: key.lifecycle) }
            if key.wildcard { Label("Wildcard dictionary key", systemImage: "asterisk").foregroundStyle(.blue) }
            if key.recursiveReference == true { Label("Recursive schema reference", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange) }
            Text(key.description ?? "Apple does not provide a description for this property.")
                .foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            detail("Raw Key", key.key)
            detail("Full Path", key.pathString)
            detail("Object", object.identifier)
            detail("Type", key.type?.description ?? "Not specified")
            detail("Presence", key.presence?.description ?? "Not specified")
            if let value = key.defaultValue { detail("Default", value.description) }
            if let value = key.values { detail("Allowed Values", value.description) }
            if let value = key.range { detail("Range", value.description) }
            if let value = key.format { detail("Format", value.description) }
            if let value = key.repetition { detail("Repetition", value.description) }
            if let value = key.combinetype { detail("Combine Type", value.description) }
            supportedOSDetails(key.supportedOS ?? [:])
            HStack {
                Button("Copy Raw Key") { copy(key.key) }
                Button("Copy Full Path") { copy(key.pathString) }
                if let description = key.description { Button("Copy Description") { copy(description) } }
            }
        }
    }

    @ViewBuilder
    private func supportedOSDetails(_ support: [String: JSONDocumentValue]) -> some View {
        if !support.isEmpty {
            Divider()
            Text("Platform Support").font(.headline)
            ForEach(support.keys.sorted(), id: \.self) { platform in
                DisclosureGroup(platform) {
                    Text(support[platform]?.description ?? "")
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            if let summary {
                Text("Apple Device Management catalog loaded: \(summary.objectCount) objects, \(summary.keyCount) keys, \(summary.deprecatedObjectCount) deprecated objects, \(summary.removedObjectCount) removed objects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(14).background(.bar)
    }

    private func statistic(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 1) { Text(value.formatted()).font(.headline); Text(title).font(.caption2).foregroundStyle(.secondary) }
    }

    private func placeholder(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func loadCatalog() {
        do {
            let result = try AppleSchemaService.load()
            catalog = result.0
            summary = result.1
            selectedObjectID = result.0.objects.first?.id
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func expandAllSchema() {
        expandedSchemaPaths = Set(catalog?.objects.flatMap { schemaContainerPaths($0.keys) } ?? [])
    }

    private func expandVisibleSchema() {
        guard let object = selectedObject else { return }
        expandedSchemaPaths = Set(schemaContainerPaths(object.keys, depth: 0, maximumDepth: 3))
    }

    private func expandSchemaSearchMatches() {
        guard let object = selectedObject else { return }
        addSchemaSearchParents(object.keys, parents: [])
    }

    private func schemaContainerPaths(_ keys: [AppleSchemaKey], depth: Int = 0, maximumDepth: Int = .max) -> [String] {
        keys.flatMap { key in
            key.children.isEmpty ? [] : (depth < maximumDepth ? [key.pathString] : []) + schemaContainerPaths(key.children, depth: depth + 1, maximumDepth: maximumDepth)
        }
    }

    private func addSchemaSearchParents(_ keys: [AppleSchemaKey], parents: [String]) {
        for key in keys {
            if key.matches(search) { expandedSchemaPaths.formUnion(parents) }
            addSchemaSearchParents(key.children, parents: parents + (key.children.isEmpty ? [] : [key.pathString]))
        }
    }

    private func lifecycleMatches(_ value: AppleSchemaLifecycle) -> Bool {
        switch lifecycle {
        case .all: return true
        case .current: return value == .current
        case .deprecated: return value == .deprecated
        case .removed: return value == .removed
        }
    }

    private func normalizeSelection() {
        if let selectedObjectID, objects.contains(where: { $0.id == selectedObjectID }) { return }
        selectedObjectID = objects.first?.id
        selectedKeyPath = nil
    }

    private func find(path: String, in keys: [AppleSchemaKey]) -> AppleSchemaKey? {
        for key in keys {
            if key.pathString == path { return key }
            if let found = find(path: path, in: key.children) { return found }
        }
        return nil
    }

    private func familyTitle(_ value: String) -> String {
        switch value {
        case "mdm-profile": return "Configuration Profile"
        case "mdm-command": return "MDM Command"
        case "mdm-checkin": return "MDM Check-in"
        case "mdm-error": return "MDM Error"
        case "declarative-configuration": return "Declarative Configuration"
        case "declarative-asset": return "Declarative Asset"
        case "declarative-activation": return "Declarative Activation"
        case "declarative-management": return "Declarative Management"
        case "declarative-status": return "Declarative Status"
        case "declarative-protocol": return "Declarative Protocol"
        default: return value
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct SchemaKeyDisclosure: View {
    let key: AppleSchemaKey
    @Binding var selectedPath: String?
    @Binding var expandedPaths: Set<String>
    let search: String
    private var expanded: Binding<Bool> { Binding(get: { expandedPaths.contains(key.pathString) }, set: { if $0 { expandedPaths.insert(key.pathString) } else { expandedPaths.remove(key.pathString) } }) }

    var body: some View {
        if key.children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(key.children) { child in
                        SchemaKeyDisclosure(key: child, selectedPath: $selectedPath, expandedPaths: $expandedPaths, search: search)
                    }
                }
                .padding(.leading, 18).padding(.top, 7)
            } label: { row }
            .onAppear { if !search.isEmpty && key.matches(search) { expandedPaths.insert(key.pathString) } }
            .onChange(of: search) { value in if !value.isEmpty && key.matches(value) { expandedPaths.insert(key.pathString) } }
        }
    }

    private var row: some View {
        Button {
            selectedPath = key.pathString
        } label: {
            HStack(spacing: 8) {
                Image(systemName: key.wildcard ? "asterisk" : "key.fill").foregroundStyle(key.wildcard ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName).foregroundStyle(.primary)
                    if key.title != nil { Text(key.key).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                Spacer()
                LifecycleBadge(value: key.lifecycle)
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selectedPath == key.pathString ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct LifecycleBadge: View {
    let value: AppleSchemaLifecycle
    var body: some View {
        if value != .current {
            Text(value.rawValue.uppercased())
                .font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(value == .removed ? .red : .orange)
                .background((value == .removed ? Color.red : Color.orange).opacity(0.12), in: Capsule())
        }
    }
}
