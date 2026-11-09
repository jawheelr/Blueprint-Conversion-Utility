import SwiftUI

struct ProfileSettingEditView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let profileID: String
    let payload: ProfileInspectorPayload
    let node: ProfileInspectorNode
    let evaluation: SettingEvaluation
    @State private var proposedValue: String
    @State private var decision: OverrideDecision

    init(profileID: String, payload: ProfileInspectorPayload, node: ProfileInspectorNode, evaluation: SettingEvaluation, existing: ProfileSettingOverride?) {
        self.profileID = profileID
        self.payload = payload
        self.node = node
        self.evaluation = evaluation
        _proposedValue = State(initialValue: existing?.proposedValue ?? evaluation.proposedValue ?? node.value.description)
        _decision = State(initialValue: existing?.decision ?? .apply)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Resolve Recommendation").font(.largeTitle.bold()).help("Resolve how this source setting should be represented in the generated Blueprint. The source Configuration Profile remains unchanged.")
            Text(node.displayName).font(.title2.bold())
            Text(evaluation.reason).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox("Source") {
                VStack(alignment: .leading, spacing: 8) {
                    labelled("Raw key", node.rawKey)
                    labelled("Current value", node.value.description)
                    labelled("Source path", node.pathString)
                }.frame(maxWidth: .infinity, alignment: .leading).help(decisionHelp)
            }
            GroupBox("Recommended destination decision") {
                VStack(alignment: .leading, spacing: 10) {
                    labelled("Action", evaluation.recommendation.rawValue)
                    labelled("Timing", evaluation.timing.rawValue)
                    Text("Decision").font(.headline)
                    ForEach(OverrideDecision.allCases) { option in
                        HStack(spacing: 10) {
                            Button {
                                decision = option
                            } label: {
                                HStack {
                                    Image(systemName: decision == option ? "largecircle.fill.circle" : "circle")
                                    Text(option.rawValue)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(ProfileInspectorHelp.decision(option))
                            InspectorHelpButton(title: option.rawValue, text: ProfileInspectorHelp.decision(option))
                        }
                        .padding(.vertical, 3)
                    }
                    if decision == .apply {
                        TextField("Proposed destination value or instruction", text: $proposedValue, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(2...6).help(ProfileInspectorHelp.proposedValue)
                    }
                    Text("BCU records a destination override. The Jamf source Configuration Profile is not modified.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            HStack {
                if model.profileSettingOverrides[node.id] != nil {
                    Button("Remove Decision", role: .destructive) { model.removeProfileSettingOverride(nodeID: node.id); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Decision") {
                    model.saveProfileSettingOverride(ProfileSettingOverride(
                        id: node.id, profileID: profileID, payloadID: payload.id, nodeID: node.id,
                        displayName: node.displayName, rawKey: node.rawKey,
                        sourceValue: node.value.description, proposedValue: proposedValue,
                        recommendation: evaluation.recommendation, reason: evaluation.reason, decision: decision
                    ))
                    dismiss()
                }.buttonStyle(.borderedProminent).help("Save this administrator decision for the current profile. The decision is cleared when another source profile is selected.")
            }
        }.padding(24).frame(minWidth: 620, minHeight: 540)
    }

    private var decisionHelp: String {
        switch decision {
        case .apply: return ProfileInspectorHelp.applyDestination
        case .keepSource: return ProfileInspectorHelp.keepSource
        case .reviewLater: return ProfileInspectorHelp.reviewLater
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
}
