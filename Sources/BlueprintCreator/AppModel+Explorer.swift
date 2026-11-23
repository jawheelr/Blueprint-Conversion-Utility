import Foundation

/// Actions in the Blueprints Explorer that change Jamf and so need confirmation.
enum ExplorerAction: String, Identifiable {
    case save, saveAndDeploy, deploy, undeploy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .save: return "Save Changes"
        case .saveAndDeploy: return "Save and Deploy"
        case .deploy: return "Deploy Blueprint"
        case .undeploy: return "Undeploy Blueprint"
        }
    }

    var detail: String {
        switch self {
        case .save: return "The edited name, description, scope and steps replace the saved blueprint in Jamf. A deployed blueprint shows Out of date until it is deployed again."
        case .saveAndDeploy: return "The edits are saved and the blueprint is then deployed to its scoped groups right away."
        case .deploy: return "The blueprint is deployed to its scoped groups."
        case .undeploy: return "The blueprint is removed from its scoped devices."
        }
    }
}

extension AppModel {
    var explorerDirty: Bool {
        guard let draft = explorerDraft, let original = explorerOriginal else { return false }
        return !JSONTree.changedPaths(from: original, to: draft).isEmpty
    }

    var explorerChanges: [String] {
        guard let draft = explorerDraft, let original = explorerOriginal else { return [] }
        return JSONTree.changedPaths(from: original, to: draft)
    }

    var explorerSelectedState: String {
        guard let draft = explorerDraft else { return "UNKNOWN" }
        return ExplorerBlueprintSummary.deploymentState(in: draft)
    }

    func explorerValue(at path: [JSONPathStep]) -> Any? {
        guard let draft = explorerDraft else { return nil }
        return JSONTree.value(in: draft, at: path)
    }

    func explorerSet(_ value: Any, at path: [JSONPathStep]) {
        guard let draft = explorerDraft, let updated = JSONTree.setting(value, in: draft, at: path) as? [String: Any] else { return }
        explorerDraft = updated
    }

    func explorerRemove(at path: [JSONPathStep]) {
        guard let draft = explorerDraft, let updated = JSONTree.removing(in: draft, at: path) as? [String: Any] else { return }
        explorerDraft = updated
    }

    func resetExplorer() {
        explorerGeneration += 1
        showExplorer = false
        explorerBlueprints = []
        explorerSelectedID = nil
        explorerDraft = nil
        explorerOriginal = nil
        explorerLoading = false
        explorerWorking = false
        explorerMessage = nil
        explorerPendingAction = nil
    }

    func loadExplorerSchemaIfNeeded() {
        guard explorerSchema == nil else { return }
        Task {
            let catalog = await Task.detached { try? AppleSchemaService.load().0 }.value
            if let catalog { explorerSchema = catalog }
        }
    }

