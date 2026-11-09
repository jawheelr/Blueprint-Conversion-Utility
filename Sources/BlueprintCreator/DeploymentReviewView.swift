import SwiftUI

struct DeploymentReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if model.takeoverCapabilities.commandAvailable && model.workflowMode == .takeover {
            takeoverReview
        } else {
            standardReview
        }
    }

    private var takeoverReview: some View {
        VStack(spacing: 18) {
            Text(model.importMode == .convert ? "Import Converted Profile" : "Profile Takeover").font(.largeTitle.bold())
            Text("The Classic profile remains scoped. jamf-cli evaluates whether the installed profile can be adopted without reinstalling it.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            GroupBox("Takeover Analysis") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.takeoverVerdict.title, systemImage: verdictIcon).font(.headline).foregroundStyle(verdictColor)
                    ForEach(Array(model.takeoverMessages.enumerated()), id: \.offset) { _, item in Text(item).font(.caption).textSelection(.enabled) }
                    if model.takeoverMessages.isEmpty { Text("Preview takeover to receive a verdict before creation.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Source Profile") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Name", value: model.selectedProfile?.name ?? "None")
                    LabeledContent("Profile ID", value: model.selectedProfile?.id ?? "None")
                    LabeledContent("Type", value: model.mobile ? "Mobile" : "Computer")
                    LabeledContent("Source Profile Action", value: "Remain scoped")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            if model.takeoverVerdict == .notEvaluated || model.takeoverVerdict == .failed {
                Button("Preview Takeover") { Task { await model.runTakeoverImport(dryRun: true) } }.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button(primaryTitle) { Task { await model.runTakeoverImport(dryRun: false) } }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() } }
        }.padding(28).frame(width: 780, height: 650)
    }

    private var standardReview: some View {
        VStack(spacing: 20) {
            Text("Create Blueprint").font(.largeTitle.bold())
            Text("The adaptive plan must be ready before any Platform request is sent.").foregroundStyle(.secondary)
            GroupBox("Conversion Plan") { Text(model.conversionPlanSummary).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
            Picker("Platform device group", selection: $model.selectedGroup) {
                Text("Select a compatible Platform group").tag(DeviceGroup?.none)
                ForEach(model.groups) { group in Text(group.name).tag(Optional(group)) }
            }.onChange(of: model.selectedGroup) { _ in model.generate() }
            VStack(spacing: 12) {
                standardButton("Create Blueprint Only", "plus.circle.fill", .createOnly)
                standardButton("Create and Distribute Blueprint", "paperplane.fill", .createAndDistribute)
                standardButton("Create and Distribute Blueprint and Unscope Configuration Profile", "arrow.triangle.2.circlepath.circle.fill", .createDistributeAndUnscope)
            }.frame(width: 560)
            HStack { Spacer(); Button("Cancel") { dismiss() } }
        }.padding(28).frame(width: 780, height: 650)
    }

    private func standardButton(_ title: String, _ icon: String, _ choice: DeploymentChoice) -> some View {
        Button { if choice == .createDistributeAndUnscope { model.requestCreateDistributeAndUnscope() } else { Task { await model.performDeployment(choice) } } } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 6) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.conversionReady || model.selectedGroup == nil || model.busy)
    }
    private var verdictIcon: String { model.takeoverVerdict == .supported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    private var verdictColor: Color { model.takeoverVerdict == .supported ? .green : .orange }
    private var primaryTitle: String {
        if model.importMode == .convert { return "Create Converted Blueprint" }
        return model.takeoverVerdict == .supported ? "Create Takeover Blueprint" : "Import Alongside Existing Profile"
    }
}
