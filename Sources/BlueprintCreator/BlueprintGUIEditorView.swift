import SwiftUI
import AppKit

struct BlueprintGUIEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var advanced = false
    @State private var advancedTab = 0
    @State private var showManualApproach = false
    @State private var showConditions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step == 0 ? "Let's create your Blueprint" : step == 1 ? "Review your Blueprint" : "Create your Blueprint").font(.largeTitle.bold())
                    Text(step == 2 ? "Follow the live operation below." : "Review the configuration profile and conversion settings.").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Dry Run", isOn: $model.dryRunEnabled).toggleStyle(.switch)
                Toggle("Advanced", isOn: $advanced).toggleStyle(.switch)
            }
            HStack(spacing: 8) { stepButton(1, "Setup", 0); stepButton(2, "Review", 1); stepButton(3, "Create", 2) }
            HStack(alignment: .top, spacing: 14) {
                ScrollView { mainContent.frame(maxWidth: .infinity) }.frame(maxWidth: .infinity)
                if advanced { advancedPanel.frame(minWidth: 360, idealWidth: 440, maxWidth: 540) }
            }
            footer
        }
        .onChange(of: model.busy) { running in if running && advanced { advancedTab = 0 } }
        .onChange(of: model.selectedProfileID) { _ in
            // Each profile begins with a clean automatic discovery workflow.
            step = 0
            advancedTab = 0
            showManualApproach = false
        }
        .sheet(isPresented: $showConditions) {
            ActivationConditionsEditor().environmentObject(model)
        }
    }

    private func stepButton(_ number: Int, _ title: String, _ index: Int) -> some View {
        Button { if index <= step { step = index } } label: {
            HStack { Text("\(number)").bold(); Text(title).fontWeight(.semibold) }
                .foregroundStyle(step == index ? Color.white : Color.secondary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(step == index ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: Capsule())
        }.buttonStyle(.plain).disabled(index > step)
    }

    @ViewBuilder private var mainContent: some View {
        if step == 0 { setupView }
        else if step == 1 { reviewView }
        else { createView }
    }

    private var setupView: some View {
        VStack(spacing: 14) {
            card { profileSummary }
            recommendationCard
            activationBar
        }
    }

    private var recommendationCard: some View {
        card(tint: recommendationColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Recommended Approach", systemImage: recommendationIcon).font(.title3.bold())
                    Spacer()
                    if model.recommendationIsAutomatic { Text("Selected by jamf-cli analysis").font(.caption).foregroundStyle(.secondary) }
                }
                Text(model.recommendedApproach.title).font(.title2.bold())
                ForEach(model.recommendationReasons, id: \.self) { reason in
                    Label(reason, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    if model.recommendedApproach != .analyzing {
                        Button(showManualApproach ? "Hide Alternatives" : "Change Approach") { showManualApproach.toggle() }
                    }
                    Button("Profile Inspector") { model.showProfileInspector = true }
                        .disabled(model.profileInspection == nil || model.profileInspectionLoading)
                        .help(model.profileInspectionLoading ? "Profile Inspector is still parsing the selected profile." : model.profileInspection == nil ? "Profile Inspector becomes available after the selected profile has been evaluated and parsed." : "Open the Profile Inspector for the evaluated profile. Review configured keys, recommendations, destination representation, unresolved decisions, and whether a setting is native, wrapped, or unknown.")
                    Button("View Analysis") { advanced = true; advancedTab = 0 }
                        .help("Open the full evaluation summary and raw jamf-cli activity for the selected profile.")
                    Spacer()
                    Text("Scope: " + (model.importScopeMode == .preserveSource ? "Use Existing Scope" : "Choose Another Group"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if showManualApproach && model.selectedApproach != .analyzing {
                    Divider()
                    Picker("Approach", selection: Binding(
                        get: { model.selectedApproach },
                        set: { model.useManualApproach($0) }
                    )) {
                        Text("Take Over the Installed Profile").tag(RecommendedProfileApproach.takeover)
                        Text("Convert to a New Blueprint").tag(RecommendedProfileApproach.convert)
                        Text("Create Blueprint for Review").tag(RecommendedProfileApproach.createForReview)
                    }
                    Picker("Scope", selection: $model.importScopeMode) {
                        Text("Use Existing Scope").tag(ImportScopeMode.preserveSource)
                        Text("Choose Another Group").tag(ImportScopeMode.overrideSelected)
                    }
                if model.importScopeMode == .overrideSelected {
                    Divider()
                    if model.groupsLoading {
                        HStack { ProgressView().controlSize(.small); Text("Loading compatible groups...") }
                    } else if let error = model.groupsLoadError {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unable to load compatible groups.").foregroundStyle(.red)
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Retry Groups") { Task { await model.reloadCompatibleGroups() } }
                        }
                    } else if model.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No compatible \(model.mobile ? "mobile-device" : "computer") groups were returned.")
                            Button("Retry Groups") { Task { await model.reloadCompatibleGroups() } }
                        }
                    } else {
                        Picker("Target Group", selection: $model.selectedGroup) {
                            Text("Select a compatible group").tag(DeviceGroup?.none)
                            ForEach(model.groups) { group in
                                Text(group.name)
                                    .tag(Optional(group))
                                    .onAppear {
                                        Task { await model.loadMoreGroupsIfNeeded(currentGroup: group) }
                                    }
                            }
                            if model.groupsLoadingMore {
                                Text("Loading more groups...").tag(model.selectedGroup)
                            }
                        }
                        .onChange(of: model.selectedGroup) { _ in model.scheduleAutomaticTakeoverEvaluation() }
                    }
                }
                }
            }
        }
    }

    private var recommendationColor: Color {
        switch model.recommendedApproach {
        case .takeover: return .green
        case .convert, .createForReview, .evaluationIncomplete: return .orange
        case .unavailable: return .red
        case .analyzing: return .blue
        }
    }

    private var recommendationIcon: String {
        switch model.recommendedApproach {
        case .takeover: return "checkmark.shield.fill"
        case .convert: return "arrow.triangle.2.circlepath"
        case .createForReview: return "doc.text.magnifyingglass"
        case .unavailable: return "xmark.octagon.fill"
        case .evaluationIncomplete: return "questionmark.diamond.fill"
        case .analyzing: return "hourglass"
        }
    }

    private var reviewView: some View {
        VStack(spacing: 14) {
            card { VStack(alignment: .leading, spacing: 12) { profileSummary; Divider(); row("Approach", model.selectedApproach.title); row("Scope", model.importScopeMode.title); row("Blueprint Activation Conditions", model.blueprintActivationCondition.isEmpty ? "None configured" : "Configured") } }
            card(tint: .purple) { outcomes }
            activationBar
        }
    }

    private var createView: some View {
        VStack(spacing: 14) {
            card(tint: model.runStage == .failed ? .red : model.runStage == .completed ? .green : .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(model.runStage.title, systemImage: runIcon).font(.title2.bold()).foregroundStyle(runColor)
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                    }
                    if model.busy { ProgressView().progressViewStyle(.linear) }
                    ForEach(expectedStages, id: \.rawValue) { stage in stageRow(stage) }
                    Divider()
                    Text(model.runDetail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if model.runStage == .failed { Button("View Logs") { model.showLogs = true } }
                    if model.runStage == .completed && model.lastTakeoverDeploymentValidated {
                        Button("Review Classic Profile") { model.requestTakeoverUnscopeReview() }
                    }
                }
            }
            card(tint: .purple) { outcomes }
        }
    }

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Advanced", selection: $advancedTab) { Text("jamf-cli Activity").tag(0); Text("Blueprint JSON").tag(1) }.pickerStyle(.segmented)
            if advancedTab == 0 { activityView } else { jsonView }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var activityView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label("jamf-cli Activity", systemImage: "terminal").font(.headline); Spacer(); Button("Copy Output") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.takeoverRawOutput, forType: .string) } }
            HStack { Text("Current stage").foregroundStyle(.secondary); Spacer(); Text(model.runStage.title).bold() }
            ScrollView { Text(model.takeoverRawOutput.isEmpty ? model.runDetail : model.takeoverRawOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 300).padding(10).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var jsonView: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Blueprint JSON", systemImage: "curlybraces").font(.headline)
            TextEditor(text: $model.json).font(.system(.caption, design: .monospaced)).disabled(model.busy).onChange(of: model.json) { _ in model.loadBlueprintGUIFromJSON() }
            Label(model.jsonValidationMessage, systemImage: jsonValid ? "checkmark.circle.fill" : "xmark.octagon.fill").font(.caption).foregroundStyle(jsonValid ? .green : .red)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Back") { step -= 1 }.controlSize(.large).disabled(model.busy) }
            Spacer()
            if step < 2 { Button("Next") { step += 1 }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.selectedProfile == nil || !jsonValid) }
            else if model.dryRunEnabled {
                Button(finalButtonTitle) {
                    advancedTab = 0
                    Task { await model.performGuidedFinalAction(deploymentIntent: .createOnly) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.selectedProfile == nil || !jsonValid || model.busy)
            } else {
                Button("Create Only") {
                    advancedTab = 0
                    Task { await model.performGuidedFinalAction(deploymentIntent: .createOnly) }
                }
                .controlSize(.large)
                .disabled(model.selectedProfile == nil || !jsonValid || model.busy || !model.evaluateDeploymentSafeguards().canCreate)
                Button("Create and Deploy") {
                    advancedTab = 0
                    Task { await model.performGuidedFinalAction(deploymentIntent: .createAndDeploy) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.selectedProfile == nil || !jsonValid || model.busy || !model.evaluateDeploymentSafeguards().canDeploy)
                .help(model.evaluateDeploymentSafeguards().canDeploy ? "Create the Blueprint and explicitly deploy it." : model.evaluateDeploymentSafeguards().reasons.joined(separator: "\n"))
                Button("Create, Deploy, and Unscope") {
                    advancedTab = 0
                    model.requestCreateDeployAndUnscope()
                }
                .controlSize(.large)
                .disabled(model.selectedProfile == nil || !jsonValid || model.busy || !model.evaluateDeploymentSafeguards().canDeploy)
                .help(model.evaluateDeploymentSafeguards().canDeploy ? "Deploy first, validate DEPLOYED, then explicitly unscope the Classic Configuration Profile." : model.evaluateDeploymentSafeguards().reasons.joined(separator: "\n"))
            }
        }
    }

    private var finalButtonTitle: String {
        if model.busy { return "Running..." }
        if model.runStage == .completed { return model.dryRunEnabled ? "Run Preview Again" : "Run Again" }
        return model.dryRunEnabled ? "Run Dry-Run Preview" : "Create Blueprint"
    }

    private var expectedStages: [BlueprintRunStage] {
        if model.workflowMode == .takeover && model.takeoverCapabilities.commandAvailable {
            return [.validatingAPI, .preparing, .downloadingProfile, .resolvingScope, .processingPayloads, .evaluatingTakeover, .creatingBlueprint, .awaitingDeployment, .validatingJSON]
        }
        return [.validatingAPI, .downloadingProfile, .resolvingScope, .processingPayloads, .generatingBlueprint, .validatingJSON, .awaitingDeployment]
    }

    private func stageRow(_ stage: BlueprintRunStage) -> some View {
        let completed = model.completedRunStages.contains(stage)
        let active = model.runStage == stage
        return HStack {
            if active && model.busy { ProgressView().controlSize(.small).frame(width: 18) }
            else { Image(systemName: completed ? "checkmark.circle.fill" : model.runStage == .failed && active ? "xmark.octagon.fill" : "circle").foregroundStyle(completed ? .green : model.runStage == .failed && active ? .red : .secondary).frame(width: 18) }
            Text(stage.title).foregroundStyle(completed ? .green : active ? .primary : .secondary)
        }
    }

    private var runIcon: String { model.runStage == .failed ? "xmark.octagon.fill" : model.runStage == .completed ? "checkmark.circle.fill" : model.busy ? "hourglass" : "play.circle.fill" }
    private var runColor: Color { model.runStage == .failed ? .red : model.runStage == .completed ? .green : .blue }
    private var jsonValid: Bool { !model.jsonValidationMessage.localizedCaseInsensitiveContains("invalid") && !model.jsonValidationMessage.localizedCaseInsensitiveContains("error") }
    private var profileSummary: some View { HStack { Image(systemName: "doc.text.fill").font(.title2).foregroundStyle(.blue); VStack(alignment: .leading) { Text("Selected Configuration Profile").font(.headline); Text(model.selectedProfile?.name ?? "← Select a Configuration Profile").font(.title3.bold()); if let profile = model.selectedProfile { Text("ID: \(profile.id) • \(profile.scope.summary)").font(.caption).foregroundStyle(.secondary) } }; Spacer() } }
    private var activationBar: some View { HStack(spacing: 8) { Image(systemName: "info.circle.fill").foregroundStyle(.blue); Text("Blueprint Activation Conditions").font(.subheadline.bold()); Text(model.blueprintActivationCondition.isEmpty ? "No activation conditions configured." : conditionSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1); Spacer(); Button("Edit Conditions") { showConditions = true }.controlSize(.small) }.padding(.horizontal, 12).padding(.vertical, 8).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
    private var conditionSummary: String { model.blueprintActivationCondition.isEmpty ? "No activation conditions configured." : model.blueprintActivationCondition }
    private var outcomes: some View { VStack(alignment: .leading, spacing: 9) { Label("What will happen?", systemImage: "list.bullet.circle.fill").font(.title3.bold()); Text(model.selectedApproach == .takeover ? "BCU will attempt to adopt the existing installed profile into Blueprint management using the selected scope and settings." : "BCU will create a new Blueprint using the selected scope and settings.").foregroundStyle(.secondary) } }
    private func row(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).bold() } }
    private func card<Content: View>(tint: Color = .blue, @ViewBuilder content: () -> Content) -> some View { content().padding(18).background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)).overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.2)))) }
}


