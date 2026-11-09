import SwiftUI
import AppKit

private enum KBTopic: String, CaseIterable, Identifiable {
    case adminStart = "Admin Start Guide"
    case overview = "Application Overview"
    case workflow = "Conversion Workflow"
    case profileInspector = "Profile Inspector"
    case takeover = "Profile Takeover Walkthrough"
    case editor = "GUI and JSON Editor Walkthrough"
    case platform = "Platform API"
    case cli = "jamf-cli"
    case payloads = "Payload Compatibility"
    case deployment = "Deployment and Unscoping"
    case groups = "Device Groups"
    case troubleshooting = "Troubleshooting"
    case updates = "Updates and Support"
    var id: String { rawValue }
}

struct KnowledgeBaseView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: KBTopic? = .adminStart

    var body: some View {
        NavigationSplitView {
            List(KBTopic.allCases, selection: $selection) { topic in
                Label(topic.rawValue, systemImage: icon(for: topic)).tag(topic)
            }
            .navigationTitle("Knowledge Base")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    article(selection ?? .adminStart)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Project on GitHub") {
                    NSWorkspace.shared.open(AppUpdateService.repositoryURL)
                }
                Button("Check for Updates") { Task { await model.checkForAppUpdates(manual: true) } }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(14)
            .background(.bar)
        }
        .frame(width: 980, height: 700)
    }

    @ViewBuilder
    private func article(_ topic: KBTopic) -> some View {
        switch topic {
        case .adminStart:
            heading("Admin Start Guide", "Prepare, analyze, review, and deploy safely")
            paragraph("Use this guide as the standard administrator workflow for production conversions.")
            subsection("Before you begin")
            bullets(["Confirm APIs ready.", "Start with a controlled Platform Device Group.", "Keep a rollback plan and do not unscope the source profile until deployment and representative-device behavior are validated."])
            subsection("Administrator workflow")
            numbered(["Configure and test Connections.", "Select a Configuration Profile and wait for profile-specific jamf-cli analysis.", "Review the Recommended Approach, then explicitly choose an alternative only when intended.", "Confirm Approach, Scope, and Target Group. Target Group appears below Scope when Choose Another Group is selected.", "Run Dry Run and review Advanced jamf-cli Activity for the currently selected profile.", "Create Only first, inspect the Blueprint, deploy to a controlled group, and validate representative devices.", "Authorize source-profile unscoping separately only after successful validation."])
            subsection("Profile Inspector placement")
            paragraph("After evaluation, Profile Inspector appears in the Recommended Approach card directly between Change Approach and View Analysis. It is enabled after profile parsing completes and always opens the inspector for the currently evaluated profile.")
            subsection("Profile Inspector and recommendation decisions")
            numbered(["Open Profile Inspector after the selected profile finishes loading.", "Use Expand Configured, Expand All, or the disclosure arrows to review nested settings.", "Click anywhere on a setting row to select it and review the recommendation, timing, reason, migration behavior, confidence, and evidence.", "For Review, Edit Before Conversion, Replace, or Remove findings, choose Resolve Before Continuing.", "Select Apply to Destination, Keep Source Value, or Review Later. Applying creates a destination override and never edits the Jamf source profile.", "Clear the Action Needed filter before final review and resolve each remaining recommendation intentionally."])
            note("Destination override decisions are tied to the currently selected profile and are cleared when another profile is selected.")
            paragraph("Hover over every recommendation badge for action-specific guidance. Keep, Convert, Edit Before Conversion, Replace, Remove, Preserve as Legacy, Review, and Metadata each explain what the action means, when to use it, and whether the likely destination is a native component or a configuration-profile wrapper. In the decision sheet, each Decision option also provides its own detailed tooltip.")
            subsection("Understanding destination decisions")
            paragraph("A Profile Inspector recommendation describes the intended destination treatment, not an immediate change to the Jamf source profile. The source remains read-only. Apply to Destination records an administrator-approved destination override; Keep Source Value preserves the configured value using the best supported representation; Review Later leaves the finding unresolved for later review.")
            bullets(["Keep: Preserve a current setting without semantic change.", "Convert: Translate a structured setting into the supported destination representation.", "Edit Before Conversion: Confirm or change the intended destination value before final Blueprint generation.", "Replace: Review a deprecated setting and choose its modern destination representation when one exists.", "Remove: Do not carry an Apple-removed setting forward without a supported replacement.", "Preserve as Legacy: Keep vendor-defined or wildcard content in a configuration-profile wrapper.", "Review: BCU cannot make a safe automatic decision.", "Metadata: Preserve payload identity and descriptive fields unless references are rewritten together."])
            subsection("Native Blueprint components and profile wrappers")
            paragraph("A native Blueprint or DDM component may be editable in the Jamf Blueprint GUI when Jamf exposes that component and property. Acceptance through the API does not guarantee a complete GUI editor. If Apple or Jamf provides no native equivalent, BCU preserves the key in a configuration-profile wrapper. Wrapped content remains part of the Blueprint, but individual wrapped keys may require BCU, profile-content replacement, or API editing later.")
            note("A dry-run message such as 'kept in profile wrapper' means behavior was preserved as profile content; it does not mean the key became a native Jamf GUI control.")
            subsection("Decision fields")
            bullets(["Proposed destination value or instruction records the intended destination value or handling note.", "For Boolean settings, use true or false.", "Confidence describes the strength of the evidence, not whether Jamf offers GUI editing.", "Evidence identifies the Apple lifecycle, schema match, configured value, payload type, or BCU compatibility rule that produced the recommendation.", "Schema Match Exact means Apple defines the key at the current nested path; Wildcard means Apple allows arbitrary vendor keys there; Unknown requires administrator review."])
            warning("In this development stage, verify on Review that an Apply to Destination decision changes the generated Blueprint JSON before relying on the decision for production deployment. If the JSON does not change, treat the saved value as a recorded administrator decision rather than an applied transformation.")
            subsection("Apple Schema Browser")
            paragraph("The Apple Schema Browser is a Help-menu reference and diagnostic tool. It supports full-row selection, disclosure expansion, search-path expansion, wider wrapped details, and Expand All, Collapse All, and Expand Configured controls. Normal migrations should use Profile Inspector; use the Schema Browser to inspect Apple definitions or troubleshoot a schema match.")
            note("Analysis may refresh the recommendation, but it must not overwrite an explicit administrator-selected Approach.")
            warning("Blueprint creation or an initial deployment request is not proof that devices adopted the intended state.")
        case .overview:
            heading("Application Overview", "What Blueprint Conversion Utility does")
            paragraph("Blueprint Conversion Utility migrates computer and mobile-device configuration profiles into Jamf Platform Blueprints. All network operations use Platform OAuth against the regional api.jamfcloud.com host.")
            bullets([
                "Loads source profiles through the Platform-published /proclassic profile gateway.",
                "Uses the bundled Jamf profileconvert engine to produce native DDM and compatible legacy components.",
                "Creates and distributes Blueprints with native Platform endpoints.",
                "Optionally removes all active scope from the source profile only after Blueprint creation and distribution succeed.",
                "Reads the source profile back and verifies that no active scope remains."
            ])
            note("The /proclassic path describes the resource family exposed by Jamf Platform. The app does not use a separate Jamf Pro URL, credential, or token.")

        case .profileInspector:
            heading("Profile Inspector", "Evaluate settings, resolve recommendations, and understand destination editability")
            paragraph("Profile Inspector appears in the Recommended Approach card after evaluation, directly between Change Approach and View Analysis. The global application-header shortcut was removed so the inspector is opened only in the context of the evaluated profile.")
            subsection("Opening and navigating")
            numbered(["Select a Configuration Profile and wait for evaluation and profile parsing to finish.", "In Recommended Approach, choose Profile Inspector.", "Click anywhere in a setting row to select it.", "Use Expand Configured, Expand All, Collapse All, search, and Action Needed to focus the review.", "Hover over a recommendation badge or select its information button for the full explanation."])
            subsection("Recommendation meanings")
            bullets(["Keep: Preserve a current Apple-defined setting unless another conversion finding conflicts.", "Convert: Translate a structured setting into the supported Blueprint destination while preserving nested relationships.", "Edit Before Conversion: Confirm or change the intended destination before Blueprint creation.", "Replace: Prefer a modern representation for a deprecated setting when one exists; this does not automatically mean changing a Boolean value.", "Remove: Do not carry an Apple-removed or unsupported setting forward without a supported replacement.", "Preserve as Legacy: Keep vendor-defined or wildcard content in a configuration-profile wrapper.", "Review: BCU cannot safely choose the destination automatically.", "Metadata: Preserve identifiers, UUIDs, and descriptive values unless every related reference is rewritten together."])
            subsection("Resolve Before Continuing")
            paragraph("Action-needed settings provide Resolve Before Continuing. Each Decision is explained beside the choice and through hover help.")
            bullets(["Apply to Destination: Record an administrator-approved destination override. The Jamf source profile is never edited.", "Keep Source Value: Preserve the source value using a native destination when available or a configuration-profile wrapper otherwise.", "Review Later: Leave the recommendation unresolved. Dry Run may continue, but the finding remains visible for later review."])
            subsection("Native components and profile wrappers")
            paragraph("A native Blueprint or DDM component may be editable in the Jamf Blueprint GUI when Jamf exposes that component and property. API acceptance alone does not guarantee a GUI editor. If no native equivalent exists, BCU preserves the key in a configuration-profile wrapper. Wrapped keys may require BCU, replacement profile content, or API editing later.")
            note("A dry-run message saying a key was kept in a profile wrapper means the behavior was preserved as profile content; it did not become a native Jamf GUI control.")
            subsection("Before production deployment")
            warning("Verify on Review that every Apply to Destination decision changes the generated Blueprint JSON as intended. If the JSON does not change, treat the item as a recorded decision rather than an applied transformation.")
        case .workflow:
            heading("Conversion Workflow", "The phases executed for each profile")
            numbered([
                "Choose Computers or Mobile Devices and select a source profile.",
                "The app retrieves XML and payload content through the Platform profile gateway.",
                "blueprint-profile-convert reconstructs and converts the mobileconfig locally.",
                "Select a device group that matches the active device family.",
                "Review generated JSON, conversion mappings, and warnings.",
                "Choose create only, create and distribute, or create, distribute, and unscope.",
                "The app reports complete success, failure, or partial completion with the returned Blueprint ID and error snippet."
            ])
            note("Every destructive phase is gated. A creation failure prevents distribution. A distribution failure prevents source-profile modification.")

        case .takeover:
            heading("Profile Takeover Walkthrough", "Evaluate and import an existing profile safely")
            numbered([
                "Select a computer or mobile configuration profile and wait for its details to finish loading.",
                "Choose Profile Takeover in the GUI. The right pane changes to Blueprint Takeover.",
                "BCU automatically runs public jamf-cli import-profile with --dry-run. Automatic evaluation cannot create or modify a Blueprint.",
                "Review the supported, unsupported, or failed verdict and every reported reason.",
                "Choose whether to preserve the source scope or replace it with a selected Platform group.",
                "Use Re-evaluate after changing options. The Classic profile action remains Remain scoped.",
                "Create the takeover Blueprint only after the verdict and scope are correct.",
                "Verify device declaration status and settings on representative devices before changing the Classic profile."
            ])
            warning("An unsupported takeover can import alongside the Classic profile and may produce conflicting settings. The action button explicitly says Import Alongside Existing Profile in this state.")
        case .editor:
            heading("GUI and JSON Editor Walkthrough", "Edit one Blueprint through two synchronized views")
            numbered([
                "Choose GUI for guided fields or JSON for direct serialized editing.",
                "In GUI, edit the Blueprint name, description, first step name, and activation condition.",
                "Select or clear component checkboxes to control which standard-conversion components remain in steps[0].components.",
                "Choose Apply GUI Changes to JSON to serialize the guided changes.",
                "In JSON, edit advanced fields directly. Valid JSON refreshes the GUI model; invalid JSON keeps the last valid GUI values.",
                "Choose Reload from JSON after a manual JSON edit, or Format and Load GUI to validate and normalize the document.",
                "Review the Validation and Evaluation card before opening Deployment Review."
            ])
            note("Takeover identity and payload structure are generated by jamf-cli. The standard Blueprint editor does not rewrite identity-sensitive takeover payloads.")
        case .platform:
            heading("Platform API", "Connection and permissions")
            paragraph("Connections requires the regional Platform URL, client ID, client secret, and Platform Environment ID. The client secret is stored in macOS Keychain.")
            bullets([
                "OAuth token endpoint: /auth/token",
                "Mobile profiles: /proclassic/mobiledeviceconfigurationprofiles",
                "Computer profiles: /proclassic/osxconfigurationprofiles",
                "Platform groups: /device-groups/v1/device-groups",
                "Blueprint operations: /blueprints/v1/blueprints"
            ])
            subsection("Connection test")
            paragraph("The Platform test validates OAuth plus access to both computer and mobile configuration-profile collections. A successful token alone is not treated as a complete test.")
            subsection("Scope header")
            paragraph("The app sends X-Environment-Id for every scoped request using the configured Platform Environment ID.")

        case .cli:
            heading("jamf-cli", "How Jamf conversion code is used")
            paragraph("The application ships Jamf Concepts jamf-cli and a dedicated blueprint-profile-convert helper. The helper is compiled inside the Jamf CLI Go module so it can use internal/profileconvert directly.")
            bullets([
                "Helper location: inside the application bundle (Contents/Resources/bin)",
                "Bundled fallback location: the app's Contents/Resources/bin directory",
                "Passcode payloads can become com.jamf.ddm.passcode-settings.",
                "Supported Safari and software-update settings can become native DDM components.",
                "Compatible remaining payloads are wrapped in com.jamf.ddm-configuration-profile."
            ])
            subsection("Diagnostic tab")
            paragraph("Connections > jamf-cli runs only jamf-cli --version. The contained output shows the exact query, executable, stdout, stderr, exit code, and duration. The test sends no credentials and makes no API request.")
            subsection("Security")
            paragraph("Conversion uses a private temporary directory and mobileconfig file. Credentials are never passed to the helper. Temporary data is deleted after conversion.")

        case .payloads:
            heading("Payload Compatibility", "Native, legacy, and disabled payloads")
            paragraph("The converter promotes mappings supported by Jamf's profileconvert engine and filters payload types that Blueprints explicitly disables.")
            bullets([
                "Native mappings are emitted as dedicated DDM components.",
                "Compatible legacy payloads remain in the configuration-profile component.",
                "Disabled payloads are excluded and surfaced as conversion warnings.",
                "Examples of disabled payloads include com.apple.security.root, com.apple.security.pkcs1, and com.apple.vpn.managed.",
                "If no components remain after filtering, Blueprint creation is blocked and the source profile is not modified."
            ])
            warning("Review all conversion warnings before unscoping the source profile. An excluded payload is not deployed by the resulting Blueprint.")

        case .deployment:
            heading("Deployment and Unscoping", "Safe migration actions")
            bullets([
                "Create Blueprint Only creates the Blueprint and leaves distribution and the source profile unchanged.",
                "Create and Distribute Blueprint creates and deploys the Blueprint but leaves the source profile unchanged.",
                "Create and Distribute Blueprint and Unscope Configuration Profile deploys first, then clears source scope."
            ])
            subsection("Scope removal")
            paragraph("Unscoping sets all-device and all-user flags to false and clears devices, groups, buildings, departments, users, user groups, limitations, and exclusions. The Platform response may return empty self-closing or nested containers; verification checks semantic assignments rather than XML formatting.")
            subsection("Partial completion")
            paragraph("If the Blueprint was deployed but profile cleanup fails, the result is marked partially completed. The Blueprint is retained and the source profile is not reported as modified.")

        case .groups:
            heading("Device Groups", "Family-aware target selection")
            paragraph("The device-group picker is filtered by the selected source type.")
            bullets([
                "Computers shows confirmed computer or macOS groups only.",
                "Mobile Devices shows confirmed mobile, iOS, or iPadOS groups only.",
                "Switching device family clears incompatible selections.",
                "Automatic matching compares the source scope with compatible Platform groups.",
                "No Platform group matched is informational; select a compatible target manually."
            ])

        case .troubleshooting:
            heading("Troubleshooting", "Common failures and next steps")
            subsection("HTTP 400 configuration validation")
            paragraph("Inspect the reported component path and conversion warnings. Disabled or unsupported payloads must not remain in the legacy component.")
            subsection("No Platform group matched")
            paragraph("Choose a compatible target group manually. This message does not mean profile conversion or unscoping failed.")
            subsection("Profile cleanup verification")
            paragraph("The result includes active scope indicators and a bounded XML snippet only when an all-device flag or assigned object ID/name remains.")
            subsection("Diagnostic information")
            bullets([
                "Open Logs from the application menu.",
                "Use Connections > jamf-cli > Test jamf-cli.",
                "Include Platform trace IDs and the failed phase in support reports.",
                "Do not repeat a completed create-and-distribute operation solely to retry cleanup."
            ])

        case .updates:
            heading("Updates and Support", "GitHub release checks")
            paragraph("The app checks the latest release from github.com/jawheelr/Blueprint-Conversion-Utility on first launch and then no more than once every seven days. If a newer semantic version exists, an Update Available window shows release notes and opens the official GitHub release page.")
            bullets([
                "No update is installed silently.",
                "No GitHub credentials are required for public releases.",
                "Use Blueprint Conversion Utility > Check for Updates to run a manual check.",
                "A failed weekly background check is logged without blocking startup. The next automatic attempt occurs after the seven-day interval.",
                "Manual checks report whether the current version is up to date."
            ])
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
    }
    private func subsection(_ value: String) -> some View { Text(value).font(.title2.bold()) }
    private func paragraph(_ value: String) -> some View { Text(value).textSelection(.enabled) }
    private func bullets(_ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                HStack(alignment: .top) { Text("•").bold(); Text(value).textSelection(.enabled) }
            }
        }
    }
    private func numbered(_ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(alignment: .top) { Text("\(index + 1).").bold().frame(width: 24, alignment: .trailing); Text(value) }
            }
        }
    }
    private func note(_ value: String) -> some View {
        Label(value, systemImage: "info.circle.fill").padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func warning(_ value: String) -> some View {
        Label(value, systemImage: "exclamationmark.triangle.fill").padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func icon(for topic: KBTopic) -> String {
        switch topic {
        case .adminStart: return "checklist"
        case .overview: return "app.badge"
        case .workflow: return "arrow.triangle.2.circlepath"
        case .profileInspector: return "doc.text.magnifyingglass"
        case .takeover: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .editor: return "slider.horizontal.3"
        case .platform: return "network"
        case .cli: return "terminal"
        case .payloads: return "shippingbox"
        case .deployment: return "paperplane"
        case .groups: return "person.3"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .updates: return "arrow.down.circle"
        }
    }
}
