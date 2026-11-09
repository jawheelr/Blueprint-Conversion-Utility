import Foundation

actor TakeoverImportService {
    func detect(executable: URL) throws -> TakeoverCapabilities {
        let result = try run(executable, ["pro", "blueprints", "import-profile", "--help"], [:])
        let help = result.stdout + "\n" + result.stderr
        guard result.exitCode == 0, help.contains("import-profile") else { return TakeoverCapabilities() }
        return TakeoverCapabilities(
            commandAvailable: true,
            supportsConvert: help.contains("--convert"),
            supportsComputerGroups: help.contains("--computer-group"),
            supportsMobileGroups: help.contains("--mobile-device-group"),
            supportsSkipExclusions: help.contains("--skip-exclusions"),
            supportsSkipLimitations: help.contains("--skip-limitations"),
            supportsStripDefaults: help.contains("--strip-defaults"),
            supportsIncludeUnsupported: help.contains("--include-unsupported"),
            supportsTakeoverOnly: help.contains("--takeover-only"),
            supportsDeploy: help.contains("--deploy")
        )
    }

    func execute(
        executable: URL, profile: JamfProfile, mobile: Bool, blueprintName: String,
        importMode: ProfileImportMode, scopeMode: ImportScopeMode, group: DeviceGroup?,
        stripDefaults: Bool, skipExclusions: Bool, skipLimitations: Bool,
        includeUnsupported: Bool, dryRun: Bool, deploymentIntent: DeploymentIntent = .createOnly,
        settings: AppSettings, secret: String
    ) throws -> TakeoverImportResult {
        var args = ["pro", "blueprints", "import-profile", profile.id,
                    "--type", mobile ? "mobile" : "computer",
                    "--blueprint-name", blueprintName,
                    "--environment-id", settings.environmentID,
                    "--url", settings.platformURL,
                    "--no-input", "--no-update-check", "--no-color"]
        if importMode == .convert { args.append("--convert") }
        if stripDefaults { args.append("--strip-defaults") }
        if skipExclusions { args.append("--skip-exclusions") }
        if skipLimitations { args.append("--skip-limitations") }
        if includeUnsupported { args.append("--include-unsupported") }
        if dryRun { args.append("--dry-run") }
        if !dryRun && importMode == .preserveInstalled { args.append("--takeover-only") }
        if !dryRun && deploymentIntent.requestsDeployment { args.append("--deploy") }
        if scopeMode == .overrideSelected, let group {
            args += [mobile ? "--mobile-device-group" : "--computer-group", group.name]
        }
        let env = ["JAMF_CLIENT_ID": settings.platformClientID,
                   "JAMF_CLIENT_SECRET": secret,
                   "JAMF_ENVIRONMENT_ID": settings.environmentID,
                   "JAMF_URL": settings.platformURL,
                   "JAMF_CLI_NO_UPDATE_CHECK": "1", "JAMF_CLI_NO_HINTS": "1"]
        let result = try run(executable, args, env)
        let combined = result.stdout + "\n" + result.stderr
        let lower = combined.lowercased()
        let unsupportedTakeoverPhrases = ["takeover not supported", "takeover is not supported", "takeover is unsupported", "takeover not possible", "takeover is not possible", "cannot take over", "converting the profile rather than keeping it as installed"]
        let takeoverIsUnsupported = unsupportedTakeoverPhrases.contains { lower.contains($0) }
        let verdict: TakeoverVerdict
        if takeoverIsUnsupported { verdict = .unsupported }
        else if lower.contains("takeover supported") { verdict = .supported }
        else if result.exitCode != 0 { verdict = .failed }
        else if dryRun { verdict = .previewGenerated }
        else { verdict = .unknown }
        let lines = combined.split(separator: "\n").map(String.init)
        let messages = lines.filter { line in
            let value = line.lowercased()
            return value.contains("takeover supported") || unsupportedTakeoverPhrases.contains(where: { value.contains($0) }) || value.contains("refused") || value.contains("warning:")
        }
        let dropped = lines.filter { $0.lowercased().contains("dropped") || $0.lowercased().contains("discarded") }
        return TakeoverImportResult(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode, verdict: verdict, messages: messages, droppedKeys: dropped)
    }

    private func run(_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process(); let output = Pipe(); let errors = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = output; process.standardError = errors
        try process.run(); process.waitUntilExit()
        return (String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                process.terminationStatus)
    }
}
