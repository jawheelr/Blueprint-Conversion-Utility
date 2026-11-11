import SwiftUI
import AppKit

struct ProfileInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPayloadID: String?
    @State private var selectedNodeID: String?
    @State private var search = ""
    @State private var filter: InspectorFindingFilter = .all
    @State private var expandedNodeIDs: Set<String> = []
    @State private var editTarget: EditTarget?

    private var document: ProfileInspectorDocument? { model.profileInspection }
    private var payloads: [ProfileInspectorPayload] {
        guard let document else { return [] }
        return document.payloads.filter { payload in
            let query = search.isEmpty || payload.displayName.localizedCaseInsensitiveContains(search) || payload.payloadType.localizedCaseInsensitiveContains(search) || matches(payload.nodes, search)
            let evaluation = SettingEvaluationService.evaluate(payload)
            let finding: Bool
            switch filter {
            case .all: finding = true
            case .unknown: finding = contains(payload.nodes, kind: .unknown)
            case .wildcard: finding = contains(payload.nodes, kind: .wildcard)
            case .deprecated: finding = contains(payload.nodes, lifecycle: .deprecated)
            case .removed: finding = contains(payload.nodes, lifecycle: .removed)
            case .actionNeeded: finding = evaluation.recommendation.priority >= SettingRecommendation.review.priority
            }
            return query && finding
        }
    }
    private var selectedPayload: ProfileInspectorPayload? { document?.payloads.first { $0.id == selectedPayloadID } }
    private var selectedNode: ProfileInspectorNode? { guard let payload = selectedPayload, let id = selectedNodeID else { return nil }; return find(id, payload.nodes) }

    var body: some View {
        VStack(spacing: 0) {
            header; Divider(); content; Divider(); footer
        }
        .frame(minWidth: 1260, minHeight: 780)
        .onAppear { initialize() }
        .onChange(of: model.profileInspection?.id) { _ in initialize() }
        .onChange(of: search) { value in if !value.isEmpty { expandSearchMatches() }; normalizeSelection() }
        .onChange(of: filter) { _ in normalizeSelection() }
        .sheet(item: $editTarget) { target in
            ProfileSettingEditView(profileID: target.profileID, payload: target.payload, node: target.node, evaluation: target.evaluation, existing: model.profileSettingOverrides[target.node.id])
                .environmentObject(model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profile Inspector").font(.largeTitle.bold()).help(ProfileInspectorHelp.inspector)
                    Text(document.map { "\($0.profileName) · Profile ID \($0.profileID)" } ?? "Select a Configuration Profile to inspect its settings.").foregroundStyle(.secondary)
                }
                Spacer()
                if let document { HStack(spacing: 16) { statistic("Payloads", document.payloadCount); statistic("Settings", document.settingCount); statistic("Wildcard", document.wildcardMatchCount); statistic("Unknown", document.unknownSettingCount) } }
            }
            HStack {
                TextField("Search payloads, friendly names, raw keys, paths, descriptions, or values", text: $search).textFieldStyle(.roundedBorder)
                Picker("Findings", selection: $filter) { ForEach(InspectorFindingFilter.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 190).help(ProfileInspectorHelp.actionNeeded)
                Button("Expand All") { expandAll() }
                Button("Collapse All") { expandedNodeIDs.removeAll() }
                Button("Expand Configured") { expandConfigured() }
            }
        }.padding(18)
    }

    @ViewBuilder private var content: some View {
        if model.profileInspectionLoading { ProgressView("Parsing the selected Configuration Profile...").frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if let error = model.profileInspectionError { placeholder("Unable to Parse Profile", "exclamationmark.triangle.fill", error) }
        else if document == nil { placeholder("No Profile Selected", "doc.badge.gearshape", "Select a Configuration Profile. BCU will parse and evaluate its configured settings.") }
        else {
            HSplitView {
                payloadList.frame(minWidth: 280, idealWidth: 330)
                if let payload = selectedPayload { tree(payload).frame(minWidth: 500, idealWidth: 610) }
                else { placeholder("Select a Payload", "shippingbox", "Choose a payload to inspect its settings.") }
                details.frame(minWidth: 390, idealWidth: 470)
            }
        }
    }

    private var payloadList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Profile Contents").font(.headline); Spacer(); Text("\(payloads.count)").font(.caption).foregroundStyle(.secondary) }.padding(12); Divider()
            List(payloads, selection: $selectedPayloadID) { payload in
                let evaluation = SettingEvaluationService.evaluate(payload)
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Image(systemName: payload.matchKind == .unknown ? "questionmark.diamond" : "shippingbox.fill").foregroundStyle(payload.matchKind == .unknown ? .orange : .blue); Text(payload.displayName).lineLimit(1); Spacer(); RecommendationBadge(value: evaluation.recommendation) }
                    Text(payload.payloadType).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Text(evaluation.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }.tag(payload.id).padding(.vertical, 4)
            }
        }
    }

    private func tree(_ payload: ProfileInspectorPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let evaluation = SettingEvaluationService.evaluate(payload)
                HStack { VStack(alignment: .leading) { Text(payload.displayName).font(.title2.bold()); Text(payload.payloadType).font(.caption.monospaced()).foregroundStyle(.secondary) }; Spacer(); RecommendationBadge(value: evaluation.recommendation) }
                if let finding = evaluation.primaryFinding { Label(finding, systemImage: "lightbulb.fill").font(.caption).foregroundStyle(.secondary) }
                Divider()
                ForEach(payload.nodes) { node in InspectorNodeDisclosure(node: node, payload: payload, selectedNodeID: $selectedNodeID, expandedNodeIDs: $expandedNodeIDs, search: search) }
            }.padding(18)
        }
    }

    @ViewBuilder private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if let node = selectedNode, let payload = selectedPayload { nodeDetails(node, payload) }
                else if let payload = selectedPayload { payloadDetails(payload) }
                else { Text("Evaluation").font(.title2.bold()); Text("Select a payload or setting.").foregroundStyle(.secondary) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func payloadDetails(_ payload: ProfileInspectorPayload) -> some View {
        let evaluation = SettingEvaluationService.evaluate(payload)
        return Group {
            HStack { Text("Payload Evaluation").font(.title2.bold()); Spacer(); RecommendationBadge(value: evaluation.recommendation); InspectorHelpButton(title: evaluation.recommendation.rawValue, text: ProfileInspectorHelp.recommendation(evaluation.recommendation)) }
            detail("Recommended approach", evaluation.recommendation.rawValue)
            detail("Summary", evaluation.summary)
            if let finding = evaluation.primaryFinding { detail("Primary finding", finding) }
            Divider(); detail("Display Name", payload.displayName); detail("Payload Type", payload.payloadType); detail("Schema Match", payload.matchKind.rawValue); detail("Lifecycle", payload.lifecycle.rawValue)
            if let source = payload.schemaSource { detail("Apple Schema Source", source); Button("Open Schema Definition") { model.showAppleSchema = true }.help(ProfileInspectorHelp.openSchema) }
        }
    }

    private func nodeDetails(_ node: ProfileInspectorNode, _ payload: ProfileInspectorPayload) -> some View {
        let evaluation = SettingEvaluationService.evaluate(node, payload: payload)
        return Group {
            HStack { Text(node.displayName).font(.title2.bold()); Spacer(); RecommendationBadge(value: evaluation.recommendation); InspectorHelpButton(title: evaluation.recommendation.rawValue, text: ProfileInspectorHelp.recommendation(evaluation.recommendation)) }
            Text(node.schema.description ?? "Apple does not provide a description for this property.").foregroundStyle(.secondary).textSelection(.enabled)
            GroupBox("Evaluation") {
                VStack(alignment: .leading, spacing: 10) {
                    detail("Recommended action", evaluation.recommendation.rawValue).help(ProfileInspectorHelp.recommendation)
                    detail("When to edit", evaluation.timing.rawValue).help(ProfileInspectorHelp.timing)
                    detail("Why", evaluation.reason)
                    detail("Migration behavior", evaluation.migrationBehavior)
                    detail("Confidence", evaluation.confidence.rawValue).help(ProfileInspectorHelp.confidence)
                    if let proposed = evaluation.proposedValue { detail("Proposed destination value or action", proposed) }
                    detail("Evidence", evaluation.evidence.joined(separator: "\n")).help(ProfileInspectorHelp.evidence)
                    if let override = model.profileSettingOverrides[node.id] {
                        detail("Administrator decision", override.decision.rawValue)
                        if override.decision == .apply { detail("Destination override", override.proposedValue) }
                    }
                    if evaluation.recommendation.priority >= SettingRecommendation.review.priority || model.profileSettingOverrides[node.id] != nil {
                        Button(model.profileSettingOverrides[node.id] == nil ? "Resolve Before Continuing" : "Edit Decision") {
                            editTarget = EditTarget(profileID: document?.profileID ?? "", payload: payload, node: node, evaluation: evaluation)
                        }.buttonStyle(.borderedProminent).help("Open the destination decision editor. This records administrator intent for the generated destination and never modifies the Jamf source profile.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider(); detail("Source value", node.value.description); detail("Value type", node.value.typeName); detail("Raw key", node.rawKey); detail("Source path", node.pathString); detail("Schema match", node.schema.kind.rawValue).help(ProfileInspectorHelp.schemaMatch)
            if let path = node.schema.schemaPath { detail("Apple Schema Path", path) }
            if let source = node.schema.source { detail("Apple Schema Source", source); Button("Open Schema Definition") { model.showAppleSchema = true }.help(ProfileInspectorHelp.openSchema) }
            HStack { Button("Copy Key") { copy(node.rawKey) }; Button("Copy Path") { copy(node.pathString) }; Button("Copy Value") { copy(node.value.description) } }
        }
    }

    private var footer: some View { HStack { if let d = document, !d.diagnostics.isEmpty { Label("\(d.diagnostics.count) parser finding(s)", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            if model.unresolvedInspectorRecommendations > 0 { Label("\(model.unresolvedInspectorRecommendations) recommendation(s) need a decision", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            Spacer(); Text("Source profile is read-only").font(.caption).foregroundStyle(.secondary); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(14).background(.bar) }

    private func initialize() { normalizeSelection(); expandConfigured() }
    private func normalizeSelection() { if selectedPayloadID == nil || !payloads.contains(where: { $0.id == selectedPayloadID }) { selectedPayloadID = payloads.first?.id; selectedNodeID = nil }; if expandedNodeIDs.isEmpty { expandConfigured() } }
    private func expandAll() { expandedNodeIDs = Set(document?.payloads.flatMap { containerIDs($0.nodes) } ?? []) }
    private func expandConfigured() { guard let d = document else { return }; expandedNodeIDs = Set(d.payloads.flatMap { configuredContainerIDs($0.nodes, depth: 0) }) }
    private func expandSearchMatches() { guard let d = document else { return }; for payload in d.payloads { addSearchParents(payload.nodes, parents: []) } }
    private func containerIDs(_ nodes: [ProfileInspectorNode]) -> [String] { nodes.flatMap { $0.children.isEmpty ? [] : [$0.id] + containerIDs($0.children) } }
    private func configuredContainerIDs(_ nodes: [ProfileInspectorNode], depth: Int) -> [String] { nodes.flatMap { node in node.children.isEmpty ? [] : (depth < 3 ? [node.id] : []) + configuredContainerIDs(node.children, depth: depth + 1) } }
    private func addSearchParents(_ nodes: [ProfileInspectorNode], parents: [String]) { for node in nodes { if nodeMatches(node, search) { expandedNodeIDs.formUnion(parents) }; addSearchParents(node.children, parents: parents + (node.children.isEmpty ? [] : [node.id])) } }
    private func nodeMatches(_ node: ProfileInspectorNode, _ q: String) -> Bool { [node.displayName, node.rawKey, node.pathString, node.value.description, node.schema.description ?? ""].contains { $0.localizedCaseInsensitiveContains(q) } }
    private func matches(_ nodes: [ProfileInspectorNode], _ q: String) -> Bool { q.isEmpty || nodes.contains { nodeMatches($0, q) || matches($0.children, q) } }
    private func contains(_ nodes: [ProfileInspectorNode], kind: ProfileSchemaMatchKind) -> Bool { nodes.contains { $0.schema.kind == kind || contains($0.children, kind: kind) } }
    private func contains(_ nodes: [ProfileInspectorNode], lifecycle: AppleSchemaLifecycle) -> Bool { nodes.contains { $0.schema.lifecycle == lifecycle || contains($0.children, lifecycle: lifecycle) } }
    private func find(_ id: String, _ nodes: [ProfileInspectorNode]) -> ProfileInspectorNode? { for n in nodes { if n.id == id { return n }; if let value = find(id, n.children) { return value } }; return nil }
    private func detail(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) } }
    private func statistic(_ title: String, _ value: Int) -> some View { VStack(alignment: .trailing) { Text(value.formatted()).font(.headline); Text(title).font(.caption2).foregroundStyle(.secondary) } }
    private func placeholder(_ title: String, _ icon: String, _ detail: String) -> some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary); Text(title).font(.title2.bold()); Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32) }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}

private struct EditTarget: Identifiable {
    let profileID: String
    let payload: ProfileInspectorPayload
    let node: ProfileInspectorNode
    let evaluation: SettingEvaluation
    var id: String { node.id }
}

private enum InspectorFindingFilter: String, CaseIterable, Identifiable { case all = "All Settings", actionNeeded = "Action Needed", unknown = "Unknown", wildcard = "Wildcard Matches", deprecated = "Deprecated", removed = "Removed"; var id: String { rawValue } }

private struct InspectorNodeDisclosure: View {
    let node: ProfileInspectorNode
    let payload: ProfileInspectorPayload
    @Binding var selectedNodeID: String?
    @Binding var expandedNodeIDs: Set<String>
    let search: String
    private var expanded: Binding<Bool> { Binding(get: { expandedNodeIDs.contains(node.id) }, set: { if $0 { expandedNodeIDs.insert(node.id) } else { expandedNodeIDs.remove(node.id) } }) }
    var body: some View {
        if node.children.isEmpty { row }
        else { DisclosureGroup(isExpanded: expanded) { VStack(alignment: .leading, spacing: 7) { ForEach(node.children) { child in InspectorNodeDisclosure(node: child, payload: payload, selectedNodeID: $selectedNodeID, expandedNodeIDs: $expandedNodeIDs, search: search) } }.padding(.leading, 18).padding(.top, 6) } label: { row } }
    }
    private var row: some View {
        let evaluation = SettingEvaluationService.evaluate(node, payload: payload)
        return Button { selectedNodeID = node.id } label: { HStack(spacing: 8) { Image(systemName: node.schema.kind == .unknown ? "questionmark.diamond" : node.children.isEmpty ? "key.fill" : "folder.fill").foregroundStyle(node.schema.kind == .unknown ? .orange : .secondary); VStack(alignment: .leading, spacing: 2) { Text(node.displayName).foregroundStyle(.primary); HStack { Text(node.rawKey).font(.caption.monospaced()); Text(node.value.description).lineLimit(1) }.foregroundStyle(.secondary) }; Spacer(); RecommendationBadge(value: evaluation.recommendation) }.padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selectedNodeID == node.id ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 7)) }
        .buttonStyle(.plain)
        .help(ProfileInspectorHelp.recommendation(evaluation.recommendation))
    }
}

private struct RecommendationBadge: View {
    let value: SettingRecommendation
    var body: some View { Text(value.rawValue.uppercased()).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3).foregroundStyle(color).background(color.opacity(0.12), in: Capsule()).help(ProfileInspectorHelp.recommendation(value)) }
    private var color: Color { switch value { case .keep: return .green; case .convert: return .blue; case .edit, .review: return .orange; case .replace: return .purple; case .remove: return .red; case .legacy, .metadata: return .secondary } }
}
