import Foundation

/// Locates the helper executables. Release builds run only the copies sealed
/// inside the application bundle (covered by the app's code signature); a
/// user-writable copy is never trusted, because any process running as the
/// user could replace it.
enum ManagedToolRepository {
    static func bundledTool(_ name: String) -> URL? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    /// Development-only fallback for `swift run`, where there is no bundle.
    private static func developmentTool(_ name: String) -> URL? {
        #if DEBUG
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/\(name)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        #else
        return nil
        #endif
    }

    static func resolve(_ name: String) -> URL? {
        bundledTool(name) ?? developmentTool(name)
    }

    static func validatedConverter() throws -> URL {
        guard let url = resolve("blueprint-profile-convert") else {
            throw AppFailure.message("The bundled profile conversion helper is missing from the application.")
        }
        return url
    }
}
