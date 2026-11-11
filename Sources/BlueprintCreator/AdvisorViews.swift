import SwiftUI

/// Small info button for a single tool message. Shows the plain-language
/// explanation, the suggested action and, when available, the matching jamf-cli
/// documentation excerpt. Renders nothing for messages the rules do not recognise.
struct AdvisorInfoButton: View {
    @EnvironmentObject var model: AppModel
    let line: String
    @State private var showing = false

    var body: some View {
        if let finding = AdvisorRules.classify(line) {
            let passage = model.advice?.items.first { $0.id == finding.id }?.passage
            Button {
                showing.toggle()
            } label: {
                Image(systemName: finding.severity.symbol)
                    .foregroundStyle(color(for: finding.severity))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(finding.category.title): \(finding.explanation)")
            .popover(isPresented: $showing, arrowEdge: .trailing) {
                AdvisorFindingDetail(finding: finding, passage: passage)
                    .padding(16)
                    .frame(width: 440, alignment: .leading)
            }
            .accessibilityLabel("Explain: \(finding.category.title)")
        }
    }

    private func color(for severity: FindingSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .review: return .orange
        case .action: return .red
        }
    }
}

struct AdvisorFindingDetail: View {
    let finding: AdvisorFinding
    let passage: AdvisorPassage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: finding.severity.symbol)
                Text(finding.category.title).font(.headline)
                Spacer()
                Text(finding.severity.label).font(.caption).foregroundStyle(.secondary)
            }
            if !finding.subject.isEmpty {
                Text(finding.subject).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            Text(finding.explanation).fixedSize(horizontal: false, vertical: true)
            Label(finding.action, systemImage: "arrow.right.circle")
                .fixedSize(horizontal: false, vertical: true)
            if let passage {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("From the jamf-cli documentation").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(String(passage.text.prefix(600)) + (passage.text.count > 600 ? "…" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text("\(passage.source) · \(passage.heading)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Divider()
            Text("Original message: \(finding.sourceLine)")
                .font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }
}

/// Sheet with the overall "what needs to change" summary.
struct AdvisorPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Explain & Recommend", systemImage: "sparkles").font(.title2.bold())
                Spacer()
                if model.adviceRefreshing { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let advice = model.advice {
                        content(advice)
                    } else if model.adviceRefreshing {
                        Text("Reviewing the conversion results…").foregroundStyle(.secondary)
                    } else {
                        Text("Select a profile and preview it to get recommendations.").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Advice only. Nothing here changes, deploys or unscopes a profile. Profile contents and credentials are never sent to the model; only the finding categories and payload type names are.")
                .font(.caption2).foregroundStyle(.secondary).padding(12)
        }
        .frame(width: 720, height: 640)
        .onAppear { if model.advice == nil { model.refreshAdvice() } }
    }

    @ViewBuilder
    private func content(_ advice: AdvisorAdvice) -> some View {
        Text(advice.headline).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
        if !advice.topChanges.isEmpty {
            section("What to change") {
                ForEach(Array(advice.topChanges.enumerated()), id: \.offset) { index, change in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                        Text(change).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if !advice.risks.isEmpty {
            section("Worth reviewing") {
                ForEach(Array(advice.risks.enumerated()), id: \.offset) { _, risk in
                    Label(risk, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !advice.items.isEmpty {
            section("Details (\(advice.items.count))") {
                ForEach(advice.items) { item in
                    DisclosureGroup {
                        AdvisorFindingDetail(finding: item.finding, passage: item.passage).padding(.vertical, 6)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.finding.severity.symbol)
                            Text(item.finding.subject.isEmpty ? item.finding.category.title : "\(item.finding.category.title): \(item.finding.subject)")
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        if let hint = advice.aiHint { aiPrompt(hint) }
        Text(advice.source.label).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let version = advice.corpusVersion {
            Text("Reference: \(version)").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func aiPrompt(_ hint: AdvisorAIHint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(hint == .appleIntelligenceOff ? "Add an AI-written summary" : "AI-written summary is off",
                  systemImage: "sparkles").font(.headline)
            Text(hint == .appleIntelligenceOff
                 ? "Apple Intelligence is turned off on this Mac. Turn it on in System Settings to get a plain-language summary written on your Mac. Nothing leaves your Mac, and the built-in guidance below still works without it."
                 : "You turned the on-device AI summary off. Turn it back on to add a plain-language summary written on your Mac.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if hint == .appleIntelligenceOff {
                    Button("Open Apple Intelligence Settings") { AdvisorPreferences.openAppleIntelligenceSettings() }
                    Button("Check Again") { model.refreshAdvice() }
                } else {
                    Button("Turn On AI Summary") { AdvisorPreferences.useOnDeviceAI = true; model.refreshAdvice() }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            body()
        }
    }
}

/// Settings tab: lets the user choose whether Explain & Recommend may use Apple's on-device model.
struct AdvisorSettingsForm: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(AdvisorPreferences.key) private var useAI = true
    @State private var status = AdvisorPreferences.deviceStatus()

    var body: some View {
        Form {
            Toggle("Use on-device AI to write the summary", isOn: $useAI)
                .onChange(of: useAI) { _ in model.refreshAdvice() }
            Text("When on, Explain & Recommend asks Apple's on-device model to summarise the findings in plain language. It runs on this Mac only. Profile contents and credentials are never sent to it. When off, or when the model is unavailable, built-in guidance is used.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("On-device model") { Text(status).foregroundStyle(.secondary) }
            HStack {
                Button("Open Apple Intelligence Settings") { AdvisorPreferences.openAppleIntelligenceSettings() }
                Button("Refresh Status") { status = AdvisorPreferences.deviceStatus() }
            }
        }
        .formStyle(.grouped)
        .onAppear { status = AdvisorPreferences.deviceStatus() }
    }
}
