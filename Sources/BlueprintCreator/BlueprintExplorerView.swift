import SwiftUI

struct BlueprintExplorerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection: ExplorerSelection = .details
    @State private var pendingOpenID: String?
    @State private var confirmClose = false

    private var filtered: [ExplorerBlueprintSummary] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.explorerBlueprints }
        return model.explorerBlueprints.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = model.explorerMessage {
                Label(message, systemImage: "info.circle.fill").font(.callout).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.12)).textSelection(.enabled)
            }
            HStack(spacing: 0) {
                list.frame(width: 270)
                Divider()
                if model.explorerDraft != nil {
                    outline.frame(width: 250)
                    Divider()
                    editor.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(model.explorerWorking ? "Opening…" : "Select a blueprint to inspect and edit it.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 1180, minHeight: 720)
        .task { model.loadExplorerSchemaIfNeeded(); if model.explorerBlueprints.isEmpty { await model.loadExplorerList() } }
        .confirmationDialog(model.explorerPendingAction?.title ?? "", isPresented: Binding(
            get: { model.explorerPendingAction != nil }, set: { if !$0 { model.explorerPendingAction = nil } }), titleVisibility: .visible) {
            Button(model.explorerPendingAction?.title ?? "Continue", role: model.explorerPendingAction == .undeploy ? .destructive : nil) {
                Task { await model.confirmExplorerAction() }
            }
            Button("Cancel", role: .cancel) { model.explorerPendingAction = nil }
        } message: {
            Text(confirmMessage)
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: Binding(get: { pendingOpenID != nil }, set: { if !$0 { pendingOpenID = nil } }), titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                if let id = pendingOpenID { Task { await open(id, force: true) } }
                pendingOpenID = nil
            }
            Button("Keep Editing", role: .cancel) { pendingOpenID = nil }
        }
        .confirmationDialog("Close with unsaved changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard and Close", role: .destructive) { model.discardExplorerChanges(); dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private var confirmMessage: String {
        guard let action = model.explorerPendingAction else { return "" }
        var text = action.detail
        if action == .save || action == .saveAndDeploy {
            let changes = model.explorerChanges
            text += "\n\nChanged: " + changes.prefix(8).joined(separator: ", ") + (changes.count > 8 ? " and \(changes.count - 8) more" : "")
            if model.explorerSelectedState == "DEPLOYED" && action == .save { text += "\n\nIt is currently deployed and will need redeploying." }
        }
        return text
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Blueprints Explorer").font(.largeTitle.bold())
                Text("Inspect and edit existing blueprints on \(model.activeConnectionName). Changes are saved to Jamf only when you choose Save.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await model.loadExplorerList() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(model.explorerLoading || model.explorerWorking)
            Button("Close") { if model.explorerDirty { confirmClose = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
        }.padding(18)
    }

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Search blueprints", text: $search).textFieldStyle(.roundedBorder).padding(10)
            if model.explorerLoading { ProgressView().padding() }
            List(filtered) { item in
                Button { Task { await open(item.id) } } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.name).font(.headline).lineLimit(1)
                            Spacer()
                            stateBadge(item.id == model.explorerSelectedID ? model.explorerSelectedState : item.state)
                        }
                        if !item.description.isEmpty { Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(item.id == model.explorerSelectedID ? Color.accentColor.opacity(0.18) : Color.clear)
            }
            if !model.explorerLoading && model.explorerBlueprints.isEmpty {
                Text("No blueprints found.").foregroundStyle(.secondary).padding()
            }
            Text("\(model.explorerBlueprints.count) blueprint(s)").font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }

    private func stateBadge(_ state: String) -> some View {
        let (title, color): (String, Color) = {
            switch state.uppercased() {
            case "DEPLOYED": return ("Deployed", .green)
            case "NOT_DEPLOYED": return ("Not deployed", .secondary)
            case "OUT_OF_DATE": return ("Out of date", .orange)
            default: return ("Unknown", .secondary)
            }
        }()
        return Text(title).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18))).foregroundStyle(color)
    }

    private func open(_ id: String, force: Bool = false) async {
        if id == model.explorerSelectedID && !force { return }
        if !force && model.explorerDirty { pendingOpenID = id; return }
        selection = .details
        await model.openExplorerBlueprint(id)
    }

    private var steps: [[String: Any]] { model.explorerDraft?["steps"] as? [[String: Any]] ?? [] }

    private var outline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                outlineRow("Details", "doc.text", .details)
                outlineRow("Scope", "person.3", .scope)
                ForEach(steps.indices, id: \.self) { s in
                    outlineRow((steps[s]["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Step \(s + 1)", "list.number", .step(s))
                    let components = steps[s]["components"] as? [[String: Any]] ?? []
                    ForEach(components.indices, id: \.self) { c in
                        outlineRow(Self.friendly(components[c]["identifier"] as? String), "puzzlepiece.extension", .component(s, c)).padding(.leading, 18)
                    }
                }
            }.padding(10)
        }
    }

    static func friendly(_ identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "Component" }
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func outlineRow(_ title: String, _ icon: String, _ target: ExplorerSelection) -> some View {
        Button { selection = target } label: {
            Label(title, systemImage: icon).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(selection == target ? Color.accentColor.opacity(0.2) : Color.clear))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selection {
                case .details: detailsEditor
                case .scope: ScopeEditor()
                case .step(let s): StepEditor(step: s)
                case .component(let s, let c): ComponentSettingsEditor(step: s, component: c)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(.title3.bold())
            TextField("Name", text: stringBinding(["name"])).textFieldStyle(.roundedBorder)
            TextField("Description", text: stringBinding(["description"]), axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
            LabeledContent("Blueprint ID", value: model.explorerSelectedID ?? "")
            LabeledContent("Updated", value: (model.explorerDraft?["updated"] as? String) ?? "")
            LabeledContent("State") { stateBadge(model.explorerSelectedState) }
        }
    }

    private func stringBinding(_ keys: [String]) -> Binding<String> {
        let path = keys.map { JSONPathStep.key($0) }
        return Binding(get: { (model.explorerValue(at: path) as? String) ?? "" }, set: { model.explorerSet($0, at: path) })
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.explorerWorking { ProgressView().controlSize(.small) }
            Text(model.explorerDirty ? "\(model.explorerChanges.count) unsaved change(s)" : "No unsaved changes").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Revert") { model.discardExplorerChanges() }.disabled(!model.explorerDirty || model.explorerWorking)
            Button("Undeploy") { model.requestExplorerAction(.undeploy) }
                .disabled(model.explorerDraft == nil || model.explorerWorking || model.explorerSelectedState == "NOT_DEPLOYED")
            Button(model.explorerSelectedState == "DEPLOYED" ? "Redeploy" : "Deploy") { model.requestExplorerAction(.deploy) }
                .disabled(model.explorerDraft == nil || model.explorerWorking || model.explorerDirty)
            Button("Save and Deploy") { model.requestExplorerAction(.saveAndDeploy) }
                .disabled(!model.explorerDirty || model.explorerWorking)
            Button("Save Changes") { model.requestExplorerAction(.save) }
                .buttonStyle(.borderedProminent).disabled(!model.explorerDirty || model.explorerWorking)
        }.padding(14)
    }
}

