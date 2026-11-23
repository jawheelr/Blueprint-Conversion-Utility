import SwiftUI
import AppKit

private struct CLITestResult: Sendable {
    let output: String
}

struct ConnectionsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var message = "Save and test the Platform API."
    @State private var cliTestOutput = "No jamf-cli test has been run."
    @State private var cliTestRunning = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connections").font(.largeTitle.bold())
                    Text(tab == 1
                         ? "Run a local, read-only jamf-cli diagnostic."
                         : tab == 2 ? "Choose how recommendations are written."
                         : "Configure and test API connectivity.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if tab == 0 {
                    Label(
                        model.ready ? "Ready" : "Setup required",
                        systemImage: model.ready
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.ready ? .green : .orange)
                }
            }

            Picker("Connection", selection: $tab) {
                Text("Platform API").tag(0)
                Text("jamf-cli").tag(1)
                Text("Explain & Recommend").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 640)
            .frame(maxWidth: .infinity)

            GroupBox {
                if tab == 0 { VStack(spacing: 0) { connectionPicker; Divider(); platformForm } } else if tab == 1 { jamfCLIForm } else { AdvisorSettingsForm() }
            }
            .frame(maxHeight: .infinity)

            if tab == 0 {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            footer
        }
        .padding(24)
        .frame(width: 840, height: 720)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if tab == 0 {
                Button("Test Platform API") {
                    Task {
                        await model.testPlatform()
                        message = model.alert ?? model.status
                    }
                }
                .disabled(model.busy)
            } else if tab == 1 {
                Button(cliTestRunning ? "Testing..." : "Test jamf-cli") {
                    runCLITest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(cliTestRunning)
            }

            Spacer()

            if tab == 2 {
                Button("Close") { dismiss() }
            } else if tab == 1 {
                Button("Copy Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cliTestOutput, forType: .string)
                }
                Button("Clear") { cliTestOutput = "No jamf-cli test has been run." }
                Button("Close") { dismiss() }
            } else {
                Button("Cancel") { dismiss() }
                Button("Save Connections") {
                    do {
                        try model.save()
                        message = model.status
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.complete)

                Button("Save and Close") {
                    do {
                        try model.save()
                        guard model.ready else {
                            message = "The Platform API test must pass before closing."
                            return
                        }
                        model.alert = nil
                        dismiss()
                        Task { await model.load() }
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .disabled(!model.ready)
            }
        }
    }




    private var connectionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Connection", selection: Binding(
                    get: { model.activeConnectionID ?? UUID() },
                    set: { id in Task { await model.selectConnection(id, validate: false) } }
                )) {
                    ForEach(model.connections) { Text($0.displayName).tag($0.id) }
                }
                .frame(maxWidth: 360)
                .disabled(model.busy)
                Button { model.addConnection() } label: { Label("Add", systemImage: "plus") }
                    .disabled(model.busy)
                Button(role: .destructive) { confirmRemove = true } label: { Label("Remove", systemImage: "minus") }
                    .disabled(model.busy || model.connections.count < 2)
                Spacer()
            }
            HStack {
                Text("Name").frame(width: 70, alignment: .leading)
                TextField("Connection name", text: Binding(
                    get: { model.activeConnectionDraftName },
                    set: { model.setActiveConnectionName($0) }
                ))
                .frame(maxWidth: 360)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .confirmationDialog(
            "Remove \(model.activeConnectionName)?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await model.deleteActiveConnection() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Its saved client secret is deleted from the Keychain.")
        }
    }

    private var platformForm: some View {
        Form {
            TextField("Platform API URL", text: $model.settings.platformURL)
            TextField("Client ID", text: $model.settings.platformClientID)
            SecureField("Client secret", text: $model.platformSecret)
            TextField("Platform Environment ID", text: $model.settings.environmentID)
            Text("Enter the Platform Environment ID selected when the API Client was created. All scoped requests use X-Environment-Id.")
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker(
                "API Client expiration date",
                selection: Binding(
                    get: {
                        model.settings.integrationExpirationDate
                            ?? Calendar.current.startOfDay(for: Date())
                    },
                    set: { value in
                        model.settings.integrationExpirationDate = value
                        model.refreshPlatformCredentialHealth()
                    }
                ),
                displayedComponents: .date
            )
            Stepper(
                "Expiration warning: \(model.settings.expiryWarningDays) days",
                value: $model.settings.expiryWarningDays,
                in: 1...180
            )
            .onChange(of: model.settings.expiryWarningDays) { _ in
                model.refreshPlatformCredentialHealth()
            }
            Text("Use the expiration date shown in the Jamf Platform API Client overview. The default warning period is 30 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.settings.platformURL.isEmpty && !model.settings.hostIsKnownJamf {
                Label("This host is not a recognized Jamf domain (jamfcloud.com or jamf.com). Your client secret is sent to it during authentication; confirm the URL is correct.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Platform API test") {
                Text(model.platformTested ? (model.limitedAccessProblem == nil ? "Passed" : "Limited access") : "Not tested")
                    .foregroundStyle(model.platformTested ? (model.limitedAccessProblem == nil ? .green : .orange) : .secondary)
            }
            if !model.permissionReport.isEmpty { permissionsSection }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings.platformURL) { _ in model.platformTested = false }
        .onChange(of: model.settings.platformClientID) { _ in model.platformTested = false }
        .onChange(of: model.platformSecret) { _ in model.platformTested = false }
        .onChange(of: model.settings.environmentID) { _ in model.platformTested = false }
    }

    /// What the last test found, with the fix for anything missing.
    private var permissionsSection: some View {
        Section("Permissions") {
            ForEach(model.permissionReport) { check in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: icon(for: check)).foregroundStyle(color(for: check))
                        Text(check.capability.title).bold()
                        Spacer()
                        Text(check.capability.usedFor).font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem = check.problem {
                        Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    } else if case .notChecked(let note) = check.state {
                        Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.permissionReportText, forType: .string)
                }
            }
        }
    }

    private func icon(for check: PermissionCheck) -> String {
        switch check.state {
        case .ok: return "checkmark.circle.fill"
        case .denied, .failed: return "xmark.octagon.fill"
        case .notChecked: return "circle.dotted"
        }
    }

    private func color(for check: PermissionCheck) -> Color {
        switch check.state {
        case .ok: return .green
        case .denied, .failed: return .red
        case .notChecked: return .secondary
        }
    }

    private var jamfCLIForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("jamf-cli Diagnostic").font(.title2.bold())
            Text("The test executes only `jamf-cli --version`. No credentials, tokens, or API requests are used.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView([.horizontal, .vertical]) {
                Text(cliTestOutput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .padding(14)
    }

    private func runCLITest() {
        cliTestRunning = true
        cliTestOutput = "Running jamf-cli test..."

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.executeCLITest()
            }.value
            cliTestOutput = result.output
            cliTestRunning = false
        }
    }

    nonisolated private static func executeCLITest() -> CLITestResult {
        let executable = ManagedToolRepository.resolve("jamf-cli")
        let source = executable == nil ? "Not found"
            : (ManagedToolRepository.bundledTool("jamf-cli") != nil ? "Application bundle" : "Development copy")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        guard let executable else {
            return CLITestResult(output: """
            [\(timestamp)]

            Executable
            Not found

            Query
            jamf-cli --version

            Response
            No jamf-cli executable was found in the application bundle.

            Exit code
            127

            Result
            Test failed
            """)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = stdout
        process.standardError = stderr
        let start = Date()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CLITestResult(output: """
            [\(timestamp)]

            Executable
            \(executable.path)

            Source
            \(source)

            Query
            \(executable.path) --version

            Response
            \(error.localizedDescription)

            Exit code
            126

            Result
            Test failed
            """)
        }

        let out = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let err = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let duration = String(format: "%.3f seconds", Date().timeIntervalSince(start))
        let code = process.terminationStatus

        return CLITestResult(output: """
        [\(timestamp)]

        Executable
        \(executable.path)

        Source
        \(source)

        Query
        \(executable.path) --version

        Standard output
        \(out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<empty>" : out.trimmingCharacters(in: .whitespacesAndNewlines))

        Standard error
        \(err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<empty>" : err.trimmingCharacters(in: .whitespacesAndNewlines))

        Exit code
        \(code)

        Duration
        \(duration)

        Result
        \(code == 0 ? "Test passed" : "Test failed")
        """)
    }
}
