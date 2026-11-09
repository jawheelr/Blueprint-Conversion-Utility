import Foundation
import Security

private struct PlatformSecret: Codable {
    let platformClientSecret: String
}

private struct LegacySecrets: Codable {
    let jamfClientSecret: String
    let platformClientSecret: String
}

enum KeychainStore {
    private static let service = "com.jawheelr.blueprintcreator"
    private static let legacyService = "com.jarredwheeler.blueprintcreator"
    private static let account = "platform-api-client-secret"
    private static let legacyAccount = "api-client-secrets"

    static func saveSecret(_ platform: String) throws {
        guard !platform.isEmpty else {
            throw AppFailure.message("Platform API client secret is required.")
        }
        let data = try JSONEncoder().encode(
            PlatformSecret(platformClientSecret: platform)
        )
        try upsert(data: data, service: service, account: account)
    }

    static func readSecret() -> String? {
        if let value = decodePlatformSecret(read(service: service, account: account)) {
            return value
        }

        // Migrate the immediately previous application identity.
        if let value = decodePlatformSecret(read(service: legacyService, account: account)) {
            try? saveSecret(value)
            return value
        }

        // Migrate the older two-secret credential payload used before the
        // Platform-only release, checking both service names defensively.
        for candidateService in [service, legacyService] {
            if let data = read(service: candidateService, account: legacyAccount),
               let value = try? JSONDecoder().decode(LegacySecrets.self, from: data) {
                try? saveSecret(value.platformClientSecret)
                return value.platformClientSecret
            }
        }
        return nil
    }

    private static func decodePlatformSecret(_ data: Data?) -> String? {
        guard let data,
              let value = try? JSONDecoder().decode(PlatformSecret.self, from: data)
        else { return nil }
        return value.platformClientSecret
    }

    private static func upsert(data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(
                query as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ] as CFDictionary
            )
        } else {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrLabel as String] = "Blueprint Conversion Utility Platform API Credential"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw AppFailure.message(
                "Unable to save Platform API credential in Keychain. Status: \(status)"
            )
        }
    }

    private static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }
}
