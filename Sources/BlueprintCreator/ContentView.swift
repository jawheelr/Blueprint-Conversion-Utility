import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var filteredProfiles: [JamfProfile] {
        search.isEmpty
            ? model.profiles
            : model.profiles.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            workspace
                .navigationTitle("")
                .navigationSubtitle("")
        }
        .sheet(isPresented: $model.showConnections) {
            ConnectionsView().environmentObject(model)
        }
        .sheet(isPresented: $model.showAbout) { AboutView() }
        .sheet(isPresented: $model.showKB) { KnowledgeBaseView().environmentObject(model) }
        .sheet(isPresented: $model.showAppleSchema) { AppleSchemaBrowserView() }
        .sheet(isPresented: $model.showProfileInspector) { ProfileInspectorView().environmentObject(model) }
        .sheet(isPresented: $model.showLogs) { LogsView() }
        .sheet(isPresented: $model.showDeploymentReview) {
            DeploymentReviewView().environmentObject(model)
        }
        .sheet(isPresented: $model.showDeployAndUnscopeConfirmation) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Create, Deploy, and Unscope", systemImage: "exclamationmark.shield.fill")
                    .font(.title.bold()).foregroundStyle(.orange)
                Text("BCU will create the takeover Blueprint, deploy it, wait for Jamf Platform to report DEPLOYED, and only then remove the Classic Configuration Profile scope.")
                    .foregroundStyle(.secondary)
                GroupBox("Safety sequence") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Create the Blueprint with takeover-only protection.")
                        Text("2. Deploy the Blueprint.")
                        Text("3. Poll Jamf Platform until deployment is validated as DEPLOYED.")
                        Text("4. Unscope the Classic Configuration Profile only after validation.")
                        Text("If deployment is not validated, the Classic profile remains scoped.").bold()
                    }.padding(8)
                }
                Toggle("I understand the Classic Configuration Profile will be unscoped only after the Blueprint deployment is validated as DEPLOYED.", isOn: $model.deployAndUnscopeAcknowledged)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Cancel", role: .cancel) { model.showDeployAndUnscopeConfirmation = false }
                    Spacer()
                    Button("Create, Deploy, and Unscope", role: .destructive) { model.confirmCreateDeployAndUnscope() }
                        .disabled(!model.deployAndUnscopeAcknowledged || model.busy)
                }
            }.padding(26).frame(width: 680)
        }
        .sheet(isPresented: $model.showTakeoverUnscopeConfirmation) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Unscope Classic Configuration Profile", systemImage: "exclamationmark.shield.fill")
                    .font(.title.bold()).foregroundStyle(.orange)
                Text("This is a separate lifecycle action. The takeover Blueprint has already been validated as deployed. Unscoping changes the Classic Configuration Profile and can affect rollback behavior.")
                    .foregroundStyle(.secondary)
                GroupBox("Verify before continuing") {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Blueprint deployment validated as DEPLOYED", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Confirm representative devices show the expected declaration and settings, activation conditions and scope behave as intended, and dropped-key diagnostics were reviewed.")
                    }.padding(8)
                }
                Toggle("I verified takeover on representative devices and understand that unscoping the Classic Configuration Profile changes rollback and removal behavior.", isOn: $model.takeoverUnscopeAcknowledged)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Cancel", role: .cancel) { model.showTakeoverUnscopeConfirmation = false }
                    Spacer()
                    Button("Unscope Classic Configuration Profile", role: .destructive) { model.confirmTakeoverUnscope() }
                        .disabled(!model.takeoverUnscopeAcknowledged || model.busy)
                }
            }.padding(26).frame(width: 650)
        }
        .sheet(isPresented: $model.showUpdateAvailable) {
            UpdateAvailableView().environmentObject(model)
        }
        .confirmationDialog("Configuration Profile Distribution", isPresented: $model.showSourceDispositionPrompt, titleVisibility: .visible) {
            Button("Distribute Removal to All Previously Assigned Devices") { model.confirmSourceDisposition(.distributeToAll) }
            Button("Apply Removal to Newly Assigned Devices Only") { model.confirmSourceDisposition(.doNotDistribute) }
            Button("Cancel", role: .cancel) { model.pendingDistributionChoice = nil }
        } message: { Text("Both choices remove every device and group from the source profile. The selection controls Jamf redistribution behavior for the saved removal.") }
        .alert(item: $model.operationResult) { result in Alert(title: Text(result.title), message: Text(result.details), dismissButton: .default(Text("OK"))) }
        .alert(
            "Blueprint Conversion Utility",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alert ?? "")
        }
        .task {
            await model.launch()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                model.refreshPlatformCredentialHealth()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("PROFILE TYPE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("", selection: $model.mobile) {
                    Text("Computers").tag(false)
                    Text("Mobile Devices").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.mobile) { _ in
                Task { await model.refreshSelectedProfileType() }
            }

            TextField("Search profiles", text: $search)

            List(filteredProfiles, selection: $model.selectedProfileID) { profile in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name)
                            .lineLimit(1)
                        Text("Profile ID \(profile.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if model.loadingProfileID == profile.id {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .contentShape(Rectangle())
                .tag(profile.id)
            }
            .onChange(of: model.selectedProfileID) { profileID in
                guard let profileID,
                      model.loadingProfileID != profileID,
                      let profile = model.profiles.first(where: { $0.id == profileID })
                else { return }
                Task { await model.select(profile) }
            }

            Button("Refresh Workspace") { Task { await model.load() } }
                .disabled(!model.ready || model.busy)
        }
        .padding()
        .navigationTitle("Profiles")
        .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 420)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            header
            Divider()
            BlueprintGUIEditorView().environmentObject(model).padding(18)
            statusBar
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView().frame(width: 52, height: 52)
            VStack(alignment: .leading) {
                Text("Blueprint Conversion Utility").font(.title.bold())
                Text("Configuration profiles to Jamf Blueprints")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                model.ready ? "APIs ready" : "Setup required",
                systemImage: model.ready
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(model.ready ? .green : .orange)
            Button("View Logs") { model.showLogs = true }
            Button("Connections") { model.showConnections = true }
        }
        .padding(18)
    }

    private var scopeBanner: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(model.scopeNotice.split(separator: "\n").enumerated()), id: \.offset) {
                _, line in
                Text(String(line))
                    .font(line.hasPrefix("✓") || line.hasPrefix("⚠") ? .headline : .subheadline.bold())
                    .foregroundStyle(line.hasPrefix("✓") ? .green : line.hasPrefix("⚠") ? .orange : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var credentialHealthColor: Color {
        switch model.platformCredentialHealth {
        case .valid: return .green
        case .expiringSoon: return .yellow
        case .expired, .authenticationFailed: return .red
        case .notConfigured: return .secondary
        }
    }

    private var credentialHealthIcon: String {
        switch model.platformCredentialHealth {
        case .valid: return "checkmark.circle.fill"
        case .expiringSoon: return "exclamationmark.triangle.fill"
        case .expired, .authenticationFailed: return "xmark.octagon.fill"
        case .notConfigured: return "questionmark.circle.fill"
        }
    }

    private var statusBar: some View {
        HStack {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.status).font(.caption)
            Spacer(minLength: 20)
            Label(model.credentialHealthText, systemImage: credentialHealthIcon)
                .font(.caption)
                .foregroundStyle(credentialHealthColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help(model.credentialHealthText)
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(.bar)
    }
}

struct AppIconView: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "AppMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "ruler").resizable().scaledToFit().foregroundStyle(.blue)
        }
    }
}