    func loadExplorerList() async {
        guard ready else { explorerMessage = "Configure and test the Platform API first."; return }
        guard !explorerLoading, !explorerWorking else { return }
        let generation = explorerGeneration
        explorerLoading = true
        explorerMessage = nil
        defer { if generation == explorerGeneration { explorerLoading = false } }
        do {
            let list = try await makePlatform().listBlueprints()
            guard generation == explorerGeneration else { return }
            explorerBlueprints = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            AppLogger.blueprint.notice("Explorer loaded \(list.count) blueprint(s)")
        } catch {
            guard generation == explorerGeneration else { return }
            explorerMessage = error.localizedDescription
            AppLogger.errors.error("Explorer list failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func openExplorerBlueprint(_ id: String) async {
        guard !explorerWorking else { return }
        let generation = explorerGeneration
        explorerWorking = true
        explorerMessage = nil
        defer { if generation == explorerGeneration { explorerWorking = false } }
        do {
            let object = try await fetchExplorerBlueprint(id)
            guard generation == explorerGeneration else { return }
            explorerSelectedID = id
            explorerDraft = object
            explorerOriginal = object
        } catch {
            guard generation == explorerGeneration else { return }
            explorerMessage = error.localizedDescription
            AppLogger.errors.error("Explorer open failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func fetchExplorerBlueprint(_ id: String) async throws -> [String: Any] {
        let data = try await makePlatform().blueprintJSON(id: id)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppFailure.message("Jamf returned a blueprint in an unexpected format.")
        }
        return object
    }

    func discardExplorerChanges() { explorerDraft = explorerOriginal }

    /// Problems that would make Jamf reject the blueprint or leave it unusable.
    func explorerProblems() -> [String] {
        guard let draft = explorerDraft else { return ["No blueprint is open."] }
        var problems: [String] = []
        if ((draft["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty { problems.append("The name cannot be empty.") }
        let groups = ((draft["scope"] as? [String: Any])?["deviceGroups"] as? [Any]) ?? []
        if groups.isEmpty { problems.append("Scope needs at least one device group.") }
        let steps = draft["steps"] as? [[String: Any]] ?? []
        if steps.isEmpty { problems.append("A blueprint needs at least one step.") }
        for (index, step) in steps.enumerated() {
            let components = step["components"] as? [Any] ?? []
            if components.isEmpty || components.count > 100 { problems.append("Step \(index + 1) needs between 1 and 100 components.") }
            if let predicate = step["activationPredicate"] as? String, predicate.count > ActivationPredicate.maxLength {
                problems.append("Step \(index + 1)'s activation condition is longer than \(ActivationPredicate.maxLength) characters.")
            }
            for (cIndex, component) in components.enumerated() {
                let item = component as? [String: Any]
                if ((item?["identifier"] as? String) ?? "").isEmpty { problems.append("Step \(index + 1), component \(cIndex + 1) has no identifier.") }
                if !(item?["configuration"] is [String: Any]) { problems.append("Step \(index + 1), component \(cIndex + 1) needs a configuration object.") }
            }
        }
        return problems
    }

    func requestExplorerAction(_ action: ExplorerAction) {
        guard !explorerWorking, explorerDraft != nil else { return }
        if action == .save || action == .saveAndDeploy {
            let problems = explorerProblems()
            guard problems.isEmpty else { explorerMessage = problems.joined(separator: "\n"); return }
        }
        if (action == .deploy), explorerDirty {
            explorerMessage = "Save or discard your changes before deploying."
            return
        }
        explorerPendingAction = action
    }

    func confirmExplorerAction() async {
        guard let action = explorerPendingAction, let id = explorerSelectedID, let draft = explorerDraft else { return }
        explorerPendingAction = nil
        guard !explorerWorking else { return }
        let generation = explorerGeneration
        explorerWorking = true
        explorerMessage = nil
        defer { if generation == explorerGeneration { explorerWorking = false } }
        var phase = "Preparing"
        do {
            let platform = try makePlatform()
            if action == .save || action == .saveAndDeploy {
                phase = "Checking for changes made in Jamf"
                let latest = try await fetchExplorerBlueprint(id)
                let opened = explorerOriginal?["updated"] as? String
                if let opened, let current = latest["updated"] as? String, opened != current {
                    throw AppFailure.message("This blueprint was changed in Jamf after you opened it. Reload it, then reapply your edits.")
                }
                phase = "Saving"
                var body: [String: Any] = [:]
                body["name"] = draft["name"]
                if let description = draft["description"] { body["description"] = description }
                body["scope"] = draft["scope"]
                body["steps"] = draft["steps"]
                try await platform.updateBlueprint(id: id, body: try JSONTree.data(body))
                AppLogger.blueprint.notice("Explorer saved a blueprint with \(self.explorerChanges.count) change(s)")
            }
            if action == .deploy || action == .saveAndDeploy {
                phase = "Deploying"
                try await platform.deployBlueprint(id: id)
            }
            if action == .undeploy {
                phase = "Undeploying"
                try await platform.undeployBlueprint(id: id)
            }
            phase = "Reading back the result"
            let target: String? = (action == .undeploy) ? "NOT_DEPLOYED" : (action == .save ? nil : "DEPLOYED")
            var fresh = try await fetchExplorerBlueprint(id)
            if let target {
                for delay: UInt64 in [2, 3, 5, 8, 12] {
                    if ExplorerBlueprintSummary.deploymentState(in: fresh).uppercased() == target { break }
                    try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    guard generation == explorerGeneration else { return }
                    fresh = try await fetchExplorerBlueprint(id)
                }
            }
            guard generation == explorerGeneration else { return }
            explorerDraft = fresh
            explorerOriginal = fresh
            explorerMessage = "\(action.title) finished. State: \(ExplorerBlueprintSummary(json: fresh)?.stateTitle ?? "Unknown")."
            if let summary = ExplorerBlueprintSummary(json: fresh) {
                if let index = explorerBlueprints.firstIndex(where: { $0.id == summary.id }) { explorerBlueprints[index] = summary }
            }
        } catch {
            guard generation == explorerGeneration else { return }
            explorerMessage = "\(phase) failed: \(error.localizedDescription)"
            AppLogger.errors.error("Explorer \(action.rawValue, privacy: .public) failed during \(phase, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
    }
}