private struct ActivationConditionsEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var matchMode = "all"
    @State private var attribute = "Device model"
    @State private var comparison = "contains"
    @State private var value = ""
    @State private var draft = ""

    private let attributes = ["Device model", "Operating system version", "Operating system build", "Architecture", "Device name", "Serial number", "FileVault enabled", "Bootstrap token escrowed", "Supervised"]
    private let comparisons = ["is", "is not", "contains", "does not contain", "starts with", "does not start with", "ends with", "does not end with", "is like", "is not like", "matches", "does not match"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Blueprint Activation Conditions").font(.title.bold())
                    Text("Control when this Blueprint should apply to a device.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Editor", selection: $mode) { Text("Visual").tag(0); Text("Text").tag(1) }
                    .pickerStyle(.segmented).frame(width: 180)
            }

            if mode == 0 {
                Picker("Match", selection: $matchMode) { Text("Match all").tag("all"); Text("Match any").tag("any") }.frame(width: 160)
                HStack(spacing: 10) {
                    Picker("Attribute", selection: $attribute) { ForEach(attributes, id: \.self) { Text($0).tag($0) } }.frame(minWidth: 210)
                    Picker("Operator", selection: $comparison) { ForEach(comparisons, id: \.self) { Text($0).tag($0) } }.frame(minWidth: 190)
                    valueEditor
                    Button("Set") { draft = expression }
                }
                GroupBox("Preview") {
                    Text(draft.isEmpty ? "No activation condition configured." : draft)
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            } else {
                TextEditor(text: $draft).font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            }

            Spacer()
            HStack {
                Button("Clear Conditions", role: .destructive) { draft = "" }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Conditions") {
                    model.blueprintActivationCondition = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.applyBlueprintGUIToJSON()
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(minWidth: 820, minHeight: 480)
        .onAppear { draft = model.blueprintActivationCondition }
    }

    @ViewBuilder private var valueEditor: some View {
        if ["FileVault enabled", "Bootstrap token escrowed", "Supervised"].contains(attribute) {
            Picker("Value", selection: $value) { Text("Yes").tag("true"); Text("No").tag("false") }.frame(width: 120)
                .onAppear { if value.isEmpty { value = "true" } }
        } else if attribute == "Architecture" {
            Picker("Value", selection: $value) { Text("Apple silicon").tag("arm64"); Text("Intel").tag("x86_64") }.frame(width: 140)
                .onAppear { if value.isEmpty { value = "arm64" } }
        } else {
            TextField("Value", text: $value).frame(minWidth: 170)
        }
    }

    private var expression: String {
        let key = attribute.replacingOccurrences(of: " ", with: "").prefix(1).lowercased() + attribute.replacingOccurrences(of: " ", with: "").dropFirst()
        let op = ["is":"==", "is not":"!=", "contains":"contains", "does not contain":"notContains", "starts with":"startsWith", "does not start with":"notStartsWith", "ends with":"endsWith", "does not end with":"notEndsWith", "is like":"like", "is not like":"notLike", "matches":"matches", "does not match":"notMatches"][comparison] ?? comparison
        if ["true", "false"].contains(value) { return "\(key) \(op) \(value)" }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\(key) \(op) \"\(escaped)\""
    }
}
