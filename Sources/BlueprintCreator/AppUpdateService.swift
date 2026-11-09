import Foundation

struct AppUpdate: Identifiable, Sendable {
    let id = UUID()
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseNotes: String
    let releaseURL: URL
    let packageURL: URL
    let publishedAt: Date?
}

actor AppUpdateService {
    static let repositoryURL = URL(string: "https://github.com/jawheelr/Blueprint-Conversion-Utility")!
    private static let latestReleaseURL = URL(string: "https://github.com/jawheelr/Blueprint-Conversion-Utility/releases/latest")!

    func check(currentVersion: String) async throws -> AppUpdate? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("BlueprintConversionUtility/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppFailure.message("GitHub returned no HTTP response.")
        }
        guard (200...399).contains(http.statusCode), let finalURL = http.url else {
            throw AppFailure.message("The GitHub Releases page is temporarily unavailable.")
        }

        let components = finalURL.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            throw AppFailure.message("GitHub did not return a published latest release.")
        }

        let rawTag = components[tagIndex + 1].removingPercentEncoding ?? components[tagIndex + 1]
        // The tag becomes part of a download URL and file name.
        guard !rawTag.isEmpty, rawTag.count <= 40,
              rawTag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else {
            throw AppFailure.message("GitHub returned an unexpected release tag.")
        }
        guard finalURL.scheme == "https", finalURL.host?.lowercased() == "github.com" else {
            throw AppFailure.message("The release page is not hosted on github.com.")
        }
        let latest = Self.normalized(rawTag)
        let current = Self.normalized(currentVersion)
        guard Self.compare(latest, current) == .orderedDescending else { return nil }

        let packageName = "Blueprint-Conversion-Utility-\(latest).pkg"
        guard let packageURL = URL(
            string: "https://github.com/jawheelr/Blueprint-Conversion-Utility/releases/download/\(rawTag)/\(packageName)"
        ) else {
            throw AppFailure.message("Unable to construct the GitHub release package URL.")
        }

        return AppUpdate(
            currentVersion: currentVersion,
            latestVersion: latest,
            releaseName: "Blueprint Conversion Utility \(latest)",
            releaseNotes: "A newer release is available. Choose Download and Install to retrieve the release package and open it in the native macOS Installer.",
            releaseURL: finalURL,
            packageURL: packageURL,
            publishedAt: nil
        )
    }

    func downloadPackage(for update: AppUpdate) async throws -> URL {
        var request = URLRequest(url: update.packageURL)
        request.timeoutInterval = 120
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue(
            "BlueprintConversionUtility/\(update.currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AppFailure.message(
                "The release package could not be downloaded. Confirm that \(update.packageURL.lastPathComponent) is attached to the GitHub release."
            )
        }

        let header = try Data(contentsOf: temporaryURL, options: .mappedIfSafe).prefix(4)
        guard header.elementsEqual(Data([0x78, 0x61, 0x72, 0x21])) else {
            throw AppFailure.message(
                "The downloaded file is not a valid macOS installer package. No installer was opened."
            )
        }

        let updatesDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Blueprint Conversion Utility/Updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: updatesDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let destination = updatesDirectory.appendingPathComponent(
            update.packageURL.lastPathComponent
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        do {
            try await Self.verifyPackageSignature(destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// When this app is Developer ID signed, the update package must be signed
    /// by the same team. Ad-hoc builds (testing) have no team to compare, so the
    /// package signature is only logged.
    private static func verifyPackageSignature(_ package: URL) async throws {
        let check = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/sbin/pkgutil"), ["--check-signature", package.path], timeout: 60
        )
        let signatureReport = check.stdoutText + check.stderrText
        let appInfo = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/codesign"), ["-dv", Bundle.main.bundleURL.path], timeout: 30
        )
        let team = (appInfo.stdoutText + appInfo.stderrText)
            .split(separator: "\n")
            .first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
        guard let team, team != "not set", !team.isEmpty else {
            AppLogger.connections.notice("Running app has no Team ID; update package signature not enforced")
            return
        }
        guard check.status == 0, signatureReport.contains("(\(team))") else {
            throw AppFailure.message(
                "The downloaded package is not signed by this application's developer team (\(team)). No installer was opened."
            )
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV \n\t"))
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}
