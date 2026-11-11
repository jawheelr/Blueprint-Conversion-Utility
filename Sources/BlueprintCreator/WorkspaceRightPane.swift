import SwiftUI

struct WorkspaceRightPane: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if model.workflowMode == .takeover && model.takeoverCapabilities.commandAvailable {
            takeoverPane
        } else {
            standardPane
        }
    }

    private var takeoverPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Blueprint Takeover").font(.headline)
                Spacer()
                compactStatus
            }

            GroupBox("Recommendation") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.takeoverRecommendationTitle).font(.headline)
                    Text(model.takeoverRecommendationDetail).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            if let profile = model.selectedProfile {
                GroupBox("Ready Profile") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.name).lineLimit(2)
                        Text("ID \(profile.id) • \(model.mobile ? "Mobile" : "Computer")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.importScopeMode == .preserveSource
                             ? "Scope: \(profile.scope.summary)"
                             : "Scope: \(model.selectedGroup?.name ?? "Choose a group")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }

            if !model.takeoverMessages.isEmpty {
                DisclosureGroup("Evaluation details (\(model.takeoverMessages.count))", isExpanded: $model.showTakeoverDetails) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(model.takeoverMessages.enumerated()), id: \.offset) { _, message in
                                Text("• \(message)").font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .padding(.top, 8)
                }
            }

            HStack {
                Button("Re-evaluate") { model.scheduleAutomaticTakeoverEvaluation() }
                    .disabled(!model.dryRunEnabled || model.selectedProfile == nil || model.busy)
                    .help("Runs another non-modifying evaluation. Enable Dry Run first.")
                Spacer()
                Label("Classic profile remains scoped", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(primaryTitle) {
                Task { await model.runTakeoverImport(dryRun: false) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCreate)
            .help(primaryHelp)
        }
        .padding(18)
        .frame(minWidth: 300, idealWidth: 370, maxWidth: 560)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private var compactStatus: some View {
        switch model.takeoverEvaluationState {
        case .notEvaluated:
            Label(model.dryRunEnabled ? "Not evaluated" : "Dry Run off", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .waiting:
            Label("Waiting", systemImage: "clock").foregroundStyle(.secondary)
        case .evaluating:
            HStack { ProgressView().controlSize(.small); Text("Evaluating") }
        case .supported:
            Label("Supported", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unsupported:
            Label("Review", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed:
            Label("Failed", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var canCreate: Bool {
        guard model.selectedProfile != nil, !model.busy else { return false }
        if model.importScopeMode == .overrideSelected && model.selectedGroup == nil { return false }
        guard !model.dryRunEnabled else { return false }
        if model.importMode == .convert { return true }
        return model.takeoverEvaluationState == .supported || model.takeoverEvaluationState == .unsupported || model.takeoverEvaluationState == .notEvaluated
    }

    private var primaryTitle: String {
        if model.dryRunEnabled { return "Turn Off Dry Run to Create" }
        if model.importMode == .convert { return "Create Converted Blueprint" }
        if model.takeoverEvaluationState == .supported { return "Create Takeover Blueprint" }
        return "Import Profile Blueprint"
    }

    private var primaryHelp: String {
        if model.dryRunEnabled { return "Dry Run prevents creation. Turn off the switch in the editor header when ready." }
        return "Runs the explicit, modifying import-profile operation. The Classic source profile remains scoped."
    }

    private var standardPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deployment").font(.headline)
            Picker("Device group", selection: $model.selectedGroup) {
                Text("Select a group").tag(DeviceGroup?.none)
                ForEach(model.groups) { Text($0.name).tag(Optional($0)) }
            }
            .onChange(of: model.selectedGroup) { _ in model.generate() }
            GroupBox("Conversion Plan") {
                Text(model.conversionPlanSummary).font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Button("Create Blueprint") { model.requestCreate() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.ready || model.selectedProfile == nil || model.busy)
        }
        .padding(18)
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 560)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
