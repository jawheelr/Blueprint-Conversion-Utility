import Foundation

struct StoredConnections: Codable, Equatable {
    var connections: [PlatformConnection]
    var activeID: UUID?
}

/// Saves the list of Platform connections. Secrets are never stored here.
enum ConnectionStore {
    static let key = "BlueprintCreator.Connections"
    /// The single-connection settings blob that the bcu command line tool still reads.
    static let mirroredSettingsKey = "BlueprintCreator.Settings"

    static func load(defaults: UserDefaults = .standard) -> StoredConnections? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredConnections.self, from: data),
              !stored.connections.isEmpty else { return nil }
        return stored
    }

    static func save(_ stored: StoredConnections, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(stored), forKey: key)
    }

    /// Writes the active connection to the legacy keys so `bcu` follows the app's environment.
    static func mirrorActive(_ settings: AppSettings, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: mirroredSettingsKey)
    }

    /// Returns the saved connections. On the first launch after this feature shipped it
    /// turns the existing single connection into the first entry and copies its secret to
    /// that entry's own Keychain item; the legacy items are left in place.
    static func loadOrMigrate(
        defaults: UserDefaults = .standard,
        readLegacySecret: () -> String? = { KeychainStore.readSecret() },
        saveSecret: (String, UUID) -> Void = { try? KeychainStore.saveSecret($0, for: $1) }
    ) -> StoredConnections {
        if let stored = load(defaults: defaults) { return stored }
        var legacy = AppSettings()
        if let data = defaults.data(forKey: mirroredSettingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            legacy = saved
        }
        let connection = PlatformConnection(name: "Jamf Platform", settings: legacy)
        if let secret = readLegacySecret(), !secret.isEmpty { saveSecret(secret, connection.id) }
        let stored = StoredConnections(connections: [connection], activeID: connection.id)
        try? save(stored, defaults: defaults)
        return stored
    }
}
