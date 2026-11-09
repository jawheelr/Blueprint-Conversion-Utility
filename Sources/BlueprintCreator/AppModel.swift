import Foundation
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var platformSecret: String
    @Published var platformTested = false
    @Published var platformAuthenticationFailed = false
    @Published var platformCredentialHealth: PlatformCredentialHealth = .notConfigured
    @Published var profiles: [JamfProfile] = []
    @Published var groups: [DeviceGroup] = []
    @Published private(set) var allGroups: [DeviceGroup] = []
    @Published var groupsLoading = false
    @Published var groupsLoadError: String?
    @Published private(set) var groupsLoadingMore = false
    @Published private(set) var hasMoreGroups = false
    private var nextGroupPage = 0
    private let groupPageSize = 100
    @Published var conversionPlanSummary = "No conversion plan generated."
    @Published var conversionReady = false
    @Published var showSourceDispositionPrompt = false
    @Published var pendingDistributionChoice: SourceProfileDisposition?
    @Published var operationResult: OperationResult?
    @Published var showTakeoverUnscopeConfirmation = false
    @Published var takeoverUnscopeAcknowledged = false
    @Published var lastTakeoverDeploymentValidated = false
    @Published var lastTakeoverBlueprintID: String?
    @Published var selectedProfile: JamfProfile?
    @Published var selectedProfileID: String?
    @Published var loadingProfileID: String?
    @Published var selectedGroup: DeviceGroup?
    @Published var originalMatchedGroup: DeviceGroup?
    @Published var mobile = false
    @Published var json = "Configure and test the Platform API to begin."
    @Published var status = "Platform API connection is required."
    @Published var scopeNotice = ""
    @Published var busy = false
    @Published var runStage: BlueprintRunStage = .idle
    @Published var runDetail = "Ready to begin."
    @Published var completedRunStages: Set<BlueprintRunStage> = []
    @Published var alert: String?
    @Published var showConnections = false
    @Published var showAbout = false
    @Published var showKB = false
    @Published var showAppleSchema = false
    @Published var showProfileInspector = false
    @Published var profileInspection: ProfileInspectorDocument?
    @Published var profileInspectionError: String?
    @Published var profileInspectionLoading = false
    @Published var profileSettingOverrides: [String: ProfileSettingOverride] = [:]
    @Published var showLogs = false
    @Published var showDeploymentReview = false
    @Published var showUpdateAvailable = false
    @Published var editorMode: BlueprintEditorMode = .gui
    @Published var workflowMode: ProfileWorkflowMode = .takeover
    @Published var importMode: ProfileImportMode = .preserveInstalled
    @Published var importScopeMode: ImportScopeMode = .preserveSource
    @Published var takeoverCapabilities = TakeoverCapabilities()
    @Published var takeoverVerdict: TakeoverVerdict = .notEvaluated
    @Published var takeoverMessages: [String] = []
    @Published var takeoverRawOutput = ""
    @Published var takeoverStripDefaults = false
    @Published var takeoverSkipExclusions = false
    @Published var takeoverSkipLimitations = false
    @Published var takeoverIncludeUnsupported = false
    @Published var takeoverEvaluationState: TakeoverEvaluationState = .notEvaluated
    @Published var blueprintName = ""
    @Published var blueprintDescription = ""
    @Published var blueprintStepName = ""
    @Published var blueprintActivationCondition = ""
    @Published var blueprintComponents: [BlueprintComponentOption] = []
    @Published var blueprintEditableFields: [BlueprintEditableField] = []
    @Published var blueprintEditorSearch = ""
    @Published var showAdvancedImportOptions = false
    @Published var showTakeoverDetails = false
    @Published var dryRunEnabled = true
    @Published var deploymentIntent: DeploymentIntent = .createOnly
    @Published var showDeployAndUnscopeConfirmation = false
    @Published var deployAndUnscopeAcknowledged = false
    @Published var deploymentEligibility: DeploymentEligibility = .blocked(["Run Dry Run first."])
    @Published var recommendedApproach: RecommendedProfileApproach = .analyzing
    @Published var selectedApproach: RecommendedProfileApproach = .analyzing
    @Published private(set) var hasUserSelectedApproach = false
    @Published var recommendationReasons: [String] = ["Select a configuration profile."]
    @Published var recommendationIsAutomatic = true
    @Published var takeoverRecommendationTitle = "Select a profile"
    @Published var takeoverRecommendationDetail = "BCU will evaluate the profile and recommend the safest available workflow."
    @Published var jsonValidationMessage = "JSON is valid."
    private var takeoverEvaluationTask: Task<Void, Never>?
    @Published var availableUpdate: AppUpdate?
    @Published var updateDownloadInProgress = false
    @Published var updateDownloadStatus = ""
    @Published var unscopingAcknowledged = false
    @Published var conversionWarnings: [String] = []
    private let profileConvertService = ProfileConvertService()
    private let appUpdateService = AppUpdateService()
    private var profileLoadGeneration = 0

    var complete: Bool {
        !settings.platformURL.isEmpty &&
        !settings.platformClientID.isEmpty &&
        !platformSecret.isEmpty &&
        !settings.environmentID.isEmpty
    }
    var ready: Bool { complete && platformTested }


    private let takeoverService = TakeoverImportService()

    init() {
        LegacyIdentityMigration.runIfNeeded()
        if let data = UserDefaults.standard.data(forKey: "BlueprintCreator.Settings"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        platformSecret = KeychainStore.readSecret() ?? ""
        refreshPlatformCredentialHealth()
    }


    func launch() async {
        await detectTakeoverCapabilities()
        status = "Validating saved Platform API connection..."
        guard complete else {
            status = "Platform API configuration is incomplete."
            showConnections = true
            return
        }

        busy = true
        alert = nil
        platformTested = false
        defer { busy = false }
        do {
            try await makePlatform().test()
            try await makeSourceProfiles().test()
            platformTested = true
            platformAuthenticationFailed = false
            refreshPlatformCredentialHealth()
            showConnections = false
            status = "Platform API ready. Loading workspace..."
            await load()
        } catch {
            status = "Platform API connection test failed."
            platformAuthenticationFailed = true
            refreshPlatformCredentialHealth()
            alert = error.localizedDescription
            showConnections = true
        }
    }

    func save() throws {
        guard complete else {
            throw AppFailure.message(
                "Complete the Platform API URL, Client ID, Client Secret, and Platform Environment ID."
            )
        }
        try KeychainStore.saveSecret(platformSecret)
        UserDefaults.standard.set(
            try JSONEncoder().encode(settings),
            forKey: "BlueprintCreator.Settings"
        )
        status = ready ? "Platform API connection passed." : "Saved. Test the Platform API."
        AppLogger.connections.info("Platform API connection settings saved")
    }

    func testPlatform() async {
        busy = true
        status = "Testing Platform API and Platform profile gateway..."
        alert = nil
        defer { busy = false }
        do {
            try await makePlatform().test()
            try await makeSourceProfiles().test()
            platformTested = true
            platformAuthenticationFailed = false
            refreshPlatformCredentialHealth()
            status = "Platform API connection and configuration-profile access passed."
            AppLogger.connections.info("Platform API test passed")
        } catch {
            platformTested = false
            platformAuthenticationFailed = true
            refreshPlatformCredentialHealth()
            alert = error.localizedDescription
            status = "Platform API connection test failed."
            AppLogger.connections.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    func load() async {
        guard ready else { showConnections = true; return }

        // Groups must be ready before a selected profile's source scope is
        // evaluated so the Deployment picker can auto-select its target.
        await run("Loading Platform device groups...") {
            let firstPage = try await self.makePlatform().groups(page: 0, pageSize: self.groupPageSize)
            self.allGroups = firstPage.groups
            self.nextGroupPage = 1
            self.hasMoreGroups = firstPage.hasMore
            self.applyGroupFilter()
            let familyName = self.mobile ? "mobile" : "computer"
            AppLogger.groups.info(
                "Loaded \(self.allGroups.count) Platform groups; family=\(familyName, privacy: .public); compatible=\(self.groups.count)"
            )
        }
        guard alert == nil else { return }
        await refreshSelectedProfileType()
        if alert == nil {
            status = "Loaded \(profiles.count) profiles and \(groups.count) compatible groups."
        }
    }

    func refreshSelectedProfileType() async {
        guard ready else { showConnections = true; return }
        profileLoadGeneration += 1
        applyGroupFilter()
        selectedProfileID = nil
        loadingProfileID = nil
        selectedProfile = nil
        selectedGroup = nil
        originalMatchedGroup = nil
        profiles.removeAll()
        scopeNotice = ""
        json = "Loading configuration profiles..."
        await run(mobile ? "Loading mobile device profiles..." : "Loading computer profiles...") {
            self.profiles = try await self.makeSourceProfiles().profiles(mobile: self.mobile)
            AppLogger.profiles.info(
                "Profile list backend: Platform API /proclassic gateway"
            )
            AppLogger.profiles.info("Loaded \(self.profiles.count) profiles; mobile=\(self.mobile)")
        }
        if alert == nil {
            status = "Loaded \(profiles.count) \(mobile ? "mobile device" : "computer") profiles."
            json = "Select a configuration profile to generate a blueprint."
        }
    }

    func saveProfileSettingOverride(_ value: ProfileSettingOverride) {
        profileSettingOverrides[value.nodeID] = value
    }

    func removeProfileSettingOverride(nodeID: String) {
        profileSettingOverrides.removeValue(forKey: nodeID)
    }

    var unresolvedInspectorRecommendations: Int {
        guard let document = profileInspection else { return 0 }
        return document.payloads.reduce(0) { total, payload in
            total + countUnresolved(payload.nodes, payload: payload)
        }
    }

    private func countUnresolved(_ nodes: [ProfileInspectorNode], payload: ProfileInspectorPayload) -> Int {
        nodes.reduce(0) { total, node in
            let evaluation = SettingEvaluationService.evaluate(node, payload: payload)
            let requiresAction = evaluation.recommendation.priority >= SettingRecommendation.review.priority
            let resolved = profileSettingOverrides[node.id] != nil
            return total + (requiresAction && !resolved ? 1 : 0) + countUnresolved(node.children, payload: payload)
        }
    }

    private func buildProfileInspection(for profile: JamfProfile, generation: Int) {
        guard generation == profileLoadGeneration, selectedProfileID == profile.id else { return }
        do {
            let (catalog, _) = try AppleSchemaService.load()
            let document = ProfileParser(catalog: catalog).parse(profile)
            guard generation == profileLoadGeneration, selectedProfileID == profile.id else { return }
            profileInspection = document
            profileInspectionError = nil
            profileInspectionLoading = false
            AppLogger.profiles.info("Parsed profile inspector document; profile=\(profile.id, privacy: .public); payloads=\(document.payloadCount); settings=\(document.settingCount); unknown=\(document.unknownSettingCount)")
        } catch {
            profileInspection = nil
            profileInspectionError = error.localizedDescription
            profileInspectionLoading = false
            AppLogger.profiles.error("Profile inspector parse failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reloadCompatibleGroups() async {
        guard ready else { return }
        groupsLoading = true
        groupsLoadError = nil
        defer { groupsLoading = false }
        do {
            let firstPage = try await makePlatform().groups(page: 0, pageSize: groupPageSize)
            allGroups = firstPage.groups
            nextGroupPage = 1
            hasMoreGroups = firstPage.hasMore
            applyGroupFilter()
            status = "Loaded \(groups.count) compatible \(mobile ? "mobile-device" : "computer") groups."
        } catch {
            groupsLoadError = error.localizedDescription
            status = "Unable to load compatible groups."
        }
    }

    func loadMoreGroupsIfNeeded(currentGroup: DeviceGroup) async {
        guard hasMoreGroups,
              !groupsLoading,
              !groupsLoadingMore,
              let index = groups.firstIndex(where: { $0.id == currentGroup.id }),
              index >= max(0, groups.count - 10) else { return }

        groupsLoadingMore = true
        defer { groupsLoadingMore = false }
        do {
            let page = try await makePlatform().groups(page: nextGroupPage, pageSize: groupPageSize)
            let existingIDs = Set(allGroups.map(\.id))
            let additions = page.groups.filter { !existingIDs.contains($0.id) }
            allGroups.append(contentsOf: additions)
            nextGroupPage += 1
            hasMoreGroups = page.hasMore && !additions.isEmpty
            applyGroupFilter()
            status = hasMoreGroups
                ? "Loaded \(groups.count) compatible groups. Scroll for more."
                : "Loaded all \(groups.count) compatible groups."
        } catch {
            groupsLoadError = error.localizedDescription
            status = "Unable to load additional groups."
        }
    }

    func select(_ profile: JamfProfile) async {
        profileLoadGeneration += 1
        let generation = profileLoadGeneration
        let selectedID = profile.id

        // Retain the lightweight list object immediately so the row remains
        // highlighted while full profile details and conversion data load.
        takeoverEvaluationTask?.cancel()
        profileInspection = nil
        profileInspectionError = nil
        profileInspectionLoading = true
        profileSettingOverrides = [:]
        lastTakeoverDeploymentValidated = false
        lastTakeoverBlueprintID = nil
        takeoverUnscopeAcknowledged = false
        showTakeoverUnscopeConfirmation = false
        dryRunEnabled = true
        deploymentIntent = .createOnly
        deployAndUnscopeAcknowledged = false
        showDeployAndUnscopeConfirmation = false
        recommendedApproach = .analyzing
        selectedApproach = .analyzing
        hasUserSelectedApproach = false
        recommendationReasons = ["BCU is asking jamf-cli to discover the safest supported approach."]
        recommendationIsAutomatic = true
        takeoverVerdict = .notEvaluated
        takeoverMessages = []
        takeoverRawOutput = ""
        takeoverEvaluationState = .waiting
        runStage = .idle
        runDetail = "Analyzing Configuration Profile…\nProfile: \(profile.name)\nProfile ID: \(profile.id)"
        completedRunStages = []
        selectedGroup = nil
        selectedProfileID = selectedID
        selectedProfile = profile
        loadingProfileID = selectedID
        recommendedApproach = .analyzing
        selectedApproach = .analyzing
        hasUserSelectedApproach = false
        recommendationReasons = ["BCU is asking jamf-cli to discover the safest supported approach."]
        recommendationIsAutomatic = true
        conversionReady = false
        conversionPlanSummary = "Loading profile and conversion data..."
        json = "Loading and converting \(profile.name)..."
        status = "Loading \(profile.name)..."
        alert = nil

        do {
            let detail = try await makeSourceProfiles().profileDetail(
                profile,
                mobile: mobile
            )
            guard generation == profileLoadGeneration,
                  selectedProfileID == selectedID else { return }

            selectedProfile = detail
            applyScope(detail)
            await generateHybrid()
            buildProfileInspection(for: detail, generation: generation)
            workflowMode = takeoverCapabilities.commandAvailable ? .takeover : .standard
            if takeoverCapabilities.commandAvailable {
                scheduleAutomaticTakeoverEvaluation()
            } else {
                recommendedApproach = conversionReady ? .convert : .unavailable
                recommendationReasons = conversionReady
                    ? ["The bundled jamf-cli does not expose profile takeover; standard conversion is available."]
                    : ["No supported takeover or conversion path is currently available."]
            }
        } catch {
            guard generation == profileLoadGeneration,
                  selectedProfileID == selectedID else { return }
            profileInspectionLoading = false
            profileInspectionError = error.localizedDescription
            conversionReady = false
            conversionPlanSummary = "Unable to load profile."
            json = "Profile loading failed.\n\n\(error.localizedDescription)"
            status = "Unable to load \(profile.name)."
            alert = error.localizedDescription
            AppLogger.errors.error("\(error.localizedDescription, privacy: .public)")
        }

        if generation == profileLoadGeneration,
           selectedProfileID == selectedID {
            loadingProfileID = nil
        }
    }

    private func applyGroupFilter() {
        let expected: DeviceGroupFamily = mobile ? .mobile : .computer
        groups = allGroups.filter { $0.family == expected }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let selectedGroup, !groups.contains(where: { $0.id == selectedGroup.id }) {
            self.selectedGroup = nil
        }
    }

    private func applyScope(_ profile: JamfProfile) {
        AppLogger.profiles.info("Selected profile ID=\(profile.id, privacy: .public) name=\(profile.name, privacy: .public)")
        AppLogger.scope.info("Scope groups=\(profile.scope.groupNames.count) devices=\(profile.scope.individualDeviceCount) limitations=\(profile.scope.limitationCount) exclusions=\(profile.scope.exclusionCount)")

        let sourceGroups = profile.scope.groupNames
        let expectedFamily: DeviceGroupFamily = mobile ? .mobile : .computer
        let compatibleGroups = groups.filter { $0.family == expectedFamily }

        let exactMatch = compatibleGroups.first { candidate in
            sourceGroups.contains {
                $0.compare(candidate.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        let normalizedMatch = compatibleGroups.first { candidate in
            let candidateName = normalize(candidate.name)
            return sourceGroups.contains { normalize($0) == candidateName }
        }
        let match = exactMatch ?? normalizedMatch
        originalMatchedGroup = match
        selectedGroup = match

        if let match {
            let method = exactMatch != nil ? "exact name" : "normalized name"
            let sourceGroupSummary = sourceGroups.joined(separator: ", ")
            AppLogger.scope.info(
                "Matched source group to Platform group: source=\(sourceGroupSummary, privacy: .public), target=\(match.name, privacy: .public), family=\(expectedFamily.rawValue, privacy: .public), method=\(method, privacy: .public)"
            )
        }

        var messages: [String] = [
            "\(profile.name) (Profile ID \(profile.id)) — Scoped to: \(profile.scope.summary)"
        ]
        if !profile.scope.allDevices && profile.scope.groupNames.isEmpty && profile.scope.individualDeviceCount == 0 {
            messages.append("ⓘ Source profile has 0 associated devices and groups. Conversion is allowed; choose a Platform device group before submission.")
        }
        if let selectedGroup {
            messages.append("✓ Auto-selected matching group: \(selectedGroup.name)")
            AppLogger.scope.info("Auto-selected Platform group ID=\(selectedGroup.id, privacy: .public) name=\(selectedGroup.name, privacy: .public)")
        } else if !profile.scope.groupNames.isEmpty {
            messages.append("⚠ No Platform group matched the profile scope.")
            AppLogger.scope.warning("No Platform group matched profile ID=\(profile.id, privacy: .public)")
        }
        if profile.scope.individualDeviceCount == 1 {
            let deviceType = mobile ? "mobile device" : "computer"
            messages.append("⚠ Profile is scoped directly to 1 \(deviceType); direct device scope cannot be mapped to a Platform group.")
            AppLogger.scope.warning("Profile ID=\(profile.id, privacy: .public) is scoped directly to one \(deviceType, privacy: .public)")
        }
        scopeNotice = messages.joined(separator: "\n")
    }

    private func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let scalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        return scalars.joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    func evaluateDeploymentSafeguards() -> DeploymentEligibility {
        guard ready else { return .blocked(["API configuration is incomplete."]) }
        guard let profile = selectedProfile else { return .blocked(["Select a configuration profile."]) }
        if importScopeMode == .overrideSelected {
            guard let group = selectedGroup else { return .blocked(["Select a compatible Platform group."]) }
            let expected: DeviceGroupFamily = mobile ? .mobile : .computer
            guard group.family == expected else { return .blocked(["The selected group does not match the configuration profile family."]) }
        }
        // Dry Run establishes the takeover verdict. Requiring a Supported verdict
        // before Dry Run creates a circular gate and prevents evaluation entirely.
        // Only a real preserve-installed operation requires the prior Supported verdict.
        if !dryRunEnabled && workflowMode == .takeover && importMode == .preserveInstalled && takeoverVerdict != .supported {
            return .reevaluationRequired(["Run Dry-Run Preview and receive a current Takeover Supported verdict before creating or deploying."])
        }
        var review: [String] = []
        if profile.scope.individualDeviceCount > 0 { review.append("Direct-device assignments cannot be mapped automatically.") }
        if profile.scope.limitationCount > 0 { review.append("Profile limitations cannot be represented safely for automatic deployment.") }
        if profile.scope.exclusionCount > 0 && takeoverSkipExclusions { review.append("Exclusions were skipped and require review.") }
        if !profile.scope.allDevices && profile.scope.groupNames.isEmpty && profile.scope.individualDeviceCount == 0 && importScopeMode == .preserveSource { review.append("The source profile is unscoped.") }
        guard jsonValidationMessage.localizedCaseInsensitiveContains("invalid") == false else { return .blocked([jsonValidationMessage]) }
        return review.isEmpty ? .allowed : .createOnly(review)
    }

    func requestCreateDeployAndUnscope() {
        deploymentIntent = .createDeployAndUnscope
        deployAndUnscopeAcknowledged = false
        showDeployAndUnscopeConfirmation = true
    }

    func confirmCreateDeployAndUnscope() {
        guard deployAndUnscopeAcknowledged else {
            alert = "Acknowledge the deployment and unscoping safeguards before continuing."
            return
        }
        showDeployAndUnscopeConfirmation = false
        Task { await performGuidedFinalAction(deploymentIntent: .createDeployAndUnscope) }
    }

    func performGuidedFinalAction(deploymentIntent requestedIntent: DeploymentIntent? = nil) async {
        guard !busy else { return }
        guard ready else {
            alert = "Configure and test the required APIs before continuing."
            runStage = .failed; runDetail = "API configuration is incomplete."
            return
        }
        guard selectedProfile != nil else {
            alert = "Select a configuration profile first."
            runStage = .failed; runDetail = "No configuration profile is selected."
            return
        }

        deploymentIntent = requestedIntent ?? deploymentIntent
        deploymentEligibility = evaluateDeploymentSafeguards()
        guard deploymentEligibility.canCreate else {
            runStage = .failed
            runDetail = deploymentEligibility.reasons.joined(separator: "\n")
            alert = runDetail
            return
        }
        if deploymentIntent.requestsDeployment && !deploymentEligibility.canDeploy {
            runStage = .failed
            runDetail = "Automatic deployment is held for scope review. Create Only remains available.\n" + deploymentEligibility.reasons.joined(separator: "\n")
            alert = runDetail
            return
        }

        completedRunStages = []
        runStage = .validatingAPI
        runDetail = "Checking API configuration and credentials."
        completedRunStages.insert(.validatingAPI)

        if workflowMode == .takeover && takeoverCapabilities.commandAvailable {
            if importMode == .preserveInstalled && !dryRunEnabled && !takeoverCapabilities.supportsTakeoverOnly {
                runStage = .failed; runDetail = "The bundled jamf-cli does not expose --takeover-only."; alert = runDetail; return
            }
            if deploymentIntent.requestsDeployment && !takeoverCapabilities.supportsDeploy {
                runStage = .failed; runDetail = "The bundled jamf-cli does not expose --deploy."; alert = runDetail; return
            }
            runStage = .preparing
            runDetail = "Preparing the public jamf-cli import-profile operation."
            completedRunStages.insert(.preparing)
            runStage = .downloadingProfile
            runDetail = "jamf-cli is downloading and evaluating the selected configuration profile."
            await runTakeoverImport(dryRun: dryRunEnabled, automatic: false, deploymentIntent: deploymentIntent)

            if takeoverVerdict == .failed {
                runStage = .failed
                runDetail = takeoverMessages.first ?? "jamf-cli did not return a usable takeover result."
                return
            }
            if dryRunEnabled {
                completedRunStages.formUnion([.downloadingProfile, .resolvingScope, .processingPayloads, .evaluatingTakeover])
                runStage = .validatingJSON
                runDetail = "Validating the Blueprint result."
                if jsonValidationMessage.localizedCaseInsensitiveContains("invalid") {
                    runStage = .failed; runDetail = jsonValidationMessage; return
                }
                completedRunStages.insert(.validatingJSON)
                runStage = .completed
                runDetail = "Dry-run preview completed. No Blueprint was created."
            }
            // Real operations set their own completed/partial/failed result and must not be overwritten here.
            return
        }

        // Standard conversion uses BCU's conversion preflight, then opens the existing
        // deployment review for an explicit real creation choice.
        runStage = .downloadingProfile
        runDetail = "Loading and converting the selected configuration profile."
        busy = true
        await generateHybrid()
        busy = false
        guard conversionReady else {
            runStage = .failed
            runDetail = conversionPlanSummary
            return
        }
        completedRunStages.formUnion([.downloadingProfile, .resolvingScope, .processingPayloads, .generatingBlueprint])
        runStage = .validatingJSON
        runDetail = "Validating generated Blueprint JSON."
        guard !jsonValidationMessage.localizedCaseInsensitiveContains("invalid") else {
            runStage = .failed; runDetail = jsonValidationMessage; return
        }
        completedRunStages.insert(.validatingJSON)
        if dryRunEnabled {
            runStage = .completed
            runDetail = "Dry-run preview completed. No Blueprint was created."
        } else {
            runStage = .awaitingDeployment
            runDetail = "Choose how to create and distribute the Blueprint."
            requestCreate()
        }
    }

    func generate() { Task { await generateHybrid() } }
    private func generateHybrid() async {
        guard let profile = selectedProfile else { return }
        do {
            let result = try await profileConvertService.convert(profile)
            let components = (result.components ?? []).map(\.dictionary)
            guard !components.isEmpty else { throw AppFailure.message("profileconvert produced no components.") }
            conversionReady = true; conversionWarnings = result.warnings ?? []
            conversionPlanSummary = (result.conversions ?? []).isEmpty ? "jamf-cli profileconvert: legacy component ready" : (result.conversions ?? []).map { "jamf-cli profileconvert: \($0)" }.joined(separator: "\n")
            let name = result.displayName?.isEmpty == false ? result.displayName! : profile.name
            let object:[String:Any] = ["name":"\(name) (from Configuration Profile #\(profile.id))","description":profile.description.isEmpty ? "Converted from configuration profile ID \(profile.id)." : profile.description,"scope":["deviceGroups":selectedGroup.map{[$0.id]} ?? []],"steps":[["name":name,"components":components]]]
            let data=try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]);json=String(data:data,encoding:.utf8) ?? "";loadBlueprintGUIFromJSON();status="Hybrid jamf-cli conversion preflight passed."
        } catch { conversionReady=false;conversionPlanSummary="jamf-cli profileconvert failed: \(error.localizedDescription)";json="Conversion failed before Platform submission.\n\n\(error.localizedDescription)";status="Conversion failed." }
    }

    func requestTakeoverUnscopeReview() {
        guard lastTakeoverDeploymentValidated else {
            alert = "Unscoping is unavailable until Create and Deploy has been validated as DEPLOYED."
            return
        }
        takeoverUnscopeAcknowledged = false
        showTakeoverUnscopeConfirmation = true
    }

    func confirmTakeoverUnscope() {
        guard lastTakeoverDeploymentValidated else {
            alert = "Deployment validation is no longer current. Verify the Blueprint deployment before unscoping."
            showTakeoverUnscopeConfirmation = false
            return
        }
        guard takeoverUnscopeAcknowledged else {
            alert = "Confirm that takeover was verified on representative devices before unscoping the Classic Configuration Profile."
            return
        }
        guard let profile = selectedProfile else {
            alert = "Select the source Configuration Profile."
            showTakeoverUnscopeConfirmation = false
            return
        }
        showTakeoverUnscopeConfirmation = false
        Task { @MainActor in
            busy = true
            defer { busy = false }
            do {
                try await makeSourceProfiles().unscopeProfile(id: profile.id, mobile: mobile)
                operationResult = OperationResult(
                    title: "Classic Configuration Profile Unscoped",
                    details: "The Blueprint deployment was previously validated as DEPLOYED.\n\nConfiguration Profile: \(profile.name)\nProfile ID: \(profile.id)\nBlueprint ID: \(lastTakeoverBlueprintID ?? "Unknown")\n\nThe Classic Configuration Profile scope was removed only after explicit administrator confirmation."
                )
                status = "Classic Configuration Profile unscoped after explicit takeover confirmation."
                lastTakeoverDeploymentValidated = false
            } catch {
                operationResult = OperationResult(
                    title: "Configuration Profile Unscope Failed",
                    details: "The Blueprint was not changed.\n\nConfiguration Profile: \(profile.name)\nProfile ID: \(profile.id)\n\nError: \(error.localizedDescription)"
                )
            }
        }
    }

    func requestCreate() {
        guard ready, selectedProfile != nil else {
            alert = "Select a configuration profile first."
            return
        }
        guard conversionReady else {
            alert = "This profile contains payloads without a verified conversion strategy. Review the Conversion Plan."
            return
        }
        showDeploymentReview = true
    }

    func requestCreateDistributeAndUnscope() {
        pendingDistributionChoice = nil; showDeploymentReview = false; showSourceDispositionPrompt = false
        Task { @MainActor in try? await Task.sleep(nanoseconds: 250_000_000); self.showSourceDispositionPrompt = true }
    }

    func confirmSourceDisposition(_ disposition: SourceProfileDisposition) {
        pendingDistributionChoice = disposition; showSourceDispositionPrompt = false; showDeploymentReview = false
        Task { @MainActor in try? await Task.sleep(nanoseconds: 150_000_000); await self.performDeployment(.createDistributeAndUnscope) }
    }

    func performDeployment(_ choice: DeploymentChoice) async {
        guard conversionReady else { alert="Conversion is not ready.";return }; guard let profile=selectedProfile,selectedGroup != nil else { alert="Select a Platform device group.";return }
        if choice == .createDistributeAndUnscope && pendingDistributionChoice == nil { showSourceDispositionPrompt=true;return }
        showSourceDispositionPrompt=false;showDeploymentReview=false;busy=true;alert=nil;defer{busy=false}
        var blueprintID:String?;var created=false;var distributed=false;var sourceModified=false;var phase="Blueprint creation"
        do { await Task.yield();guard let data=json.data(using:.utf8) else{throw AppFailure.message("Invalid blueprint JSON.")};let platform=try makePlatform();blueprintID=try await platform.createBlueprint(data);created=true;if choice != .createOnly{phase="Blueprint distribution";try await platform.deployBlueprint(id:blueprintID!);distributed=true};if choice == .createDistributeAndUnscope{phase="Configuration profile update";switch pendingDistributionChoice{case .distributeToAll:try await makeSourceProfiles().unscopeProfile(id:profile.id,mobile:mobile);case .doNotDistribute:try await makeSourceProfiles().unscopeProfile(id:profile.id,mobile:mobile);case .none:throw AppFailure.message("No source profile action selected.")};sourceModified=true};pendingDistributionChoice=nil;operationResult=OperationResult(title:"Blueprint Operation Completed",details:"Blueprint created: Yes\nBlueprint ID: \(blueprintID ?? "Unknown")\nBlueprint distributed: \(distributed ? "Yes":"No")\nConfiguration profile modified: \(sourceModified ? "Yes":"No")")
        } catch { let snippet=String(error.localizedDescription.prefix(1800));operationResult=OperationResult(title:created && distributed ? "Blueprint Operation Partially Completed":"Blueprint Operation Failed",details:"Failed phase: \(phase)\nBlueprint created: \(created ? "Yes":"No")\nBlueprint ID: \(blueprintID ?? "Not created")\nBlueprint distributed: \(distributed ? "Yes":"No")\nConfiguration profile modified: \(sourceModified ? "Yes":"No")\n\nReturn log snippet:\n\(snippet)") }
    }

    private var bundledTakeoverCLI: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/jamf-cli")
    }

    func detectTakeoverCapabilities() async {
        do {
            takeoverCapabilities = try await takeoverService.detect(executable: bundledTakeoverCLI)
            workflowMode = takeoverCapabilities.commandAvailable ? .takeover : .standard
            AppLogger.connections.notice("Profile takeover capability=\(self.takeoverCapabilities.commandAvailable)")
        } catch {
            takeoverCapabilities = TakeoverCapabilities()
            workflowMode = .standard
            AppLogger.connections.error("Profile takeover capability check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var takeoverCommandPreview: String {
        guard let profile = selectedProfile else {
            return "Select a configuration profile to preview the command."
        }
        var parts = [
            "jamf-cli", "pro", "blueprints", "import-profile", profile.id,
            "--type", mobile ? "mobile" : "computer",
            "--blueprint-name", shellQuoted(profile.name)
        ]
        if importMode == .convert { parts.append("--convert") }
        if takeoverStripDefaults { parts.append("--strip-defaults") }
        if takeoverSkipExclusions { parts.append("--skip-exclusions") }
        if takeoverSkipLimitations { parts.append("--skip-limitations") }
        if takeoverIncludeUnsupported { parts.append("--include-unsupported") }
        if importScopeMode == .overrideSelected, let selectedGroup {
            parts.append(mobile ? "--mobile-device-group" : "--computer-group")
            parts.append(shellQuoted(selectedGroup.name))
        }
        parts.append(contentsOf: ["--environment-id", settings.environmentID, "--url", shellQuoted(settings.platformURL), "--no-input", "--no-update-check", "--no-color"])
        return parts.joined(separator: " ")
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\''") + "'"
    }

    private func applyAutomaticRecommendation(for verdict: TakeoverVerdict, messages: [String]) {
        var reasons = messages
        let recommendation: RecommendedProfileApproach
        switch verdict {
        case .supported:
            recommendation = .takeover
            if let profile = selectedProfile, profile.scope.groupNames.isEmpty && selectedGroup == nil { reasons.insert("Takeover is supported. Choose a compatible target group before deployment.", at: 0) } else { reasons.insert("jamf-cli reports that the installed profile can be adopted without reinstalling it.", at: 0) }
        case .unsupported:
            recommendation = conversionReady ? .convert : .createForReview
            reasons.insert(conversionReady ? "jamf-cli determined that the installed profile cannot be taken over. Conversion is the safest available path." : "Takeover is not supported and conversion requires administrator review.", at: 0)
        case .previewGenerated, .unknown:
            recommendation = .evaluationIncomplete
            reasons.insert("jamf-cli processed the profile but did not return a recognizable final takeover verdict.", at: 0)
        case .failed:
            let concreteFailure = messages.contains { m in let v=m.lowercased(); return v.contains("http") || v.contains("authentication") || v.contains("failed") || v.contains("invalid") || v.contains("not found") || v.contains("error") }
            recommendation = concreteFailure ? .unavailable : .evaluationIncomplete
            if !concreteFailure { reasons.insert("Profile discovery completed without a final supported/unsupported verdict.", at: 0) }
        case .notEvaluated: recommendation = .analyzing; reasons = ["Waiting for jamf-cli discovery."]
        }
        recommendedApproach = recommendation
        recommendationReasons = reasons.isEmpty ? [recommendation.title] : Array(reasons.prefix(6))
        if !hasUserSelectedApproach { applySelectedApproach(recommendation, automatic: true) }
    }
    private func applySelectedApproach(_ approach: RecommendedProfileApproach, automatic: Bool) {
        selectedApproach = approach; recommendationIsAutomatic = automatic
        switch approach {
        case .takeover: workflowMode = .takeover; importMode = .preserveInstalled
        case .convert: workflowMode = takeoverCapabilities.commandAvailable ? .takeover : .standard; importMode = .convert
        case .createForReview: workflowMode = .standard
        default: break
        }
    }
    func useManualApproach(_ approach: RecommendedProfileApproach) {
        hasUserSelectedApproach = true
        applySelectedApproach(approach, automatic: false)
        scheduleAutomaticTakeoverEvaluation()
    }

    func scheduleAutomaticTakeoverEvaluation() {
        takeoverEvaluationTask?.cancel()
        takeoverVerdict = .notEvaluated
        takeoverMessages = []
        takeoverRawOutput = ""
        guard workflowMode == .takeover,
              takeoverCapabilities.commandAvailable,
              selectedProfile != nil else {
            takeoverEvaluationState = .notEvaluated
            return
        }
        if let profile = selectedProfile {
            if profile.scope.groupNames.isEmpty && selectedGroup == nil {
                importScopeMode = .overrideSelected
                takeoverRecommendationTitle = "Analyzing profile; target group required for deployment"
                takeoverRecommendationDetail = "Compatibility discovery will continue. Choose a compatible Platform group before Create and Deploy."
            }
            takeoverRecommendationTitle = importMode == .preserveInstalled ? "Recommended: Attempt takeover" : "Converted import selected"
            takeoverRecommendationDetail = importMode == .preserveInstalled
                ? "jamf-cli will first preserve the profile as installed and automatically fall back only when takeover is not possible."
                : "The profile will be converted to native DDM components where possible and cannot take over the installed profile."
        }
        guard dryRunEnabled else {
            takeoverEvaluationState = .notEvaluated
            status = "Dry Run is off. Review the recommendation, then run the create action explicitly."
            return
        }
        recommendedApproach = .analyzing
        recommendationReasons = ["Discovering payload compatibility, scope, and takeover support with jamf-cli."]
        takeoverEvaluationState = .waiting
        let scheduledProfileID = selectedProfileID
        let scheduledGeneration = profileLoadGeneration
        if let profile = selectedProfile { runDetail = "Analyzing Configuration Profile…\nProfile: \(profile.name)\nProfile ID: \(profile.id)" }
        takeoverEvaluationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, self.selectedProfileID == scheduledProfileID, self.profileLoadGeneration == scheduledGeneration else { return }
            await self.runTakeoverImport(dryRun: true, automatic: true)
        }
    }

    private func balancedJSONObjects(in text: String) -> [[String: Any]] {
        let characters = Array(text)
        var results: [[String: Any]] = []
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false
        for index in characters.indices {
            let c = characters[index]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; continue }
            if c == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if c == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    let candidate = String(characters[objectStart...index])
                    if let data = candidate.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results.append(object)
                    }
                    start = nil
                }
            }
        }
        return results
    }

    private func validatedTakeoverCompletion(
        result: TakeoverImportResult,
        profile: JamfProfile,
        deploymentIntent: DeploymentIntent
    ) async throws -> OperationResult {
        let combined = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        var blueprintID: String?
        var deploymentState: String?
        var created = false

        // Extract complete balanced JSON objects even when logs precede or follow JSON.
        for object in balancedJSONObjects(in: combined) {
            let candidateID = object["id"] as? String ?? object["blueprintId"] as? String
            guard candidateID != nil else { continue }
            blueprintID = candidateID
            if let state = object["deploymentState"] as? [String: Any] {
                deploymentState = state["state"] as? String
            }
            created = true
            break
        }

        // Fall back to explicit success output when the CLI does not emit a parseable object.
        if !created {
            let lower = combined.lowercased()
            created = result.exitCode == 0 && (lower.contains("blueprint created") || lower.contains("created blueprint") || lower.contains("takeover supported"))
        }

        guard result.exitCode == 0, created else {
            throw AppFailure.message("jamf-cli exited without a verifiable Blueprint creation result.")
        }

        let requestedDeployment = deploymentIntent.requestsDeployment
        var finalDeploymentState = deploymentState?.uppercased()
        var validationSource = "jamf-cli response"

        if requestedDeployment, finalDeploymentState != "DEPLOYED", let blueprintID {
            runStage = .awaitingDeployment
            runDetail = "Blueprint created. Waiting for Jamf Platform to report DEPLOYED."
            status = "Blueprint created. Deployment validation is in progress."
            let delays: [UInt64] = [2, 3, 5, 8, 12, 15]
            for delay in delays {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard selectedProfileID == profile.id else {
                    throw AppFailure.message("The selected Configuration Profile changed during deployment validation.")
                }
                do {
                    if let state = try await makePlatform().blueprintDeploymentState(id: blueprintID) {
                        finalDeploymentState = state.uppercased()
                        validationSource = "Jamf Platform API read-back"
                        runDetail = "Deployment validation: \(finalDeploymentState ?? "UNKNOWN")"
                        if finalDeploymentState == "DEPLOYED" { break }
                        if ["DEPLOYMENT_FAILED", "FAILED", "ERROR"].contains(finalDeploymentState ?? "") { break }
                    }
                } catch {
                    validationSource = "Jamf Platform API read-back unavailable: \(error.localizedDescription)"
                }
            }
        }

        let dropped = result.droppedKeys.isEmpty ? "None reported" : result.droppedKeys.joined(separator: "\n• ")
        let deploymentValidated = !requestedDeployment || finalDeploymentState == "DEPLOYED"
        let validationSummary: String
        if !requestedDeployment {
            validationSummary = "Validated: Blueprint created. Deployment was not requested."
        } else if deploymentValidated {
            validationSummary = "Validated: Blueprint created and Jamf Platform reports DEPLOYED."
        } else if ["DEPLOYMENT_FAILED", "FAILED", "ERROR"].contains(finalDeploymentState ?? "") {
            validationSummary = "Partial completion: Blueprint created, but Jamf reported deployment failure."
        } else {
            validationSummary = "Partial completion: Blueprint created; deployment verification is incomplete."
        }
        let details = """
        \(validationSummary)

        Configuration Profile: \(profile.name)
        Profile ID: \(profile.id)
        Blueprint ID: \(blueprintID ?? "Not returned by jamf-cli")
        Deployment requested: \(requestedDeployment ? "Yes" : "No")
        Deployment state: \(finalDeploymentState ?? (requestedDeployment ? "VALIDATION_INCOMPLETE" : "Not requested"))
        Validation source: \(validationSource)
        Takeover verdict: \(result.verdict.title)
        Classic Configuration Profile: Remains scoped
        Dropped keys: \(dropped)
        """
        return OperationResult(
            title: requestedDeployment
                ? (deploymentValidated ? "Blueprint Created and Deployed" : "Blueprint Created - Deployment Verification Incomplete")
                : "Blueprint Created",
            details: details
        )
    }

    func runTakeoverImport(dryRun: Bool, automatic: Bool = false, deploymentIntent: DeploymentIntent = .createOnly) async {
        guard takeoverCapabilities.commandAvailable else { if !automatic { alert = "The public jamf-cli does not support pro blueprints import-profile." }; return }
        guard let profile = selectedProfile else { if !automatic { alert = "Select a configuration profile." }; return }
        let evaluatedProfileID = profile.id
        let evaluatedGeneration = profileLoadGeneration
        if !dryRun && importScopeMode == .overrideSelected && selectedGroup == nil { if !automatic { alert = "Select a Platform device group before creating or deploying." }; return }
        takeoverEvaluationState = .evaluating
        if !dryRun {
            runStage = .creatingBlueprint
            runDetail = deploymentIntent.requestsDeployment
                ? "Creating and deploying the takeover Blueprint."
                : "Creating the takeover Blueprint."
        }
        busy = true; if !automatic { alert = nil }; status = dryRun ? "Evaluating profile takeover..." : "Creating imported profile Blueprint..."
        defer { busy = false }
        do {
            let result = try await takeoverService.execute(
                executable: bundledTakeoverCLI, profile: profile, mobile: mobile,
                blueprintName: blueprintName.isEmpty ? profile.name : blueprintName, importMode: importMode,
                scopeMode: importScopeMode, group: selectedGroup,
                stripDefaults: takeoverStripDefaults, skipExclusions: takeoverSkipExclusions,
                skipLimitations: takeoverSkipLimitations, includeUnsupported: takeoverIncludeUnsupported,
                dryRun: dryRun, deploymentIntent: deploymentIntent, settings: settings, secret: platformSecret
            )
            guard !Task.isCancelled, selectedProfileID == evaluatedProfileID, profileLoadGeneration == evaluatedGeneration else { return }
            takeoverVerdict = result.verdict
            takeoverMessages = Array(Set(result.messages + result.droppedKeys)).sorted()
            takeoverRawOutput = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            applyAutomaticRecommendation(for: result.verdict, messages: takeoverMessages)
            switch result.verdict {
            case .supported:
                takeoverEvaluationState = .supported
                takeoverRecommendationTitle = "Recommended: Create takeover Blueprint"
                takeoverRecommendationDetail = "jamf-cli reports that the existing installed profile can be adopted without reinstalling it."
            case .unsupported:
                takeoverEvaluationState = .unsupported
                takeoverRecommendationTitle = "Recommended: Review before importing"
                takeoverRecommendationDetail = "Takeover is not supported. Importing can install alongside the Classic profile, so review the reported reasons before continuing."
            case .failed: takeoverEvaluationState = .failed(result.stderr.isEmpty ? result.stdout : result.stderr)
            default: takeoverEvaluationState = dryRun ? .unsupported : .notEvaluated
            }
            let targetGroupValue: Any = selectedGroup?.name ?? NSNull()
            let plan: [String: Any] = [
                "operation": "pro blueprints import-profile", "profileId": profile.id,
                "profileName": profile.name, "profileType": mobile ? "mobile" : "computer",
                "blueprintName": blueprintName.isEmpty ? profile.name : blueprintName,
                "mode": importMode.rawValue, "scopeMode": importScopeMode.rawValue,
                "targetGroup": targetGroupValue, "sourceProfileAction": "remain-scoped",
                "stripDefaults": takeoverStripDefaults, "skipExclusions": takeoverSkipExclusions,
                "skipLimitations": takeoverSkipLimitations, "includeUnsupported": takeoverIncludeUnsupported,
                "dryRun": dryRun, "takeoverVerdict": result.verdict.title,
                "messages": result.messages, "droppedKeys": result.droppedKeys, "rawOutput": takeoverRawOutput
            ]
            if let data = try? JSONSerialization.data(withJSONObject: plan, options: [.prettyPrinted, .sortedKeys]) { json = String(data: data, encoding: .utf8) ?? takeoverRawOutput }
            if dryRun {
                let hasUsableVerdict = result.verdict == .supported || result.verdict == .unsupported
                if result.exitCode != 0 && !hasUsableVerdict { throw AppFailure.message(result.stderr.isEmpty ? result.stdout : result.stderr) }
            } else if result.exitCode != 0 {
                throw AppFailure.message(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
            if !dryRun {
                let completion = try await validatedTakeoverCompletion(
                    result: result,
                    profile: profile,
                    deploymentIntent: deploymentIntent
                )
                operationResult = completion
                if deploymentIntent.requestsDeployment {
                    lastTakeoverDeploymentValidated = completion.title == "Blueprint Created and Deployed"
                    // Extracted ID is included in completion details; keep a compact reference when available.
                    let combinedOutput = [result.stdout, result.stderr].joined(separator: "\n")
                    if let match = combinedOutput.range(of: #""id"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                        let fragment = String(combinedOutput[match])
                        lastTakeoverBlueprintID = fragment.split(separator: "\"").dropFirst().dropFirst().first.map(String.init)
                    }
                } else {
                    lastTakeoverDeploymentValidated = false
                    lastTakeoverBlueprintID = nil
                }
                if deploymentIntent.requestsUnscope {
                    guard lastTakeoverDeploymentValidated else {
                        operationResult = OperationResult(
                            title: "Blueprint Created - Unscope Not Performed",
                            details: completion.details + "\n\nThe Classic Configuration Profile remains scoped because deployment was not validated as DEPLOYED."
                        )
                        runStage = .completed
                        runDetail = "Blueprint created; unscoping was not performed."
                        return
                    }
                    do {
                        try await makeSourceProfiles().unscopeProfile(id: profile.id, mobile: mobile)
                        operationResult = OperationResult(
                            title: "Blueprint Created, Deployed, and Profile Unscoped",
                            details: completion.details + "\n\nClassic Configuration Profile scope: Removed after explicit administrator confirmation."
                        )
                        lastTakeoverDeploymentValidated = false
                    } catch {
                        operationResult = OperationResult(
                            title: "Blueprint Deployed - Profile Unscope Failed",
                            details: completion.details + "\n\nThe Blueprint remains deployed. The Classic Configuration Profile could not be unscoped.\nError: \(error.localizedDescription)"
                        )
                    }
                }
                completedRunStages.insert(.creatingBlueprint)
                if deploymentIntent.requestsDeployment { completedRunStages.insert(.awaitingDeployment) }
                runStage = .completed
                runDetail = completion.title
            }
            status = dryRun ? "Takeover evaluation completed." : (operationResult?.title ?? "Profile Blueprint operation completed.")
        } catch {
            let detail = error.localizedDescription
            takeoverVerdict = .failed
            takeoverMessages = [detail]
            takeoverEvaluationState = .failed(detail)
            applyAutomaticRecommendation(for: .failed, messages: [detail])
            if !automatic && recommendedApproach == .unavailable { alert = detail }
            status = recommendedApproach == .evaluationIncomplete
                ? "Profile analysis was incomplete. Review jamf-cli Activity or retry."
                : "Takeover operation failed. Classic profile was not modified."
        }
    }

    func loadBlueprintGUIFromJSON() {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            jsonValidationMessage = "JSON is invalid. GUI retains the last valid values."
            return
        }
        blueprintName = object["name"] as? String ?? blueprintName
        blueprintDescription = object["description"] as? String ?? blueprintDescription
        if let step = (object["steps"] as? [[String: Any]])?.first {
            blueprintStepName = step["name"] as? String ?? blueprintStepName
            blueprintActivationCondition = step["activationCondition"] as? String ?? ""
            blueprintComponents = (step["components"] as? [[String: Any]] ?? []).enumerated().map { index, value in
                BlueprintComponentOption(index: index, identifier: value["identifier"] as? String ?? "Component \(index + 1)", included: true)
            }
        }
        blueprintEditableFields = flattenEditableFields(object)
        jsonValidationMessage = "JSON is valid."
    }

    private func flattenEditableFields(_ value: Any, path: String = "") -> [BlueprintEditableField] {
        var result: [BlueprintEditableField] = []
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if ["name", "description", "steps"].contains(key) && path.isEmpty { continue }
                result += flattenEditableFields(dictionary[key] as Any, path: childPath)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                result += flattenEditableFields(child, path: "\(path)[\(index)]")
            }
        } else if let boolean = value as? Bool {
            result.append(BlueprintEditableField(path: path, label: path.components(separatedBy: ".").last ?? path, kind: .boolean, value: boolean ? "true" : "false"))
        } else if value is NSNull {
            result.append(BlueprintEditableField(path: path, label: path.components(separatedBy: ".").last ?? path, kind: .null, value: "null"))
        } else if let number = value as? NSNumber {
            result.append(BlueprintEditableField(path: path, label: path.components(separatedBy: ".").last ?? path, kind: .number, value: number.stringValue))
        } else if let text = value as? String {
            result.append(BlueprintEditableField(path: path, label: path.components(separatedBy: ".").last ?? path, kind: .text, value: text))
        }
        return result
    }

    func updateEditableField(_ field: BlueprintEditableField) {
        guard let data = json.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) else {
            jsonValidationMessage = "Fix the JSON before applying field changes."
            return
        }
        let converted: Any
        switch field.kind {
        case .boolean: converted = field.value == "true"
        case .number: converted = Double(field.value) ?? 0
        case .null: converted = NSNull()
        case .text: converted = field.value
        }
        setJSONValue(&object, path: field.path, value: converted)
        guard let updated = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        json = String(data: updated, encoding: .utf8) ?? json
        loadBlueprintGUIFromJSON()
    }

    private func setJSONValue(_ root: inout Any, path: String, value: Any) {
        let tokens = path.replacingOccurrences(of: "]", with: "").split(whereSeparator: { $0 == "." || $0 == "[" }).map(String.init)
        setJSONValueRecursive(&root, tokens: tokens[...], value: value)
    }

    private func setJSONValueRecursive(_ node: inout Any, tokens: ArraySlice<String>, value: Any) {
        guard let first = tokens.first else { node = value; return }
        let rest = tokens.dropFirst()
        if var dictionary = node as? [String: Any] {
            var child = dictionary[first] ?? NSNull()
            setJSONValueRecursive(&child, tokens: rest, value: value)
            dictionary[first] = child
            node = dictionary
        } else if var array = node as? [Any], let index = Int(first), array.indices.contains(index) {
            var child = array[index]
            setJSONValueRecursive(&child, tokens: rest, value: value)
            array[index] = child
            node = array
        }
    }

    func applyBlueprintGUIToJSON() {
        guard let data = json.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            jsonValidationMessage = "Fix the JSON before applying GUI changes."
            return
        }
        object["name"] = blueprintName
        object["description"] = blueprintDescription
        if var steps = object["steps"] as? [[String: Any]], !steps.isEmpty {
            steps[0]["name"] = blueprintStepName
            if blueprintActivationCondition.isEmpty { steps[0].removeValue(forKey: "activationCondition") }
            else { steps[0]["activationCondition"] = blueprintActivationCondition }
            if let components = steps[0]["components"] as? [[String: Any]] {
                let included = Set(blueprintComponents.filter { $0.included }.map { $0.index })
                steps[0]["components"] = components.enumerated().filter { included.contains($0.offset) }.map { $0.element }
            }
            object["steps"] = steps
        }
        guard let updated = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        json = String(data: updated, encoding: .utf8) ?? json
        jsonValidationMessage = "GUI changes applied to JSON."
    }

    private func makeSourceProfiles() throws -> PlatformProfileClient {
        try PlatformProfileClient(
            url: settings.platformURL,
            clientID: settings.platformClientID,
            clientSecret: platformSecret,
            environmentID: settings.environmentID
        )
    }


    private func makePlatform() throws -> PlatformClient {
        try PlatformClient(
            url: settings.platformURL,
            clientID: settings.platformClientID,
            clientSecret: platformSecret,
            environmentID: settings.environmentID
        )
    }

    func refreshPlatformCredentialHealth(now: Date = Date()) {
        platformCredentialHealth = PlatformCredentialEvaluator.evaluate(
            expirationDate: settings.integrationExpirationDate,
            warningDays: settings.expiryWarningDays,
            authenticationPassed: platformTested,
            authenticationFailed: platformAuthenticationFailed,
            now: now
        )
    }

    var credentialHealthText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        switch platformCredentialHealth {
        case .notConfigured:
            return settings.integrationExpirationDate == nil
                ? "Credential expiration date not configured"
                : "Credential expiration configured; test Platform API"
        case let .valid(days, date):
            return "Platform credentials expire \(formatter.string(from: date)) · \(days) days remaining"
        case let .expiringSoon(days, date):
            return "Platform credentials expire soon · \(formatter.string(from: date)) · \(days) days remaining"
        case let .expired(_, date):
            return "Platform credentials expired · \(formatter.string(from: date))"
        case .authenticationFailed:
            return "Platform credentials invalid · Authentication failed"
        }
    }

    func checkForAppUpdatesIfDue() async {
        let defaults = UserDefaults.standard
        let now = Date()
        let lastSuccess = defaults.object(
            forKey: "BlueprintCreator.LastSuccessfulAppUpdateCheck"
        ) as? Date
        let lastAttempt = defaults.object(
            forKey: "BlueprintCreator.LastAppUpdateCheckAttempt"
        ) as? Date
        let successInterval: TimeInterval = 7 * 24 * 60 * 60
        let failureInterval: TimeInterval = 24 * 60 * 60

        if let lastSuccess,
           now.timeIntervalSince(lastSuccess) < successInterval {
            return
        }
        if let lastAttempt,
           now.timeIntervalSince(lastAttempt) < failureInterval {
            return
        }
        await checkForAppUpdates(manual: false)
    }

    func checkForAppUpdates(manual: Bool) async {
        let defaults = UserDefaults.standard
        let attemptKey = "BlueprintCreator.LastAppUpdateCheckAttempt"
        let successKey = "BlueprintCreator.LastSuccessfulAppUpdateCheck"
        defaults.set(Date(), forKey: attemptKey)

        let current = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        do {
            let update = try await appUpdateService.check(currentVersion: current)
            defaults.set(Date(), forKey: successKey)
            if let update {
                availableUpdate = update
                showUpdateAvailable = true
                AppLogger.connections.notice(
                    "Application update available: current=\(current, privacy: .public), latest=\(update.latestVersion, privacy: .public)"
                )
            } else if manual {
                alert = "Blueprint Conversion Utility \(current) is up to date."
            }
        } catch {
            AppLogger.connections.error(
                "Application update check failed: \(error.localizedDescription, privacy: .public)"
            )
            if manual {
                alert = "Unable to check for updates right now.\n\nThe GitHub Releases page or network connection may be unavailable. Please try again later."
            }
        }
    }

    func downloadAndInstallAvailableUpdate() async {
        guard let update = availableUpdate else { return }
        updateDownloadInProgress = true
        updateDownloadStatus = "Downloading \(update.packageURL.lastPathComponent)..."
        defer { updateDownloadInProgress = false }

        do {
            let packageURL = try await appUpdateService.downloadPackage(for: update)
            updateDownloadStatus = "Opening macOS Installer..."
            let opened = NSWorkspace.shared.open(packageURL)
            guard opened else {
                throw AppFailure.message(
                    "The package was downloaded, but macOS Installer could not be opened. Package: \(packageURL.path)"
                )
            }
            try launchUpdateRelaunchMonitor(
                applicationURL: Bundle.main.bundleURL,
                installedVersion: update.currentVersion
            )
            AppLogger.connections.notice(
                "Downloaded update package to \(packageURL.path, privacy: .public), opened macOS Installer, and started the relaunch monitor"
            )
            showUpdateAvailable = false
            updateDownloadStatus = "Installer opened. The app will close and relaunch after the update is applied."

            // Give SwiftUI enough time to commit the final status and start the
            // detached monitor before terminating the current application.
            try? await Task.sleep(nanoseconds: 400_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            updateDownloadStatus = "Update download failed."
            alert = error.localizedDescription
            AppLogger.connections.error(
                "Application update download failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func launchUpdateRelaunchMonitor(
        applicationURL: URL,
        installedVersion: String
    ) throws {
        let script = #"""
        app="$1"
        old_version="$2"
        deadline=$(( $(date +%s) + 1800 ))

        while [ "$(date +%s)" -lt "$deadline" ]; do
            if [ -d "$app" ]; then
                new_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)
                if [ -n "$new_version" ] && [ "$new_version" != "$old_version" ]; then
                    /usr/bin/open "$app"
                    exit 0
                fi
            fi
            /bin/sleep 2
        done
        exit 1
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "update-relaunch-monitor",
            applicationURL.path, installedVersion
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func run(_ message: String,
                     operation: @escaping @MainActor () async throws -> Void) async {
        busy = true
        status = message
        alert = nil
        defer { busy = false }
        do { try await operation() }
        catch {
            alert = error.localizedDescription
            status = "Operation failed."
            AppLogger.errors.error("\(error.localizedDescription, privacy: .public)")
        }
    }
}
