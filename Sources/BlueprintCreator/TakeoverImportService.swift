import Foundation

actor TakeoverImportService {
    func detect(executable: URL) async throws -> TakeoverCapabilities {
        let result = try await run(executable, ["pro", "blueprints", "import-profile", "--help"], [:], timeout: 30)
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
    ) async throws -> TakeoverImportResult {
        var args = ["pro", "blueprints", "import-profile", profile.id,
                    "--type", mobile ? "mobile" : "computer",
                    "--blueprint-name", blueprintName,
                    "--environment-id", settings.environmentID,
                    "--url", settings.platformURL,
                    "--no-input", "--no-update-check", "--no-color"]
        // Converting is jamf-cli's default (--convert is deprecated), so nothing is passed for .convert.
        if stripDefaults { args.append("--strip-defaults") }
        if skipExclusions { args.append("--skip-exclusions") }
        if skipLimitations { args.append("--skip-limitations") }
        if includeUnsupported { args.append("--include-unsupported") }
        if dryRun { args.append("--dry-run") }
        // Preview evaluates takeover with --takeover (a profile that cannot take over
        // still previews, with the reasons); creation uses --takeover-only so nothing
        // is created unless the blueprint can adopt the installed profile.
        if importMode == .preserveInstalled { args.append(dryRun ? "--takeover" : "--takeover-only") }
        if !dryRun && deploymentIntent.requestsDeployment { args.append("--deploy") }
        if scopeMode == .overrideSelected, let group {
            args += [mobile ? "--mobile-device-group" : "--computer-group", group.name]
        }
        let env = ["JAMF_CLIENT_ID": settings.platformClientID,
                   "JAMF_CLIENT_SECRET": secret,
                   "JAMF_ENVIRONMENT_ID": settings.environmentID,
                   "JAMF_URL": settings.platformURL,
                   "JAMF_CLI_NO_UPDATE_CHECK": "1", "JAMF_CLI_NO_HINTS": "1"]
        let result = try await run(executable, args, env, timeout: 900)
        let combined = result.stdout + "\n" + result.stderr
        let lower = combined.lowercased()
        let unsupportedTakeoverPhrases = ["takeover not supported", "takeover is not supported", "takeover is unsupported", "takeover not possible", "takeover is not possible", "cannot take over", "converting the profile rather than keeping it as installed"]
        let takeoverIsUnsupported = unsupportedTakeoverPhrases.contains { lower.contains($0) }
        // jamf-cli preview ends with: [dry-run] Would create blueprint "..." (takeover <label>)
        let dryRunLabel: String? = combined.split(separator: "\n").compactMap { line -> String? in
            let text = String(line)
            guard text.lowercased().contains("[dry-run] would create blueprint"),
                  let open = text.range(of: "(takeover ", options: .backwards),
                  let close = text.range(of: ")", options: .backwards), open.upperBound <= close.lowerBound
            else { return nil }
            return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
        }.last
        let labelUnsupported = dryRunLabel.map { $0.hasPrefix("not supported") || $0.hasPrefix("unsupported") || $0.hasPrefix("not possible") } ?? false
        let labelSupported = dryRunLabel.map { !labelUnsupported && ($0 == "supported" || $0.hasPrefix("supported") || $0 == "possible" || $0.hasPrefix("will take over") || $0.hasPrefix("can take over")) } ?? false
        let verdict: TakeoverVerdict
        if takeoverIsUnsupported || labelUnsupported { verdict = .unsupported }
        else if lower.contains("takeover supported") || labelSupported { verdict = .supported }
        else if result.exitCode != 0 { verdict = .failed }
        else if dryRun { verdict = .previewGenerated }
        else { verdict = .unknown }
        let lines = combined.split(separator: "\n").map(String.init)
        let messages = lines.filter { line in
            let value = line.lowercased()
            return value.contains("[dry-run] would create blueprint") || value.contains("takeover supported") || unsupportedTakeoverPhrases.contains(where: { value.contains($0) }) || value.contains("refused") || value.contains("warning:")
        }
        let dropped = lines.filter { $0.lowercased().contains("dropped") || $0.lowercased().contains("discarded") }
        return TakeoverImportResult(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode, verdict: verdict, messages: messages, droppedKeys: dropped)
    }

    /// Output is read while the process runs (no pipe-buffer deadlock) and the
    /// process is stopped if it exceeds `timeout`.
    private func run(
        _ executable: URL, _ arguments: [String], _ environment: [String: String], timeout: TimeInterval
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let output = try await ProcessRunner.run(
            executable, arguments, environment: environment, timeout: timeout
        )
        return (output.stdoutText, output.stderrText, output.status)
    }
}
