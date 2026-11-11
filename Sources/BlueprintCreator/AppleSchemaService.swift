import Foundation

struct AppleSchemaSummary: Equatable {
    let objectCount: Int
    let keyCount: Int
    let wildcardCount: Int
    let deprecatedObjectCount: Int
    let removedObjectCount: Int
}

enum AppleSchemaService {
    static func load() throws -> (AppleSchemaCatalog, AppleSchemaSummary) {
        guard let catalogURL = Bundle.main.url(forResource: "apple-device-management-catalog", withExtension: "json", subdirectory: "AppleSchema") else {
            throw AppFailure.message("The bundled Apple Device Management catalog is missing.")
        }
        guard let indexURL = Bundle.main.url(forResource: "apple-device-management-index", withExtension: "json", subdirectory: "AppleSchema") else {
            throw AppFailure.message("The bundled Apple Device Management index is missing.")
        }
        let decoder = JSONDecoder()
        let catalog = try decoder.decode(AppleSchemaCatalog.self, from: Data(contentsOf: catalogURL))
        let indexData = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any] ?? [:]
        let lifecycle = indexData["lifecycle"] as? [String: Any] ?? [:]
        let summary = AppleSchemaSummary(
            objectCount: indexData["objectCount"] as? Int ?? catalog.objects.count,
            keyCount: indexData["keyCount"] as? Int ?? 0,
            wildcardCount: indexData["wildcardKeyCount"] as? Int ?? 0,
            deprecatedObjectCount: (lifecycle["deprecatedObjects"] as? [Any])?.count ?? 0,
            removedObjectCount: (lifecycle["removedObjects"] as? [Any])?.count ?? 0
        )
        return (catalog, summary)
    }
}