private struct ScopeEditor: View {
    @EnvironmentObject private var model: AppModel
    private let path: [JSONPathStep] = [.key("scope"), .key("deviceGroups")]

    private var ids: [String] { (model.explorerValue(at: path) as? [Any])?.compactMap { $0 as? String } ?? [] }
    private func name(_ id: String) -> String { model.allGroups.first { $0.id == id }?.name ?? "Unknown group (\(id))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scope").font(.title3.bold())
            Text("The blueprint applies to devices in these groups. At least one group is required.").font(.callout).foregroundStyle(.secondary)
            ForEach(ids, id: \.self) { id in
                HStack {
                    Image(systemName: "person.3.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading) { Text(name(id)); Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    Spacer()
                    Button { model.explorerSet(ids.filter { $0 != id }, at: path) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
                .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }
            let available = model.allGroups.filter { !ids.contains($0.id) }
            Menu("Add group") {
                ForEach(available) { group in Button("\(group.name)") { model.explorerSet(ids + [group.id], at: path) } }
            }.disabled(available.isEmpty).fixedSize()
            if model.allGroups.isEmpty { Text("Device groups have not loaded yet. Refresh the workspace to choose from them.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct StepEditor: View {
    @EnvironmentObject private var model: AppModel
    let step: Int
    @State private var rows: [ActivationConditionRow] = []
    @State private var match: ActivationMatch = .all
    @State private var textMode = false
    @State private var text = ""

    private var namePath: [JSONPathStep] { [.key("steps"), .index(step), .key("name")] }
    private var predicatePath: [JSONPathStep] { [.key("steps"), .index(step), .key("activationPredicate")] }
    private var predicate: String { (model.explorerValue(at: predicatePath) as? String) ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(step + 1)").font(.title3.bold())
            TextField("Step name", text: Binding(get: { (model.explorerValue(at: namePath) as? String) ?? "" }, set: { model.explorerSet($0, at: namePath) }))
                .textFieldStyle(.roundedBorder)
            Divider()
            HStack {
                Text("Activation conditions").font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { textMode }, set: { switchMode($0) })) { Text("Visual").tag(false); Text("Text").tag(true) }
                    .pickerStyle(.segmented).frame(width: 150).labelsHidden()
            }
            if textMode {
                TextEditor(text: $text).font(.system(.caption, design: .monospaced)).frame(height: 110).border(Color.secondary.opacity(0.3))
                    .onChange(of: text) { write($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                if text.count > ActivationPredicate.maxLength { Label("Longer than \(ActivationPredicate.maxLength) characters.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption) }
            } else {
                visual
            }
            if !predicate.isEmpty { Text(predicate).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            else { Text("No activation condition: the step is always active.").font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { load() }
        .onChange(of: step) { _ in load() }
    }

    private var visual: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rows.count > 1 {
                Picker("Match", selection: Binding(get: { match }, set: { match = $0; push() })) { Text("all").tag(ActivationMatch.all); Text("any").tag(ActivationMatch.any) }
                    .pickerStyle(.segmented).frame(width: 220)
            }
            ForEach($rows) { $row in
                HStack {
                    Picker("", selection: Binding(get: { row.attribute }, set: { row.attribute = $0; row.op = $0.operators.first ?? .equals; row.value = $0.choices.first ?? ""; push() })) {
                        ForEach(ActivationAttribute.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 190)
                    Picker("", selection: Binding(get: { row.op }, set: { row.op = $0; push() })) {
                        ForEach(row.attribute.operators) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 150)
                    if row.attribute.choices.isEmpty {
                        TextField(row.attribute == .group ? "Group ID" : "Value", text: Binding(get: { row.value }, set: { row.value = $0; push() })).textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: Binding(get: { row.value }, set: { row.value = $0; push() })) { ForEach(row.attribute.choices, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                    }
                    Button { rows.removeAll { $0.id == row.id }; push() } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button("Add Condition") { rows.append(ActivationConditionRow()); push() }.buttonStyle(.borderless)
        }
    }

    private func load() {
        if let parsed = ActivationPredicate.parse(predicate) {
            rows = parsed.rows; match = parsed.match; textMode = false
        } else {
            rows = []; textMode = true
        }
        text = predicate
    }

    private func switchMode(_ toText: Bool) {
        if toText { text = predicate; textMode = true }
        else if let parsed = ActivationPredicate.parse(text) { rows = parsed.rows; match = parsed.match; textMode = false }
    }

    /// Writes the visual rows. Rows still missing a value are left out until they are filled in.
    private func push() { write(ActivationPredicate.build(rows: rows, match: match)) }

    private func write(_ value: String) {
        if value.isEmpty { model.explorerRemove(at: predicatePath) } else { model.explorerSet(value, at: predicatePath) }
    }
}
