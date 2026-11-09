import SwiftUI
import AppKit

struct UpdateAvailableView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Available").font(.largeTitle.bold())
                    if let update = model.availableUpdate {
                        Text("Version \(update.latestVersion) is available. You have \(update.currentVersion).")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let update = model.availableUpdate {
                GroupBox("Release Notes") {
                    ScrollView {
                        Text(update.releaseNotes)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    }
                    .frame(minHeight: 220)
                }

                Text("The app downloads the versioned PKG, validates it, and opens the native macOS Installer. After Installer opens, this application closes. When the installed version changes, the application relaunches automatically. Installer confirmation and administrator authorization may still be required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.updateDownloadStatus.isEmpty {
                    HStack(spacing: 8) {
                        if model.updateDownloadInProgress {
                            ProgressView().controlSize(.small)
                        }
                        Text(model.updateDownloadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Skip for Now") { dismiss() }
                        .disabled(model.updateDownloadInProgress)
                    Button("Release Page") {
                        NSWorkspace.shared.open(update.releaseURL)
                    }
                    .disabled(model.updateDownloadInProgress)
                    Spacer()
                    Button(model.updateDownloadInProgress ? "Downloading..." : "Download and Install") {
                        Task { await model.downloadAndInstallAvailableUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.updateDownloadInProgress)
                }
            }
        }
        .padding(26)
        .frame(width: 650, height: 440)
    }
}
