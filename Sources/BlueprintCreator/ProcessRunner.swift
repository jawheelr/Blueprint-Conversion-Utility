import Foundation

/// Runs a child process without blocking the caller's actor and without the
/// pipe-buffer deadlock that occurs when output is read only after exit.
enum ProcessRunner {
    struct Output: Sendable {
        let stdout: Data
        let stderr: Data
        let status: Int32
        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var flag = false
        func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
        func markTimedOut() { lock.lock(); flag = true; lock.unlock() }
        var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = 60
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try runBlocking(executable, arguments, environment: environment, timeout: timeout)
                })
            }
        }
    }

    private static func runBlocking(
        _ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval
    ) throws -> Output {
        do {
            let process = Process()
            let out = Pipe()
            let err = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            if !environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.standardError = err
            try process.run()

            let state = Box()
            let killer = DispatchWorkItem {
                if process.isRunning { state.markTimedOut(); process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

            let outBox = Box()
            let errBox = Box()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                outBox.set(out.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                errBox.set(err.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            group.wait()
            process.waitUntilExit()
            killer.cancel()

            if state.timedOut {
                throw AppFailure.message(
                    "\(executable.lastPathComponent) did not finish within \(Int(timeout)) seconds and was stopped."
                )
            }
            return Output(
                stdout: outBox.get(),
                stderr: errBox.get(),
                status: process.terminationStatus
            )
        }
    }
}

/// Validation for values that are interpolated into request paths or sent to
/// the Platform API.
enum Validators {
    /// Server-issued identifiers (profile IDs, blueprint IDs) must be a short
    /// token of letters, digits, `-` and `_`; anything else could alter a path.
    static func isSafeIdentifier(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count) else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }

    static func requireSafeIdentifier(_ value: String, label: String) throws -> String {
        guard isSafeIdentifier(value) else {
            throw AppFailure.message("\(label) is missing or has an unexpected format.")
        }
        return value
    }

    /// Returns an https base URL with a host and no embedded credentials,
    /// query or fragment.
    static func platformBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else {
            throw AppFailure.message("Platform API URL must be a valid HTTPS URL with a host name.")
        }
        return url
    }
}
